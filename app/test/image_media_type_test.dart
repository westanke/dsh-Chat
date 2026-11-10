/// 图片类型纯函数单测：魔数嗅探 + 内核白名单判定 + 扩展名映射。
///
/// 覆盖华为 HEIC 场景的关键：HEIC 的显示名常无扩展名，判类型必须靠字节；
/// 且内核只收 4 种，HEIC 必须被识别出来交给原生侧转码。
library;

import 'package:dshchat/bridge/image_media_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sniffImageMediaType 魔数嗅探', () {
    test('PNG 八字节签名', () {
      expect(
        sniffImageMediaType([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        'image/png',
      );
      // 后面带真实数据也认
      expect(
        sniffImageMediaType([
          0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00
        ]),
        'image/png',
      );
    });

    test('JPEG FF D8 FF', () {
      expect(sniffImageMediaType([0xff, 0xd8, 0xff, 0xe0, 0x00]), 'image/jpeg');
    });

    test('GIF87a / GIF89a', () {
      expect(sniffImageMediaType(_ascii('GIF89a') + [0, 0]), 'image/gif');
      expect(sniffImageMediaType(_ascii('GIF87a') + [0, 0]), 'image/gif');
    });

    test('WEBP = RIFF....WEBP', () {
      final b = <int>[..._ascii('RIFF'), 0, 0, 0, 0, ..._ascii('WEBP'), 0, 0];
      expect(sniffImageMediaType(b), 'image/webp');
    });

    test('BMP 42 4D', () {
      expect(sniffImageMediaType([0x42, 0x4d, 0x00, 0x00]), 'image/bmp');
    });

    test('HEIC = ISO-BMFF ftyp + hei/hev/mif brand', () {
      for (final brand in ['heic', 'heix', 'hevc', 'hevx', 'mif1']) {
        final b = <int>[
          0, 0, 0, 24, ..._ascii('ftyp'), ..._ascii(brand), 0, 0, 0, 0
        ];
        expect(sniffImageMediaType(b), 'image/heic',
            reason: 'brand=$brand 应识别为 HEIC');
      }
    });

    test('AVIF = ftyp + avi* brand', () {
      final b = <int>[
        0, 0, 0, 24, ..._ascii('ftyp'), ..._ascii('avif'), 0, 0, 0, 0
      ];
      expect(sniffImageMediaType(b), 'image/avif');
    });

    test('认不出 / 短数组 / 截断 ftyp 返回 null（不抛）', () {
      expect(sniffImageMediaType([]), isNull);
      expect(sniffImageMediaType([0x89, 0x50]), isNull); // 截断 PNG 签名
      expect(sniffImageMediaType(_ascii('hello world')), isNull);
      expect(sniffImageMediaType([0, 0, 0, 24, ..._ascii('ftyp')]), isNull);
    });
  });

  group('isSupportedImageMediaType 内核白名单', () {
    test('四种内核收的类型', () {
      for (final t in ['image/png', 'image/jpeg', 'image/webp', 'image/gif']) {
        expect(isSupportedImageMediaType(t), isTrue, reason: t);
      }
    });

    test('大小写 / 首尾空格宽容', () {
      expect(isSupportedImageMediaType(' IMAGE/JPEG '), isTrue);
      expect(isSupportedImageMediaType('Image/Png'), isTrue);
    });

    test('HEIC/HEIF/BMP/AVIF 与未知值一律 false（需转码）', () {
      for (final t in [
        'image/heic',
        'image/heif',
        'image/bmp',
        'image/avif',
        'application/octet-stream',
        '',
      ]) {
        expect(isSupportedImageMediaType(t), isFalse, reason: t);
      }
      expect(isSupportedImageMediaType(null), isFalse);
    });
  });

  group('mediaTypeExtension 扩展名映射', () {
    test('四种内核类型', () {
      expect(mediaTypeExtension('image/png'), 'png');
      expect(mediaTypeExtension('image/jpeg'), 'jpg');
      expect(mediaTypeExtension('image/webp'), 'webp');
      expect(mediaTypeExtension('image/gif'), 'gif');
    });

    test('转码前类型与兜底', () {
      expect(mediaTypeExtension('image/heic'), 'heic');
      expect(mediaTypeExtension('image/heif'), 'heic');
      expect(mediaTypeExtension('image/avif'), 'avif');
      expect(mediaTypeExtension('image/bmp'), 'bmp');
      expect(mediaTypeExtension('x'), 'bin');
    });
  });
}

List<int> _ascii(String s) => s.codeUnits;
