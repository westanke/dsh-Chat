/// 通用内核调用面（bridge `dshrb-v1` 子协议，issue #26 阶段 5）。
///
/// 协议事实来源：`dsh-remote-bridge` 的 `docs/api/asyncapi.yaml`（Kernel-call plane
/// 一节）与 `src/host/ws-kernel-call.ts` / `src/host/bridge/kernel-call.ts`。
///
/// ## 它为什么是「协商出来的」
///
/// 四个帧（`kernel-call` / `kernel-call-cancel` / `kernel-call-result` /
/// `kernel-endpoints`）**只在客户端声明的子协议清单里有 `dshrb-v1` 时才存在**。
/// 老 App 的清单里没有它 ⇒ 老连接上这些帧不存在、行为逐字不变 —— 新能力是纯增量。
/// 所以本仓不提供它的时候一切照旧，提供它才多出一块可调用的内核端点面。
///
/// ## 配对用 callId，不是 requestId
///
/// 这一组**不进 `REQUEST_ID_ECHO_EXCLUDED_KINDS` 之外**的 requestId 回显通道：
/// 客户端自铸 `callId`，服务端原样带回，按它配对。重试用**同一个 callId** 才幂等
/// （桥按 `principal + callId` 查 24 小时幂等表回放上次结果），换一个 id 就是新调用。
///
/// ## 端点目录是唯一真相
///
/// 桥在握手后立刻推一帧 `kernel-endpoints`（白名单 ∩ 运行中内核目录）。客户端
/// **不许硬编码端点表**（那正是 B2 换源要消灭的「第二份真相」）；目录里没有的端点
/// 永远调不到，里面有的也可能因 scope 不足当场被拒。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dlog.dart';
import 'gateway.dart';

/// `kernel-endpoints` 里的一条：能调什么、要什么权限、接受哪些 wire 键。
///
/// 元素形状**尚未冻结**（桥当前发 `{endpoint, scope, stream, wires, summary}`），
/// 所以未知字段一律忽略 —— 内核升级加字段不该让本仓解析失败。
class KernelEndpoint {
  const KernelEndpoint({
    required this.endpoint,
    required this.scope,
    required this.summary,
    this.stream = false,
    this.wires = const [],
  });

  factory KernelEndpoint.fromJson(Map<String, dynamic> json) {
    final wires = json['wires'];
    return KernelEndpoint(
      endpoint: (json['endpoint'] ?? '') as String,
      scope: (json['scope'] ?? '') as String,
      summary: (json['summary'] ?? '') as String,
      stream: json['stream'] == true,
      wires: [
        if (wires is List)
          for (final w in wires)
            if (w is String) w,
      ],
    );
  }

  /// 内核描述符端点名（`namespace/method`，如 `session/search`）。
  final String endpoint;

  /// 需要的设备 scope（`chat.read` / `chat.write` / `settings.read` …）。
  final String scope;

  /// 桥白名单里那句人话摘要（可直接显示）。
  final String summary;

  /// 流式端点：桥会把结果收进 `{frames, truncated?}` 再一次性返回。
  final bool stream;

  /// 该端点接受的 wire 键集合。`args` 的键必须与之**完全一致**（内核 strict codec
  /// 既拒缺键也拒多键），所以这张表是拼参数时的唯一依据。
  final List<String> wires;

  @override
  String toString() => 'KernelEndpoint($endpoint, $scope${stream ? ', stream' : ''})';
}

/// `kernel-call-result` 的内容：成功带 `value`，失败带 `error{code,message}`。
///
/// `value` 形状由端点决定、**不做保证**（客户端必须容忍未知字段）；唯一的保留形状
/// 是流式端点返回 `{frames: [...], truncated?}`。
class KernelCallResult {
  const KernelCallResult.ok(this.value) : ok = true, code = null, message = null;

  const KernelCallResult.failed(this.code, this.message)
    : ok = false,
      value = null;

  final bool ok;
  final Object? value;

  /// 稳定错误码：`METHOD_NOT_ALLOWED`（不在白名单，**先于**目录查询，所以错误码
  /// 不能当存在性探针）/ `kernel/endpoint-unknown`（白名单里有但内核没装）/
  /// `call/in-flight` / `call/cancelled` / `call/timeout` / 端点自己的错误码。
  final String? code;
  final String? message;

  /// 便捷：成功且 `value` 是对象。
  Map<String, dynamic>? get object {
    final v = value;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// 便捷：成功且 `value` 是列表。
  List<Object?>? get list {
    final v = value;
    if (v is List) return v;
    return null;
  }

  @override
  String toString() => ok ? 'KernelCallResult.ok($value)' : 'KernelCallResult($code: $message)';
}

/// 在飞调用登记表（`callId` → 结算器）。
///
/// 与 [PendingRegistry] 分开：那一张按 `requestId` 配对经典请求/应答帧，这一张按
/// 客户端自铸的 `callId` 配对调用结果帧，两套 id 语义不同、生命周期也不同（调用
/// 可被取消、可幂等重放）。
class KernelCallRegistry {
  final Map<String, Completer<KernelCallResult>> _inflight = {};

  int get length => _inflight.length;

  bool contains(String callId) => _inflight.containsKey(callId);

  /// 登记一次调用。同 id 覆盖（调用方保证 id 唯一）。
  void add(String callId, Completer<KernelCallResult> completer) =>
      _inflight[callId] = completer;

  /// 取出并摘除；已摘除的不会被二次结算。
  Completer<KernelCallResult>? take(String? callId) {
    if (callId == null || callId.isEmpty) return null;
    return _inflight.remove(callId);
  }

  /// 结算一条。取不到（已取消/已结算）就什么也不做 —— 取消之后结果帧照样会来，
  /// 协议明确要求客户端按 callId 去重。
  KernelCallResult? settle(String? callId, KernelCallResult result) {
    final completer = take(callId);
    if (completer == null || completer.isCompleted) return null;
    completer.complete(result);
    return result;
  }

  /// 全部失败（掉线 / 关闭）：不结算就干挂到调用方超时，UI 上表现为一直转圈。
  void failAll(String message) {
    final all = List.of(_inflight.entries);
    _inflight.clear();
    for (final entry in all) {
      final completer = entry.value;
      if (completer.isCompleted) continue;
      // 先挂吞异常监听：没人 await 的 fire-and-forget 调用直接 completeError 会冒成
      // 未捕获异步异常（与 PendingRegistry.fail 同款处理）。
      completer.future.catchError((Object _) => const KernelCallResult.failed('X', ''));
      completer.completeError(RequestException('NOT_CONNECTED', message));
    }
  }
}

/// `GatewayClient` 的内核调用面（实现在本文件，`gateway.dart` import + export）。
extension GatewayKernel on GatewayClient {
  /// 握手后桥推来的端点目录（白名单 ∩ 内核目录）。
  ///
  /// 空表有两种意思：桥没提供 `dshrb-v1`（老桥），或握手后那帧还没到。两者对调用方
  /// 是同一件事 —— **没有目录就不猜端点**，按「这能力不可用」处理。
  List<KernelEndpoint> get kernelEndpoints => kernelCatalog;

  /// 调用面是否真的可用：要的是能力位 `kernel-call-v1`（桥每次 hello 现算），
  /// 不是「我发了子协议」——桥可能因为内核服务缺席而拒开。
  bool get kernelCallsEnabled => hasCapability('kernel-call-v1');

  /// 某个端点当前是否可调（目录里有 = 白名单 ∩ 内核都成立）。
  KernelEndpoint? kernelEndpoint(String endpoint) {
    for (final e in kernelCatalog) {
      if (e.endpoint == endpoint) return e;
    }
    return null;
  }

  /// 按端点名调一次内核端点（`kernel-call` 帧）。
  ///
  /// [args] 的键必须与 [KernelEndpoint.wires] 完全一致 —— 少一个多一个都会被内核
  /// strict codec 拒（本地不校验，让桥回原始错误码，免得客户端自己发明一套判据）。
  ///
  /// 重试要传**同一个** [callId] 才能幂等回放；不传则自动生成，每次都是新调用。
  Future<KernelCallResult> kernelCall(
    String endpoint, {
    Map<String, dynamic>? args,
    String? callId,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final id = callId ?? _newKernelCallId();
    if (kernelCallRegistry.contains(id)) {
      return const KernelCallResult.failed(
        'call/in-flight',
        '同一个 callId 已有调用在飞行中',
      );
    }
    final completer = Completer<KernelCallResult>();
    kernelCallRegistry.add(id, completer);
    final sent = sendRawFrame({
      'type': 'kernel-call',
      'callId': id,
      'endpoint': endpoint,
      if (args != null && args.isNotEmpty) 'args': args,
    });
    if (!sent) {
      kernelCallRegistry.take(id);
      return const KernelCallResult.failed(
        'NOT_CONNECTED',
        '连接未建立，内核调用未发出',
      );
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        kernelCallRegistry.take(id);
        return const KernelCallResult.failed('call/timeout', '内核调用超时');
      },
    );
  }

  /// 取消一次在飞调用（`kernel-call-cancel`）。尽力而为：内核可能已经跑完，
  /// 结果帧照样会来，本仓按 callId 去重后丢弃。
  void kernelCancel(String callId) {
    if (callId.isEmpty) return;
    sendRawFrame({'type': 'kernel-call-cancel', 'callId': callId});
  }

  String _newKernelCallId() =>
      'k${DateTime.now().microsecondsSinceEpoch}-${_kernelSeq++}';
}

int _kernelSeq = 0;

/// 解析 `kernel-endpoints` 帧。元素形状未冻结 ⇒ 坏条目直接跳过，不连坐整帧。
List<KernelEndpoint> parseKernelEndpoints(Object? raw) {
  if (raw is! List) return const [];
  final out = <KernelEndpoint>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final json = Map<String, dynamic>.from(e);
    final endpoint = json['endpoint'];
    if (endpoint is! String || endpoint.isEmpty) continue;
    out.add(KernelEndpoint.fromJson(json));
  }
  return out;
}

/// 解析 `kernel-call-result` 的 data：`{callId, ok, value?, error?{code,message}}`。
KernelCallResult parseKernelCallResult(Map<String, dynamic> data) {
  if (data['ok'] == true) return KernelCallResult.ok(data['value']);
  final error = data['error'];
  if (error is Map) {
    final code = error['code'];
    final message = error['message'];
    return KernelCallResult.failed(
      code is String && code.isNotEmpty ? code : 'KERNEL_FAILED',
      message is String ? message : '内核调用失败',
    );
  }
  return const KernelCallResult.failed('KERNEL_FAILED', '内核调用失败（无错误详情）');
}

/// 日志用：端点目录摘要（逐条打会刷屏）。
String describeKernelCatalog(List<KernelEndpoint> catalog) =>
    catalog.isEmpty
    ? '空（桥未提供 dshrb-v1，或目录帧未到）'
    : '${catalog.length} 条：${catalog.map((e) => e.endpoint).join('、')}';

/// 便于诊断页/设置页显示：目录按 scope 分组。
Map<String, List<KernelEndpoint>> groupKernelEndpointsByScope(
  List<KernelEndpoint> catalog,
) {
  final out = <String, List<KernelEndpoint>>{};
  for (final e in catalog) {
    (out[e.scope] ??= <KernelEndpoint>[]).add(e);
  }
  return out;
}

/// 调试用（`debugPrint` 走 DSH 日志前缀，避免混进普通 stdout）。
void logKernelCatalog(List<KernelEndpoint> catalog) {
  // vivo 的 logcat 会滤掉 flutter/debugPrint，真机联调只能靠文件日志：
  // 目录帧是判断「这次协商成没成」的唯一现场，必须落盘。
  final line = '[dsh-gw] kernel-endpoints ${describeKernelCatalog(catalog)}';
  debugPrint(line);
  DshLog.w(line);
}
