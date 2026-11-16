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
    const sid: string = sessionId ?? '';
    let job: Promise<Uint8Array>;
    if (ref.attachmentId.length > 0) {
      job = api.fetchAttachment(ref.attachmentId, sid);
    } else {
      // 交接图也必须带 sessionId（bridge 校验 name + sessionId 同时存在）。
      job = api.fetchImageHandoff(ref.handoffName, sid);
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
