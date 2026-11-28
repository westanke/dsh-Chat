/// subagentHistory 的 WS 优先 / REST 回退测试。
///
/// 回退证明方式同 mobile_ws_first_test：假网关没有 token，REST 会在发网络
/// 请求前抛 NO_TOKEN —— 最终看到 NO_TOKEN 就说明确实落到了 REST。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/history_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<({String type, Map<String, dynamic> payload})> requests = [];
  final Map<String, Map<String, dynamic> Function(Map<String, dynamic>)>
  replies = {};
  final Map<String, RequestException> errors = {};

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type: type, payload: Map<String, dynamic>.from(payload)));
    final error = errors[type];
    if (error != null) throw error;
    final reply = replies[type];
    if (reply == null) {
      throw RequestException('UNKNOWN_TYPE', 'unknown frame $type');
    }
    return reply(payload);
  }

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) => request(type, payload);
}

Map<String, dynamic> _reply() => <String, dynamic>{
  'leadSessionId': 'lead-1',
  'subagentId': 'sub-1',
  'events': <dynamic>[
    {
      'type': 'user/message',
      'seq': 3,
      'time': 1000,
      'data': {
        'content': [
          {'type': 'text', 'text': '查一下'},
        ],
      },
    },
    {
      'type': 'assistant/message',
      'seq': 4,
      'time': 2000,
      'data': {
        'message': {
          'content': [
            {'type': 'text', 'text': '查到了'},
          ],
        },
      },
    },
  ],
  'hasMore': true,
  'projections': {
    'kind': 'team',
    'values': {'members': 2},
  },
  'bytes': 4096,
  'truncated': true,
  'historyFormatVersion': 1,
};

void main() {
  group('subagentHistory WS', () {
    test('声明帧 → 只走 WS，参数与 HistoryPage 字段全部落地', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['subagent-history'];
      gw.replies['subagent-history'] = (_) => _reply();

      final page = await gw.subagentHistory(
        'lead-1',
        'sub-1',
        maxMessages: 80,
        beforeSeq: 2,
      );

      expect(gw.requests.single.type, 'subagent-history');
      expect(gw.requests.single.payload, {
        'leadSessionId': 'lead-1',
        'subagentId': 'sub-1',
        'maxMessages': 80,
        'beforeSeq': 2,
      });
      expect(page.items.map((m) => m.text), ['查一下', '查到了']);
      expect(page.rawEvents.length, 2);
      expect(page.hasMore, isTrue);
      expect(page.projections, {
        'kind': 'team',
        'values': {'members': 2},
      });
      expect(page.bytes, 4096);
      expect(page.truncated, isTrue);
      expect(page.historyFormatVersion, 1);
    });

    test('可选参数为 null → 不发空字段', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['subagent-history'];
      gw.replies['subagent-history'] = (_) => _reply();

      await gw.subagentHistory('lead-1', 'sub-1');

      expect(gw.requests.single.payload, {
        'leadSessionId': 'lead-1',
        'subagentId': 'sub-1',
      });
    });

    test('帧失败 → 回退 REST（NO_TOKEN 证明到了 REST）', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['subagent-history'];
      gw.errors['subagent-history'] = RequestException('TIMEOUT', '请求超时');

      await expectLater(
        gw.subagentHistory('lead-1', 'sub-1'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests.map((r) => r.type), ['subagent-history']);
    });

    test('没声明帧（老桥）→ 直接 REST，不发帧', () async {
      final gw = _FakeGateway();

      await expectLater(
        gw.subagentHistory('lead-1', 'sub-1'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests, isEmpty);
    });

    test('WS 空 events → HistoryPage 空但 hasMore 保留', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['subagent-history'];
      gw.replies['subagent-history'] = (_) => <String, dynamic>{
        'events': <dynamic>[],
        'hasMore': false,
      };

      final HistoryPage page = await gw.subagentHistory('lead-1', 'sub-1');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });
}
