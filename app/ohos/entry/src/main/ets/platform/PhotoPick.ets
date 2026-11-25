/**
 * 选图（系统相册 picker）→ 读字节 → 魔数嗅探 → 复制进应用缓存目录。
 *
 * 对齐安卓 DshPlatform.pickImage：返回 {path,name,mediaType}，取消回 null，
 * 失败 error 带中文文案。差异说明：
 * - Dart 侧 `File(picked['path']).readAsBytes()` 读不了鸿蒙的
 *   `file://media/Photo/...` URI，必须先复制到应用沙盒 cacheDir；
 * - 内核只收 PNG/JPEG/WebP/GIF 四种 mediaType，而鸿蒙相册多是 HEIC，
 *   所以非白名单格式用 ImageKit 先转码成 JPEG 再落盘（安卓 ImagePickHelper 同口径）。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import {
  isSupportedImageMediaType,
  mediaTypeExtension,
  sniffImageMediaType
} from '../core/ImageMediaType';
import { Dlog } from './Dlog';

/** 选图结果（error 非空即失败）。 */
export class PickedPhoto {
  path: string = '';
  name: string = '';
  mediaType: string = '';
  error: string = '';
}

/** 8MiB 上限（与安卓一致）。 */
const MAX_IMAGE_BYTES: number = 8 * 1024 * 1024;

/** 拉起系统相册选择器；用户取消返回 null。 */
export async function pickImage(context: common.UIAbilityContext): Promise<PickedPhoto | null> {
  const picker = new photoAccessHelper.PhotoViewPicker();
  const opts: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  opts.maxSelectNumber = 1;
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(opts);
  if (result.photoUris.length === 0) {
    return null;
  }
  return cachePickedImage(context, result.photoUris[0]);
}

/** 读相册 URI → 嗅探 → 必要时转码 → 写 cacheDir。 */
async function cachePickedImage(context: common.UIAbilityContext, uri: string): Promise<PickedPhoto> {
  const out: PickedPhoto = new PickedPhoto();
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
    const u8: Uint8Array = new Uint8Array(buf, 0, readLen);
    fs.closeSync(file.fd);
    file = null;
    const sniffed: string | null = sniffImageMediaType(u8);
    if (sniffed !== null) {
      out.mediaType = sniffed;
    }
    if (isSupportedImageMediaType(out.mediaType)) {
      // 内核直接收：原样落盘，不重新编码（保画质、省时间）。
      out.path = await writeCacheBytes(context, buf, mediaTypeExtension(out.mediaType));
      out.name = cacheNameOf(out.path);
      return out;
    }
    // HEIC/HEIF/BMP/AVIF/未知：先转 JPEG。
    const jpeg: ArrayBuffer | null = await transcodeToJpeg(uri);
    if (jpeg === null) {
      out.error = '无法识别的图片格式';
      return out;
    }
    out.mediaType = 'image/jpeg';
    out.path = await writeCacheBytes(context, jpeg, 'jpg');
    out.name = cacheNameOf(out.path);
    return out;
  } catch (e) {
    if (file !== null) {
      try {
        fs.closeSync(file.fd);
      } catch (e2) {
        // 关闭失败不再抛出。
      }
    }
    Dlog.warn('cachePickedImage failed: ' + JSON.stringify(e));
    if (out.error.length === 0) {
      out.error = '图片读取失败';
    }
    return out;
  }
}

/** 从缓存绝对路径取文件名（UI 上的 chip 显示用）。 */
function cacheNameOf(path: string): string {
  const parts: string[] = path.split('/');
  return parts.length > 0 ? parts[parts.length - 1] : path;
}

/** 把字节写进应用缓存目录，返回绝对路径。 */
async function writeCacheBytes(
  context: common.UIAbilityContext,
  buf: ArrayBuffer,
  ext: string
): Promise<string> {
  const dest: string = context.cacheDir + '/picked-' + Date.now().toString() + '.' + ext;
  const file: fs.File = await fs.open(
    dest,
    fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
  );
  try {
    await fs.write(file.fd, buf);
  } finally {
    fs.closeSync(file.fd);
  }
  return dest;
}

/** 用 ImageKit 解码后再编码成 JPEG；失败回 null。 */
async function transcodeToJpeg(uri: string): Promise<ArrayBuffer | null> {
  let src: image.ImageSource | null = null;
  let pixelMap: image.PixelMap | null = null;
  let packer: image.ImagePacker | null = null;
  try {
    src = image.createImageSource(uri);
    if (src === null) {
      return null;
    }
    pixelMap = await src.createPixelMap();
    packer = image.createImagePacker();
    const opts: image.PackingOption = { format: 'image/jpeg', quality: 92 };
    return await packer.packing(pixelMap, opts);
  } catch (e) {
    Dlog.warn('transcodeToJpeg failed: ' + JSON.stringify(e));
    return null;
  } finally {
    if (packer !== null) {
      try {
        await packer.release();
      } catch (e) {
        // 释放失败忽略。
      }
    }
    if (pixelMap !== null) {
      try {
        await pixelMap.release();
      } catch (e) {
        // 同上。
      }
    }
    if (src !== null) {
      try {
        await src.release();
      } catch (e) {
        // 同上。
      }
    }
  }
}
