// 活动条承载后台任务绿色胶囊（2026-11-28 用户要求）。
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/activity_strip.dart';
import 'package:dshchat/ui/tool_present.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _a = LiveActivity(
  kind: ToolActivityKind.thinking,
  label: '思考中',
  detail: null,
  since: null,
);

Future<void> _pump(
  WidgetTester tester, {
  LiveActivity? activity,
  int jobs = 0,
  VoidCallback? onOpenJobs,
  bool showSchedule = false,
  VoidCallback? onOpenSchedule,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ActivityStrip(
          activity: activity,
          colors: const DsColors(false),
          jobsRunning: jobs,
          onOpenJobs: onOpenJobs,
          showSchedule: showSchedule,
          onOpenSchedule: onOpenSchedule,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('只有后台任务时活动条也显示绿色胶囊并可点', (tester) async {
    var taps = 0;
    await _pump(tester, jobs: 2, onOpenJobs: () => taps++);
    expect(find.text('后台 2'), findsOneWidget);
    await tester.tap(find.text('后台 2'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('活动与后台任务同时在：活动文案和胶囊同排', (tester) async {
    await _pump(tester, activity: _a, jobs: 1);
    expect(find.textContaining('思考中'), findsOneWidget);
    expect(find.text('后台 1'), findsOneWidget);
  });

  testWidgets('定时任务收起成浅黄时钟图标，只有它时也占位', (tester) async {
    var taps = 0;
    await _pump(tester, showSchedule: true, onOpenSchedule: () => taps++);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('没有活动也没有任务时不占位', (tester) async {
    await _pump(tester);
    expect(find.byType(ActivityStrip), findsOneWidget);
    expect(find.textContaining('后台'), findsNothing);
    expect(
      tester.getSize(find.byType(ActivityStrip)).height,
      0,
    );
  });
}
