/**
 * HTTP 传输 —— core/Transport.ts HttpTransport 的平台实现（@ohos.net.http）。
 * 口径：响应头键转小写存 Map（core 的 header() 大小写不敏感查询依赖此保证）。
 *
 * ⚠️ PATCH：@ohos http.RequestMethod 没有 PATCH 成员（实测 SDK 枚举只有
 * OPTIONS/GET/HEAD/POST/PUT/DELETE/TRACE/CONNECT）。工作区改名
 * PATCH /api/v1/chat/workspaces/{id} 用字符串 'PATCH' 直接透传底层 netstack，
 * 真机验证阶段确认；失败则在 PORT-MAP 记坑（保底：不支持改名）。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { HttpRequest, HttpResponse } from '../core/Transport';
import type { HttpTransport } from '../core/Transport';

const DEFAULT_TIMEOUT_MS: number = 30000;

function methodOf(name: string): http.RequestMethod {
  if (name === 'POST') {
    return http.RequestMethod.POST;
  }
  if (name === 'PUT') {
    return http.RequestMethod.PUT;
  }
  if (name === 'DELETE') {
    return http.RequestMethod.DELETE;
  }
  if (name === 'PATCH') {
    // RequestMethod 无 PATCH 成员，字符串透传（见文件头注释）。
    return 'PATCH' as Object as http.RequestMethod;
  }
  return http.RequestMethod.GET;
}

export class HttpTransportImpl implements HttpTransport {
  request(req: HttpRequest): Promise<HttpResponse> {
    return new Promise<HttpResponse>((resolve: (r: HttpResponse) => void,
      reject: (e: Error) => void): void => {
      const client = http.createHttp();
      const headerOut: Record<string, string> = {};
      req.headers.forEach((value: string, key: string): void => {
        headerOut[key] = value;
      });
      const options: http.HttpRequestOptions = {
        method: methodOf(req.method),
        header: headerOut,
        connectTimeout: req.timeoutMs,
        readTimeout: req.timeoutMs,
      };
      if (req.body !== null && req.body.length > 0) {
        options.extraData = req.body;
      }
      client.request(req.url, options).then((resp: http.HttpResponse): void => {
        const headers: Map<string, string> = new Map();
        const rawHeader: Record<string, string> =
          resp.header as Record<string, string>;
        const keys: string[] = Object.keys(rawHeader);
        for (const k of keys) {
          const v: string | undefined = rawHeader[k];
          if (typeof v === 'string') {
            headers.set(k.toLowerCase(), v);
          }
        }
        let bodyText = '';
        let rawBytes: Uint8Array | null = null;
        if (typeof resp.result === 'string') {
          bodyText = resp.result;
        } else if (resp.result !== null && resp.result !== undefined) {
          rawBytes = new Uint8Array(resp.result as ArrayBuffer);
          const decoder = util.TextDecoder.create('utf-8');
          bodyText = decoder.decodeWithStream(rawBytes);
        }
        const out: HttpResponse = new HttpResponse(resp.responseCode, headers, bodyText);
        out.bodyBytes = rawBytes;
        resolve(out);
      }).catch((e: BusinessError): void => {
        reject(new Error('HTTP_' + e.code + ': ' + e.message));
      });
    });
  }
}
