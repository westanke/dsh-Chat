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
    // 一次掉线在 @ohos webSocket 上常常连发 error + close 两个回调；
    // 不去重会让状态机同一次掉线排两次退避（真机实证：1s 档被 2s 档顶掉）。
    let settled: boolean = false;
    let downSent: boolean = false;
    const settleOnce = (): void => {
      if (!settled) {
        settled = true;
        clearTimeout(timeoutId);
      }
    };
    /** onDown 去重：真正的「第一次上报掉线」返回 true，其余返回 false。 */
    const claimDown = (): boolean => {
      settleOnce();
      if (downSent) {
        return false;
      }
      downSent = true;
      return true;
    };
    const timeoutId: number = setTimeout((): void => {
      if (!settled) {
        settled = true;
        Dlog.warn('[ws] connect timeout');
        if (!downSent) {
          downSent = true;
          callbacks.onDown('timeout');
        }
      }
    }, connectTimeoutMs);

    socket.on('open', (err: BusinessError | undefined): void => {
      if (err) {
        return;
      }
      settleOnce();
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
      // ArrayBuffer 非 JSON 文本帧（协议 v3 全是文本），忽略。
    });

    socket.on('close', (err: BusinessError | undefined,
      value: webSocket.CloseResult): void => {
      // close code 透传给 core：4001 = 令牌/设备被吊销（重连无意义）、
      // 1009 = 单帧超 1 MiB。拿不到就当 0（core 按普通掉线处理）。
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
      if (claimDown()) {
        callbacks.onDown(why, code);
      }
    });

    socket.on('error', (err: BusinessError): void => {
      Dlog.warn('[ws] error ' + err.message);
      if (claimDown()) {
        callbacks.onDown('error');
      }
    });

    const connectOptions: webSocket.WebSocketRequestOptions = {
      header: headersLower,
      protocol: subprotocol,
    };
    socket.connect(url, connectOptions, (err: BusinessError | undefined): void => {
      if (err) {
        Dlog.warn('[ws] connect callback err=' + err.message);
        if (claimDown()) {
          callbacks.onDown('error:' + err.message);
        }
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
