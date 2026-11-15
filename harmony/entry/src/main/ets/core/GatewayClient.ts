/**
 * Gateway 长连接客户端 —— 对照 app/lib/bridge/gateway.dart（410 行）移植。
 *
 * 协议：WS `/ws/mobile`，子协议 `dsh-mobile-v1`，令牌走 `Authorization: Bearer` 头
 * （鸿蒙侧子协议传不了 token，见 core/Transport.ts 文件头；Android 用
 * `dsh-auth.<token>` 子协议，服务端两种都认）。配对走 REST（GatewayApi.pairViaRest）。
 *
 * 语义与 Android 的对齐点：
 * - hello 帧校验 protocol==3，device map 存下来，backoffIndex 归零，进入 READY；
 * - 心跳 25s（自续一次性调度，替代 Android 的 periodic Timer）；
 * - 掉线自动重连，退避 1→2→4→8→16→30→30…秒（1<<index 封顶 30，index 封顶 5）；
 * - 请求超时→TIMEOUT（pending 移除）；未连接发送→NOT_CONNECTED；
 * - subscribe 帧响应不回显 requestId，发出即成功（服务端排除表）。
 * 与 Android 的已知偏差（见 harmony/docs/PORT-MAP.md）：Android 初连失败不自动重连
 * （onDone 不触发）；鸿蒙平台层 open 失败走 onDown，初连失败也会进自动重连
 * ——与姊妹仓 EventsChannel 行为一致（真机验证过），不视为缺陷。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';
import { MessageDelta, MessageCommitted } from './Models';
import { PendingQuestion, PendingApproval } from './Questions';
import { GatewayEvent, GatewayState, RequestException, requestExceptionFromFrame } from './GatewayEvents';
import {
  EventSocketHandle, TimerBridge, WebSocketCallbacks, WebSocketTransport,
  HEARTBEAT_INTERVAL_MS, MAX_BACKOFF_INDEX, MAX_BACKOFF_SECONDS,
  WS_HELLO_TIMEOUT_MS,
} from './Transport';

/** 挂起中的请求（requestId → 结算器 + 超时句柄；姊妹仓 MobileChannel 同款 interface）。 */
interface PendingRequest {
  resolve: (frame: JsonMap) => void;
  reject: (err: Error) => void;
  timer: number;
}

/** 外部依赖注入（平台层提供实现，node 测试用 Fake）。 */
export interface GatewayDeps {
  ws: WebSocketTransport;

  timers: TimerBridge;

  /** 本机 IANA 时区名（Android 走 MethodChannel，鸿蒙由平台层注入）。 */
  timeZoneId(): string;
}

export class GatewayClient {
  private baseUrl: string;
  private deps: GatewayDeps;
  private token: string = '';
  private deviceName: string = '';

  private state: GatewayState = GatewayState.IDLE;
  private handle: EventSocketHandle | null = null;
  private helloTimer: number = -1;
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;
  private backoffIndex: number = 0;
  private requestSeq: number = 0;
  private pending: Map<string, PendingRequest> = new Map();
  private disposed: boolean = false;
  /** 连接代数：每次 connect() 递增；陈旧的 onDown/catch 回调一律忽略。 */
  private attempt: number = 0;

  /** hello 帧里服务端的 device 信息（设备表占位名换真名用）。 */
  private serverDevice: JsonMap | null = null;
  /** hello 是否已结算（初始 true：未连接时 settleHello 是 no-op）。 */
  private helloSettled: boolean = true;
  private helloResolve: (() => void) | null = null;
  private helloReject: ((err: Error) => void) | null = null;

  private listener: ((event: GatewayEvent) => void) | null = null;

  constructor(baseUrl: string, deps: GatewayDeps) {
    this.baseUrl = baseUrl;
    this.deps = deps;
  }

  /** 设置事件监听（UI 层订阅 delta/committed/提问/审批等）。 */
  setEventListener(listener: (event: GatewayEvent) => void): void {
    this.listener = listener;
  }

  getState(): GatewayState {
    return this.state;
  }

  /** REST 拼 URL 用（GatewayApi 的 restJson/fetchAttachment）。 */
  getBaseUrl(): string {
    return this.baseUrl;
  }

  getToken(): string {
    return this.token;
  }

  getServerDevice(): JsonMap | null {
    return this.serverDevice;
  }

  setToken(token: string, deviceName: string): void {
    this.token = token;
    this.deviceName = deviceName;
  }

  /** 鉴权连接（hello 到达即 resolve；失败 reject 稳定错误码）。 */
  connect(): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void, reject: (e: Error) => void) => {
      if (this.token === '') {
        reject(new RequestException('NO_TOKEN', '缺少访问令牌'));
        return;
      }
      if (this.disposed) {
        reject(new RequestException('DISPOSED', '客户端已关闭'));
        return;
      }
      this.state = GatewayState.CONNECTING;
      this.helloSettled = false;
      this.helloResolve = resolve;
      this.helloReject = reject;
      this.attempt += 1;
      const myAttempt: number = this.attempt;

      const headers: Map<string, string> = new Map();
      headers.set('Authorization', 'Bearer ' + this.token);
      const self: GatewayClient = this;
      const callbacks: WebSocketCallbacks = {
        onOpen: (): void => {
          self.armHelloTimeout();
        },
        onMessage: (text: string): void => {
          self.onFrame(text);
        },
        onDown: (reason: string): void => {
          self.onDown(myAttempt, reason);
        },
      };
      this.handle = this.deps.ws.open(this.wsUrl(), headers, callbacks, 'dsh-mobile-v1', 10000);
    });
  }

  /** 携带新令牌重连（换会话/重配对后）。 */
  reconnect(token: string, deviceName: string): Promise<void> {
    this.token = token;
    this.deviceName = deviceName;
    return this.connect();
  }

  /** 关闭并释放；之后不再自动重连。 */
  dispose(): void {
    this.disposed = true;
    this.teardown();
    this.state = GatewayState.CLOSED;
  }

  // ------------------------------------------------------------------
  // 帧收发
  // ------------------------------------------------------------------

  /**
   * 发起一次请求并等待回显（error 帧或超时 reject 稳定错误码）。
   * data 优先取 data.requestId，兜底顶层 requestId（Android 双兜底口径）。
   */
  requestWithTimeout(type: string, payload: JsonMap | null, timeoutMs: number): Promise<JsonMap> {
    return new Promise<JsonMap>((resolve: (d: JsonMap) => void, reject: (e: Error) => void) => {
      const self: GatewayClient = this;
      this.requestSeq += 1;
      const requestId: string = 'r' + this.requestSeq.toString() + '-' + timeoutMs.toString();

      let settled: boolean = false;
      const ok = (data: JsonMap): void => {
        if (settled) {
          return;
        }
        settled = true;
        self.deps.timers.cancel(timer);
        self.pending.delete(requestId);
        resolve(data);
      };
      const fail = (err: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        self.deps.timers.cancel(timer);
        self.pending.delete(requestId);
        reject(err);
      };
      const timer: number = this.deps.timers.schedule(timeoutMs, (): void => {
        fail(new RequestException('TIMEOUT', '请求超时: ' + type));
      });

      if (this.handle === null) {
        fail(new RequestException('NOT_CONNECTED', '连接未就绪'));
        return;
      }
      const pr: PendingRequest = { resolve: ok, reject: fail, timer: timer };
      this.pending.set(requestId, pr);

      const b: WireBuilder = new WireBuilder();
      b.put('type', type);
      if (payload !== null) {
        const keys: string[] = Object.keys(payload);
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i];
          if (k === 'type' || k === 'requestId') {
            continue;
          }
          b.put(k, JsonAccess.raw(payload, k));
        }
      }
      b.put('requestId', requestId);
      this.handle.send(JSON.stringify(b.buildMap()));
    });
  }

  request(type: string, payload: JsonMap | null): Promise<JsonMap> {
    return this.requestWithTimeout(type, payload, 30000);
  }

  /**
   * 订阅会话事件流。subscribe 帧的响应不回显 requestId（服务端排除表），
   * 所以不登记 pending，发出即成功。
   */
  subscribe(sessionId: string): boolean {
    if (this.handle === null) {
      return false;
    }
    const b: WireBuilder = new WireBuilder();
    b.put('type', 'subscribe');
    b.put('sessionId', sessionId);
    this.handle.send(JSON.stringify(b.buildMap()));
    return true;
  }

  // ------------------------------------------------------------------
  // 内部：帧解析
  // ------------------------------------------------------------------

  private onFrame(text: string): void {
    const frame: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(text));
    if (frame === null) {
      return;
    }
    const kind: string = JsonAccess.strOr(frame, 'kind', '');
    const data: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(frame, 'data'));
    // 双兜底：requestId 可能在 data 里，也可能在顶层。
    let requestId: string = '';
    if (data !== null) {
      requestId = JsonAccess.strOr(data, 'requestId', '');
    }
    if (requestId === '') {
      requestId = JsonAccess.strOr(frame, 'requestId', '');
    }

    if (kind === 'hello') {
      this.onHello(data, requestId);
      return;
    }
    if (kind === 'paired') {
      return; // 鸿蒙配对走 REST，配对帧不出现；出现也忽略。
    }
    if (kind === 'pong') {
      return;
    }
    if (kind === 'ping') {
      if (this.handle !== null) {
        const b: WireBuilder = new WireBuilder();
        b.put('type', 'pong');
        this.handle.send(JSON.stringify(b.buildMap()));
      }
      return;
    }
    if (kind === 'event') {
      this.onEventData(data);
      return;
    }
    if (kind === 'connection-resync-required') {
      const dropped: boolean = data !== null && JsonAccess.boolOr(data, 'dropped', false);
      this.emit(GatewayEvent.resync(dropped));
      return;
    }
    if (kind === 'error') {
      const err: RequestException = requestExceptionFromFrame(data);
      const p: PendingRequest | undefined = requestId !== '' ? this.pending.get(requestId) : undefined;
      if (p !== undefined) {
        this.pending.delete(requestId);
        p.reject(err);
      }
      return;
    }
    // 默认：带 requestId 的回显帧 → 结算对应请求。
    const p: PendingRequest | undefined = requestId !== '' ? this.pending.get(requestId) : undefined;
    if (p !== undefined) {
      this.pending.delete(requestId);
      const empty: JsonMap = {};
      p.resolve(data !== null ? data : empty);
    }
  }

  private onHello(data: JsonMap | null, requestId: string): void {
    const protocol: number = JsonAccess.numOr(data, 'protocol', 0);
    if (protocol !== 3) {
      this.settleHello(new RequestException('PROTOCOL', '协议版本不符: ' + protocol.toString()));
      if (this.handle !== null) {
        this.handle.close();
      }
      return;
    }
    this.serverDevice = data !== null ? JsonAccess.obj(data, 'device') : null;
    this.backoffIndex = 0;
    this.state = GatewayState.READY;
    this.cancelHelloTimer();
    this.scheduleHeartbeat();
    this.settleHello(null);
  }

  private onEventData(data: JsonMap | null): void {
    if (data === null) {
      return;
    }
    const etype: string = JsonAccess.strOr(data, 'type', '');
    const sessionId: string = JsonAccess.strOr(data, 'sessionId', '');
    if (etype === 'chat.message.delta') {
      const d: MessageDelta = MessageDelta.fromJson(data);
      this.emit(GatewayEvent.delta(d));
      return;
    }
    if (etype === 'chat.message.committed') {
      const c: MessageCommitted = MessageCommitted.fromJson(data);
      this.emit(GatewayEvent.committed(c));
      return;
    }
    if (etype === 'chat.turn.failed') {
      const msg: string = JsonAccess.strOr(data, 'message', '执行失败');
      this.emit(GatewayEvent.turnFailed(sessionId, msg));
      return;
    }
    if (etype === 'chat.session.event') {
      const ev: string = JsonAccess.strOr(data, 'eventType', '');
      this.emit(GatewayEvent.sessionEvent(sessionId, ev));
      return;
    }
    if (etype === 'userQuestions/requested') {
      const q: PendingQuestion = PendingQuestion.fromJson(sessionId, data);
      this.emit(GatewayEvent.questionRequested(q));
      return;
    }
    if (etype === 'userQuestions/answered' || etype === 'userQuestions/dismissed') {
      const callId: string = JsonAccess.strOr(data, 'callId', '');
      this.emit(GatewayEvent.questionResolved(sessionId, callId));
      return;
    }
    if (etype === 'approval.requested') {
      const a: PendingApproval = PendingApproval.fromJson(sessionId, data);
      this.emit(GatewayEvent.approvalRequested(a));
      return;
    }
    if (etype === 'approval.resolved') {
      const approvalId: string = JsonAccess.strOr(data, 'approvalId', '');
      this.emit(GatewayEvent.approvalResolved(sessionId, approvalId));
      return;
    }
    if (etype === 'chat.deliverables.presented') {
      // 帧里只有 files+seq，不就地插卡，转会话事件防抖重拉 history。
      this.emit(GatewayEvent.sessionEvent(sessionId, 'deliverables/presented'));
      return;
    }
    if (etype === 'chat.models.updated') {
      const provider: string = JsonAccess.strOr(data, 'provider', '');
      this.emit(GatewayEvent.modelsUpdated(provider));
      return;
    }
    // 其余事件忽略（Android 同口径）。
  }

  // ------------------------------------------------------------------
  // 内部：连接生命周期
  // ------------------------------------------------------------------

  private onDown(attemptOfThisConnection: number, reason: string): void {
    if (attemptOfThisConnection !== this.attempt) {
      return; // 陈旧回调（连接已被替换/关闭），忽略。
    }
    const wasReady: boolean = this.state === GatewayState.READY;
    this.teardown();
    // hello 尚未结算时把 connect() 的 Promise 打回去（已结算则是 no-op）。
    this.settleHello(new RequestException('CONNECT_FAIL', '连接中断: ' + reason));

    if (this.disposed || !wasReady) {
      // 未 READY 过（初连失败）：不自动重连，报给调用方（Android 同口径）。
      this.state = GatewayState.CLOSED;
      return;
    }
    // READY 过的连接掉线：自动重连，退避 1,2,4,8,16,30,30…（index 封顶 5）。
    const delay: number = Math.min(1 << this.backoffIndex, MAX_BACKOFF_SECONDS);
    this.backoffIndex = Math.min(this.backoffIndex + 1, MAX_BACKOFF_INDEX);
    this.state = GatewayState.CONNECTING;
    const self: GatewayClient = this;
    const failedAttempt: number = this.attempt;
    this.reconnectTimer = this.deps.timers.schedule(delay * 1000, (): void => {
      self.connect().catch((err: Error): void => {
        // 重连失败（含 CONNECT_FAIL/TIMEOUT/PROTOCOL）：终止重连链。
        // 代数判定防迟到回调覆盖新连接的状态（本轮 attempt 已被更新则不置 CLOSED）。
        if (self.attempt === failedAttempt + 1) {
          self.state = GatewayState.CLOSED;
        }
      });
    });
  }

  private teardown(): void {
    this.cancelHelloTimer();
    this.cancelHeartbeat();
    if (this.reconnectTimer >= 0) {
      this.deps.timers.cancel(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    // 拒绝所有在途请求，避免它们挂到超时（姊妹仓 MobileChannel.close 同款）。
    this.pending.forEach((pr: PendingRequest): void => {
      this.deps.timers.cancel(pr.timer);
      pr.reject(new RequestException('NOT_CONNECTED', '连接已断开'));
    });
    this.pending.clear();
    if (this.handle !== null) {
      this.handle.close();
      this.handle = null;
    }
  }

  private armHelloTimeout(): void {
    const self: GatewayClient = this;
    this.helloTimer = this.deps.timers.schedule(WS_HELLO_TIMEOUT_MS, (): void => {
      if (self.state === GatewayState.READY) {
        return;
      }
      self.settleHello(new RequestException('TIMEOUT', 'hello 超时'));
      if (self.handle !== null) {
        self.handle.close();
      }
    });
  }

  private cancelHelloTimer(): void {
    if (this.helloTimer >= 0) {
      this.deps.timers.cancel(this.helloTimer);
      this.helloTimer = -1;
    }
  }

  /** 心跳自续（一次性调度到期后发 ping 并排下一次）。 */
  private scheduleHeartbeat(): void {
    this.cancelHeartbeat();
    const self: GatewayClient = this;
    this.heartbeatTimer = this.deps.timers.schedule(HEARTBEAT_INTERVAL_MS, (): void => {
      if (self.state !== GatewayState.READY || self.handle === null) {
        return;
      }
      const b: WireBuilder = new WireBuilder();
      b.put('type', 'ping');
      self.handle.send(JSON.stringify(b.buildMap()));
      self.scheduleHeartbeat();
    });
  }

  private cancelHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      this.deps.timers.cancel(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private settleHello(err: Error | null): void {
    if (this.helloSettled) {
      return;
    }
    this.helloSettled = true;
    if (err !== null && this.helloReject !== null) {
      const r: (e: Error) => void = this.helloReject;
      r(err);
    } else if (err === null && this.helloResolve !== null) {
      const r: () => void = this.helloResolve;
      r();
    }
    this.helloResolve = null;
    this.helloReject = null;
  }

  private emit(event: GatewayEvent): void {
    if (this.listener !== null) {
      this.listener(event);
    }
  }

  private wsUrl(): string {
    let url: string = this.baseUrl;
    if (url.indexOf('http://') === 0) {
      url = 'ws://' + url.substring(7);
    } else if (url.indexOf('https://') === 0) {
      url = 'wss://' + url.substring(8);
    }
    while (url.length > 0 && url.charAt(url.length - 1) === '/') {
      url = url.substring(0, url.length - 1);
    }
    return url + '/ws/mobile';
  }

  /** 时区名透传（sendText 的 clientTimeZone 字段用）。 */
  clientTimeZone(): string {
    return this.deps.timeZoneId();
  }
}
