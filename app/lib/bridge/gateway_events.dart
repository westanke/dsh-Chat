/// 网关推送事件与请求异常类型（从 gateway.dart 拆出：宪法 §7 单文件 ≤500 行）。
///
/// 网关事件由 `GatewayClient.events` 广播；UI（chat_state.dart）消费。
/// 会话内核事件（`chat.session.event`）：实时流只带 {sessionId, eventType, seq}，
/// **不带事件体**（bridge chat-adapter.ts 的 base 就这三个字段）——工具调用因此
/// 拿不到 name/arguments，UI 只能靠重拉 history 拿完整明细；这里把 eventType
/// 透出来，让上层决定「值得重拉」的类型（tool/call 等）。
library;

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

class SessionEventReceived extends GatewayEvent {
  SessionEventReceived(this.sessionId, this.eventType);
  final String sessionId;
  final String eventType;
}

/// WS 请求 / REST 通道共用的错误（code 是稳定的错误名，如 HTTP_404/TIMEOUT）。
class RequestException implements Exception {
  RequestException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RequestException($code): $message';
}
