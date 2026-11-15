/**
 * 图片真实类型的纯逻辑判据（平台无关、node 可单测）。
 * 移植自安卓版 app/lib/bridge/image_media_type.dart，魔数表与
 * bridge `src/host/image-handoff.ts` sniffMediaType、安卓侧 ImagePickHelper 同表。
 *
 * 背景（安卓仓 docs/huawei-heic-upload-report.md）：
 * - 判类型只信**字节魔数**，不信文件名扩展名——华为/荣耀图库常返回无扩展名、
 *   纯数字 ID 或 null 的显示名，按文件名猜扩展名会把 JPEG 误拒、也认不出 HEIC。
 * - 内核内联 prompt 只收 4 种 mediaType（dsh-attachment-local 的
 *   `imageLimits.mediaTypes` 是 Object.freeze 死字面量，无配置入口）。
 *   HEIC/HEIF/BMP/AVIF 由客户端侧先转码成 JPEG/PNG，白名单用来核对转码结果。
 */

/** 内核内联 prompt 接受的图片类型；其它一律转码后再发。 */
const SUPPORTED_IMAGE_MEDIA_TYPES: string[] = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
];

/** 该 mediaType 是否可以直接内联发送（大小写/首尾空格宽容）。 */
export function isSupportedImageMediaType(mediaType: string | null): boolean {
  if (mediaType === null) {
    return false;
  }
  const t = mediaType.trim().toLowerCase();
  for (let i = 0; i < SUPPORTED_IMAGE_MEDIA_TYPES.length; i++) {
    if (SUPPORTED_IMAGE_MEDIA_TYPES[i] === t) {
      return true;
    }
  }
  return false;
}

/** mediaType → 展示/缓存文件扩展名。 */
export function mediaTypeExtension(mediaType: string): string {
  switch (mediaType.trim().toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'image/bmp':
      return 'bmp';
    case 'image/heic':
    case 'image/heif':
      return 'heic';
    case 'image/avif':
      return 'avif';
    default:
      return 'bin';
  }
}

/** 按字节魔数嗅探真实 mediaType；认不出返回 null。 */
export function sniffImageMediaType(bytes: Uint8Array): string | null {
  if (matches(bytes, 0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (matches(bytes, 0, [0xff, 0xd8, 0xff])) {
    return 'image/jpeg';
  }
  if (asciiAt(bytes, 0, 'GIF87a') || asciiAt(bytes, 0, 'GIF89a')) {
    return 'image/gif';
  }
  if (asciiAt(bytes, 0, 'RIFF') && asciiAt(bytes, 8, 'WEBP')) {
    return 'image/webp';
  }
  if (matches(bytes, 0, [0x42, 0x4d])) {
    return 'image/bmp';
  }
  if (asciiAt(bytes, 4, 'ftyp') && bytes.length >= 12) {
    const brand = readAscii(bytes, 8, 4);
    if (brand.indexOf('avi') === 0) {
      return 'image/avif';
    }
    if (
      brand.indexOf('hei') === 0 ||
      brand.indexOf('hev') === 0 ||
      brand.indexOf('mif') === 0
    ) {
      return 'image/heic';
    }
  }
  return null;
}

/** [off] 起是否正好是签名字节序列。 */
function matches(b: Uint8Array, off: number, sig: number[]): boolean {
  if (b.length < off + sig.length) {
    return false;
  }
  for (let i = 0; i < sig.length; i++) {
    if ((b[off + i] & 0xff) !== sig[i]) {
      return false;
    }
  }
  return true;
}

/** 从 [off] 起是否正好是 ASCII 串 s。 */
function asciiAt(b: Uint8Array, off: number, s: string): boolean {
  if (b.length < off + s.length) {
    return false;
  }
  for (let i = 0; i < s.length; i++) {
    if ((b[off + i] & 0xff) !== s.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

/** 从 [off] 起读 len 个字节当 ASCII 串（用于 ftyp brand）。 */
function readAscii(b: Uint8Array, off: number, len: number): string {
  if (b.length < off + len) {
    return '';
  }
  let out = '';
  for (let i = 0; i < len; i++) {
    out += String.fromCharCode(b[off + i] & 0xff);
  }
  return out;
}
