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
import { onFrameOn, requestOn, requestWithTimeoutOn, subscribeOn } from './GatewayRequests';
import { WireBuilder } from './Wire';
import { MessageDelta, MessageCommitted } from './Models';

import { GatewayEvent, GatewayState, RequestException, requestExceptionFromFrame, eventFromFrame } from './GatewayEvents';
import {
  EventSocketHandle, TimerBridge, WebSocketCallbacks, WebSocketTransport,
  HEARTBEAT_INTERVAL_MS, MAX_BACKOFF_INDEX, MAX_BACKOFF_SECONDS,
  WS_HELLO_TIMEOUT_MS,
} from './Transport';

/** 挂起中的请求（requestId → 结算器 + 超时句柄；姊妹仓 MobileChannel 同款 interface）。 */
export interface PendingRequest {
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

  /** 可选诊断出口（真机 hilog 拿不到应用日志时落盘取证用；不传则静默）。 */
  trace?: (message: string) => void;
}

export class GatewayClient {
  private baseUrl: string;
  /** 依赖注入（GatewayFrames 的帧收发函数也用；UI 不直接读）。 */
  deps: GatewayDeps;
  private token: string = '';
  private deviceName: string = '';

  private state: GatewayState = GatewayState.IDLE;
  /** 当前连接句柄（帧收发/心跳/teardown 共用）。 */
  handle: EventSocketHandle | null = null;
  private helloTimer: number = -1;
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;
  private backoffIndex: number = 0;
  /** 请求序号（requestWithTimeout 生成 requestId 用）。 */
  requestSeq: number = 0;
  /** 在途请求表（帧回收 / teardown 拒绝用）。 */
  pending: Map<string, PendingRequest> = new Map();
  private disposed: boolean = false;
  /** 连接代数：每次 connect() 递增；陈旧的 onDown/catch 回调一律忽略。 */
  private attempt: number = 0;
  /**
   * 是否处于「掉线重连链」中。READY 过的连接掉线后置 true：
   * 此后每一次重连尝试失败（TCP 拒连 / 握手失败 / hello 超时）都继续按退避
   * 接力重排，直到连上（onHello 归零）或致命错误（协议不符/令牌缺失）或 dispose()。
   * 真机实证：不加这条，重连那一次失败就永久 CLOSED，必须重启 App（见 PORT-MAP）。
   */
  private reconnecting: boolean = false;
  /**
   * 已处理过掉线回调的连接代数。一次掉线在平台上常常连发 error + close
   * 两个回调；状态机必须只认第一次，否则同一次掉线会排两次退避
   * （真机实证：1s 档被 2s 档顶掉）。0 表示尚无（attempt 从 1 起）。
   */
  private downAttempt: number = 0;

  /** hello 帧里服务端的 device 信息（设备表占位名换真名用）。 */
  private serverDevice: JsonMap | null = null;
  /** hello 是否已结算（初始 true：未连接时 settleHello 是 no-op）。 */
  private helloSettled: boolean = true;
  private helloResolve: (() => void) | null = null;
  private helloReject: ((err: Error) => void) | null = null;

  private listener: ((event: GatewayEvent) => void) | null = null;
  private stateListener: ((state: GatewayState) => void) | null = null;

  constructor(baseUrl: string, deps: GatewayDeps) {
    this.baseUrl = baseUrl;
    this.deps = deps;
  }

  /** 设置事件监听（UI 层订阅 delta/committed/提问/审批等）。 */
  setEventListener(listener: (event: GatewayEvent) => void): void {
    this.listener = listener;
  }

  /** 设置连接状态监听（READY 触发 UI 重拉会话/历史）。 */
  setStateListener(listener: (state: GatewayState) => void): void {
    this.stateListener = listener;
  }

  private traceMsg(message: string): void {
    if (this.deps.trace !== undefined) {
      this.deps.trace(message);
    }
  }

  private applyState(next: GatewayState): void {
    this.traceMsg('state -> ' + next.toString());
    this.state = next;
    if (this.stateListener !== null) {
      this.stateListener(next);
    }
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
      this.applyState(GatewayState.CONNECTING);
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
    this.applyState(GatewayState.CLOSED);
  }

  // ------------------------------------------------------------------
  // 帧收发（实现见 GatewayRequests.ts）
  // ------------------------------------------------------------------

  /**
   * 发起一次请求并等待回显（error 帧或超时 reject 稳定错误码）。
   * data 优先取 data.requestId，兜底顶层 requestId（Android 双兜底口径）。
   */
  requestWithTimeout(type: string, payload: JsonMap | null, timeoutMs: number): Promise<JsonMap> {
    return requestWithTimeoutOn(this, type, payload, timeoutMs);
  }

  request(type: string, payload: JsonMap | null): Promise<JsonMap> {
    return requestOn(this, type, payload);
  }

  /**
   * 订阅会话事件流。subscribe 帧的响应不回显 requestId（服务端排除表），
   * 所以不登记 pending，发出即成功。
   */
  subscribe(sessionId: string): boolean {
    return subscribeOn(this, sessionId);
  }

  // ------------------------------------------------------------------
  // 内部：帧解析（实现见 GatewayRequests.ts）
  // ------------------------------------------------------------------

  private onFrame(text: string): void {
    onFrameOn(this, text, (event: GatewayEvent): void => { this.emit(event); },
      (data: JsonMap | null, requestId: string): void => { this.onHello(data, requestId); });
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
    this.reconnecting = false;
    this.applyState(GatewayState.READY);
    this.cancelHelloTimer();
    this.scheduleHeartbeat();
    this.settleHello(null);
  }

  private onEventData(data: JsonMap | null): void {
    const ev: GatewayEvent | null = eventFromFrame(data);
    if (ev !== null) {
      this.emit(ev);
    }
  }

  // ------------------------------------------------------------------
  // 内部：连接生命周期
  // ------------------------------------------------------------------

  private onDown(attemptOfThisConnection: number, reason: string): void {
    if (attemptOfThisConnection !== this.attempt) {
      return; // 陈旧回调（连接已被替换/关闭），忽略。
    }
    if (attemptOfThisConnection === this.downAttempt) {
      return; // 同一次掉线的第二个回调（error 之后紧跟 close），忽略。
    }
    this.downAttempt = attemptOfThisConnection;
    this.traceMsg('onDown#' + attemptOfThisConnection.toString() + ' ' + reason
      + ' state=' + this.state.toString());
    const wasReady: boolean = this.state === GatewayState.READY;
    this.teardown();
    // hello 尚未结算时把 connect() 的 Promise 打回去（已结算则是 no-op）。
    this.settleHello(new RequestException('CONNECT_FAIL', '连接中断: ' + reason));

    if (this.disposed) {
      this.applyState(GatewayState.CLOSED);
      return;
    }
    // 已经在重连链里：任意一次重连尝试又掉了（TCP 未连上就 close、握手失败），
    // 也继续按退避接力 —— 安卓 _onDone 无条件退避同口径。
    if (!wasReady && !this.reconnecting) {
      // 初连失败（从未 READY 过）：不自动重连，报给调用方（Android 同口径）。
      this.applyState(GatewayState.CLOSED);
      return;
    }
    this.scheduleReconnect();
  }

  /**
   * 排一次退避重连，退避 1,2,4,8,16,30,30…（index 封顶 5）。
   * 重连尝试失败不是终点：继续按同一序列接力，直到成功或致命错误。
   */
  private scheduleReconnect(): void {
    this.reconnecting = true;
    const delay: number = Math.min(1 << this.backoffIndex, MAX_BACKOFF_SECONDS);
    this.backoffIndex = Math.min(this.backoffIndex + 1, MAX_BACKOFF_INDEX);
    this.traceMsg('scheduleReconnect delay=' + delay.toString() + 's');
    this.applyState(GatewayState.CONNECTING);
    const self: GatewayClient = this;
    const failedAttempt: number = this.attempt;
    this.reconnectTimer = this.deps.timers.schedule(delay * 1000, (): void => {
      self.reconnectTimer = -1;
      self.connect().catch((err: Error): void => {
        // 代数判定：本轮 attempt 已被更新说明有新连接在跑，交给它自己收口。
        if (self.attempt !== failedAttempt + 1 || self.disposed) {
          return;
        }
        if (!self.isFatal(err)) {
          // 偶发失败（拒连/握手超时）：留在链里，继续退避。
          if (self.reconnectTimer < 0) {
            self.scheduleReconnect();
          }
          return;
        }
        self.reconnecting = false;
        // 致命错误：链已终止，把残留的 hello 超时/重连 timer 一并清掉。
        self.teardown();
        self.applyState(GatewayState.CLOSED);
      });
    });
  }

  /**
   * 致命错误 —— 重试无用，只有这类才终止重连链（Android 只认 CONNECT_FAIL 之外的
   * 语义更宽，这里取「配置/凭据类」作为不可自愈项，与 bridge 服务端 4001 鉴权失败对齐）。
   */
  private isFatal(err: Error): boolean {
    if (!(err instanceof RequestException)) {
      return false;
    }
    const code: string = (err as RequestException).code;
    return code === 'NO_TOKEN' || code === 'PROTOCOL' || code === 'DISPOSED';
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
