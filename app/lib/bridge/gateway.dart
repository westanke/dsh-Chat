/// dsh-remote-bridge 移动网关 WS 客户端（ws://HOST:3090/ws/mobile）。
/// 协议事实来源：dsh-remote-bridge docs/api/asyncapi.yaml + docs/project/API.md
/// 「移动端网关 WebSocket」一节；参考实现 kotlin-sdk MobileGatewayClient.kt。
/// 常量锚点（宪法 §5：只在此处定义）：
///   - 子协议首位必须是 dsh-mobile-v1
///   - hello.protocol == 3
///   - close 4001 = 鉴权失败/设备吊销（重连无意义）
///   - 重连退避 1,2,4,8,16s 封顶 30s
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'device.dart';
import 'dlog.dart';

import 'dart:math';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

/// 连接状态。
enum GatewayState { idle, connecting, ready, closed, authFailed }

/// 网关推送事件（客户端 UI 消费）。
sealed class GatewayEvent {}

class DeltaEvent extends GatewayEvent {
  DeltaEvent(this.delta);
  final MessageDelta delta;
}

class CommittedEvent extends GatewayEvent {
  CommittedEvent(this.committed);
  final MessageCommitted committed;
}

class TurnFailedEvent extends GatewayEvent {
  TurnFailedEvent(this.sessionId, this.message);
  final String sessionId;
  final String message;
}

class ResyncEvent extends GatewayEvent {
  ResyncEvent(this.dropped);
  final int dropped;
}

/// 会话内核事件（`chat.session.event`）：实时流只带 {sessionId, eventType, seq}，
/// **不带事件体**（bridge chat-adapter.ts 的 base 就这三个字段）。
///
/// 工具调用因此拿不到 name/arguments —— UI 只能靠重拉 history 拿到完整明细。
/// 这里把 eventType 透出来，让上层决定「值得重拉」的类型（tool/call 等）。
class SessionEventReceived extends GatewayEvent {
  SessionEventReceived(this.sessionId, this.eventType);
  final String sessionId;
  final String eventType;
}

class RequestException implements Exception {
  RequestException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RequestException($code): $message';
}

class GatewayClient {
  GatewayClient({required this.baseUrl});

  /// 如 http://192.168.1.10:3090（不带路径）。
  final String baseUrl;

  WebSocketChannel? _ws;
  GatewayState _state = GatewayState.idle;
  int _deltaCount = 0;
  String? token;
  String deviceId = '';
  String deviceName = '';

  /// hello.data.device（配对后的设备档案：name/id/scopes/rootIds/platform/model）。
  Map<String, dynamic>? device;

  int _requestSeq = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  Timer? _heartbeat;
  StreamSubscription<dynamic>? _sub;
  int _backoffIndex = 0;
  bool _disposed = false;
  bool _authDead = false;

  final _stateCtrl = StreamController<GatewayState>.broadcast();
  final _eventCtrl = StreamController<GatewayEvent>.broadcast();

  Stream<GatewayState> get state => _stateCtrl.stream;
  Stream<GatewayEvent> get events => _eventCtrl.stream;
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
      protocols: ['dsh-mobile-v1', 'dsh-pair.$code'],
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
    await _connect(
      protocols: ['dsh-mobile-v1', 'dsh-auth.$t'],
      headers: const {},
    );
  }

  Future<void> _connect({
    required List<String> protocols,
    required Map<String, String> headers,
  }) async {
    if (_disposed) return;
    _setState(GatewayState.connecting);
    try {
      final ws = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl),
        protocols: protocols,
        headers: headers,
      );
      _ws = ws;
      await ws.ready.timeout(const Duration(seconds: 10));
      _sub = ws.stream.listen(
        _onFrame,
        onDone: _onDone,
        onError: (Object e) => _onDone(),
      );
      _startHeartbeat();
      // hello 会异步到达；等它确认协议版本。
      await _helloFuture.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      await _teardown();
      throw RequestException('TIMEOUT', '连接或握手超时');
    } catch (e) {
      await _teardown();
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
    if (kind != 'pong') DshLog.w('gw <- kind=$kind rid=$requestId');
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
      case 'event':
        _onEventData(data);
      case 'connection-resync-required':
        final dropped = (data['dropped'] ?? 0) as int;
        debugPrint('[dsh-gw] resync dropped=$dropped');
        DshLog.w('gw resync dropped=$dropped');
        _eventCtrl.add(ResyncEvent(dropped));
      case 'error':
        debugPrint(
          '[dsh-gw] error code=${data['code']} msg=${data['message']}',
        );
        DshLog.w('gw error code=${data['code']} msg=${data['message']}');
        final requestId = data['requestId'] as String?;
        final pending = requestId == null ? null : _pending.remove(requestId);
        if (pending != null && !pending.isCompleted) {
          pending.completeError(
            RequestException(
              (data['code'] ?? 'ERROR') as String,
              (data['message'] ?? '') as String,
            ),
          );
        }
      default:
        // 应答帧：requestId 回显关联（协议统一规则）。
        final requestId = data['requestId'] as String?;
        final pending = requestId == null ? null : _pending.remove(requestId);
        if (pending != null && !pending.isCompleted) {
          debugPrint('[dsh-gw] resp kind=$kind');
          pending.complete(data);
        }
    }
  }

  void _onEventData(Map<String, dynamic> data) {
    final type = (data['type'] ?? '') as String;
    final payload = Map<String, dynamic>.from(data['data'] as Map? ?? const {});
    DshLog.w('gw event $type sid=${payload['sessionId']}');
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
      case 'chat.session.event':
        // 实时流只带 eventType，不带事件体（工具名/参数要靠 history 重拉）。
        final eventType = (payload['eventType'] ?? '') as String;
        DshLog.w('gw session.event $eventType sid=${payload['sessionId']}');
        _eventCtrl.add(
          SessionEventReceived(
            (payload['sessionId'] ?? '') as String,
            eventType,
          ),
        );
      default:
        break; // 其余事件第一版忽略（approval/question 后续接）
    }
  }

  void _onDone() {
    _teardown().then((_) {
      if (_disposed || _authDead) {
        _setState(GatewayState.closed);
        return;
      }
      // 退避重连：1,2,4,8,16… 封顶 30s。
      final delay = Duration(seconds: min(30, 1 << _backoffIndex));
      _backoffIndex = min(_backoffIndex + 1, 5);
      _setState(GatewayState.connecting);
      Timer(delay, () {
        if (!_disposed && !_authDead && _ws == null) {
          connect().catchError((Object e) {
            if (e is RequestException && e.code == 'CONNECT_FAIL') {
              _setState(GatewayState.closed);
            }
          });
        }
      });
    });
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        await ws.sink.close(ws_status.normalClosure);
      } catch (_) {}
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // 服务端 30s 周期缺 2 次 pong 即断；客户端 25s 主动 ping 保持活性。
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendRaw({'type': 'ping'});
    });
  }

  bool _sendRaw(Map<String, dynamic> frame) {
    final ws = _ws;
    if (ws == null) return false;
    try {
      ws.sink.add(jsonEncode(frame));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// request/response：发 {type, ...payload, requestId}，等回显 requestId 的帧。
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final requestId =
        'r${++_requestSeq}-${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    final sent = _sendRaw({'type': type, ...payload, 'requestId': requestId});
    DshLog.w('gw -> $type rid=$requestId sent=$sent');
    if (!sent) {
      _pending.remove(requestId);
      throw RequestException('NOT_CONNECTED', '连接未建立，发送失败');
    }
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(requestId);
        throw RequestException('TIMEOUT', '请求 $type 超时');
      },
    );
  }

  // ---- 业务封装 ----

  Future<List<DshWorkspace>> workspaces() async {
    final r = await request('workspaces', const {});
    final list = r['workspaces'] as List? ?? const [];
    return list
        .map((e) => DshWorkspace.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<DshSession>> sessions() async {
    final r = await request('sessions', const {});
    final list = r['sessions'] as List? ?? const [];
    return list
        .map((e) => DshSession.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<HistoryPage> history(String sessionId, {int? maxMessages}) async {
    final r = await request('history', {
      'sessionId': sessionId,
      'maxMessages': ?maxMessages,
    });
    final events = r['events'] as List? ?? const [];
    return HistoryPage.fromEvents(events);
  }

  /// 发消息。sessionId 省略则服务端自动建会话（响应携带新 sessionId）。
  Future<String?> sendText({
    String? sessionId,
    required String text,
    String mode = 'queue',
  }) async {
    final r = await request('message', {
      'sessionId': ?sessionId,
      'mode': mode,
      'content': [PromptPart.text(text).toJson()],
      'clientTimeZone': DshDevice.ianaZone,
    });
    return r['sessionId'] as String? ?? sessionId;
  }

  /// 停止当前回合（对照 companion ChatHeader 的「停止运行」）。
  /// session-cancelled 应答不在 REQUEST_ID_ECHO_EXCLUDED_KINDS 排除表里，
  /// 会经 withRequestIdEcho 注入 data.requestId（ws-protocol.ts:611），因此
  /// 可以像其它请求一样 await（ws-sessions.ts:93-102：缺 sessionId 回
  /// MISSING_PARAMS，否则 chat.cancel 后回 {kind:'session-cancelled'}）。
  Future<void> cancelTurn(String sessionId) async {
    await request('session-cancel', {'sessionId': sessionId});
  }

  /// 订阅会话推送。subscribed 帧在 bridge 的 REQUEST_ID_ECHO_EXCLUDED_KINDS
  /// 排除表里（不回显 requestId），不能走 request() 等应答——发出即成功，
  /// 与 kotlin-sdk MobileGatewayClient.subscribe() 一致。
  void subscribe(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return;
    _sendRaw({'type': 'subscribe', 'sessionId': sessionId});
  }

  void dispose() {
    _disposed = true;
    _teardown();
    _stateCtrl.close();
    _eventCtrl.close();
  }
}
