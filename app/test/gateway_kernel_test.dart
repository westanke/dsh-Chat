/// 通用内核调用面（`dshrb-v1`）的纯逻辑回归。
///
/// 覆盖三件不依赖连接的东西：目录帧的宽容解析、结果帧的三态、在飞登记表的结算语义。
/// 「真的能调到内核端点」属于联调范畴（见 docs/protocol-conformance.md §4.1）。
library;

import 'dart:async';

import 'package:dshchat/bridge/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseKernelEndpoints', () {
    test('正常条目按序解析，stream / wires 缺省有默认值', () {
      final catalog = parseKernelEndpoints([
        {
          'endpoint': 'session/search',
          'scope': 'chat.read',
          'summary': '搜索会话内容',
          'wires': ['query'],
        },
        {'endpoint': 'productAnalytics/enabled', 'scope': 'settings.read', 'summary': '开关'},
      ]);
      expect(catalog, hasLength(2));
      expect(catalog.first.endpoint, 'session/search');
      expect(catalog.first.scope, 'chat.read');
      expect(catalog.first.wires, ['query']);
      expect(catalog.first.stream, isFalse);
      // 缺 wires 时是空表而不是 null —— 调用方拼参数时不必判空。
      expect(catalog.last.wires, isEmpty);
      expect(catalog.last.stream, isFalse);
    });

    test('坏条目跳过，不连坐整帧（元素形状还没冻结）', () {
      final catalog = parseKernelEndpoints([
        {'endpoint': 'session/search', 'scope': 'chat.read', 'summary': 'ok'},
        {'scope': 'chat.read'}, // 没有 endpoint
        {'endpoint': '', 'scope': 'chat.read'}, // 空 endpoint
        'not-a-map',
        null,
        {'endpoint': 'pluginMarket/search', 'scope': 'settings.read', 'wires': 'bad'},
      ]);
      expect(catalog.map((e) => e.endpoint), ['session/search', 'pluginMarket/search']);
      // wires 不是列表时退化成空表，而不是抛错。
      expect(catalog.last.wires, isEmpty);
    });

    test('未知字段忽略，非列表直接回空表', () {
      final catalog = parseKernelEndpoints([
        {
          'endpoint': 'session/state',
          'scope': 'chat.read',
          'summary': '会话状态',
          'futureField': {'nested': true},
        },
      ]);
      expect(catalog.single.endpoint, 'session/state');
      expect(parseKernelEndpoints(null), isEmpty);
      expect(parseKernelEndpoints({'endpoints': []}), isEmpty);
    });
  });

  group('parseKernelCallResult', () {
    test('ok=true 带 value', () {
      final r = parseKernelCallResult({'ok': true, 'value': {'items': []}});
      expect(r.ok, isTrue);
      expect(r.code, isNull);
      expect(r.object, {'items': []});
    });

    test('ok=false 带 error{code,message}', () {
      final r = parseKernelCallResult({
        'ok': false,
        'error': {'code': 'kernel/endpoint-unknown', 'message': '内核没装这个端点'},
      });
      expect(r.ok, isFalse);
      expect(r.code, 'kernel/endpoint-unknown');
      expect(r.message, '内核没装这个端点');
      expect(r.object, isNull);
    });

    test('ok=false 但缺 error 详情时给兜底码，不抛错', () {
      final r = parseKernelCallResult({'ok': false});
      expect(r.ok, isFalse);
      expect(r.code, 'KERNEL_FAILED');
      expect(r.message, isNotEmpty);
    });

    test('list 便捷只在 value 真是列表时返回', () {
      expect(parseKernelCallResult({'ok': true, 'value': [1, 2]}).list, [1, 2]);
      expect(parseKernelCallResult({'ok': true, 'value': {'a': 1}}).list, isNull);
    });
  });

  group('KernelCallRegistry', () {
    test('settle 取走登记并结算一次', () async {
      final registry = KernelCallRegistry();
      final completer = Completer<KernelCallResult>();
      registry.add('k1', completer);
      expect(registry.contains('k1'), isTrue);
      expect(registry.length, 1);

      final settled = registry.settle('k1', const KernelCallResult.ok('v'));
      expect(settled?.value, 'v');
      expect(await completer.future, isA<KernelCallResult>());
      // 已摘除：同 id 再来一次什么也不做（取消后晚到的结果帧就走这条路）。
      expect(registry.settle('k1', const KernelCallResult.ok('again')), isNull);
      expect(registry.length, 0);
    });

    test('未知 callId / 空 callId 静默丢弃', () {
      final registry = KernelCallRegistry();
      expect(registry.settle('nope', const KernelCallResult.ok(null)), isNull);
      expect(registry.settle(null, const KernelCallResult.ok(null)), isNull);
      expect(registry.settle('', const KernelCallResult.ok(null)), isNull);
    });

    test('take 后重复结算不二次 complete', () async {
      final registry = KernelCallRegistry();
      final completer = Completer<KernelCallResult>();
      registry.add('k2', completer);
      expect(registry.take('k2'), same(completer));
      expect(registry.take('k2'), isNull);
    });

    test('failAll 让在飞调用全部失败，并清空登记表', () async {
      final registry = KernelCallRegistry();
      final a = Completer<KernelCallResult>();
      final b = Completer<KernelCallResult>();
      registry.add('ka', a);
      registry.add('kb', b);

      registry.failAll('连接已断开');

      await expectLater(a.future, throwsA(isA<RequestException>()));
      await expectLater(b.future, throwsA(isA<RequestException>()));
      expect(registry.length, 0);
    });

    test('failAll 对已完成的 completer 不重复结算', () async {
      final registry = KernelCallRegistry();
      final done = Completer<KernelCallResult>()..complete(const KernelCallResult.ok(1));
      final pending = Completer<KernelCallResult>();
      registry.add('done', done);
      registry.add('pending', pending);

      registry.failAll('掉线');

      // 已完成的那个原样保留结果，不会变成异常。
      expect((await done.future).ok, isTrue);
      await expectLater(pending.future, throwsA(isA<RequestException>()));
    });
  });

  group('目录辅助', () {
    const catalog = [
      KernelEndpoint(endpoint: 'session/search', scope: 'chat.read', summary: '搜索'),
      KernelEndpoint(endpoint: 'messageFeedback/put', scope: 'chat.write', summary: '反馈'),
      KernelEndpoint(endpoint: 'session/state', scope: 'chat.read', summary: '状态'),
    ];

    test('groupKernelEndpointsByScope 按 scope 分组且保持原序', () {
      final grouped = groupKernelEndpointsByScope(catalog);
      expect(grouped.keys, ['chat.read', 'chat.write']);
      expect(grouped['chat.read']!.map((e) => e.endpoint), [
        'session/search',
        'session/state',
      ]);
      expect(grouped['chat.write']!.single.endpoint, 'messageFeedback/put');
    });

    test('describeKernelCatalog 空表时说明原因，非空时列出端点名', () {
      expect(describeKernelCatalog(const []), contains('dshrb-v1'));
      final text = describeKernelCatalog(catalog);
      expect(text, contains('3 条'));
      expect(text, contains('session/search'));
    });
  });
}
