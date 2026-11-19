/**
 * Gateway 状态与事件 —— 对照 app/lib/bridge/gateway_events.dart（88 行）。
 *
 * ArkTS 无「sealed class 层级」，事件照 core/Content.ts PromptPart 的扁平口径：
 * 单一 GatewayEvent 类 + type 常量 + 全默认值字段，按 type 分派消费。
 * 字段宽容：fromFrame 缺键/类型不符一律默认值，绝不抛异常（姊妹仓同款规矩）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { MessageDelta, MessageCommitted, ToolCallEvent, ToolResultEvent } from './Models';
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
  /** chat.tool.call：工具开始执行（bridge 原样透传内核事件）。 */
  static readonly TOOL_CALL: string = 'toolCall';
  /** chat.tool.result：工具结果（含 error.code 失败分类）。 */
  static readonly TOOL_RESULT: string = 'toolResult';
  /** chat.turn.start：一轮开始（bridge 常发，此前未接）。 */
  static readonly TURN_START: string = 'turnStart';
  /** chat.turn.end：一轮结束（reason.kind 判收起/截断提示，官方 client.js:4935）。 */
  static readonly TURN_END: string = 'turnEnd';
  /** 连接被服务端语义化关闭（4001 吊销 / 1009 帧超限），UI 提示用。 */
  static readonly LINK_CLOSED: string = 'linkClosed';
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
  toolCall: ToolCallEvent | null = null;
  toolResult: ToolResultEvent | null = null;
  /** turn.end 的 reason.kind（'aborted'|'interrupted'|'error'|'max-tokens'|…；''=无）。 */
  turnReasonKind: string = '';
  /** linkClosed 的 WS close code（4001 吊销 / 1009 帧超限；0=未携带）。 */
  linkCode: number = 0;
  /** linkClosed 的 close reason 原文。 */
  linkReason: string = '';

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

  static turnStarted(sessionId: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.TURN_START;
    e.sessionId = sessionId;
    return e;
  }

  static turnEnded(sessionId: string, reasonKind: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.TURN_END;
    e.sessionId = sessionId;
    e.turnReasonKind = reasonKind;
    return e;
  }

  static linkClosed(code: number, reason: string): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.LINK_CLOSED;
    e.linkCode = code;
    e.linkReason = reason;
    return e;
  }

  static toolCall(call: ToolCallEvent): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.TOOL_CALL;
    e.sessionId = call.sessionId;
    e.toolCall = call;
    return e;
  }

  static toolResult(result: ToolResultEvent): GatewayEvent {
    const e: GatewayEvent = new GatewayEvent();
    e.type = GatewayEventType.TOOL_RESULT;
    e.sessionId = result.sessionId;
    e.toolResult = result;
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

/** 事件帧 → GatewayEvent（十三支映射，纯函数；未知 type 回 null 由调用方忽略）。 */
export function eventFromFrame(data: JsonMap | null): GatewayEvent | null {
  if (data === null) {
    return null;
  }
  const rawType: string = JsonAccess.strOr(data, 'type', '');
  // 真实帧外层带 `chat.` 前缀（bridge normalizeDshEvent：`chat.${payload.type}`），
  // 历史测试桩/部分旧帧不带；统一剥前缀再比，两形状都认。
  const etype: string = rawType.startsWith('chat.') ? rawType.substring(5) : rawType;
  const sessionId: string = JsonAccess.strOr(data, 'sessionId', '');
  // 事件体在内层 data（Android gateway.dart:219 `payload = data['data']`）；
  // 缺内层时退回外层，兼容只带一层字段的旧帧/测试桩。
  const inner: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(data, 'data'));
  const payload: JsonMap = inner !== null ? inner : data;
  // sessionId 内外层都可能带：内层优先，退回外层。
  const innerSid: string = JsonAccess.strOr(payload, 'sessionId', '');
  const payloadSessionId: string = innerSid !== '' ? innerSid : sessionId;
  if (etype === 'message.delta') {
    return GatewayEvent.delta(MessageDelta.fromJson(payload));
  }
  if (etype === 'message.committed') {
    return GatewayEvent.committed(MessageCommitted.fromJson(payload));
  }
  if (etype === 'turn.start') {
    return GatewayEvent.turnStarted(payloadSessionId);
  }
  if (etype === 'turn.end') {
    const reason: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(payload, 'reason'));
    return GatewayEvent.turnEnded(payloadSessionId, JsonAccess.strOr(reason, 'kind', ''));
  }
  if (etype === 'turn.failed') {
    return GatewayEvent.turnFailed(sessionId, JsonAccess.strOr(payload, 'message', '执行失败'));
  }
  if (etype === 'session.event') {
    return GatewayEvent.sessionEvent(payloadSessionId, JsonAccess.strOr(payload, 'eventType', ''));
  }
  if (etype === 'userQuestions/requested') {
    return GatewayEvent.questionRequested(PendingQuestion.fromJson(payloadSessionId, payload));
  }
  if (etype === 'userQuestions/answered' || etype === 'userQuestions/dismissed') {
    return GatewayEvent.questionResolved(payloadSessionId, JsonAccess.strOr(payload, 'callId', ''));
  }
  if (etype === 'approval.requested') {
    return GatewayEvent.approvalRequested(PendingApproval.fromJson(payloadSessionId, payload));
  }
  if (etype === 'approval.resolved') {
    return GatewayEvent.approvalResolved(payloadSessionId, JsonAccess.strOr(payload, 'approvalId', ''));
  }
  if (etype === 'deliverables.presented') {
    // 帧里只有 files+seq，不就地插卡，转会话事件防抖重拉 history。
    return GatewayEvent.sessionEvent(payloadSessionId, 'deliverables/presented');
  }
  if (etype === 'tool.call') {
    return GatewayEvent.toolCall(ToolCallEvent.fromJson(payload));
  }
  if (etype === 'tool.result') {
    return GatewayEvent.toolResult(ToolResultEvent.fromJson(payload));
  }
  if (etype === 'models.updated') {
    return GatewayEvent.modelsUpdated(JsonAccess.strOr(payload, 'provider', ''));
  }
  // 其余事件忽略（Android 同口径）。
  return null;
}
