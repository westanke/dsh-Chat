/// 主机直连（含候选探活/失败换地址），连接页与启动自动连接共用。
///
/// 为什么不放在连接页里：启动路径（main.dart 的 _autoConnect）也要同样的
/// 「先探活、再择优、记住上次地址」逻辑，复制一份必然走散（IKX5KQ）。
library;

import 'endpoint_select.dart';
import 'gateway.dart';
import 'hosts.dart';

/// 连接成功的结果：网关 + 诊断（探了哪几条、选了哪条、为什么）。
class HostConnectResult {
  const HostConnectResult({
    required this.gateway,
    required this.host,
    this.selection,
  });

  final GatewayClient gateway;

  /// 写回后的主机记录（baseUrl=本次成功地址，preferredEndpoint 同步）。
  final DshHost host;

  /// 单条地址的老码没有探活，这里是 null。
  final EndpointSelection? selection;

  /// 一句诊断：给连接页/日志看「试了哪几条、哪条成了」。
  String get note => selection?.note ?? '单地址直连 ${gateway.baseUrl}';
}

/// 连接失败：把探活诊断一起带出来（否则用户只知道「连不上」）。
class HostConnectException implements Exception {
  HostConnectException(this.message, {this.note = ''});

  final String message;
  final String note;

  @override
  String toString() => note.isEmpty ? message : '$message；$note';
}

/// 一条候选地址的连接预算：隧道端点 RTT 比局域网高一个量级，握手要给足时间。
class EndpointTimeouts {
  const EndpointTimeouts({required this.connect, required this.hello});

  final Duration connect;
  final Duration hello;
}

/// 隧道地址放宽到 20s/15s，局域网保持 10s/8s。
///
/// 为什么按端点类型分：现场实测手机到 trycloudflare 的 ICMP RTT 288ms、本机 wss 握手
/// 2.2s；同一个 10s 预算在弱网下会把「慢」判成「不通」，而局域网没有这个必要。
EndpointTimeouts timeoutsFor(String baseUrl) =>
    classifyEndpoint(baseUrl) == EndpointKind.tunnel
        ? const EndpointTimeouts(
            connect: Duration(seconds: 20),
            hello: Duration(seconds: 15),
          )
        : const EndpointTimeouts(
            connect: Duration(seconds: 10),
            hello: Duration(seconds: 8),
          );

/// 这组候选要不要先探活。
///
/// 多候选必然要探（择优）；**单条的隧道地址也要探** —— 不探就分不清「手机到不了
/// Cloudflare」和「到得了但桥握手超时」，现场只能看到一句 RequestException(TIMEOUT)。
/// 局域名单条不探，省一个 RTT。
bool shouldProbeCandidates(List<String> candidates) {
  if (candidates.length > 1) return true;
  if (candidates.isEmpty) return false;
  return classifyEndpoint(candidates.first) == EndpointKind.tunnel;
}

/// 探活择优后连接；失败按候选表轮换重试（每条最多试一次）。
/// 成功后把本次地址写回主机记录，下次启动先试它。
Future<HostConnectResult> connectHost(
  DshHost host, {
  Duration probeTimeout = kEndpointProbeTimeout,
}) async {
  final token = host.token;
  if (token == null || token.isEmpty) {
    throw HostConnectException('这条记录没有配对 token，请重新配对');
  }
  final candidates = host.candidates;
  EndpointSelection? selection;
  var target = host.baseUrl;
  if (shouldProbeCandidates(candidates)) {
    selection = await selectEndpoint(
      candidates,
      preferred: host.preferredEndpoint ?? host.baseUrl,
      timeout: probeTimeout,
    );
    final chosen = selection.chosen;
    if (chosen == null) {
      // 探活全失败就别再白等握手超时：直接说清是哪一层不通。
      throw HostConnectException(
        '这些地址都探不通（/api/v1/healthz 无响应）',
        note: selection.note,
      );
    }
    target = chosen;
  }
  return _retry(
    host: host,
    token: token,
    candidates: candidates,
    start: target,
    selection: selection,
    failures: <String>[],
  );
}

/// 用一次性配对码换令牌，多候选时同样先探活、失败换地址（桥 `/tunnel` 的一行短码入口）。
///
/// 为什么不复用 [connectHost]：那条路要有 token；这里恰恰是**还没有 token**、
/// 要先在选中的地址上完成配对。配对只在一条地址上做——成功了就把整张候选表
/// 记进主机记录，之后自动连接按 [connectHost] 的规则探活换址。
Future<HostConnectResult> pairHost(
  DshHost host, {
  required String code,
  required String deviceId,
  required String deviceName,
  Duration probeTimeout = kEndpointProbeTimeout,
}) async {
  final candidates = host.candidates;
  if (candidates.isEmpty) {
    throw HostConnectException('没有可用的地址，请重新导入配置');
  }
  var selection = shouldProbeCandidates(candidates)
      ? await selectEndpoint(
          candidates,
          preferred: host.preferredEndpoint ?? host.baseUrl,
          timeout: probeTimeout,
        )
      : null;
  final order = <String>[
    if (selection?.chosen != null) selection!.chosen!,
    ...candidates.where((url) => url != selection?.chosen),
  ];
  final failures = <String>[];
  for (final target in order) {
    final budget = timeoutsFor(target);
    final gateway = GatewayClient(
      baseUrl: target,
      connectTimeout: budget.connect,
      helloTimeout: budget.hello,
    );
    try {
      await gateway.pair(code: code, newDeviceId: deviceId, name: deviceName);
      gateway.setEndpointCandidates(candidates);
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = host.copyWith(
        baseUrl: gateway.baseUrl,
        preferredEndpoint: gateway.baseUrl,
        lastUsedAt: now,
      );
      await DshHosts.upsert(updated);
      return HostConnectResult(
        gateway: gateway,
        host: updated,
        selection: selection,
      );
    } on Object catch (e) {
      failures.add('$target：${e is RequestException ? e.message : e}');
      gateway.dispose();
    }
  }
  throw HostConnectException(
    '配对失败：${failures.join('；')}',
    note: selection?.note ?? '',
  );
}

/// 从 [start] 起按候选表继续试（每条一次），成功则写回主机记录。
Future<HostConnectResult> _retry({
  required DshHost host,
  required String token,
  required List<String> candidates,
  required String start,
  required EndpointSelection? selection,
  required List<String> failures,
}) async {
  var target = start;
  final tried = <String>{};
  while (!tried.contains(target)) {
    tried.add(target);
    final budget = timeoutsFor(target);
    final gateway = GatewayClient(
      baseUrl: target,
      connectTimeout: budget.connect,
      helloTimeout: budget.hello,
    )..token = token;
    gateway.setEndpointCandidates(candidates);
    try {
      await gateway.connect();
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = host.copyWith(
        baseUrl: gateway.baseUrl,
        preferredEndpoint: gateway.baseUrl,
        lastUsedAt: now,
      );
      await DshHosts.upsert(updated);
      return HostConnectResult(
        gateway: gateway,
        host: updated,
        selection: selection,
      );
    } on Object catch (e) {
      failures.add('$target：${e is RequestException ? e.message : e}');
      gateway.dispose();
      // 令牌被吊销/失效这一类，换地址也是同样的结果，别把用户等满每条预算。
      if (e is RequestException && e.code == 'AUTH_FAILED') break;
      final rotated = gateway.rotateEndpoint();
      target = gateway.baseUrl;
      if (!rotated) break;
    }
  }
  throw HostConnectException(
    failures.join('；'),
    note: selection?.note ?? '',
  );
}
