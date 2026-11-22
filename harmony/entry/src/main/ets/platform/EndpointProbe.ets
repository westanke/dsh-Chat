/**
 * 候选地址并发探活（IKX5KQ）——平台层实现，core 只放判据。
 *
 * 打 `GET /api/v1/healthz`（bridge 免鉴权端点）：拿到任意 <500 的响应即算路通，
 * 4xx 也证明可达（鉴权/版本问题留给 WS 握手报）。单条硬超时 2.5s。
 */

import { HttpRequest, HttpTransport } from '../core/Transport';
import { EndpointProbe } from '../core/EndpointSelect';
import { Dlog } from './Dlog';

export const ENDPOINT_PROBE_TIMEOUT_MS: number = 2500;

/** 探活一条地址；任何异常都收成「不可达 + 原因」，不往上抛。 */
export function probeEndpoint(transport: HttpTransport, baseUrl: string,
  timeoutMs: number = ENDPOINT_PROBE_TIMEOUT_MS): Promise<EndpointProbe> {
  const started: number = Date.now();
  const url: string = baseUrl.replace(/\/+$/, '') + '/api/v1/healthz';
  const req: HttpRequest = new HttpRequest('GET', url, new Map(), null, timeoutMs);
  return transport.request(req).then((resp): EndpointProbe => {
    const ms: number = Date.now() - started;
    if (resp.status >= 500) {
      return new EndpointProbe(baseUrl, false, ms, 'HTTP ' + String(resp.status));
    }
    return new EndpointProbe(baseUrl, true, ms, '');
  }).catch((e: Error): EndpointProbe => {
    Dlog.warn('[probe] ' + baseUrl + ' ' + e.message);
    return new EndpointProbe(baseUrl, false, -1, shortError(e.message));
  });
}

/** 并发探活全部候选（总耗时≈最慢那条）。 */
export function probeEndpoints(transport: HttpTransport, baseUrls: string[],
  timeoutMs: number = ENDPOINT_PROBE_TIMEOUT_MS): Promise<EndpointProbe[]> {
  if (baseUrls.length === 0) {
    return Promise.resolve([] as EndpointProbe[]);
  }
  const jobs: Promise<EndpointProbe>[] = [];
  for (const u of baseUrls) {
    jobs.push(probeEndpoint(transport, u, timeoutMs));
  }
  return Promise.all(jobs);
}

function shortError(message: string): string {
  if (message.length === 0) {
    return '连不上';
  }
  return message.length <= 60 ? message : message.substring(0, 60) + '…';
}
