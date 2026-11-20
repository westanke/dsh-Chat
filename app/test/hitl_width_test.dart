// HITL 卡片的宽窗限宽回归测试（docs/design-tokens.md §4.16）。
//
// 不变量：卡片在手机上铺满正文列（不受上限约束），宽窗收在 720 与正文同一
// 竖轴。这里直接量渲染出来的卡片宽度，而不是只断言 getter 的数值——限宽是
// 布局行为，数值对但没套上 ConstrainedBox 的话看表面看不出来。

import 'package:dshchat/bridge/questions.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/hitl_state.dart';
import 'package:dshchat/ui/question_card.dart';
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
  testWidgets('手机（360dp）上卡片铺满整行，不受上限约束', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(360, 800));
    expect(width, 360);
  });

  testWidgets('平板横屏（1181dp）上卡片收在 720，与正文同一竖轴', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(1181, 738));
    expect(width, DsSpacing.hitlPanelMaxWidth);
  });

  testWidgets('平板竖屏（738dp，中等档）同样收住', (tester) async {
    final width = await _approvalCardWidth(tester, const Size(738, 1181));
    expect(width, DsSpacing.hitlPanelMaxWidth);
  });
}
