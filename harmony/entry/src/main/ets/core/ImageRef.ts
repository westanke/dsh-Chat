/// 图片引用 —— 对齐安卓 chat_image.dart 的 DsImageRef/imageRefsOf/handoffRefOf。
/// 历史消息里的图片有两种形态：attachment 引用（'sha256:<hex>'）与
/// image-handoff 占位（纯文本模型的 `[Image: source: .../<64hex>.<ext>]`）。
/// 下载执行在 ChatStore（带缓存），本文件只做纯逻辑。
import { ContentImageRef, handoffImageNameOf } from './Content';

export class DsImageRef {
  attachmentId: string = '';
  handoffName: string = '';

  static attachment(id: string): DsImageRef {
    const r: DsImageRef = new DsImageRef();
    r.attachmentId = id;
    return r;
  }

  static handoff(name: string): DsImageRef {
    const r: DsImageRef = new DsImageRef();
    r.handoffName = name;
    return r;
  }

  get cacheKey(): string {
    return this.attachmentId.length > 0
      ? this.attachmentId
      : 'handoff:' + this.handoffName;
  }
}

/** ContentImageRef 列表 → 待显示 ref 列表。 */
export function imageRefsOf(images: ContentImageRef[]): DsImageRef[] {
  const out: DsImageRef[] = [];
  for (const i of images) {
    out.push(DsImageRef.attachment(i.attachmentId));
  }
  return out;
}

/** 从消息文本提取 image-handoff 占位（没有回 null）。 */
export function handoffRefOf(text: string): DsImageRef | null {
  const name: string | null = handoffImageNameOf(text);
  return name === null ? null : DsImageRef.handoff(name);
}
