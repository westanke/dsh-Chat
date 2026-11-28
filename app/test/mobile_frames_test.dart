/// WS 移动帧模型的解析 / round-trip / 纯函数单测。
///
/// 帧形状依据（dsh-remote-bridge HEAD 2026-11-28）：
/// - `tasks`：src/host/ws-goals.ts readProjection → data{sessionId, asOfSeq?, todos?}
/// - `chat.session.snapshot`：src/host/chat/access.ts:249 →
///   data{sessionId, cursor?, hasMore?, recordCount?}
library;

import 'package:dshchat/bridge/mobile_frames.dart';
import 'package:dshchat/bridge/projections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionTasks', () {
    test('解析 tasks 数据且 todos 与 todoItems 同一套规则', () {
      final tasks = SessionTasks.fromJson(<String, dynamic>{
        'sessionId': 's1',
        'asOfSeq': 12,
        'todos': <dynamic>[
          {'content': '写单测', 'status': 'in_progress'},
          {'content': '收尾', 'status': 'completed'},
          {'content': '   ', 'status': 'pending'}, // 空白 content → 丢弃
          {
            'id': 'x',
            'text': '变体',
            'status': 'pending',
          }, // 非 content/status → 丢弃
        ],
      });
      expect(tasks.sessionId, 's1');
      expect(tasks.asOfSeq, 12);
      expect(tasks.hasTodosProjection, isTrue);
      expect(tasks.todos.map((t) => t.content), ['写单测', '收尾']);
      expect(tasks.todos.first.isInProgress, isTrue);
      expect(tasks.todos.last.isCompleted, isTrue);
      // 与现有 projections 推导完全一致。
      final fromProjections = todoItems(<String, dynamic>{
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '写单测', 'status': 'in_progress'},
            {'content': '收尾', 'status': 'completed'},
          ],
        },
      });
      expect(
        fromProjections.map((t) => t.content),
        tasks.todos.map((t) => t.content),
      );
    });

    test('todos 缺席 / null 不算「权威空清单」', () {
      for (final json in <Map<String, dynamic>>[
        {'sessionId': 's1'},
        {'sessionId': 's1', 'todos': null},
      ]) {
        final tasks = SessionTasks.fromJson(json);
        expect(tasks.hasTodosProjection, isFalse, reason: 'json=$json');
        expect(tasks.todos, isEmpty);
      }
    });

    test('显式 JSON round-trip', () {
      const tasks = SessionTasks(
        sessionId: 's9',
        asOfSeq: 33,
        todos: [
          TodoItem(content: 'a', status: 'pending'),
          TodoItem(content: 'b', status: 'completed'),
        ],
        hasTodosProjection: true,
      );
      final again = SessionTasks.fromJson(tasks.toJson());
      expect(again.sessionId, 's9');
      expect(again.asOfSeq, 33);
      expect(again.hasTodosProjection, isTrue);
      expect(again.todos.map((t) => t.toJson()), [
        {'content': 'a', 'status': 'pending'},
        {'content': 'b', 'status': 'completed'},
      ]);
    });

    test('无 todos 投影也能 round-trip', () {
      const tasks = SessionTasks(sessionId: 's2');
      final again = SessionTasks.fromJson(tasks.toJson());
      expect(again.hasTodosProjection, isFalse);
      expect(again.asOfSeq, isNull);
    });
  });

  group('SessionSnapshot', () {
    test('解析 cursor / hasMore / recordCount', () {
      final snap = SessionSnapshot.fromJson(<String, dynamic>{
        'sessionId': 's1',
        'cursor': 42,
        'hasMore': true,
        'recordCount': 300,
      });
      expect(snap.sessionId, 's1');
      expect(snap.cursor, 42);
      expect(snap.hasMore, isTrue);
      expect(snap.recordCount, 300);
    });

    test('字段缺席时保守解析（cursor null / hasMore false）', () {
      final snap = SessionSnapshot.fromJson(<String, dynamic>{
        'sessionId': 's1',
      });
      expect(snap.cursor, isNull);
      expect(snap.hasMore, isFalse);
      expect(snap.recordCount, isNull);
    });

    test('显式 JSON round-trip', () {
      const snap = SessionSnapshot(
        sessionId: 's1',
        cursor: 7,
        hasMore: true,
        recordCount: 11,
      );
      final again = SessionSnapshot.fromJson(snap.toJson());
      expect(again.toJson(), snap.toJson());
    });
  });

  group('shouldSkipSessionResync', () {
    const base = SessionSnapshot(sessionId: 's1', cursor: 100);

    test('已有基线且 cursor 未前进 → 可跳过', () {
      expect(
        shouldSkipSessionResync(
          base,
          const SessionSnapshot(sessionId: 's1', cursor: 100),
        ),
        isTrue,
      );
      expect(
        shouldSkipSessionResync(
          base,
          const SessionSnapshot(sessionId: 's1', cursor: 80),
        ),
        isTrue,
      );
    });

    test('cursor 前进 → 不可跳过', () {
      expect(
        shouldSkipSessionResync(
          base,
          const SessionSnapshot(sessionId: 's1', cursor: 101),
        ),
        isFalse,
      );
    });

    test('缺基线 / 缺 cursor / 会话不同 / 有积压 → 不可跳过', () {
      expect(shouldSkipSessionResync(null, base), isFalse);
      expect(shouldSkipSessionResync(base, null), isFalse);
      expect(
        shouldSkipSessionResync(base, const SessionSnapshot(sessionId: 's1')),
        isFalse,
      );
      expect(
        shouldSkipSessionResync(
          base,
          const SessionSnapshot(sessionId: 's2', cursor: 100),
        ),
        isFalse,
      );
      expect(
        shouldSkipSessionResync(
          base,
          const SessionSnapshot(sessionId: 's1', cursor: 100, hasMore: true),
        ),
        isFalse,
      );
    });
  });

  group('projectionsWithTodos', () {
    const tasks = SessionTasks(
      sessionId: 's1',
      todos: [TodoItem(content: '权威', status: 'completed')],
      hasTodosProjection: true,
    );

    test('合并进 values.todos，保留其它投影', () {
      final merged = projectionsWithTodos(<String, dynamic>{
        'kind': 'baseline',
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '本地推导', 'status': 'pending'},
          ],
          'team': <String, dynamic>{'members': 1},
        },
      }, tasks);
      expect(merged!['kind'], 'baseline');
      expect(todoItems(merged).single.content, '权威');
      expect((merged['values'] as Map)['team'], {'members': 1});
    });

    test('projections 为 null 时生成最小形状', () {
      final merged = projectionsWithTodos(null, tasks);
      expect(todoItems(merged).single.content, '权威');
    });

    test('没有权威清单时原样返回（不清本地推导）', () {
      final projections = <String, dynamic>{
        'values': <String, dynamic>{
          'todos': <dynamic>[
            {'content': '本地推导', 'status': 'pending'},
          ],
        },
      };
      final merged = projectionsWithTodos(
        projections,
        const SessionTasks(sessionId: 's1'),
      );
      expect(identical(merged, projections), isTrue);
      expect(todoItems(merged).single.content, '本地推导');
    });
  });
}
