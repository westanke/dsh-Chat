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
}
