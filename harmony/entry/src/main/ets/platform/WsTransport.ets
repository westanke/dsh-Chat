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
    const socket = webSocket.createWebSocket();
    const subprotocol: string = protocol.length > 0 ? protocol : SUBPROTOCOL_FALLBACK;

    // @ohos 的 header 是 Record；core 口径键是小写。
    const headersLower: Record<string, string> = {};
    headers.forEach((value: string, key: string): void => {
      headersLower[key.toLowerCase()] = value;
    });

    // core 接口同步返回句柄；连接过程通过 callbacks 上报（onDown 恰好一次）。
    let settled: boolean = false;
    const settleOnce = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeoutId);
      }
    };
    const timeoutId: number = setTimeout((): void => {
      if (!settled) {
        settled = true;
        callbacks.onDown('timeout');
      }
    }, connectTimeoutMs);

    socket.on('open', (err: BusinessError | undefined): void => {
      if (err) {
        return;
      }
      settleOnce();
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
      // ArrayBuffer 非 JSON 文本帧（协议 v3 全是文本），忽略。
    });

    socket.on('close', (err: BusinessError | undefined): void => {
      settleOnce();
      callbacks.onDown('close');
    });

    socket.on('error', (err: BusinessError): void => {
      settleOnce();
      callbacks.onDown('error');
    });

    const connectOptions: webSocket.WebSocketRequestOptions = {
      header: headersLower,
      protocol: subprotocol,
    };
    socket.connect(url, connectOptions, (err: BusinessError | undefined): void => {
      if (err && !settled) {
        settleOnce();
        callbacks.onDown('error:' + err.message);
      }
    });

    const handle: EventSocketHandle = {
      send: (text: string): void => {
        socket.send(text).catch((e: BusinessError): void => {
          Dlog.warn('ws send failed: ' + e.message);
        });
      },
      close: (): void => {
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
