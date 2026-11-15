/**
 * 图片类型判据测试 —— 对应安卓 app/lib/bridge/image_media_type.dart。
 * 口径：只信字节魔数，不信扩展名；白名单只 4 种可内联类型。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  isSupportedImageMediaType,
  mediaTypeExtension,
  sniffImageMediaType,
} from '../../entry/src/main/ets/core/ImageMediaType.ts';

/** 由 ASCII 片段构造字节数组。 */
function asciiBytes(s: string): Uint8Array {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    out[i] = s.charCodeAt(i) & 0xff;
  }
  return out;
}

test('isSupportedImageMediaType: 白名单 4 种，大小写/空格宽容', () => {
  assert.equal(isSupportedImageMediaType('image/png'), true);
  assert.equal(isSupportedImageMediaType('IMAGE/JPEG'), true);
  assert.equal(isSupportedImageMediaType(' image/webp '), true);
  assert.equal(isSupportedImageMediaType('image/gif'), true);
  assert.equal(isSupportedImageMediaType('image/heic'), false);
  assert.equal(isSupportedImageMediaType('image/bmp'), false);
  assert.equal(isSupportedImageMediaType('image/avif'), false);
  assert.equal(isSupportedImageMediaType(null), false);
});

test('mediaTypeExtension: 映射到展示扩展名，未知回 bin', () => {
  assert.equal(mediaTypeExtension('image/png'), 'png');
  assert.equal(mediaTypeExtension('image/jpeg'), 'jpg');
  assert.equal(mediaTypeExtension('image/webp'), 'webp');
  assert.equal(mediaTypeExtension('image/gif'), 'gif');
  assert.equal(mediaTypeExtension('image/bmp'), 'bmp');
  assert.equal(mediaTypeExtension('image/heic'), 'heic');
  assert.equal(mediaTypeExtension('image/heif'), 'heic');
  assert.equal(mediaTypeExtension('image/avif'), 'avif');
  assert.equal(mediaTypeExtension('image/x-weird'), 'bin');
});

test('sniffImageMediaType: PNG 八字节签名', () => {
  const b = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
  assert.equal(sniffImageMediaType(b), 'image/png');
});

test('sniffImageMediaType: JPEG FF D8 FF', () => {
  const b = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00]);
  assert.equal(sniffImageMediaType(b), 'image/jpeg');
});

test('sniffImageMediaType: GIF87a / GIF89a', () => {
  assert.equal(sniffImageMediaType(asciiBytes('GIF89a....')), 'image/gif');
  assert.equal(sniffImageMediaType(asciiBytes('GIF87a....')), 'image/gif');
});

test('sniffImageMediaType: RIFF + WEBP', () => {
  const b = asciiBytes('RIFF????WEBPVP8 ');
  assert.equal(sniffImageMediaType(b), 'image/webp');
});

test('sniffImageMediaType: BMP 42 4D', () => {
  const b = new Uint8Array([0x42, 0x4d, 0x00, 0x00]);
  assert.equal(sniffImageMediaType(b), 'image/bmp');
});

test('sniffImageMediaType: ISO-BMFF ftyp brand → avif / heic', () => {
  const avif = asciiBytes('????ftypavif');
  assert.equal(sniffImageMediaType(avif), 'image/avif');
  assert.equal(sniffImageMediaType(asciiBytes('????ftypheic')), 'image/heic');
  assert.equal(sniffImageMediaType(asciiBytes('????ftyphevc')), 'image/heic');
  assert.equal(sniffImageMediaType(asciiBytes('????ftypmif1')), 'image/heic');
  // mp4 brand 不在表内
  assert.equal(sniffImageMediaType(asciiBytes('????ftypmp42')), null);
});

test('sniffImageMediaType: 认不出/过短回 null，不抛', () => {
  assert.equal(sniffImageMediaType(new Uint8Array(0)), null);
  assert.equal(sniffImageMediaType(asciiBytes('hello world')), null);
  assert.equal(sniffImageMediaType(new Uint8Array([0x89])), null);
});
