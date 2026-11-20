/// 会话内容搜索的纯逻辑回归（`session/search`，走 `dshrb-v1` 通用调用面）。
///
/// 这里只测不碰网络的部分：返回值解析、args 拼装。真正的调用链要靠联调
/// （见 docs/protocol-conformance.md §4.1 与 docs/design-tokens.md §4.14）。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/ui/session_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSessionSearchHits', () {
    test('正常返回按序解析，片段压成一行', () {
      final hits = parseSessionSearchHits({
        'items': [
          {'sessionId': 's1', 'snippet': '第一条\n命中的  内容'},
          {'sessionId': 's2', 'snippet': '第二条'},
        ],
        'hasMore': false,
      });
      expect(hits.map((h) => h.sessionId), ['s1', 's2']);
      expect(hits.first.snippet, '第一条 命中的 内容');
      expect(hits.last.snippet, '第二条');
    });

    test('坏条目跳过：缺 sessionId / 空 sessionId / 非 map', () {
      final hits = parseSessionSearchHits({
        'items': [
          {'snippet': '没有 id'},
          {'sessionId': '', 'snippet': '空 id'},
          'not-a-map',
          null,
          {'sessionId': 'ok', 'snippet': '留下'},
        ],
      });
      expect(hits.map((h) => h.sessionId), ['ok']);
    });

    test('snippet 缺席或不是字符串时给空串，不抛错', () {
      final hits = parseSessionSearchHits({
        'items': [
          {'sessionId': 'a'},
          {'sessionId': 'b', 'snippet': 42},
        ],
      });
      expect(hits.map((h) => h.snippet), ['', '']);
    });

    test('形状不认识一律回空表（搜索失败不该让抽屉红一片）', () {
      expect(parseSessionSearchHits(null), isEmpty);
      expect(parseSessionSearchHits('nope'), isEmpty);
      expect(parseSessionSearchHits({'items': 'not-a-list'}), isEmpty);
      expect(parseSessionSearchHits({}), isEmpty);
    });
  });

  group('sessionSearchArgs', () {
    const withRequest = KernelEndpoint(
      endpoint: 'session/search',
      scope: 'chat.read',
      summary: '搜索',
      wires: ['request'],
    );

    test('目录说 wires=[request] 时包一层 request', () {
      expect(sessionSearchArgs(withRequest, '审批'), {
        'request': {'query': '审批'},
      });
    });

    test('目录说 wires=[query] 时直接放 query', () {
      const flat = KernelEndpoint(
        endpoint: 'session/search',
        scope: 'chat.read',
        summary: '搜索',
        wires: ['query'],
      );
      expect(sessionSearchArgs(flat, 'x'), {'query': 'x'});
    });

    test('目录缺席（不支持时）退回已知形状', () {
      expect(sessionSearchArgs(null, 'x'), {
        'request': {'query': 'x'},
      });
    });

    test('形状不认识时塞进第一个 wire 键，让桥回参数错误而不是空参数', () {
      const odd = KernelEndpoint(
        endpoint: 'session/search',
        scope: 'chat.read',
        summary: '搜索',
        wires: ['payload'],
      );
      expect(sessionSearchArgs(odd, 'x'), {
        'payload': {'query': 'x'},
      });
    });
  });

  group('SessionSearchController.visible', () {
    test('有查询串就可见，哪怕空结果 / 还在搜 / 出错', () {
      // 真机 v1.0.21 第一次联调踩的坑：写成「有命中才可见」时，搜不到东西
      // 整节直接消失，用户看到的是「搜索没生效」，而不是「没有匹配」。
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final c = SessionSearchController(gateway: gw, debounce: const Duration(minutes: 1));
      addTearDown(() {
        c.dispose();
        gw.dispose();
      });

      expect(c.visible, isFalse, reason: '没输入时不该占位');
      c.update('   ');
      expect(c.visible, isFalse, reason: '纯空白等同没输入');
      c.update('dsh');
      expect(c.visible, isTrue, reason: '在搜（busy）也要可见，否则看不到「搜索中…」');
    });

    test('清空输入立刻回到不可见', () {
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final c = SessionSearchController(gateway: gw, debounce: const Duration(minutes: 1));
      addTearDown(() {
        c.dispose();
        gw.dispose();
      });
      c.update('x');
      expect(c.visible, isTrue);
      c.update('');
      expect(c.visible, isFalse);
      expect(c.hits, isEmpty);
      expect(c.busy, isFalse);
      expect(c.error, isNull);
    });
  });

  group('SessionSearchController 跟随端点目录（能力晚到）', () {
    test('目录晚到时，已输入的查询会在目录到达后补发', () async {
      // 真机踩的第二坑：抽屉输完字，kernel-endpoints 这一帧还没到，
      // 这一节整节不出现；等目录到了也没人重发那次查询。
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final c = SessionSearchController(gateway: gw, debounce: const Duration(milliseconds: 10));
      addTearDown(() {
        c.dispose();
        gw.dispose();
      });

      expect(c.supported, isFalse, reason: '目录还没到');
      c.update('审批');
      expect(c.busy, isFalse, reason: '能力没有时不假装在搜');
      expect(c.query, '审批', reason: '查询串要留住，等能力到了补发');

      gw.capabilities = const ['kernel-call-v1'];
      // 桥推来目录（真的会发请求，会打到不存在的 127.0.0.1:1 —— 结果无所谓，
      // 这里只验证「有没有真的发出去」：busy 会被置起，最后落到 error）。
      gw.debugSetKernelCatalog(const [
        KernelEndpoint(
          endpoint: 'session/search',
          scope: 'chat.read',
          summary: '搜索',
          wires: ['request'],
        ),
      ]);
      expect(c.supported, isTrue);
      expect(c.busy, isTrue, reason: '补发时立即进入搜索中');

      // 让定时器和请求都落地，避免 pending timer 泄漏到下一个用例。
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.error, isNotNull, reason: '连不上时该报错，而不是永远转圈');
      expect(c.busy, isFalse);
    });

    test('能力消失（重连清空目录）时撤掉命中', () {
      final gw = GatewayClient(baseUrl: 'http://127.0.0.1:1');
      final c = SessionSearchController(gateway: gw, debounce: const Duration(minutes: 1));
      addTearDown(() {
        c.dispose();
        gw.dispose();
      });

      gw.capabilities = const ['kernel-call-v1'];
      gw.debugSetKernelCatalog(const [
        KernelEndpoint(endpoint: 'session/search', scope: 'chat.read', summary: '搜索'),
      ]);
      c.update('x');
      expect(c.supported, isTrue);

      gw.debugSetKernelCatalog(const []);
      expect(c.supported, isFalse);
      expect(c.hits, isEmpty);
      expect(c.busy, isFalse);
      expect(c.error, isNull);
    });
  });
}
