/// 三项 REST 改优先 WS 的单元测试：`hello.frames` 可用性判断 + 帧解析 + 回退。
///
/// 回退路径的断言技巧：假网关没有 token，REST 适配层会在发网络请求前抛
/// `NO_TOKEN`（gateway_rest.dart），所以「最终抛 NO_TOKEN」= 确实走了 REST 兜底。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只实现 request 的假网关（不连网络）。
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

void main() {
  group('hello.frames', () {
    test('解析字符串数组，丢掉非字符串/空串', () {
      expect(
        parseHelloFrames(<dynamic>['tasks', 'history', '', 42, null, '  ']),
        ['tasks', 'history', '  '],
      );
    });

    test('老桥无字段 / 形状不对 → 空表（按「帧不可用」处理）', () {
      expect(parseHelloFrames(null), isEmpty);
      expect(parseHelloFrames('tasks'), isEmpty);
      expect(parseHelloFrames(<dynamic>[1, 2]), isEmpty);
    });

    test('hasFrame 只看 hello.frames；没声明就是 false', () {
      final gw = _FakeGateway();
      expect(gw.hasFrame('tasks'), isFalse);
      gw.supportedFrames = const ['tasks', 'history'];
      expect(gw.hasFrame('tasks'), isTrue);
      expect(gw.hasFrame('history'), isTrue);
      expect(gw.hasFrame('workspace-update'), isFalse);
      // 能力位不再参与帧可用性判断（老桥可能只有 REST 侧的能力位）。
      gw.capabilities = const ['task-capability-only'];
      expect(gw.hasFrame('tasks'), isTrue);
    });
  });

  group('agentPresets', () {
    test('声明 agent-presets 帧 + 成功 → 只走 WS，解析 presets', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['agent-presets'];
      gw.replies['agent-presets'] = (_) => <String, dynamic>{
        'presets': <dynamic>[
          {'id': 'p1', 'name': '默认', 'trust': 'system', 'isDefault': true},
        ],
      };
      final presets = await gw.agentPresets();
      expect(presets.single.id, 'p1');
      expect(presets.single.isDefault, isTrue);
      expect(gw.requests.map((r) => r.type), ['agent-presets']);
    });

    test('帧被拒（UNKNOWN_TYPE）→ 回退 REST（NO_TOKEN 证明到了 REST）', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['agent-presets'];
      await expectLater(
        gw.agentPresets(),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests.map((r) => r.type), ['agent-presets']);
    });

    test('没声明帧（老桥）→ 直接走 REST，不发帧', () async {
      final gw = _FakeGateway();
      await expectLater(
        gw.agentPresets(),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests, isEmpty);
    });
  });

  group('selectAgentPreset', () {
    test('声明 session-agent-preset → 发该帧并返回桥确认的 id', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['session-agent-preset'];
      gw.replies['session-agent-preset'] = (payload) => <String, dynamic>{
        'type': 'session-agent-preset',
        'sessionId': payload['sessionId'],
        'accepted': true,
        'agentPresetId': payload['agentPresetId'],
      };
      final applied = await gw.selectAgentPreset('s1', 'p2');
      expect(applied, 'p2');
      expect(gw.requests.single.type, 'session-agent-preset');
      expect(gw.requests.single.payload, {
        'sessionId': 's1',
        'agentPresetId': 'p2',
      });
    });

    test('只声明 select-agent-preset → 用那条帧名发', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['select-agent-preset'];
      gw.replies['select-agent-preset'] = (payload) => <String, dynamic>{
        'accepted': true,
        'agentPresetId': payload['agentPresetId'],
      };
      expect(await gw.selectAgentPreset('s1', 'p3'), 'p3');
      expect(gw.requests.single.type, 'select-agent-preset');
    });

    test('帧报错（含 409）→ 回退 REST（NO_TOKEN 证明到了 REST）', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['session-agent-preset'];
      gw.errors['session-agent-preset'] = RequestException(
        'AGENT_PRESET_LOCKED',
        '409',
        statusCode: 409,
      );
      await expectLater(
        gw.selectAgentPreset('s1', 'p2'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
    });

    test('没声明帧 → 直接走 REST', () async {
      final gw = _FakeGateway();
      await expectLater(
        gw.selectAgentPreset('s1', 'p2'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests, isEmpty);
    });
  });

  group('renameWorkspace', () {
    test('声明 workspace-update → 发帧（字段 name），不回退', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['workspace-update'];
      gw.replies['workspace-update'] = (_) => <String, dynamic>{};
      await gw.renameWorkspace('ws1', '手机会话');
      expect(gw.requests.single.type, 'workspace-update');
      expect(gw.requests.single.payload, {
        'workspaceId': 'ws1',
        'name': '手机会话',
      });
    });

    test('帧报错 → 回退 REST PATCH（NO_TOKEN 证明到了 REST）', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['workspace-update'];
      gw.errors['workspace-update'] = RequestException('NOT_IMPLEMENTED', '老桥');
      await expectLater(
        gw.renameWorkspace('ws1', '手机会话'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests.single.type, 'workspace-update');
    });

    test('没声明帧 → 直接走 REST', () async {
      final gw = _FakeGateway();
      await expectLater(
        gw.renameWorkspace('ws1', '手机会话'),
        throwsA(
          isA<RequestException>().having((e) => e.code, 'code', 'NO_TOKEN'),
        ),
      );
      expect(gw.requests, isEmpty);
    });
  });

  group('sessionTasks', () {
    test('声明 tasks 帧 → 发帧并解析（id 缺失时用请求参数兜底）', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['tasks'];
      gw.replies['tasks'] = (_) => <String, dynamic>{
        'todos': <dynamic>[
          {'content': '跑测试', 'status': 'in_progress'},
        ],
      };
      final tasks = await gw.sessionTasks('s1');
      expect(tasks.sessionId, 's1');
      expect(tasks.todos.single.content, '跑测试');
      expect(gw.requests.single.payload, {'sessionId': 's1'});
    });

    test('没声明 tasks 帧 → 抛 NOT_SUPPORTED，不发帧', () async {
      final gw = _FakeGateway();
      await expectLater(
        gw.sessionTasks('s1'),
        throwsA(
          isA<RequestException>().having(
            (e) => e.code,
            'code',
            'NOT_SUPPORTED',
          ),
        ),
      );
      expect(gw.requests, isEmpty);
    });
  });

  group('history compact', () {
    test('compact=false（默认）不下发 compact 参数、应答不标摘要', () async {
      final gw = _FakeGateway();
      gw.replies['history'] = (_) => <String, dynamic>{
        'events': <dynamic>[],
        'hasMore': false,
      };
      final page = await gw.history('s1');
      expect(page.compact, isFalse);
      expect(gw.requests.single.payload.containsKey('compact'), isFalse);
    });

    test('compact=true → 下发 compact 且解析应答 compact:true', () async {
      final gw = _FakeGateway();
      gw.replies['history'] = (_) => <String, dynamic>{
        'events': <dynamic>[],
        'hasMore': false,
        'compact': true,
      };
      final page = await gw.history('s1', maxMessages: 40, compact: true);
      expect(page.compact, isTrue);
      expect(gw.requests.single.payload, {
        'sessionId': 's1',
        'maxMessages': 40,
        'compact': true,
      });
    });
  });
}
