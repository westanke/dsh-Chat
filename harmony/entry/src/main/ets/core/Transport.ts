/**
 * 平台传输注入点 —— 对照姊妹仓 dsh-companion-harmony 的 core/DshTransport.ts 口径。
 *
 * core 层只声明「平台能给我什么」（HttpTransport / WebSocketTransport / TimerBridge），
 * 平台层（entry/src/main/ets/platform/*.ets，后续接入）实现这些接口；
 * 业务逻辑（GatewayClient / GatewayApi / GatewayRest）永远只依赖接口，
 * 所以 harmony/test/ 用 node 直测（CI 无鸿蒙 SDK 也能跑）。
 *
 * 关键口径（姊妹仓实测 + bridge 仓服务端行为）：
 * - WS 子协议只传 `dsh-mobile-v1` 单值；令牌走 `Authorization: Bearer` 头
 *   （服务端 server.ts 有该 fallback，姊妹仓真机验证过）。
 *   Android 走的 `dsh-auth.<token>` 子协议在 @ohos.net.webSocket 不可配置，不用。
 * - 配对走 REST `POST /api/v1/pairings/exchange`（不走 `dsh-pair.<code>` 子协议，
 *   同上原因）。见 core/GatewayApi.ts pairViaRest()。
 * - HttpResponse.headers 的键必须是小写（平台层负责），header() 大小写不敏感查询才成立。
 */

/** 连接超时（GatewayClient 的 WS ready 等待，Android 口径 10s）。 */
export const WS_CONNECT_TIMEOUT_MS: number = 10000;
/** hello 帧等待超时（Android 口径 8s）。 */
export const WS_HELLO_TIMEOUT_MS: number = 8000;
/** 单次请求默认超时（Android 口径 30s）。 */
export const REQUEST_TIMEOUT_MS: number = 30000;
/** HTTP 默认超时（REST 口径 30s）。 */
export const HTTP_TIMEOUT_MS: number = 30000;
/** WS 心跳间隔（Android 口径 25s）。 */
export const HEARTBEAT_INTERVAL_MS: number = 25000;
/** 重连退避封顶秒数（Android 口径 30s；序列 1,2,4,8,16,30,30…）。 */
export const MAX_BACKOFF_SECONDS: number = 30;
/** 退避序列最大指数（1<<5=32 → min 30）。 */
export const MAX_BACKOFF_INDEX: number = 5;

/** 一次 HTTP 请求的描述（平台无关）。 */
export class HttpRequest {
  method: string = 'GET';
  url: string = '';
  headers: Map<string, string> = new Map();
  /** GET/HEAD 必须为 null。 */
  body: string | null = null;
  timeoutMs: number = HTTP_TIMEOUT_MS;

  constructor(method: string, url: string, headers: Map<string, string>,
              body: string | null, timeoutMs: number) {
    this.method = method;
    this.url = url;
    this.headers = headers;
    this.body = body;
    this.timeoutMs = timeoutMs;
  }
}

/** 一次 HTTP 响应。headers 键由平台层保证为小写。 */
export class HttpResponse {
  status: number = 0;
  headers: Map<string, string> = new Map();
  body: string = '';
  /** 原始字节（二进制端点用；JSON 端点忽略）。平台层填，node 测试可用 null。 */
  bodyBytes: Uint8Array | null = null;

  constructor(status: number, headers: Map<string, string>, body: string) {
    this.status = status;
    this.headers = headers;
    this.body = body;
  }

  isSuccessful(): boolean {
    return this.status >= 200 && this.status < 300;
  }

  /** 大小写不敏感地取响应头；键由平台层保证为小写。 */
  header(name: string): string | null {
    const key: string = name.toLowerCase();
    return this.headers.has(key) ? this.headers.get(key) as string : null;
  }
}

/** 平台 HTTP 实现：`@ohos.net.http` 达成（平台层职责）。 */
export interface HttpTransport {
  request(req: HttpRequest): Promise<HttpResponse>;
}

/** WS 事件回调；`onDown` 在关闭或失败时恰好调用一次。 */
export interface WebSocketCallbacks {
  onOpen(): void;

  onMessage(text: string): void;

  onDown(reason: string): void;
}

/** 已打开的 WS 句柄。 */
export interface EventSocketHandle {
  send(text: string): void;

  close(): void;
}

/**
 * 平台 WS 实现：给定 URL 与握手头，打开长连接。
 * `protocol` 是可选 WS 子协议（Sec-WebSocket-Protocol，单值）：
 * `/ws/mobile` 必须传 `dsh-mobile-v1`。令牌不放子协议，走 Bearer 头。
 */
export interface WebSocketTransport {
  open(url: string, headers: Map<string, string>, callbacks: WebSocketCallbacks,
       protocol: string, connectTimeoutMs: number): EventSocketHandle;
}

/** 延迟执行能力（一次性调度），供心跳与重连退避使用。 */
export interface TimerBridge {
  schedule(delayMs: number, action: () => void): number;

  cancel(handle: number): void;
}

