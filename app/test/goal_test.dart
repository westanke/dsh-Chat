/// 目标（goal）投影解析与状态口径的单测（对照 dsh-go goals_api + GoalLook）。
library;

import 'package:dshchat/bridge/goal.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/goal_dock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _projection({
  String id = 'g1',
  int revision = 3,
  String objective = '把登录迁到新接口',
  String phase = 'active',
  int maxGoalRounds = 256,
  int roundsStarted = 0,
  Map<String, dynamic>? blockedReason,
}) => {
  'values': {
    'goal': {
      'goal': {
        'id': id,
        'revision': revision,
        'objective': objective,
        'phase': phase,
        'maxGoalRounds': maxGoalRounds,
        'blockedReason': ?blockedReason,
      },
      'roundsStarted': roundsStarted,
    },
  },
};

void main() {
  group('goalOf', () {
    test('解析投影里的目标与轮次', () {
      final g = goalOf(_projection(roundsStarted: 2))!;
      expect(g.goal.id, 'g1');
      expect(g.goal.revision, 3);
      expect(g.goal.objective, '把登录迁到新接口');
      expect(g.goal.phase, GoalPhase.active);
      expect(g.goal.maxGoalRounds, 256);
      expect(g.roundsStarted, 2);
      expect(g.ref, const GoalRef('g1', 3));
    });

    test('投影缺失 / 形状不认识 → null（不报错）', () {
      expect(goalOf(null), isNull);
      expect(goalOf(const {}), isNull);
      expect(goalOf(const {'values': {}}), isNull);
      expect(goalOf(const {'values': {'goal': null}}), isNull);
    });

    test('phase 不认识 → 整条丢弃', () {
      expect(goalOf(_projection(phase: 'unknown')), isNull);
    });

    test('受阻原因只在 blocked 时解析', () {
      final blocked = goalOf(
        _projection(
          phase: 'blocked',
          blockedReason: {'code': 'no-progress', 'message': '连续三轮没有进展'},
        ),
      )!;
      expect(blocked.goal.blockedReason?.message, '连续三轮没有进展');
      final active = goalOf(
        _projection(blockedReason: {'code': 'x', 'message': '不该显示'}),
      )!;
      expect(active.goal.blockedReason, isNull);
    });
  });

  group('goalHeadline', () {
    test('取第一条非空行', () {
      expect(goalHeadline('  第一行  \n第二行'), '第一行');
      expect(goalHeadline('\n\n 只有这行'), '只有这行');
      expect(goalHeadline('单行目标'), '单行目标');
    });
  });

  group('状态口径', () {
    test('进行中不显示状态词，暂停/受阻才显示', () {
      expect(goalStateLabel(goalOf(_projection())!), isNull);
      expect(goalStateLabel(goalOf(_projection(phase: 'paused'))!), '已暂停');
      expect(goalStateLabel(goalOf(_projection(phase: 'blocked'))!), '受阻');
      expect(goalStateLabel(goalOf(_projection(phase: 'complete'))!), '已完成');
    });

    test('暂停/恢复按钮的可用性', () {
      expect(goalCanPause(goalOf(_projection())!), isTrue);
      expect(goalCanPause(goalOf(_projection(phase: 'paused'))!), isFalse);
      expect(goalCanResume(goalOf(_projection(phase: 'paused'))!), isTrue);
      expect(goalCanResume(goalOf(_projection())!), isFalse);
    });

    test('状态行带轮次，最大轮次为 0 时只写已跑轮次', () {
      expect(
        goalStatusLine(goalOf(_projection(roundsStarted: 3))!),
        '进行中 · 第 3 / 256 轮',
      );
      expect(
        goalStatusLine(goalOf(_projection(roundsStarted: 3, maxGoalRounds: 0))!),
        '进行中 · 第 3 轮',
      );
      expect(goalStatusLine(goalOf(_projection())!), '进行中');
    });
  });

  group('GoalDockBar', () {
    testWidgets('显示目标首行；暂停目标带「已暂停」，进行中不带状态词', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalDockBar(
              goal: goalOf(_projection(objective: '把登录迁到新接口\n细节不必上条'))!,
              colors: DsColors(false),
            ),
          ),
        ),
      );
      expect(find.text('目标'), findsOneWidget);
      expect(find.text('把登录迁到新接口'), findsOneWidget);
      expect(find.text('已暂停'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalDockBar(
              goal: goalOf(_projection(phase: 'paused'))!,
              colors: DsColors(false),
            ),
          ),
        ),
      );
      expect(find.text('已暂停'), findsOneWidget);
    });
  });
}
