/**
 * 进程内图片字节缓存 + 拉取 —— 从 ChatStore 拆出（500 行纪律，2026-11-16）。
 * attachment 走 /api/v1/attachments（sessionId 必带），handoff 走
 * /api/v1/image-handoff；immutable 资源不淘汰（安卓 _bytesCache 同款）。
 */

import { GatewayApi } from './GatewayApi';
import { DsImageRef } from './ImageRef';
import { RequestException } from './GatewayEvents';

export class ImageFetcher {
  private cache: Map<string, Uint8Array> = new Map();

  fetch(api: GatewayApi, sessionId: string | null, ref: DsImageRef): Promise<Uint8Array> {
    const cached: Uint8Array | undefined = this.cache.get(ref.cacheKey);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    let job: Promise<Uint8Array>;
    if (ref.attachmentId.length > 0) {
      const sid: string = sessionId ?? '';
      job = api.fetchAttachment(ref.attachmentId, sid);
    } else {
      job = api.fetchImageHandoff(ref.handoffName);
    }
    return job.then((bytes: Uint8Array): Uint8Array => {
      if (bytes.length === 0) {
        throw new RequestException('EMPTY', '图片为空');
      }
      this.cache.set(ref.cacheKey, bytes);
      return bytes;
    });
  }
}
