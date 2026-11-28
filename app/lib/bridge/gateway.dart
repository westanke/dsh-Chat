/// dsh-remote-bridge 移动网关 WS 客户端（ws://HOST:3090/ws/mobile）。
/// 协议事实来源：dsh-remote-bridge docs/api/asyncapi.yaml + docs/project/API.md
/// 「移动端网关 WebSocket」一节；参考实现 kotlin-sdk MobileGatewayClient.kt。
/// 常量锚点（宪法 §5：只在此处定义）：
///   - 子协议 `dsh-mobile-v1` 必须**在清单里**（issue #26 阶段 2 起位置无关；
///     服务端挑第一个认识的，协商结果永远是 dsh-mobile-v1）
///   - 子协议 `dshrb-v1` 可选：声明了才启用 kernel-call 通用调用面四帧
///   - hello.protocol == 3
///   - close 4001 = 鉴权失败/设备吊销（重连无意义）
///   - 重连退避 1,2,4,8,16s 封顶 30s
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dlog.dart';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'device.dart';
import 'endpoint_select.dart';
import 'gateway_events.dart';
import 'gateway_kernel.dart';
import 'gateway_liveness.dart';
import 'gateway_pending.dart';
import 'mobile_frames.dart';
import 'models.dart';
import 'questions.dart';
import 'queue.dart';
export 'gateway_api.dart';
export 'gateway_events.dart';
export 'gateway_http.dart';
export 'gateway_kernel.dart';
export 'gateway_pending.dart';
export 'gateway_rest.dart';
export 'questions.dart';

/// 网关推送事件与异常类型在 gateway_events.dart（宪法 §7 拆分）。

/// 订阅/退订要发的帧（纯函数，便于单测）。
///
/// 桥的语义：`subscribe` **合并**进入白名单（可订多个会话），`unsubscribe`
/// 清空白名单回到「接收所有已授权会话」。单连接的 dsh-Chat 一次只跟一个会话，
/// 所以换会话时要先退订再订阅——否则连接待过的每个会话都永久留在白名单里，
/// 事件量与授权判定白付（以前 `subscribe(null)` 直接 return，一次都没退订过）。
List<Map<String, Object?>> subscriptionFrames(String? current, String? next) {
  if (next == null || next.isEmpty) {
    return current == null
        ? const []
        : const [
            {'type': 'unsubscribe'},
          ];
  }
  if (current == next) return const [];
  return [
    if (current != null) {'type': 'unsubscribe'},
    {'type': 'subscribe', 'sessionId': next},
  ];
}

/// 服务端在握手阶段关连接时，把这个关闭码翻成用户能照着做的一句话。
///
/// 桥的判据（`src/host/ws-handler.ts`）：4001 + `TOKEN_INVALID` / `AUTH_FAILED` /
/// `Device revoked` / `AUTH_REQUIRED` / `PAIRING_FAILED`。不翻的话，`connect()` 只会
/// 等到 helloTimeout 报「连接或握手超时」——现场分不清是网络不通还是令牌失效。
String gatewayDownMessage(int? code, String? reason) {
  if (code == 4001) {
    return switch (reason) {
      'Device revoked' => '这台设备已被吊销，请重新配对',
      'TOKEN_INVALID' || 'AUTH_FAILED' => '配对令牌已失效，请重新配对',
      'AUTH_REQUIRED' => '这条记录没有令牌，请重新配对',
      'DEVICE_ID_REQUIRED' => '缺少设备标识，请重新配对',
      'PAIRING_FAILED' => '配对失败，配对码可能已过期',
      _ => '服务端拒绝连接：${reason ?? '未知原因'}',
    };
  }
  if (code == 429) return '连接数已满，稍后再试';
  return '连接被服务端关闭${code == null ? '' : '（close $code）'}';
}

/// 老桥（2026-11-23 之前）hello 不带 maxFrameBytes 时的回退值：
/// bridge docs/project/API.md「maxFrameBytes ... 老桥不发，客户端回退 1 MiB」。
/// 新桥一律以 hello 实际值为准，禁止再用这个常量硬判。
const int defaultMaxFrameBytes = 1024 * 1024;

/// 解析 hello.data.maxFrameBytes（正整数才认；其它形状回 null 走回退值）。
int? parseMaxFrameBytes(Object? raw) => raw is int && raw > 0 ? raw : null;

/// 解析 hello.data.frames（本桥支持的客户端帧 type 全集；老桥无此字段 → 空表）。
///
/// 空表 = **不知道**，调用方必须按「帧不可用」处理（回退 REST/旧行为），
/// 不能把「没这个字段」当成「支持所有帧」。
List<String> parseHelloFrames(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final f in raw)
      if (f is String && f.isNotEmpty) f,
  ];
}

class GatewayClient {
  GatewayClient({
    required this.baseUrl,
    Duration? connectTimeout,
    Duration? helloTimeout,
  }) : connectTimeout = connectTimeout ?? const Duration(seconds: 10),
       helloTimeout = helloTimeout ?? const Duration(seconds: 8);

  /// WebSocket 建连（TCP+TLS+upgrade）等待上限。隧道端点的 RTT 比局域网高一个量级，
  /// 用同一个 10s 会把「慢」误判成「不通」（IKX5KQ 现场：288ms RTT + 冷启动）。

  /// 如 http://192.168.1.10:3090（不带路径）。重连换候选地址时会变
  /// （IKX5KQ：LAN 断了自动落到隧道，不让用户重贴配置）。
  String baseUrl;

  /// 建连与 hello 的等待上限，见构造参数说明。
  final Duration connectTimeout;
  final Duration helloTimeout;

  /// 按序尝试的候选地址（DSH1 endpoints 全量；老单地址码为空表）。
  /// 当前订阅的会话（null = 未订阅/已退订）。重连后白名单在服务端被重置，
  /// 靠这个字段在 hello 里补订阅。
  String? _subscribedSessionId;

  List<String> _endpointCandidates = const [];

  List<String> get endpointCandidates => _endpointCandidates;

  /// 最近一次握手成功的地址（写回 DshHost.preferredEndpoint）。
  String? connectedEndpoint;

  /// 设置候选表：baseUrl 不在表里时以表首为准（导入新码覆盖旧地址）。
  void setEndpointCandidates(Iterable<String> urls) {
    final list = normalizeEndpoints(urls);
    if (list.isEmpty) return;
    _endpointCandidates = list;
    if (!list.contains(baseUrl)) baseUrl = list.first;
  }

  /// 当前地址连不上时换下一条；只有一条候选时返回 false（老行为不变）。
  bool rotateEndpoint() {
    if (_endpointCandidates.length < 2) return false;
    final i = _endpointCandidates.indexOf(baseUrl);
    final next = _endpointCandidates[(i + 1) % _endpointCandidates.length];
    if (next == baseUrl) return false;
    baseUrl = next;
    DshLog.w('gw endpoint rotate → $next');
    return true;
  }

  /// 重连前重新探活并择优（用户 2026-11-23 口径：任何场景要重连都先按
  /// 「局域网 → 虚拟网 → 隧道」探活，同档取最快，再连过去）。
  ///
  /// 与 [rotateEndpoint] 的区别：换址不是「轮流试」，而是按档位+延迟重挑一次；
  /// 挑不到可达地址时返回 false，交回退避循环继续重试。
  Future<bool> reprobeEndpoints() async {
    final candidates = _endpointCandidates;
    if (candidates.length < 2) return false;
    final selection = await selectEndpoint(
      candidates,
      preferred: connectedEndpoint ?? baseUrl,
    );
    final chosen = selection.chosen;
    DshLog.w('gw endpoint reprobe ${selection.note}');
    if (chosen == null) return false;
    if (chosen == baseUrl) return false;
    baseUrl = chosen;
    return true;
  }

  WebSocketChannel? _ws;
  GatewayState _state = GatewayState.idle;
  int _deltaCount = 0;
  String? token;
  String deviceId = '';
  String deviceName = '';

  /// hello.data.device（配对后的设备档案：name/id/scopes/rootIds/platform/model）。
  Map<String, dynamic>? device;

  /// hello.data.capabilities（`<能力>-v<主版本>`，只增不撤）。协议要求**用能力位
  /// 探测特性、不硬比版本**；位名权威来源 bridge `src/host/capabilities.ts`。
  List<String> capabilities = const [];

  /// hello.data.frames：本桥**实际支持**的客户端帧 type 全集。
  ///
  /// 老桥不认这个字段 → 空表。判「这条帧能不能发」用它，不要拿 REST 能力位
  /// 推断帧面（能力位与传输解耦，同一个能力可能只有 REST 侧登记过）。
  ///
  /// 字段名带 supported 前缀：测试里的假网关普遍有名为 `frames` 的收帧记录表，
  /// 直接叫 frames 会撞名。
  List<String> supportedFrames = const [];

  /// hello.data.port：LAN 直连与隧道数据端口不同，诊断页用它说清接入通道。
  int? listenerPort;

  /// hello.data.maxFrameBytes：本连接**入站单帧上限**（UTF-8 字节）。桥从
  /// 2.17.3 起下发（ws-handler.ts:735），老桥缺席时按 [defaultMaxFrameBytes]
  /// 回退。发送前据此预检，超限直接给「走附件」提示而不是等 close 1009。
  int? maxFrameBytes;

  /// 本次连接实际生效的单帧上限（字节）。
  int get frameLimitBytes => maxFrameBytes ?? defaultMaxFrameBytes;

  /// 最近一次发送是否因超限被本地拦下（[requestWithTimeout] 用来区分
  /// 「没连接」与「帧太大」，两者都不该报 NOT_CONNECTED）。
  bool _lastSendTooLarge = false;

  int _requestSeq = 0;
  final PendingRegistry _pending = PendingRegistry();
  final KernelCallRegistry _kernelCalls = KernelCallRegistry();

  /// 握手后桥推来的内核端点目录（`kernel-endpoints` 帧，白名单 ∩ 运行中内核）。
  /// 没协商 `dshrb-v1`、或桥的内核服务缺席时恒为空 —— 空表就是「这能力不可用」。
  ///
  /// **目录是异步到的**：`hello` 之后桥才推这一帧，重连时 `hello` 还会先把目录
  /// 清空。所以界面不能只在自身重建时读一次快照 —— 那会让「能力刚可用」和
  /// 「能力不可用」长得一模一样（真机踩过：抽屉里输完字，这一节整节不出现）。
  /// 要听变化就用 [kernelCatalogListenable]。
  final ValueNotifier<List<KernelEndpoint>> _catalog =
      ValueNotifier<List<KernelEndpoint>>(const []);

  /// 目录的当前快照。
  List<KernelEndpoint> get kernelCatalog => _catalog.value;

  /// 目录变化通知：能力位和端点表都可能晚于首屏到达。
  ValueListenable<List<KernelEndpoint>> get kernelCatalogListenable => _catalog;

  /// 测试用：不真的连桥，直接把目录塞进去，验证「能力晚到」这条时序。
  @visibleForTesting
  void debugSetKernelCatalog(List<KernelEndpoint> endpoints) =>
      _catalog.value = endpoints;

  final Liveness _live = Liveness();
  Timer? _heartbeat;
  StreamSubscription<dynamic>? _sub;
  int _backoffIndex = 0;
  bool _disposed = false;
  bool _authDead = false;

  /// 同一次掉线只收口一次。`_sendRaw`/心跳/onDone 三处都会调 `_onDown`，
  /// 而 failAll 会同步触发调用方的失败处理（常立刻重发请求 → 又 `_onDown`），
  /// 无闸门时打成无限微任务循环：真机上 UI 线程 100%+、5s 无响应（ANR）。
  bool _downHandled = false;

  final _stateCtrl = StreamController<GatewayState>.broadcast();
  final _eventCtrl = StreamController<GatewayEvent>.broadcast();

  /// 后台任务推送走旁路流（[JobPush]）：不进 [events] 的穷尽分派。
  final _jobCtrl = StreamController<JobPush>.broadcast();

  /// 语音推送（`speech-state` / `speech-preparing` / `speech-transcript`）
  /// 走旁路流：原始帧交给 [SpeechController]，不进 [events]。
  final _speechCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<GatewayState> get state => _stateCtrl.stream;
  Stream<GatewayEvent> get events => _eventCtrl.stream;

  /// 后台任务推送（`chat.job.updated` / `chat.job.finished`）。
  Stream<JobPush> get jobPushes => _jobCtrl.stream;

  /// 语音推送原始帧（kind + data），供 `SpeechController.attachPushStream`。
  Stream<Map<String, dynamic>> get speechPushes => _speechCtrl.stream;
  GatewayState get currentState => _state;

  String get _wsUrl {
    final base = baseUrl
        .replaceFirst(RegExp(r'^http'), 'ws')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/ws/mobile';
  }

  /// 首次配对：子协议 dsh-pair.<code> + X-DSH-Device-ID。
  /// 成功后服务端推 paired{token, device}，随后 hello —— 连接即可用。
  Future<void> pair({
    required String code,
    required String newDeviceId,
    required String name,
  }) async {
    deviceId = newDeviceId;
    deviceName = name;
    await _connect(
      protocols: _subprotocols('dsh-pair.$code'),
      headers: {
        'X-DSH-Device-ID': deviceId,
        'X-DSH-Device-Name': base64Encode(utf8.encode(deviceName)),
      },
    );
  }

  /// 用已保存的 token 连接（子协议 dsh-auth，token 放子协议第二位）。
  Future<void> connect() async {
    final t = token;
    if (t == null || t.isEmpty) throw RequestException('NO_TOKEN', '尚未配对');
    final name = DshDevice.deviceName.trim();
    await _connect(
      protocols: _subprotocols('dsh-auth.$t'),
      headers: <String, String>{
        if (name.isNotEmpty)
          'X-DSH-Device-Name': base64Encode(utf8.encode(DshDevice.displayName)),
      },
    );
  }

  /// 子协议清单：`dsh-mobile-v1` 必须在内（位置无关），`dshrb-v1` 是**可选增量**。
  ///
  /// 声明 `dshrb-v1` 只影响本连接能不能收发通用内核调用面那四帧（握手回显仍是
  /// dsh-mobile-v1，桥按**客户端声明的清单**判断，不看协商结果）。老桥不认识它时
  /// 会照常握手、只是永不推 `kernel-endpoints` ⇒ 本仓的目录为空 ⇒ 调用面判为不可用。
  List<String> _subprotocols(String credential) => [
    'dsh-mobile-v1',
    'dshrb-v1',
    credential,
  ];

  Future<void> _connect({
    required List<String> protocols,
    required Map<String, String> headers,
  }) async {
    if (_disposed) return;
    _setState(GatewayState.connecting);
    _downHandled = false; // 新连接：掉线闸门复位
    _helloCompleter = null; // 每次连接都要等新的 hello，别复用已完成的旧 future
    try {
      final ws = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl),
        protocols: protocols,
        headers: headers,
      );
      _ws = ws;
      await ws.ready.timeout(connectTimeout);
      _sub = ws.stream.listen(
        _onFrame,
        // close code 只能从 channel 取（onDone/onError 回调不带参数），
        // 且必须在 teardown 之前读，晚一步就是 null。
        onDone: () => _onDown(ws.closeCode, ws.closeReason),
        onError: (Object e) => _onDown(ws.closeCode, ws.closeReason),
      );
      _startHeartbeat();
      // hello 会异步到达；等它确认协议版本。
      await _helloFuture.timeout(helloTimeout);
    } on TimeoutException {
      await _teardown();
      throw RequestException('TIMEOUT', '连接或握手超时');
    } catch (e) {
      await _teardown();
      // 已经是我们自己映射好的原因（掉线/鉴权）就原样抛：再包一层 CONNECT_FAIL
      // 会把「令牌失效」说成「连接失败」，用户不知道该重新配对。
      if (e is RequestException) rethrow;
      // WebSocketChannelException: connection rejected —— 401/403/429 都在这里
      throw RequestException('CONNECT_FAIL', e.toString());
    }
  }

  Completer<void>? _helloCompleter;

  Future<void> get _helloFuture {
    _helloCompleter ??= Completer<void>();
    return _helloCompleter!.future;
  }

  void _setState(GatewayState s) {
    debugPrint('[dsh-gw] state $s');
    DshLog.w('gw state=$s');
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _onFrame(dynamic raw) {
    _live.seenAt(DateTime.now()); // 收到帧就算活着（坏帧也算）
    Map<String, dynamic> frame;
    try {
      frame = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return; // 非文本帧或坏 JSON，忽略
    }
    final kind = (frame['kind'] ?? '') as String;
    final data = Map<String, dynamic>.from(frame['data'] as Map? ?? const {});
    // requestId 回显在 data 里（ws-protocol.ts:611 withRequestIdEcho 注入 data.requestId），
    // 顶层没有；两处都兜着读。
    final requestId = (frame['requestId'] ?? data['requestId']) as String?;
    // 逐帧日志会写死 UI 线程（真机：流式期间同步写盘 → tap 5s 无响应 → ANR）。
    if (kind != 'pong' && kind != 'event') {
      DshLog.w('gw <- kind=$kind rid=$requestId');
    }
    switch (kind) {
      case 'hello':
        final protocol = (data['protocol'] ?? 0) as int;
        if (protocol != 3) {
          _helloCompleter?.completeError(
            RequestException('PROTOCOL', '协议版本不符：server=$protocol, client=3'),
          );
          _helloCompleter = null;
          return;
        }
        if (data['device'] is Map) {
          device = Map<String, dynamic>.from(data['device'] as Map);
        }
        // 能力位与监听端口：每次 hello 现算，重连后可能变化（桥 apply 期
        // 惰性解析 + 每次现算，见 bridge STATUS「hello 能力位每次现算」）。
        final caps = data['capabilities'];
        capabilities = [
          if (caps is List)
            for (final c in caps)
              if (c is String) c,
        ];
        // 客户端帧白名单跟着 hello 走：老桥没有 frames 字段 → 空表（按不可用处理）。
        supportedFrames = parseHelloFrames(data['frames']);
        listenerPort = data['port'] is int ? data['port'] as int : null;
        // 单帧上限跟着 hello 走：重连后桥可能换了配置，不能沿用上一轮的值。
        maxFrameBytes = parseMaxFrameBytes(data['maxFrameBytes']);
        // 目录跟着 hello 作废：重连后桥可能换了内核版本、或这次没协商上
        // dshrb-v1。留着上一轮的目录会让 UI 以为端点还在，点了才报端点不存在。
        _catalog.value = const [];
        DshLog.w(
          'gw hello caps=${capabilities.length} '
          'frames=${supportedFrames.length} port=$listenerPort',
        );
        connectedEndpoint = baseUrl;
        // 重连后服务端订阅白名单已重置：补发一次订阅，否则事件过滤退回
        // 「接收所有已授权会话」（会影响后台会话的通知与流量）。
        final resubscribe = _subscribedSessionId;
        if (resubscribe != null) {
          _sendRaw({'type': 'subscribe', 'sessionId': resubscribe});
        }
        _backoffIndex = 0;
        _authDead = false;
        _setState(GatewayState.ready);
        _helloCompleter?.complete();
        _helloCompleter = null;
      case 'paired':
        token = (data['token'] ?? '') as String;
      case 'pong':
        break;
      case 'ping':
        {
          _sendRaw({'type': 'pong'}); // 服务端应用层 ping
        }
      case 'kernel-endpoints':
        // 只在协商到 dshrb-v1 时才会来（握手后立刻推一帧，先于其它业务帧）。
        // 目录是**唯一**的端点真相来源：不硬编码端点表，只按它判断能调什么。
        final catalog = parseKernelEndpoints(data['endpoints']);
        _catalog.value = catalog;
        logKernelCatalog(catalog);
      case 'kernel-call-result':
        // 按 callId 配对（这一组**不走** requestId 回显）。取消之后结果仍会来，
        // 登记表里取不到就静默丢弃 —— 协议要求客户端自己按 callId 去重。
        _kernelCalls.settle(
          data['callId'] as String?,
          parseKernelCallResult(data),
        );
      case 'speech-state':
      case 'speech-preparing':
      case 'speech-transcript':
        // ws-speech 的三条主动推送；交给语音控制器做跟随/准备/转写结果。
        _speechCtrl.add({'kind': kind, 'data': data});
      case 'event':
        _onEventData(data);
      case 'connection-resync-required':
        final dropped = (data['dropped'] ?? 0) as int;
        debugPrint('[dsh-gw] resync dropped=$dropped');
        DshLog.w('gw resync dropped=$dropped');
        _eventCtrl.add(ResyncEvent(dropped));
      case 'error':
        final code = (data['code'] ?? 'ERROR') as String;
        final message = (data['message'] ?? '') as String;
        final requestType = data['requestType'] as String?;
        final retryable = data['retryable'] == true;
        final statusCode = data['statusCode'] is int
            ? data['statusCode'] as int
            : null;
        final details = data['details'] is Map
            ? Map<String, dynamic>.from(data['details'] as Map)
            : null;
        DshLog.w(
          'gw error code=$code msg=$message type=$requestType '
          'retryable=$retryable rid=$requestId',
        );
        final error = RequestException(
          code,
          message,
          retryable: retryable,
          statusCode: statusCode,
          details: details,
        );
        final pending = _pending.take(requestId);
        if (pending != null) {
          PendingRegistry.fail(pending, error);
          break;
        }
        // 分发前被拒（UNKNOWN_TYPE / INVALID_FRAME / MISSING_TYPE）只回
        // requestType、不回 requestId（ws-protocol.ts），不兜底就干挂 30s。
        if (requestType != null &&
            _pending.failOfType(
                  requestType,
                  code,
                  message,
                  retryable: retryable,
                  statusCode: statusCode,
                  details: details,
                ) >
                0) {
          break;
        }
        // 谁都没认领：上抛给 UI，别让服务端主动错误静默消失。
        _eventCtrl.add(GatewayErrorEvent(requestType, error));
      default:
        // 应答帧：requestId 回显关联（协议统一规则）。排除表见 bridge
        // REQUEST_ID_ECHO_EXCLUDED_KINDS：subscribed / event /
        // approval-resolved / kernel-endpoints 等不回显，它们各有分支。
        final p = _pending.take(requestId);
        if (p != null && !p.isCompleted) {
          p.completer.complete(data);
        }
    }
  }

  void _onEventData(Map<String, dynamic> data) {
    final type = (data['type'] ?? '') as String;
    final payload = Map<String, dynamic>.from(data['data'] as Map? ?? const {});
    // delta 最高频（流式每帧一条），逐条记会刷爆日志文件。
    if (type != 'chat.message.delta') {
      DshLog.w('gw event $type sid=${payload['sessionId']}');
    }
    switch (type) {
      case 'chat.message.delta':
        _deltaCount++;
        if (_deltaCount % 25 == 1) debugPrint('[dsh-gw] delta #$_deltaCount');
        _eventCtrl.add(DeltaEvent(MessageDelta.from(payload)));
      case 'chat.message.committed':
        debugPrint('[dsh-gw] committed role=${payload['role']}');
        DshLog.w('gw committed role=${payload['role']}');
        _eventCtrl.add(CommittedEvent(MessageCommitted.from(payload)));
      case 'chat.turn.failed':
        debugPrint('[dsh-gw] turn.failed msg=${payload['message']}');
        _eventCtrl.add(
          TurnFailedEvent(
            (payload['sessionId'] ?? '') as String,
            (payload['message'] ?? '执行失败') as String,
          ),
        );
      case 'chat.turn.start':
        _eventCtrl.add(
          TurnStartedEvent((payload['sessionId'] ?? '') as String),
        );
      case 'chat.turn.end':
        // 官方轮结束判据（client.js:4935/4941）；reason.kind 宽容解析。
        final reason = payload['reason'];
        final reasonKind = reason is Map && reason['kind'] is String
            ? reason['kind'] as String
            : null;
        _eventCtrl.add(
          TurnEndedEvent((payload['sessionId'] ?? '') as String, reasonKind),
        );
      case 'chat.session.status':
        // host 级轮状态：turn/end 丢了也能把「生成中」收掉（兜底判据）。
        _eventCtrl.add(
          SessionStatusEvent(
            (payload['sessionId'] ?? '') as String,
            payload['running'] == true,
          ),
        );
      case 'chat.session.event':
        // 实时流只带 eventType，不带事件体（工具名/参数要靠 history 重拉）。
        // 桥 fdb85da 起 tool/call、tool/result 升级为独立帧（下方两个 case），
        // 本分支退化为老桥兼容路径与低频事件的防抖重拉入口。
        final eventType = (payload['eventType'] ?? '') as String;
        DshLog.w('gw session.event $eventType sid=${payload['sessionId']}');
        _eventCtrl.add(
          SessionEventReceived(
            (payload['sessionId'] ?? '') as String,
            eventType,
          ),
        );
      case 'chat.tool.call':
        // 工具开始执行（参数已定稿）：按 callId 去重覆盖 preparing 行。
        DshLog.w(
          'gw tool.call callId=${payload['callId']} name=${payload['name']}',
        );
        _eventCtrl.add(ToolCallEvent(ToolCallStarted.from(payload)));
      case 'chat.tool.result':
        // 工具结果（error.code 是内核失败分类，UI 端分派已停止/已取消/失败）。
        DshLog.w('gw tool.result callId=${payload['callId']}');
        _eventCtrl.add(ToolResultEvent(ToolCallOutcome.from(payload)));
      case 'chat.userQuestions/requested':
        final q = PendingQuestion.from(
          (payload['sessionId'] ?? '') as String,
          payload,
        );
        DshLog.w(
          'gw question requested callId=${q.callId} n=${q.questions.length}',
        );
        _eventCtrl.add(QuestionRequestedEvent(q));
      case 'chat.userQuestions/answered' || 'chat.userQuestions/dismissed':
        // settled（App 先答 / 电脑端先答 / 超时 / 中止）：卡片要移除。
        DshLog.w('gw question settled $type callId=${payload['callId']}');
        _eventCtrl.add(
          QuestionResolvedEvent(
            (payload['sessionId'] ?? '') as String,
            (payload['callId'] ?? '') as String,
          ),
        );
      case 'chat.approval.requested':
        final a = PendingApproval.from(payload);
        DshLog.w('gw approval requested id=${a.approvalId} tool=${a.toolName}');
        _eventCtrl.add(ApprovalRequestedEvent(a));
      case 'chat.approval.resolved':
        DshLog.w('gw approval resolved id=${payload['approvalId']}');
        _eventCtrl.add(
          ApprovalResolvedEvent(
            (payload['sessionId'] ?? '') as String,
            (payload['approvalId'] ?? '') as String,
          ),
        );
      case 'chat.deliverables.presented':
        // 内核 present 成功的实时帧（bridge chat-adapter.ts:1575 把
        // deliverables/presented 转成本帧，不再走 chat.session.event）。
        // 帧里只有 files+seq，没有过程组上下文 —— 不就地插卡，转成会话事件
        // 触发防抖重拉 history，由 projector 按轮尾统一落位。
        DshLog.w('gw deliverables.presented sid=${payload['sessionId']}');
        _eventCtrl.add(
          SessionEventReceived(
            (payload['sessionId'] ?? '') as String,
            'deliverables/presented',
          ),
        );
      case 'chat.models.updated':
        // 模型目录更新推送（桥 v2.11.0，issue #1）：provider 侧模型清单
        // 可能变化。模型面板打开时必重拉 models 帧，这里仅上抛事件留扩展点。
        DshLog.w('gw models.updated provider=${payload['provider']}');
        _eventCtrl.add(
          ModelsUpdatedEvent(
            payload['provider'] is String
                ? payload['provider'] as String
                : null,
          ),
        );
      case 'queue-item-updated':
        // 队列快照推送（bridge 22a5223）：整份 queue，客户端直接替换。
        final qsid = (payload['sessionId'] ?? '') as String;
        _eventCtrl.add(
          QueueUpdatedEvent(qsid, QueueEntry.listFrom(payload['queue'])),
        );
      case 'chat.session.snapshot':
        // 订阅基线（能力位 session-snapshot-v1）：只带 cursor 切点，不带正文。
        // 老桥不发这条；字段缺席时模型保持 null，上层按「无法判定」处理。
        _eventCtrl.add(SessionSnapshotEvent(SessionSnapshot.fromJson(payload)));
      case 'chat.job.updated' || 'chat.job.finished':
        // 后台任务推送（bridge src/host/ws-jobs.ts）：不新增 kind，复用 event 帧；
        // 非终态走 updated，终态（completed/killed/failed）走 finished，形状一致。
        final jobId = (payload['jobId'] ?? '') as String;
        if (jobId.isNotEmpty) {
          DshLog.w('gw $type job=$jobId status=${payload['status']}');
          _jobCtrl.add(JobPush.fromJson(payload));
        }
      default:
        break; // 其余事件忽略（goal/task 等低频帧暂不消费）
    }
  }

  /// 掉线收口（onDone/onError 共用；code/reason 来自 close 帧，须在 teardown 前读）。
  void _onDown(int? code, String? reason) {
    if (_downHandled) return; // 幂等：重入会与 failAll 的失败处理打成正反馈死循环
    _downHandled = true;
    final hello = _helloCompleter;
    if (hello != null && !hello.isCompleted) {
      hello.completeError(
        RequestException(
          code == 4001 ? 'AUTH_FAILED' : 'LINK_CLOSED',
          gatewayDownMessage(code, reason),
        ),
      );
    }
    _helloCompleter = null;
    final revoked = code == 4001;
    if (revoked) _authDead = true;
    DshLog.w('gw down code=$code reason=$reason');
    // 在途请求立刻失败，别让它们各自干挂到 30s 超时（companion 坑
    // 「请求悬挂」：掉线后按钮一直转圈，用户以为卡死）。
    _pending.failAll('连接已断开${code == null ? '' : '（close $code）'}');
    // 内核调用面同理：在途的 kernel-call 也不会再等到结果帧（桥换了连接就认不出
    // 那批 callId 了），挂着只会拖到 35s 超时。取消过的 callId 已从表里取走，
    // 晚到的结果帧按协议静默丢弃。
    _kernelCalls.failAll('连接已断开${code == null ? '' : '（close $code）'}');
    if (code != null && code != 1000 && code != 1005) {
      _eventCtrl.add(
        LinkClosedEvent(code, reason, limitBytes: frameLimitBytes),
      );
    }
    _teardown().then((_) {
      if (_disposed) {
        _setState(GatewayState.closed);
        return;
      }
      if (revoked) {
        _setState(GatewayState.authFailed); // 设备已吊销：重连无意义
        return;
      }
      _scheduleReconnect();
    });
  }

  /// 退避重连 1,2,4,8,16,30s（index 封顶 5）。重连失败**不是终点**（companion 坑
  /// 「重连链提前终止」）：只有凭据/协议类收口，拒连/429/握手超时按退避接力。
  void _scheduleReconnect() {
    if (_disposed || _authDead) return;
    final delay = Duration(seconds: min(30, 1 << _backoffIndex));
    _backoffIndex = min(_backoffIndex + 1, 5);
    _setState(GatewayState.connecting);
    Timer(delay, () async {
      if (_disposed || _authDead || _ws != null) return;
      try {
        await connect();
        return;
      } catch (e) {
        // 落到下面统一处理（凭据类收口、其余按探活/退避接力）。
        if (e is RequestException &&
            (e.code == 'NO_TOKEN' || e.code == 'PROTOCOL')) {
          _authDead = true;
          _setState(GatewayState.authFailed);
          return;
        }
        // 重连失败先重新探活择优（LAN→虚拟网→隧道），挑到了就重置退避。
        if (await reprobeEndpoints()) _backoffIndex = 0;
        if (_ws == null) _scheduleReconnect();
      }
    });
  }

  /// 能力位探测（`<能力>-v<主版本>`，只增不撤），如 `mobile-session-stats-v1`。
  bool hasCapability(String name) => capabilities.contains(name);

  /// 本桥是否声明支持某条客户端帧（hello.frames）。老桥无字段 → 恒 false。
  bool hasFrame(String type) => supportedFrames.contains(type);

  /// 内核调用面的在途登记表：`gateway_kernel.dart` 的 extension 靠它配对结果帧。
  KernelCallRegistry get kernelCallRegistry => _kernelCalls;

  /// 发一条原始帧（不登记、不等应答）。给 `gateway_kernel.dart` 的通用调用面用：
  /// 那一组用 callId 配对，不走 requestId 回显，套不进 [requestWithTimeout]。
  bool sendRawFrame(Map<String, dynamic> frame) => _sendRaw(frame);

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        // 握手没完成时（TCP 连上了但服务端不回 101），sink.close 会一直等对端，
        // 于是「超时到点」之后整个连接流程反而挂死：真机上表现为按钮变灰、
        // 两分钟没有任何反馈。这里给关闭本身一个上限，超了就走人。
        await ws.sink
            .close(ws_status.normalClosure)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  void _startHeartbeat() {
    _live.reset();
    _heartbeat?.cancel(); // 服务端 30s 缺 2 次 pong 即断；客户端 25s 主动 ping 保活
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      // 静默只记录不断链：判死权在服务端（缺 2 次 pong 才 terminate），客户端抢先
      // 收口会误杀活连接——真机表现为每 ~50s 一次无谓重连，收尾把主线程拖住 → ANR。
      if (_live.isStaleAt(DateTime.now())) {
        DshLog.w('gw peer silent=${_live.silentFor(DateTime.now())}（仅记录）');
      }
      _sendRaw({'type': 'ping'});
    });
  }

  bool _sendRaw(Map<String, dynamic> frame) {
    _lastSendTooLarge = false;
    final ws = _ws;
    if (ws == null) return false;
    // 半死连接**不由客户端判死**：对端静默只是「没东西可推」，写进去的帧照样会到
    // （桥重启时由 onDone/onError 收口，服务端心跳也会主动断）。这里若抢先收口，
    // 会把活连接打成「每 ~50s 一次无谓重连」的循环。
    String encoded;
    try {
      encoded = jsonEncode(frame);
    } catch (_) {
      return false;
    }
    // 协议上限按 UTF-8 字节算（桥 transport 也是按字节收）。本地先拦：
    // 超限帧发出去只会换来 close 1009，提示还不如「图片/大文件走附件」直接。
    final bytes = utf8.encode(encoded).length;
    if (bytes > frameLimitBytes) {
      _lastSendTooLarge = true;
      DshLog.w('gw frame too large bytes=$bytes limit=$frameLimitBytes');
      return false;
    }
    try {
      ws.sink.add(encoded);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// request/response：发 {type, ...payload, requestId}，等回显 requestId 的帧。
  /// 可自定义超时版（session-wait 长轮询用：固定 30s 会先于应答到期）。
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    final requestId =
        'r${++_requestSeq}-${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    // 带上帧类型：error 帧在分发前被拒时只回 requestType（没有 requestId），
    // 靠它把同类型在途请求立刻结算。
    _pending.add(requestId, type, completer);
    final sent = _sendRaw({'type': type, ...payload, 'requestId': requestId});
    DshLog.w('gw -> $type rid=$requestId sent=$sent');
    if (!sent) {
      _pending.take(requestId);
      if (_lastSendTooLarge) {
        throw RequestException(
          'PAYLOAD_TOO_LARGE',
          frameLimitHint(frameLimitBytes),
        );
      }
      throw RequestException('NOT_CONNECTED', '连接未建立，发送失败');
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.take(requestId);
        throw RequestException('TIMEOUT', '请求 $type 超时', retryable: true);
      },
    );
  }

  /// 常规请求：30s 超时（协议请求帧的缺省口径）。
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) => requestWithTimeout(type, payload, const Duration(seconds: 30));

  /// `history` 的等待上限：隧道链路单独放宽。
  ///
  /// 真机反馈（2026-11-23）：隧道模式下 1.0.28 一直报「加载历史失败：请求 history 超时」。
  /// 实测一个正常长度的会话首屏序列化后 **602 KB**（约 8000 条事件记录、首屏 200 条消息），
  /// 过 Cloudflare quick tunnel 单帧要 4.5 秒；手机在移动网络、链路抖动时就更久，
  /// 30 秒的通用上限会被顶穿。隧道模式给 90 秒，局域网/直连维持 30 秒不变。
  ///
  /// 这只是兜底：桥侧同时给 WS 开了 permessage-deflate（同一份 JSON 压到 19.5%），
  /// 客户端也把首屏页从 200 条降到 80 条 —— 正常网络下不该再走到这个上限。
  Duration get historyTimeout =>
      classifyEndpoint(baseUrl) == EndpointKind.tunnel
      ? const Duration(seconds: 90)
      : const Duration(seconds: 30);

  // ---- 业务封装（实现在 gateway_api.dart 的 extension GatewayApi）----

  /// 订阅会话推送。subscribed 在 REQUEST_ID_ECHO_EXCLUDED_KINDS 里（不回显
  /// requestId），不能走 request() 等应答——发出即成功（同 kotlin-sdk）。
  void subscribe(String? sessionId) {
    final next = (sessionId == null || sessionId.isEmpty) ? null : sessionId;
    for (final frame in subscriptionFrames(_subscribedSessionId, next)) {
      // 走公开的 sendRawFrame：测试可覆写它核对「到底发了什么帧」。
      sendRawFrame(frame);
    }
    _subscribedSessionId = next;
  }

  /// 当前订阅的会话（诊断/测试用；null = 已退订）。
  String? get subscribedSessionId => _subscribedSessionId;

  void dispose() {
    _disposed = true;
    _teardown();
    _stateCtrl.close();
    _eventCtrl.close();
    _jobCtrl.close();
    _speechCtrl.close();
    _catalog.dispose();
  }
}

/// REST 字节下载（附件 / 图片交接）实现在 gateway_http.dart（§7 单文件 ≤500 行），
/// 这里 export 让消费方只需 import gateway。
