/**
 * WS 层测试的 Fake 基建（node 测试专用，不要求 ArkTS 兼容）：
 * - FakeTimers：手动推进的 TimerBridge，退避序列/心跳/超时全可控。
 * - FakeSocket：记录 open 参数与 send 帧，测试代码扮演服务端注入帧。
 * - FakeHttp：记录请求并按脚本回 HTTP 响应。
 */

import {
  EventSocketHandle, TimerBridge, WebSocketCallbacks, WebSocketTransport,
  HttpRequest, HttpResponse, HttpTransport,
} from '../../entry/src/main/ets/core/Transport.ts';

interface TimerEntry {
  id: number;
  at: number;
  action: () => void;
}

export class FakeTimers implements TimerBridge {
  private seq: number = 0;
  private now: number = 0;
  entries: TimerEntry[] = [];

  schedule(delayMs: number, action: () => void): number {
    this.seq += 1;
    this.entries.push({ id: this.seq, at: this.now + delayMs, action: action });
    return this.seq;
  }

  cancel(handle: number): void {
    this.entries = this.entries.filter((e: TimerEntry): boolean => e.id !== handle);
  }

  /** 推进虚拟时钟，按到期顺序触发（含重入：action 里新排的 timer 也照跑）。 */
  advance(ms: number): void {
    const target: number = this.now + ms;
    for (;;) {
      let best: TimerEntry | null = null;
      for (const e of this.entries) {
        if (e.at <= target && (best === null || e.at < best.at)) {
          best = e;
        }
      }
      if (best === null) {
        break;
      }
      this.entries = this.entries.filter((e: TimerEntry): boolean => e.id !== best!.id);
      this.now = best.at;
      best.action();
    }
    this.now = target;
  }

  /** 当前最早到期 timer 的延迟（0 = 无 timer）。 */
  nextDelay(): number {
    let best: TimerEntry | null = null;
    for (const e of this.entries) {
      if (best === null || e.at < best.at) {
        best = e;
      }
    }
    return best === null ? 0 : best.at - this.now;
  }

  pendingCount(): number {
    return this.entries.length;
  }
}

export class FakeSocket implements WebSocketTransport {
  lastUrl: string = '';
  lastHeaders: Map<string, string> = new Map();
  lastProtocol: string = '';
  lastTimeoutMs: number = 0;
  callbacks: WebSocketCallbacks | null = null;
  sent: string[] = [];
  closedCount: number = 0;
  private openCount: number = 0;

  open(url: string, headers: Map<string, string>, callbacks: WebSocketCallbacks,
       protocol: string, connectTimeoutMs: number): EventSocketHandle {
    this.lastUrl = url;
    this.lastHeaders = headers;
    this.callbacks = callbacks;
    this.lastProtocol = protocol;
    this.lastTimeoutMs = connectTimeoutMs;
    this.openCount += 1;
    const self: FakeSocket = this;
    return {
      send(text: string): void {
        self.sent.push(text);
      },
      close(): void {
        self.closedCount += 1;
      },
    };
  }

  openCountOf(): number {
    return this.openCount;
  }

  // ---- 测试代码扮演服务端 ----

  serverOpen(): void {
    if (this.callbacks !== null) {
      this.callbacks.onOpen();
    }
  }

  serverFrame(frame: Record<string, unknown> | string): void {
    if (this.callbacks === null) {
      return;
    }
    this.callbacks.onMessage(typeof frame === 'string'
      ? frame
      : JSON.stringify(frame));
  }

  /** 最后发出帧里的 requestId（客户端→服务端；无则空串）——配回应答帧用。 */
  lastRequestId(): string {
    if (this.sent.length === 0) {
      return '';
    }
    const frame: Record<string, unknown> =
      JSON.parse(this.sent[this.sent.length - 1]) as Record<string, unknown>;
    return typeof frame['requestId'] === 'string' ? frame['requestId'] as string : '';
  }

  serverHello(protocol: number = 3, requestId: string = ''): void {
    this.serverFrame({ kind: 'hello', data: { protocol, device: { platform: 'test' } },
      requestId });
  }

  serverDown(reason: string): void {
    if (this.callbacks !== null) {
      this.callbacks.onDown(reason);
    }
  }

  /** 最后发出的一帧（客户端→服务端）。 */
  lastSent(): Record<string, unknown> {
    return JSON.parse(this.sent[this.sent.length - 1]) as Record<string, unknown>;
  }

  lastSentOf(n: number): Record<string, unknown> {
    return JSON.parse(this.sent[this.sent.length - 1 - n]) as Record<string, unknown>;
  }
}

export class FakeHttp implements HttpTransport {
  requests: HttpRequest[] = [];
  /** 队列式应答：每个请求按顺序弹出一个；空了回 200 {}。 */
  responses: HttpResponse[] = [];

  request(req: HttpRequest): Promise<HttpResponse> {
    this.requests.push(req);
    const resp: HttpResponse = this.responses.length > 0
      ? (this.responses.shift() as HttpResponse)
      : new HttpResponse(200, new Map<string, string>(), '{}');
    return Promise.resolve(resp);
  }

  push(status: number, body: string): void {
    this.responses.push(new HttpResponse(status, new Map<string, string>(), body));
  }
}
