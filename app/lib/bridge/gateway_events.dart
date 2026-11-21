/// 网关推送事件与请求异常类型（从 gateway.dart 拆出：宪法 §7 单文件 ≤500 行）。
///
/// 网关事件由 `GatewayClient.events` 广播；UI（chat_state.dart）消费。
/// 会话内核事件（`chat.session.event`）：实时流只带 {sessionId, eventType, seq}，
/// **不带事件体**（bridge chat-adapter.ts 的 base 就这三个字段）——工具调用因此
/// 拿不到 name/arguments，UI 只能靠重拉 history 拿完整明细；这里把 eventType
/// 透出来，让上层决定「值得重拉」的类型（tool/call 等）。
library;

import 'models.dart';
import 'questions.dart';
import 'queue.dart';

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

/// 轮开始（桥一直在发 chat.turn.start，此前未消费）。
class TurnStartedEvent extends GatewayEvent {
  TurnStartedEvent(this.sessionId);
  final String sessionId;
}

/// 轮结束（chat.turn.end）：官方轮状态判据（client.js:4935 turnLocation
/// status、:4941 outerHidden=turnClosed）；alwaysOpen 判
/// reason.kind∈{aborted,interrupted,error}。
class TurnEndedEvent extends GatewayEvent {
  TurnEndedEvent(this.sessionId, this.reasonKind);
  final String sessionId;

  /// payload.reason.kind（宽容解析：缺帧/缺 kind → null）。
  final String? reasonKind;
}

class ResyncEvent extends GatewayEvent {
  ResyncEvent(this.dropped);
  final int dropped;
}

/// 连接被服务端关闭（非 1000/1005 的正常收尾）。桥的语义化关闭码：
/// - 4001 鉴权失败/设备已吊销（ws-handler `close(4001,'Device revoked')`）——
///   重连无意义，收口到 [GatewayState.authFailed]，用户须重新配对；
/// - 1009 单帧超过 1 MiB（桥的帧上限）——客户端发了过大请求；
/// - 1013 服务端忙（连接数上限，HTTP 层伴随 429 + Retry-After: 5）。
/// 老实现不读 close code，把三类全当普通掉线（companion 坑位「WS 半死/掉线
/// 不分因」），用户只看到「已断开」，不知道该重新配对还是等。
class LinkClosedEvent extends GatewayEvent {
  LinkClosedEvent(this.code, this.reason);
  final int? code;
  final String? reason;

  bool get revoked => code == 4001;
  bool get frameTooLarge => code == 1009;
}

class SessionEventReceived extends GatewayEvent {
  SessionEventReceived(this.sessionId, this.eventType);
  final String sessionId;
  final String eventType;
}

/// DSH 向用户提问（chat.userQuestions/requested；replay 同形状带 replayed）。
class QuestionRequestedEvent extends GatewayEvent {
  QuestionRequestedEvent(this.question);
  final PendingQuestion question;
}

/// 提问已结算（chat.userQuestions/answered|dismissed：电脑端先答 / 超时 / 中止）。
class QuestionResolvedEvent extends GatewayEvent {
  QuestionResolvedEvent(this.sessionId, this.callId);
  final String sessionId;
  final String callId;
}

/// 工具审批请求（chat.approval.requested，chat-adapter.ts:1477-1492）。
class ApprovalRequestedEvent extends GatewayEvent {
  ApprovalRequestedEvent(this.approval);
  final PendingApproval approval;
}

/// 审批已结算（chat.approval.resolved：其他端已决定）。
class ApprovalResolvedEvent extends GatewayEvent {
  ApprovalResolvedEvent(this.sessionId, this.approvalId);
  final String sessionId;
  final String approvalId;
}

/// 模型目录更新推送（chat.models.updated，桥 v2.11.0 新增，issue #1 适配；
/// data={provider}，插在 chat.agent-preset.selected 事件族后）。
/// App 的模型面板每次打开都重拉 models 帧（数据天然新鲜），本事件目前仅
/// 上抛到事件流留扩展点，不改变 UI 行为。
class ModelsUpdatedEvent extends GatewayEvent {
  ModelsUpdatedEvent(this.provider);
  final String? provider;
}

/// 工具开始执行（chat.tool.call，桥 fdb85da 起：工具调用有了自己的帧，
/// 不再只能靠 chat.session.event 重拉 history；参数已定稿，覆盖 preparing 行）。
class ToolCallEvent extends GatewayEvent {
  ToolCallEvent(this.call);
  final ToolCallStarted call;
}

/// 工具结果（chat.tool.result：message.role='tool' + error.code 内核分类）。
class ToolResultEvent extends GatewayEvent {
  ToolResultEvent(this.result);
  final ToolCallOutcome result;
}

/// 队列快照推送（`queue-item-updated`，bridge 22a5223 / IKX2AE）：
/// 整份快照（不是增量），只推已订阅会话。
class QueueUpdatedEvent extends GatewayEvent {
  QueueUpdatedEvent(this.sessionId, this.queue);

  final String sessionId;
  final List<QueueEntry> queue;
}

/// WS 请求 / REST 通道共用的错误（code 是稳定的错误名，如 HTTP_404/TIMEOUT）。
class RequestException implements Exception {
  RequestException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RequestException($code): $message';
}
