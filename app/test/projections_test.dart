/// history 投影纯函数单测（提交 D）。
/// 对照 dsh-companion data/Trajectory.kt、AgentTeamProjection.kt、
/// ChatPresentation.kt；桥 fixture 见
/// dsh-remote-bridge/tests/mobile-gateway-ws.spec.ts:1251-1253,2250。
library;

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/bridge/projections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trajectoryOf', () {
    test('按 data.turn 分组、组内按 seq 排序、丢弃内核过程细节', () {
      // 故意乱序给，验证组内 sortedBy(seq) 而非数组顺序。
      final events = <Map<String, dynamic>>[
        {
          'type': 'turn/end',
          'seq': 6,
          'time': 140,
          'data': {'turn': 1, 'reason': {'kind': 'completed'}},
        },
        {
          'type': 'user/message',
          'seq': 2,
          'time': 110,
          'data': {'turn': 1, 'content': 'hi'},
        },
        {
          'type': 'tool/call',
          'seq': 4,
          'time': 120,
          'data': {'turn': 1, 'name': 'bash'},
        },
        // 以下四条按 companion Trajectory.kt:172-185 刻意丢弃。
        {'type': 'turn/start', 'seq': 1, 'time': 100, 'data': {'turn': 1}},
        {'type': 'step/start', 'seq': 3, 'time': 115, 'data': {'turn': 1}},
        {'type': 'step/end', 'seq': 3, 'time': 116, 'data': {'turn': 1}},
        {'type': 'tool/result', 'seq': 5, 'time': 130, 'data': {'turn': 1}},
      ];
      final turns = trajectoryOf(events);
      expect(turns.length, 1);
      expect(turns[0].turn, 1);
      expect(turns[0].nodes.length, 3);
      expect(turns[0].nodes[0].seq, 2);
      expect(turns[0].nodes[2].seq, 6);
      expect(turns[0].nodes.map((n) => n.kind), <TrajectoryNodeKind>[
        TrajectoryNodeKind.user,
        TrajectoryNodeKind.tool,
        TrajectoryNodeKind.turnEnd,
      ]);
      expect(turns[0].nodes[1].label, 'bash');
      expect(turns[0].toolCalls, 1);
      // 按 seq 序首尾 time 差：140 - 110 = 30。
      expect(turns[0].durationMillis, 30);
      expect(turns[0].nodes[1].raw!['name'], 'bash');
    });

    test('无 data.turn 的未知轮次垫底，未知事件类型保留为 other', () {
      final turns = trajectoryOf(<Map<String, dynamic>>[
        {
          'type': 'user/message',
          'seq': 2,
          'time': 100,
          'data': {'turn': 1},
        },
        {
          'type': 'mystery/event',
          'seq': 9,
          'time': 200,
          'data': <String, dynamic>{},
        },
      ]);
      expect(turns.length, 2);
      expect(turns[0].turn, 1);
      expect(turns[1].isUnknown, true);
      expect(turns[1].nodes.single.kind, TrajectoryNodeKind.other);
      expect(turns[1].nodes.single.type, 'mystery/event');
      expect(turns[1].durationMillis, isNull);
    });

    test('空历史返回空列表', () {
      expect(trajectoryOf(const <Map<String, dynamic>>[]), isEmpty);
    });
  });

  group('todoItems', () {
    test('只认 {content,status}，丢弃变体 / 空白 / 缺字段', () {
      final todos = todoItems(<String, dynamic>{
        'values': {
          'todos': [
            {'content': '检查 SDK', 'status': 'completed'},
            {'content': '构建 APK', 'status': 'in_progress'},
            // 桥 fixture 的 {id,text,status} 变体：companion 会丢弃。
            {'id': 'x', 'text': '整理待办', 'status': 'pending'},
            {'content': '   ', 'status': 'pending'},
            {'content': '没有状态'},
          ],
        },
      });
      expect(todos.length, 2);
      expect(todos[0].content, '检查 SDK');
      expect(todos[0].isCompleted, isTrue);
      expect(todos[1].isInProgress, isTrue);
    });

    test('projections 缺席 / values 缺失 / todos 非数组都返回空', () {
      expect(todoItems(null), isEmpty);
      expect(todoItems(<String, dynamic>{}), isEmpty);
      expect(todoItems(<String, dynamic>{'values': null}), isEmpty);
      expect(
        todoItems(<String, dynamic>{
          'values': {'todos': 'not-a-list'},
        }),
        isEmpty,
      );
    });
  });

  group('agentTeamProjectionOf', () {
    test('解析成员 / 任务 / 子会话，补齐缺省值', () {
      final team = agentTeamProjectionOf(<String, dynamic>{
        'values': {
          'agentTeam': {
            'members': [
              {'id': 'lead', 'name': 'lead', 'role': 'lead', 'phase': 'active'},
              {'id': 'w1'},
            ],
            'tasks': [
              {
                'id': 't1',
                'subject': '做 X',
                'status': 'completed',
                'ownerName': 'w1',
                'blockedBy': ['t0'],
                'writeScopes': ['lib/'],
                'ready': false,
              },
            ],
          },
          'subagentCatalog': [
            {'id': 's1', 'mode': 'fork', 'label': '子会话', 'createdAt': 123},
            {'sessionId': 's2'},
          ],
        },
      });
      expect(team, isNotNull);
      expect(team!.hasTeam, isTrue);
      expect(team.members.length, 2);
      expect(team.members[0].isLead, isTrue);
      // name 缺省回退到 id。
      expect(team.members[1].name, 'w1');
      expect(team.members[1].role, 'teammate');
      expect(team.tasks.single.blockedBy, <String>['t0']);
      expect(team.tasks.single.writeScopes, <String>['lib/']);
      expect(team.tasks.single.ready, isFalse);
      expect(team.completedTasks, 1);
      expect(team.subagents.length, 2);
      // 兼容老夹具 sessionId。
      expect(team.subagents[1].id, 's2');
      expect(team.failure, isNull);
    });

    test('空壳 / 投影缺席返回 null；仅有 failure 也返回非 null', () {
      expect(agentTeamProjectionOf(null), isNull);
      expect(agentTeamProjectionOf(<String, dynamic>{'values': {}}), isNull);
      expect(
        agentTeamProjectionOf(<String, dynamic>{
          'values': {
            'agentTeam': {'failure': 'team plugin unavailable'},
          },
        })!.failure,
        'team plugin unavailable',
      );
    });
  });

  group('prettyJson', () {
    test('null 给空态文案，其余输出缩进 JSON', () {
      expect(prettyJson(null), '（这条事件没有载荷）');
      expect(prettyJson(<String, dynamic>{'a': 1}), contains('"a": 1'));
    });
  });

  group('HistoryPage 保留原始事件与投影', () {
    test('fromEvents 归一化 rawEvents 并透传 projections', () {
      final page = HistoryPage.fromEvents(
        <dynamic>[
          {
            'event': {
              'type': 'user/message',
              'seq': 1,
              'time': 10,
              'data': {
                'content': 'hi',
                'source': {'kind': 'user'},
              },
            },
          },
        ],
        projections: <String, dynamic>{
          'asOfSeq': 1,
          'values': {
            'todos': [
              {'content': 'x', 'status': 'pending'},
            ],
          },
        },
      );
      expect(page.items.length, 1);
      expect(page.rawEvents.length, 1);
      expect(page.rawEvents.single['type'], 'user/message');
      expect(page.rawEvents.single['seq'], 1);
      // REST 外包装已剥掉，data 是 Map。
      expect(page.rawEvents.single['data'], isA<Map<String, dynamic>>());
      expect(page.projections!['asOfSeq'], 1);
    });

    test('不给 projections 时为 null（老用例兼容）', () {
      final page = HistoryPage.fromEvents(<dynamic>[
        {
          'type': 'user/message',
          'seq': 1,
          'time': 10,
          'data': {
            'content': 'hi',
            'source': {'kind': 'user'},
          },
        },
      ]);
      expect(page.projections, isNull);
      expect(page.rawEvents.length, 1);
    });
  });
}
