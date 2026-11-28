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

/// 会话轮状态（`chat.session.status`，桥 host 级推：与跟随流无关，
/// 所以能补上「tail 帧丢了」时的结束判据）。
///
/// 语义：`running=false` = 该会话已无在跑的轮。正常收尾时 turn/end 先到、
/// 这条紧随其后；**只有 turn/end 丢了**（老桥 / 断流）它才是有用的兜底。
class SessionStatusEvent extends GatewayEvent {
  SessionStatusEvent(this.sessionId, this.running);
  final String sessionId;
  final bool running;
}

class ResyncEvent extends GatewayEvent {
  ResyncEvent(this.dropped);
  final int dropped;
}

/// 连接被服务端关闭（非 1000/1005 的正常收尾）。桥的语义化关闭码：
/// - 4001 鉴权失败/设备已吊销（ws-handler `close(4001,'Device revoked')`）——
///   重连无意义，收口到 [GatewayState.authFailed]，用户须重新配对；
/// - 1009 单帧超过 hello 下发的 maxFrameBytes（老桥缺省 1 MiB）——客户端发了过大请求；
/// - 1013 服务端忙（连接数上限，HTTP 层伴随 429 + Retry-After: 5）。
/// 老实现不读 close code，把三类全当普通掉线（companion 坑位「WS 半死/掉线
/// 不分因」），用户只看到「已断开」，不知道该重新配对还是等。
class LinkClosedEvent extends GatewayEvent {
  LinkClosedEvent(this.code, this.reason, {this.limitBytes});
  final int? code;
  final String? reason;

  /// 这次连接 hello 下发的单帧上限（字节）；仅 1009 提示文案用。
  final int? limitBytes;

  bool get revoked => code == 4001;
  bool get frameTooLarge => code == 1009;

  /// 1013 = 服务端连接数满（HTTP 层伴随 429 + Retry-After）。
  bool get serverBusy => code == 1013;
}

/// 没有 requestId / requestType 可归属的错误帧（服务端主动推送的错误）。
///
/// 普通请求错误由 `RequestException` 直接结算给调用方；这条事件只补
/// 「谁都认领不了」的错误，让 UI 也能看到 retryable/details。
class GatewayErrorEvent extends GatewayEvent {
  GatewayErrorEvent(this.requestType, this.error);
  final String? requestType;
  final RequestException error;
}

/// 单帧上限的人话单位（协议字段是字节，UI 一律按 KiB 展示）。
String frameLimitText(int bytes) => '${(bytes / 1024).ceil()} KiB';

/// 超限提示：图片/大文件走附件，而不是让用户猜为什么发不出去。
String frameLimitHint(int bytes) =>
    '请求内容超过连接上限 ${frameLimitText(bytes)}，图片/大文件请走附件';

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

/// 后台任务推送（`chat.job.updated` / `chat.job.finished`，bridge
/// `src/host/ws-jobs.ts`）：同一个 event 帧，data =
/// `{sessionId, jobId, status, progress?, finishedAt?}`，非终态走 updated、
/// 终态（completed/killed/failed）走 finished，两者形状一致。
///
/// 刻意**不并入 [GatewayEvent]**：任务推送是会话作用域的旁路流
/// （[GatewayClient.jobPushes]），不进聊天时间线的事件穷尽分派——否则每加一类
/// 运维帧都要改 UI 的 switch，且 ChatState 对它毫无兴趣。桥只推已订阅且已授权
/// 的会话，**没有回放**：重连后必须重拉 job-list 才有基线（见 jobs.dart）。
class JobPush {
  const JobPush({
    required this.sessionId,
    required this.jobId,
    required this.status,
    this.progress,
    this.finishedAt,
  });

  factory JobPush.fromJson(Map<String, dynamic> json) => JobPush(
    sessionId: (json['sessionId'] ?? '') as String,
    jobId: (json['jobId'] ?? '') as String,
    status: (json['status'] ?? '') as String,
    progress: json['progress'] is String ? json['progress'] as String : null,
    finishedAt: json['finishedAt'] is int ? json['finishedAt'] as int : null,
  );

  final String sessionId;
  final String jobId;

  /// 线值原样透传：running / stopping / completed / killed / failed。
  final String status;

  /// 运行进度行；终态帧不带（桥在终态清空）。
  final String? progress;

  /// 结束时刻（epoch ms）；通常只有终态帧带。
  final int? finishedAt;

  /// 终态判据按 status 推导（桥的终态集合由协议定死）。
  bool get terminal =>
      status == 'completed' || status == 'killed' || status == 'failed';

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'jobId': jobId,
    'status': status,
    if (progress != null) 'progress': progress,
    if (finishedAt != null) 'finishedAt': finishedAt,
  };
}

/// WS 请求 / REST 通道共用的错误（code 是稳定的错误名，如 HTTP_404/TIMEOUT）。
///
/// bridge 的 error 帧带 retryable（仅上游/内部错误为 true）、statusCode 与
/// details（如 RATE_LIMITED 的 retryAfterMs）。以前只取 code/message，UI 无法
/// 判断「重试有没有意义、要等多久」；字段一路带到 [ChatState.reportError]。
class RequestException implements Exception {
  RequestException(
    this.code,
    this.message, {
    this.retryable = false,
    this.statusCode,
    this.details,
  });
  final String code;
  final String message;
  final bool retryable;
  final int? statusCode;
  final Map<String, dynamic>? details;

  /// 服务端限流。
  bool get rateLimited => code == 'RATE_LIMITED' || statusCode == 429;

  /// RATE_LIMITED 的 details.retryAfterMs（缺省/形状不对为 null）。
  int? get retryAfterMs {
    final raw = details?['retryAfterMs'];
    if (raw is int) return raw >= 0 ? raw : null;
    if (raw is num) return raw >= 0 ? raw.toInt() : null;
    return null;
  }

  /// 等待秒数（向上取整，UI 显示「约 N 秒后再试」）。
  int? get retryAfterSeconds {
    final ms = retryAfterMs;
    return ms == null ? null : (ms / 1000).ceil();
  }

  @override
  String toString() => 'RequestException($code): $message';
}
