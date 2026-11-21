/**
 * WebSocket 传输 —— core/Transport.ts WebSocketTransport 的平台实现。
 * @ohos.net.webSocket：子协议走 protocol 选项，令牌走 header（core 口径：
 * 只传单子协议 dsh-mobile-v1，Authorization Bearer 头带令牌）。
 */

import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type {
  WebSocketTransport, WebSocketCallbacks, EventSocketHandle,
} from '../core/Transport';
import { Dlog } from './Dlog';

const SUBPROTOCOL_FALLBACK: string = 'dsh-mobile-v1';

export class WsTransport implements WebSocketTransport {
  open(url: string, headers: Map<string, string>, callbacks: WebSocketCallbacks,
    protocol: string, connectTimeoutMs: number): EventSocketHandle {
    const headersLower: Record<string, string> = {};
    headers.forEach((value: string, key: string): void => {
      headersLower[key.toLowerCase()] = value;
    });
    const preferred: string = protocol.length > 0 ? protocol : SUBPROTOCOL_FALLBACK;
    let current: webSocket.WebSocket | null = null;
    let downSent: boolean = false;
    let fellBack: boolean = false;

    const reportDown = (why: string, code: number = 0): void => {
      if (downSent) {
        return;
      }
      downSent = true;
      callbacks.onDown(why, code);
    };

    /**
     * 建一次连接。`multi` = 本次用的是逗号串清单（`dsh-mobile-v1,dshrb-v1`）。
     *
     * @ohos 的 `protocol` 选项文档只写「子协议字符串」，没承诺接受逗号清单；
     * 若平台按 WebSocket 规范校验 token，带逗号会**直接连接失败**（`ws` 库就
     * throw `An invalid or duplicated subprotocol`）。所以失败时自动退回单协议
     * ——内核面/正文搜索随之降级（`kernelSearchSupportedOn` 为 false），但连接
     * 与老功能不受影响。真机日志会留一条 `[ws] fallback single protocol`。
     */
    const start = (proto: string, multi: boolean): void => {
      const socket = webSocket.createWebSocket();
      current = socket;
      let settled: boolean = false;
      let attemptDown: boolean = false;
      const settle = (): void => {
        settled = true;
        clearTimeout(timer);
      };
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        if (multi && !fellBack) {
          fellBack = true;
          Dlog.warn('[ws] fallback single protocol (timeout)');
          try {
            socket.close().catch((): void => {});
          } catch (e) {
            // 未建成的 socket close 可能抛，忽略。
          }
          start(SUBPROTOCOL_FALLBACK, false);
          return;
        }
        settle();
        reportDown('timeout');
      }, connectTimeoutMs);
      const fail = (why: string, code: number = 0): void => {
        if (settled) {
          return;
        }
        if (multi && !fellBack) {
          fellBack = true;
          Dlog.warn('[ws] fallback single protocol (' + why + ')');
          settled = true;
          clearTimeout(timer);
          try {
            socket.close().catch((): void => {});
          } catch (e) {
            // 同上。
          }
          start(SUBPROTOCOL_FALLBACK, false);
          return;
        }
        if (attemptDown) {
          return;
        }
        attemptDown = true;
        settle();
        reportDown(why, code);
      };

      socket.on('open', (err: BusinessError | undefined): void => {
        if (err) {
          fail('error:' + err.message);
          return;
        }
        if (settled) {
          return;
        }
        settle();
        Dlog.warn('[ws] open ' + url);
        callbacks.onOpen();
      });

      socket.on('message', (err: BusinessError | undefined,
        value: string | ArrayBuffer): void => {
        if (err) {
          return;
        }
        if (typeof value === 'string') {
          callbacks.onMessage(value);
        }
      });

      socket.on('close', (err: BusinessError | undefined,
        value: webSocket.CloseResult): void => {
        let code: number = 0;
        let why: string = 'close';
        if (value !== undefined && value !== null) {
          code = value.code;
          if (value.reason !== undefined && value.reason !== '') {
            why = value.reason;
          }
        }
        Dlog.warn('[ws] close code=' + code.toString() + ' ' + why
          + (err ? ' err=' + err.message : ''));
        // 握手前就关（能力面被拒/协议不符）：先试单协议降级。
        if (!settled && multi && !fellBack) {
          fellBack = true;
          Dlog.warn('[ws] fallback single protocol (close ' + code.toString() + ')');
          settled = true;
          clearTimeout(timer);
          start(SUBPROTOCOL_FALLBACK, false);
          return;
        }
        fail(why, code);
      });

      socket.on('error', (err: BusinessError): void => {
        Dlog.warn('[ws] error ' + err.message);
        fail('error');
      });

      const connectOptions: webSocket.WebSocketRequestOptions = {
        header: headersLower,
        protocol: proto,
      };
      try {
        socket.connect(url, connectOptions, (err: BusinessError | undefined): void => {
          if (err) {
            Dlog.warn('[ws] connect callback err=' + err.message);
            fail('error:' + err.message);
          }
        });
      } catch (e) {
        fail('error:connect throw');
      }
    };

    start(preferred, preferred.indexOf(',') >= 0);
    const handle: EventSocketHandle = {
      send: (text: string): void => {
        const socket: webSocket.WebSocket | null = current;
        if (socket === null) {
          return;
        }
        socket.send(text).catch((e: BusinessError): void => {
          Dlog.warn('ws send failed: ' + e.message);
        });
      },
      close: (): void => {
        const socket: webSocket.WebSocket | null = current;
        if (socket === null) {
          return;
        }
        try {
          socket.close().catch((e: BusinessError): void => {
            // 关闭失败忽略（幂等）。
          });
        } catch (e) {
          // close 异常忽略。
        }
      },
    };
    return handle;
  }
}
