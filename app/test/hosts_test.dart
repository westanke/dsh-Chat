import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dshchat/bridge/hosts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('DshHosts.remove（删除单条过期/失效主机）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    DshHost host(String baseUrl, {String id = ''}) => DshHost(
          id: id.isEmpty ? DshHost.stableId(baseUrl) : id,
          displayName: '家里电脑',
          baseUrl: baseUrl,
          token: 'tok',
          lastUsedAt: 100,
        );

    test('删存在的记录：返回 true、load 不再含该条、持久化同步', () async {
      await DshHosts.clear(); // 重置静态缓存
      final a = host('http://192.168.1.10:3090');
      final b = host('http://192.168.1.11:3090');
      await DshHosts.upsert(a);
      await DshHosts.upsert(b);
      expect((await DshHosts.load()).length, 2);

      expect(await DshHosts.remove(a), isTrue);
      final left = await DshHosts.load();
      expect(left.length, 1);
      expect(left.single.baseUrl, 'http://192.168.1.11:3090');

      // 直接读 shared_preferences，确认落盘也是删后的数组。
      final sp = await SharedPreferences.getInstance();
      final raw = jsonDecode(sp.getString('dsh.hosts')!) as List;
      expect(raw.length, 1);
    });

    test('删不存在的记录：返回 false、列表不变', () async {
      await DshHosts.clear();
      await DshHosts.upsert(host('http://a:1'));
      expect(await DshHosts.remove(host('http://b:2')), isFalse);
      expect((await DshHosts.load()).length, 1);
    });

    test('按 id 兜底匹配（baseUrl 不同的历史脏数据）', () async {
      await DshHosts.clear();
      final stale = host('http://old:1', id: 'fixed-id');
      await DshHosts.upsert(stale);
      final byDifferentUrl = host('http://new:2', id: 'fixed-id');
      expect(await DshHosts.remove(byDifferentUrl), isTrue);
      expect(await DshHosts.load(), isEmpty);
    });

    test('删空后仍写合法 JSON 数组（不是 remove 键）', () async {
      await DshHosts.clear();
      final h = host('http://x:1');
      await DshHosts.upsert(h);
      await DshHosts.remove(h);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('dsh.hosts'), '[]');
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
