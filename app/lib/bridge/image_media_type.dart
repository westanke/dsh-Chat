/// 图片真实类型的纯 Dart 判据（平台无关、可单测）。
///
/// 背景（docs/huawei-heic-upload-report.md）：
/// - 判类型只信**字节魔数**，不信文件名扩展名或 `OpenableColumns.DISPLAY_NAME`——
///   华为/荣耀图库常返回无扩展名、纯数字 ID 或 null 的显示名，按文件名猜扩展名
///   会把 JPEG 误拒、也认不出 HEIC。
/// - 内核内联 prompt 只收 4 种 mediaType
///   （`@deepseek-ai/dsh-attachment-local/lib/index.js:998-1009` 的
///   `imageLimits.mediaTypes` 是 `Object.freeze` 死字面量，无配置入口）。
///   HEIC/HEIF/BMP/AVIF 由 Kotlin 侧 `ImagePickHelper` 先转码成 JPEG/PNG，
///   本文件的白名单用来核对原生侧回传的 mediaType。
/// - 魔数表与 `dsh-remote-bridge/src/host/image-handoff.ts:165-189`
///   `sniffMediaType`、Kotlin 侧 `ImagePickHelper.sniffMediaType` 保持一致。
library;

/// 内核内联 prompt 接受的图片类型；其它一律在原生侧转码后再发。
const supportedImageMediaTypes = <String>{
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
};

/// 该 mediaType 是否可以直接内联发送（大小写/首尾空格宽容）。
bool isSupportedImageMediaType(String? mediaType) =>
    mediaType != null &&
    supportedImageMediaTypes.contains(mediaType.trim().toLowerCase());

/// mediaType → 展示/缓存文件扩展名。
String mediaTypeExtension(String mediaType) {
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

/// 按字节魔数嗅探真实 mediaType；认不出返回 null。
///
/// 与 bridge `sniffMediaType` 同表：PNG 八字节签名、JPEG `FF D8 FF`、
/// GIF87a/GIF89a、RIFF@0 + WEBP@8、BMP `42 4D`、
/// ISO-BMFF `ftyp`@4 且 brand@8 `avi*`→avif / `hei*|hev*|mif*`→heic。
String? sniffImageMediaType(List<int> bytes) {
  if (_matches(bytes, 0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (_matches(bytes, 0, const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (_asciiAt(bytes, 0, 'GIF87a') || _asciiAt(bytes, 0, 'GIF89a')) {
    return 'image/gif';
  }
  if (_asciiAt(bytes, 0, 'RIFF') && _asciiAt(bytes, 8, 'WEBP')) {
    return 'image/webp';
  }
  if (_matches(bytes, 0, const [0x42, 0x4d])) return 'image/bmp';
  if (_asciiAt(bytes, 4, 'ftyp') && bytes.length >= 12) {
    final brand = _readAscii(bytes, 8, 4);
    if (brand.startsWith('avi')) return 'image/avif';
    if (brand.startsWith('hei') ||
        brand.startsWith('hev') ||
        brand.startsWith('mif')) {
      return 'image/heic';
    }
  }
  return null;
}

bool _matches(List<int> b, int off, List<int> sig) {
  if (b.length < off + sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if ((b[off + i] & 0xff) != sig[i]) return false;
  }
  return true;
}

/// 从 [off] 起是否正好是 ASCII 串 [s]。
bool _asciiAt(List<int> b, int off, String s) {
  if (b.length < off + s.length) return false;
  for (var i = 0; i < s.length; i++) {
    if ((b[off + i] & 0xff) != s.codeUnitAt(i)) return false;
  }
  return true;
}

/// 从 [off] 起读 [len] 个字节当 ASCII 串（用于 ftyp brand）。
String _readAscii(List<int> b, int off, int len) {
  if (b.length < off + len) return '';
  return String.fromCharCodes(
    List<int>.generate(len, (i) => b[off + i] & 0xff),
  );
}
