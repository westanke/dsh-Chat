import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/hosts.dart';

void main() {
  group('DshHost', () {
    test('stableId：同输入同输出（幂等导入）', () {
      expect(DshHost.stableId('http://192.168.1.10:3090'),
          DshHost.stableId('http://192.168.1.10:3090'));
      expect(
        DshHost.stableId('http://192.168.1.10:3090'),
        isNot(DshHost.stableId('http://192.168.1.11:3090')),
      );
      expect(DshHost.stableId('http://x').length, 16);
    });

    test('toJson/fromJson round-trip（token 缺省不发键）', () {
      final h = DshHost(
        id: 'abc',
        displayName: '家里电脑',
        baseUrl: 'http://192.168.1.10:3090',
        token: 'tok',
        lastUsedAt: 42,
      );
      final back = DshHost.fromJson(h.toJson());
      expect(back.id, 'abc');
      expect(back.displayName, '家里电脑');
      expect(back.baseUrl, 'http://192.168.1.10:3090');
      expect(back.token, 'tok');
      expect(back.lastUsedAt, 42);
      final noToken = DshHost(
        id: 'x',
        displayName: '',
        baseUrl: 'http://x',
        lastUsedAt: 1,
      ).toJson();
      expect(noToken.containsKey('token'), isFalse);
    });
  });

  group('decodeDsh1（companion ConnectionShare 宽容口径）', () {
    // 构造一份合法 DSH1 文本（URL-safe 无填充 Base64）。
    String encode(String json) {
      var s = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
      return 'DSH1:$s';
    }

    test('标准格式：前缀 + endpoints[0].baseUrl + token', () {
      final text = encode(
        '{"displayName":"家里电脑","endpoints":[{"label":"LAN","baseUrl":"http://192.168.1.10:3090/api/v1"}],"token":"tok123"}',
      );
      final host = decodeDsh1(text);
      expect(host, isNotNull);
      expect(host!.displayName, '家里电脑');
      // 归一：剥 /api/v1 后缀。
      expect(host.baseUrl, 'http://192.168.1.10:3090');
      expect(host.token, 'tok123');
    });

    test('宽容：前缀前有说明文字 / 换行空白 / 结尾标点', () {
      final text = 'Pixel 9 的配置：\n${encode('{"displayName":"办公室","endpoints":[{"label":"L","baseUrl":"http://10.0.0.2:3090"}]}')}。';
      final host = decodeDsh1(text);
      expect(host, isNotNull);
      expect(host!.displayName, '办公室');
      expect(host.baseUrl, 'http://10.0.0.2:3090');
      expect(host.token, isNull);
    });

    test('宽容：前缀大小写不敏感', () {
      final text = 'dsh1:${base64Url.encode(utf8.encode('{"displayName":"x","endpoints":[{"baseUrl":"http://a:1"}]}')).replaceAll('=', '')}';
      expect(decodeDsh1(text), isNotNull);
    });

    test('垃圾输入一律返回 null 不抛异常', () {
      expect(decodeDsh1(''), isNull);
      expect(decodeDsh1('随便说点什么'), isNull);
      expect(decodeDsh1('DSH1:!!!'), isNull);
      expect(decodeDsh1('DSH1:${base64Url.encode(utf8.encode('not json'))}'), isNull);
      expect(decodeDsh1('DSH1:${base64Url.encode(utf8.encode('{"displayName":"无地址"}'))}'), isNull);
    });
  });
}
