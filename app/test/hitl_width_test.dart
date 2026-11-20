// HITL 卡片的宽度回归测试（docs/design-tokens.md §4.16）。
//
// 不变量：卡片与正文同列。列宽由 readableColumnWidth 统一算：屏宽不超过 720
// 时用满（手机逐字不变），超过 720 后按 0.9 随屏宽长——不再有 720 硬上限。
// 这里直接量渲染出来的宽度，而不是只断言函数的数值：限宽是布局行为，
// 数值对但没套上 ConstrainedBox 的话看表面看不出来。

import 'package:dshchat/bridge/questions.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/hitl_state.dart';
import 'package:dshchat/ui/question_card.dart';
import 'package:dshchat/ui/window_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _approval = PendingApproval(
  approvalId: 'ap1',
  sessionId: 's1',
  toolName: 'bash',
  reason: '需要执行命令',
);

/// 量卡片所在那一列的实际宽度：HitlPanel 自己铺满整行，限宽套在里面的
/// SingleChildScrollView 上，所以量它。
Future<double> _approvalCardWidth(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final hitl = HitlState()..pendingApprovals['ap1'] = _approval;
  addTearDown(hitl.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HitlPanel(
          state: hitl,
          sessionId: 's1',
          colors: const DsColors(false),
          onAnswer: (_, _) {},
          onDecide: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(SingleChildScrollView)).width;
}

void main() {
  testWidgets('手机（360dp）上卡片铺满整行', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(360, 800));
    expect(width, 360);
    expect(readableColumnWidth(360), 360);
  });

  testWidgets('平板横屏（1181dp）卡片与正文同列，按 0.9 缩放', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(1181, 738));
    expect(width, closeTo(1062.9, 0.5));
    expect(readableColumnWidth(1181), closeTo(1062.9, 1e-9));
  });

  testWidgets('平板竖屏（738dp，中等档）列宽 720', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(738, 1181));
    expect(width, DsSpacing.readableBaseWidth);
    expect(readableColumnWidth(738), DsSpacing.readableBaseWidth);
  });
}
