/// ChatState 的 WS 新通道单测：权威 todos 合并 / 回退、快照基线判定、紧凑历史。
library;

import 'dart:async';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/mobile_frames.dart';
import 'package:dshchat/bridge/projections.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假网关：events/state 用本地广播流，request 按 type 回放预设应答。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final _events = StreamController<GatewayEvent>.broadcast();
  final _states = StreamController<GatewayState>.broadcast();
  final List<({String type, Map<String, dynamic> payload})> requests = [];

  Map<String, dynamic>? tasksReply;
  RequestException? tasksError;
  Map<String, dynamic>? historyReply;

  @override
  Stream<GatewayEvent> get events => _events.stream;

  @override
  Stream<GatewayState> get state => _states.stream;

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type: type, payload: Map<String, dynamic>.from(payload)));
    switch (type) {
      case 'tasks':
        final error = tasksError;
        if (error != null) throw error;
        return tasksReply ??
            <String, dynamic>{'sessionId': payload['sessionId']};
      case 'history':
        return historyReply ??
            <String, dynamic>{'events': <dynamic>[], 'hasMore': false};
      default:
        return <String, dynamic>{};
    }
  }

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) => request(type, payload);

  void push(GatewayEvent event) => _events.add(event);
}

void main() {
  group('refreshSessionTasks', () {
    late _FakeGateway gw;

    setUp(() {
      gw = _FakeGateway();
      gw.supportedFrames = const ['tasks'];
    });

    test('成功：暴露 sessionTasks 并合并进 projections（页面同源可见）', () async {
      gw.tasksReply = <String, dynamic>{
        'sessionId': 's1',
        'asOfSeq': 9,
        'todos': <dynamic>[
          {'content': '权威待办', 'status': 'in_progress'},
        ],
      };
      final state = ChatState(gw);
      state.sessionId = 's1';
      state.projections = <String, dynamic>{
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '旧推导', 'status': 'pending'},
          ],
          'team': <String, dynamic>{'n': 1},
        },
      };

      await state.refreshSessionTasks('s1');

      expect(state.sessionTasks, isNotNull);
      expect(state.sessionTasks!.todos.single.content, '权威待办');
      expect(todoItems(state.projections).single.content, '权威待办');
      expect((state.projections!['values'] as Map)['team'], {'n': 1});

      state.dispose();
    });

    test('todos 为 null：不覆盖本地推导', () async {
      gw.tasksReply = <String, dynamic>{'sessionId': 's1', 'todos': null};
      final state = ChatState(gw);
      state.sessionId = 's1';
      state.projections = <String, dynamic>{
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '旧推导', 'status': 'pending'},
          ],
        },
      };

      await state.refreshSessionTasks('s1');

      expect(state.sessionTasks!.hasTodosProjection, isFalse);
      expect(todoItems(state.projections).single.content, '旧推导');

      state.dispose();
    });

    test('帧报错：静默回退，projections 与 sessionTasks 都保持原样', () async {
      gw.tasksError = RequestException('UNKNOWN_TYPE', '老桥不认');
      final state = ChatState(gw);
      state.sessionId = 's1';
      state.projections = <String, dynamic>{
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '旧推导', 'status': 'pending'},
          ],
        },
      };

      await state.refreshSessionTasks('s1');

      expect(state.sessionTasks, isNull);
      expect(todoItems(state.projections).single.content, '旧推导');
      expect(state.lastError, isNull);

      state.dispose();
    });

    test('缺 frames：不发 tasks 帧（旧行为不变）', () async {
      gw.supportedFrames = const [];
      final state = ChatState(gw);
      state.sessionId = 's1';

      await state.refreshSessionTasks('s1');

      expect(gw.requests, isEmpty);
      expect(state.sessionTasks, isNull);

      state.dispose();
    });

    test('应答到达时已切走会话：不污染当前页', () async {
      gw.tasksReply = <String, dynamic>{
        'sessionId': 's1',
        'todos': <dynamic>[
          {'content': 'A 的待办', 'status': 'pending'},
        ],
      };
      final state = ChatState(gw);
      state.sessionId = 's1';

      await state.refreshSessionTasks('s1');
      expect(state.sessionTasks, isNotNull);
      state.sessionId = 's2'; // 切走
      state.sessionTasks = null;
      state.projections = null;
      await state.refreshSessionTasks('s1'); // 迟到的旧会话请求

      expect(state.sessionTasks, isNull);
      expect(state.projections, isNull);

      state.dispose();
    });
  });

  group('chat.session.snapshot 记录与 resync 判定', () {
    test('事件流写入 latest、baseline 只记第一次', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 's1';

      gw.push(
        const SessionSnapshotEvent(
          SessionSnapshot(sessionId: 's1', cursor: 10, recordCount: 5),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.sessionSnapshots['s1']!.cursor, 10);

      gw.push(
        const SessionSnapshotEvent(
          SessionSnapshot(sessionId: 's1', cursor: 10),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // cursor 未前进：基线仍是第一次见的 10，判定可跳过。
      expect(state.shouldSkipResyncReload('s1'), isTrue);

      gw.push(
        const SessionSnapshotEvent(
          SessionSnapshot(sessionId: 's1', cursor: 12),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.shouldSkipResyncReload('s1'), isFalse);

      state.dispose();
    });

    test('没有快照时判定为 false（老桥不发 session-snapshot-v1）', () {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      expect(state.shouldSkipResyncReload('s1'), isFalse);
      state.dispose();
    });
  });

  group('prefetchCompactHistory', () {
    test('声明 history 帧 → 请求 compact:true 并缓存应答', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['history'];
      gw.historyReply = <String, dynamic>{
        'events': <dynamic>[],
        'hasMore': false,
        'compact': true,
      };
      final state = ChatState(gw);
      state.sessionId = 's1';

      final page = await state.prefetchCompactHistory('s1', maxMessages: 60);

      expect(page, isNotNull);
      expect(page!.compact, isTrue);
      expect(state.compactHistoryPrefetch, same(page));
      expect(gw.requests.single.type, 'history');
      expect(gw.requests.single.payload['compact'], isTrue);
      expect(gw.requests.single.payload['maxMessages'], 60);

      state.dispose();
    });

    test('缺 frames → 不请求、返回 null（首屏默认全文行为不变）', () async {
      final gw = _FakeGateway();
      final state = ChatState(gw);
      state.sessionId = 's1';

      final page = await state.prefetchCompactHistory('s1');

      expect(page, isNull);
      expect(gw.requests, isEmpty);
      expect(state.compactHistoryPrefetch, isNull);

      state.dispose();
    });

    test('应答没标 compact:true → 不当作摘要缓存', () async {
      final gw = _FakeGateway();
      gw.supportedFrames = const ['history'];
      gw.historyReply = <String, dynamic>{
        'events': <dynamic>[],
        'hasMore': false,
      };
      final state = ChatState(gw);
      state.sessionId = 's1';

      final page = await state.prefetchCompactHistory('s1');

      expect(page, isNull);
      expect(state.compactHistoryPrefetch, isNull);

      state.dispose();
    });
  });
}
