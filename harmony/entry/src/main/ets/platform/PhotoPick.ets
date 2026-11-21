/// 选图（系统相册 picker）→ 读文件 → 魔数嗅探 → base64。
/// 对齐安卓 composer_widgets.dart 的 pickComposerImage/resolvePickedImage
/// （error 优先 → mediaType 空走嗅探兜底 → 白名单校验）。
/// 返回 PickedImage；取消回 null；失败 image.error = 中文错误文案。
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { isSupportedImageMediaType, sniffImageMediaType } from '../core/ImageMediaType';
import { PromptPart } from '../core/Content';

/** 待发送图片 → 内核 prompt parts（顺序即选图顺序）。 */
export function promptPartsOf(images: PickedImage[]): PromptPart[] {
  const parts: PromptPart[] = [];
  for (const img of images) {
    parts.push(PromptPart.image(img.mediaType, img.base64, img.name));
  }
  return parts;
}

/** 一条消息最多带几张图（与安卓对齐）。 */
export const MAX_SELECTED_IMAGES: number = 6;

/** 选图后的拦截原因：空串表示可以加入待发送列表。 */
export function galleryErrorOf(img: PickedImage, current: number): string {
  if (img.error.length > 0) {
    return img.error;
  }
  if (current >= MAX_SELECTED_IMAGES) {
    return '一条消息最多带 ' + MAX_SELECTED_IMAGES + ' 张图片';
  }
  return '';
}

export class PickedImage {
  path: string = '';
  name: string = '';
  mediaType: string = '';
  base64: string = '';
  error: string = '';
}

/** 待发送图片的名字列表（chip 行只显示名字）。 */
export function imageNamesOf(list: PickedImage[]): string[] {
  const out: string[] = [];
  for (const img of list) {
    out.push(img.name);
  }
  return out;
}

/** 删掉第 index 张（返回新数组，不原地改——@State 需要换引用才刷新）。 */
export function withoutImageAt(list: PickedImage[], index: number): PickedImage[] {
  const out: PickedImage[] = [];
  for (let i = 0; i < list.length; i++) {
    if (i !== index) {
      out.push(list[i]);
    }
  }
  return out;
}

/** 8MiB 上限（安卓一致）。 */
const MAX_IMAGE_BYTES: number = 8 * 1024 * 1024;

/** 拉起系统相册选择器，读文件并按魔数判定类型。 */
export async function pickImageFromGallery(context: common.UIAbilityContext): Promise<PickedImage | null> {
  const picker = new photoAccessHelper.PhotoViewPicker();
  const opts: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  opts.maxSelectNumber = 1;
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(opts);
  if (result.photoUris.length === 0) {
    return null; // 用户取消
  }
  return readPickedImage(result.photoUris[0]);
}

/** 读 uri 文件（魔数嗅探 + 8MiB 上限 + base64）。失败 error 字段带文案。 */
export async function readPickedImage(uri: string): Promise<PickedImage> {
  const out: PickedImage = new PickedImage();
  out.path = uri;
  const parts: string[] = uri.split('/');
  out.name = parts.length > 0 ? parts[parts.length - 1] : uri;
  let file: fs.File | null = null;
  try {
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const st: fs.Stat = await fs.stat(file.fd);
    if (st.size > MAX_IMAGE_BYTES) {
      fs.closeSync(file.fd);
      file = null;
      out.error = '图片超过 8MB 上限';
      return out;
    }
    const buf: ArrayBuffer = new ArrayBuffer(st.size);
    const readLen: number = fs.readSync(file.fd, buf);
    fs.closeSync(file.fd);
    file = null;
    const u8: Uint8Array = new Uint8Array(buf, 0, readLen);
    const sniffed: string | null = sniffImageMediaType(u8);
    if (sniffed !== null) {
      out.mediaType = sniffed;
    }
    if (!isSupportedImageMediaType(out.mediaType)) {
      out.error = '无法识别的图片格式';
      return out;
    }
    const helper: util.Base64Helper = new util.Base64Helper();
    out.base64 = helper.encodeToStringSync(u8);
    return out;
  } catch (e) {
    if (file !== null) {
      try {
        fs.closeSync(file.fd);
      } catch (e2) {
        // 关闭失败不再抛出。
      }
    }
    if (out.error.length === 0) {
      out.error = '图片读取失败';
    }
    return out;
  }
}
