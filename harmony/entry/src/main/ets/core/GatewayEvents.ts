/**
 * Gateway 状态与事件 —— 对照 app/lib/bridge/gateway_events.dart（88 行）。
 *
 * ArkTS 无「sealed class 层级」，事件照 core/Content.ts PromptPart 的扁平口径：
 * 单一 GatewayEvent 类 + type 常量 + 全默认值字段，按 type 分派消费。
 * 字段宽容：fromFrame 缺键/类型不符一律默认值，绝不抛异常（姊妹仓同款规矩）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { MessageDelta, MessageCommitted } from './Models';
import { PendingQuestion, PendingApproval } from './Questions';

/** 长连接状态机（Android GatewayState 同款五态）。 */
export enum GatewayState {
  IDLE = 0,
  CONNECTING = 1,
  READY = 2,
  CLOSED = 3,
  AUTH_FAILED = 4,
}

/** 事件类型常量（消费方 switch 用）。 */
export class GatewayEventType {
  static readonly DELTA: string = 'delta';
  static readonly COMMITTED: string = 'committed';
  static readonly TURN_FAILED: string = 'turnFailed';
  static readonly RESYNC: string = 'resync';
  static readonly SESSION_EVENT: string = 'sessionEvent';
  static readonly QUESTION_REQUESTED: string = 'questionRequested';
  static readonly QUESTION_RESOLVED: string = 'questionResolved';
  static readonly APPROVAL_REQUESTED: string = 'approvalRequested';
  static readonly APPROVAL_RESOLVED: string = 'approvalResolved';
  static readonly MODELS_UPDATED: string = 'modelsUpdated';
}

/**
 * 事件总线上的单条事件。各形态字段全默认值，只读自己关心的 type 对应字段。
 * （Android 的 sealed GatewayEvent 系在此收敛为一个扁平类。）
 */
export class GatewayEvent {
  type: string = '';
  delta: MessageDelta | null = null;
  committed: MessageCommitted | null = null;
  sessionId: string = '';
  /** turnFailed 的错误文案 / sessionEvent 的 eventType。 */
  message: string = '';
  /** resync：服务端明确 dropped（丢历史，需全量重拉）。 */
  dropped: boolean = false;
  question: PendingQuestion | null = null;
  callId: string = '';
  approval: PendingApproval | null = null;
  approvalId: string = '';
  /** modelsUpdated 的新 provider（可空语义：'' 表示未携带）。 */
  provider: string = '';

  static delta(d: MessageDelta): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.DELTA;
    e.delta = d;
    return e;
  }

  static committed(c: MessageCommitted): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.COMMITTED;
    e.committed = c;
    return e;
  }

  static turnFailed(sessionId: string, message: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.TURN_FAILED;
    e.sessionId = sessionId;
    e.message = message;
    return e;
  }

  static resync(dropped: boolean): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.RESYNC;
    e.dropped = dropped;
    return e;
  }

  static sessionEvent(sessionId: string, eventType: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.SESSION_EVENT;
    e.sessionId = sessionId;
    e.message = eventType;
    return e;
  }

  static questionRequested(q: PendingQuestion): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.QUESTION_REQUESTED;
    e.question = q;
    return e;
  }

  static questionResolved(sessionId: string, callId: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.QUESTION_RESOLVED;
    e.sessionId = sessionId;
    e.callId = callId;
    return e;
  }

  static approvalRequested(a: PendingApproval): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.APPROVAL_REQUESTED;
    e.approval = a;
    return e;
  }

  static approvalResolved(sessionId: string, approvalId: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.APPROVAL_RESOLVED;
    e.sessionId = sessionId;
    e.approvalId = approvalId;
    return e;
  }

  static modelsUpdated(provider: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.MODELS_UPDATED;
    e.provider = provider;
    return e;
  }
}

/**
 * 稳定错误码请求异常（Android RequestException 同款，code 形如 HTTP_404/TIMEOUT/NO_TOKEN）。
 * ArkTS 允许 extends Error（姊妹仓 DshApiException 先例）。
 */
export class RequestException extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/** 从服务器 error 帧收敛错误码（宽容：缺 code 用 REQUEST_FAILED）。 */
export function requestExceptionFromFrame(data: JsonMap | null): RequestException {
  const code: string = JsonAccess.strOr(data, 'code', 'REQUEST_FAILED');
  const message: string = JsonAccess.strOr(data, 'message', '');
  return new RequestException(code, message);
}

/** 事件帧 → GatewayEvent（十一支映射，纯函数；未知 type 回 null 由调用方忽略）。 */
export function eventFromFrame(data: JsonMap | null): GatewayEvent | null {
  if (data === null) {
    return null;
  }
  const etype: string = JsonAccess.strOr(data, 'type', '');
  const sessionId: string = JsonAccess.strOr(data, 'sessionId', '');
  if (etype === 'chat.message.delta') {
    return GatewayEvent.delta(MessageDelta.fromJson(data));
  }
  if (etype === 'chat.message.committed') {
    return GatewayEvent.committed(MessageCommitted.fromJson(data));
  }
  if (etype === 'chat.turn.failed') {
    return GatewayEvent.turnFailed(sessionId, JsonAccess.strOr(data, 'message', '执行失败'));
  }
  if (etype === 'chat.session.event') {
    return GatewayEvent.sessionEvent(sessionId, JsonAccess.strOr(data, 'eventType', ''));
  }
  if (etype === 'userQuestions/requested') {
    return GatewayEvent.questionRequested(PendingQuestion.fromJson(sessionId, data));
  }
  if (etype === 'userQuestions/answered' || etype === 'userQuestions/dismissed') {
    return GatewayEvent.questionResolved(sessionId, JsonAccess.strOr(data, 'callId', ''));
  }
  if (etype === 'approval.requested') {
    return GatewayEvent.approvalRequested(PendingApproval.fromJson(sessionId, data));
  }
  if (etype === 'approval.resolved') {
    return GatewayEvent.approvalResolved(sessionId, JsonAccess.strOr(data, 'approvalId', ''));
  }
  if (etype === 'chat.deliverables.presented') {
    // 帧里只有 files+seq，不就地插卡，转会话事件防抖重拉 history。
    return GatewayEvent.sessionEvent(sessionId, 'deliverables/presented');
  }
  if (etype === 'chat.models.updated') {
    return GatewayEvent.modelsUpdated(JsonAccess.strOr(data, 'provider', ''));
  }
  // 其余事件忽略（Android 同口径）。
  return null;
}
