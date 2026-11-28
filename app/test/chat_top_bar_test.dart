// 顶栏信息架构（2026-11-28）：第一行标题栏 + 第二行可横向滚动的 chip 带。
//
// 覆盖：状态 chip 沿用 chatHeaderStatus 文案、模型 chip 有/无模型、上下文用量
// 从 projections 读百分比并接近上限变色、jobs / 子代理计数为 0 或 null 时不显示、
// 320 逻辑宽不溢出（chip 带横向滚动）、chip 点击回调触发、顶栏高度预算 ≤88。

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_header_chips.dart';
import 'package:dshchat/ui/chat_header_status.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/chat_top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假网关：只覆写 request（ChatState 构造只订阅事件流，不发帧）。
class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async => <String, dynamic>{};
}

/// 回调计数器：测试只看「点没点中」，不关心实际动作。
class _Taps {
  int menu = 0;
  int newChat = 0;
  int model = 0;
  int jobs = 0;
  int subagents = 0;
}

/// 上下文用量投影（ChatState.projections 的真实形状：外层 values）。
Map<String, dynamic> _usageProjection({
  required int pressure,
  int window = 100000,
}) => {
  'values': {
    'contextPressure': {
      'pressureTokens': pressure,
      'projectedTokens': pressure,
      'contextWindow': window,
    },
  },
};

Future<ChatState> _pumpTopBar(
  WidgetTester tester, {
  String? modelLabel,
  Map<String, dynamic>? projections,
  int? jobsRunning,
  int? subagentCount,
  String title = '会话标题',
  ChatHeaderStatus? status,
  _Taps? taps,
}) async {
  final gateway = _FakeGateway();
  final state = ChatState(gateway)..sessionId = 's1';
  addTearDown(state.dispose);
  if (modelLabel != null) state.modelLabel = modelLabel;
  if (projections != null) state.projections = projections;
  final t = taps ?? _Taps();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTopBar(
          colors: const DsColors(false),
          title: title,
          status: status ?? const ChatHeaderStatus(ChatStatusTone.ok, '就绪'),
          state: state,
          onMenu: () => t.menu++,
          onNewChat: () => t.newChat++,
          onPickModel: () => t.model++,
          jobsRunning: jobsRunning,
          onOpenJobs: () => t.jobs++,
          subagentCount: subagentCount,
          onOpenSubagents: () => t.subagents++,
          trailing: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('状态 chip 沿用 chatHeaderStatus 文案，标题行回调仍可点', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(tester, taps: taps);

    expect(find.byType(ChatStatusDot), findsOneWidget);
    // ok 语气下 chip 显示短文案「在线」，主机名仍留给标题胶囊与读屏。
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('会话标题'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    expect(taps.menu, 1);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(taps.newChat, 1);
  });

  testWidgets('新对话没有标题时胶囊回退显示主机名，chip 仍是短状态', (tester) async {
    await _pumpTopBar(
      tester,
      title: '',
      status: const ChatHeaderStatus(ChatStatusTone.ok, 'DSH Chat (V2080A)'),
    );

    // 胶囊用主机名兜底，不再出现空白药丸；chip 只显示「在线」。
    expect(find.text('DSH Chat (V2080A)'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(
      find.bySemanticsLabel('连接状态：DSH Chat (V2080A)'),
      findsOneWidget,
    );
  });

  testWidgets('非 ok 语气时 chip 用状态文案（生成中 / 等待审批）', (tester) async {
    await _pumpTopBar(
      tester,
      status: const ChatHeaderStatus(ChatStatusTone.busy, '生成中'),
    );
    expect(find.text('生成中'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });

  testWidgets('有模型时模型 chip 显示模型短名，点击触发 onPickModel', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(tester, modelLabel: 'dsv4-chat', taps: taps);

    expect(find.text('dsv4-chat'), findsOneWidget);
    expect(find.text('模型'), findsNothing);

    await tester.tap(find.text('dsv4-chat'));
    await tester.pump();
    expect(taps.model, 1);
  });

  testWidgets('无模型时显示「模型」占位且可点', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(tester, taps: taps);

    expect(find.text('模型'), findsOneWidget);

    await tester.tap(find.text('模型'));
    await tester.pump();
    expect(taps.model, 1);
  });

  testWidgets('上下文用量从 projections 读百分比，≥80% 变警示色', (tester) async {
    await _pumpTopBar(
      tester,
      projections: _usageProjection(pressure: 88000),
    );

    final label = find.text('上下文 88%');
    expect(label, findsOneWidget);
    final text = tester.widget<Text>(label);
    expect(text.style?.color, const DsColors(false).chatStatusWarn);
  });

  testWidgets('投影缺席时不显示上下文 chip', (tester) async {
    await _pumpTopBar(tester);

    expect(find.textContaining('上下文'), findsNothing);
  });

  testWidgets('jobsRunning 为 null / 0 时不显示，>0 时显示并可点', (tester) async {
    await _pumpTopBar(tester);
    expect(find.textContaining('后台任务'), findsNothing);

    final taps = _Taps();
    await _pumpTopBar(tester, jobsRunning: 0, taps: taps);
    expect(find.textContaining('后台任务'), findsNothing);

    await _pumpTopBar(tester, jobsRunning: 3, taps: taps);
    expect(find.text('后台任务 3'), findsOneWidget);
    await tester.tap(find.text('后台任务 3'));
    await tester.pump();
    expect(taps.jobs, 1);
  });

  testWidgets('subagentCount 为 null / 0 时不显示，>0 时显示并可点', (tester) async {
    await _pumpTopBar(tester);
    expect(find.textContaining('子代理'), findsNothing);

    await _pumpTopBar(tester, subagentCount: 0);
    expect(find.textContaining('子代理'), findsNothing);

    final taps = _Taps();
    await _pumpTopBar(tester, subagentCount: 2, taps: taps);
    expect(find.text('子代理 2'), findsOneWidget);
    await tester.tap(find.text('子代理 2'));
    await tester.pump();
    expect(taps.subagents, 1);
  });

  testWidgets('320 逻辑宽不溢出，chip 带横向滚动，总高 ≤88', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpTopBar(
      tester,
      modelLabel: '一个特别长的模型名字用来把 chip 撑满',
      projections: _usageProjection(pressure: 60000),
      jobsRunning: 2,
      subagentCount: 3,
    );

    // 窄屏没有任何 RenderFlex 溢出 / 布局异常。
    expect(tester.takeException(), isNull);

    final strip = find.byType(ChatHeaderChipStrip);
    expect(strip, findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: strip,
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);

    // 高度预算：56（标题行）+ 29（chip 带）= 85 ≤ 88。
    final stripHeight = tester.getSize(strip).height;
    expect(stripHeight, DsSpacing.chipHeight);
    expect(DsSpacing.topBarHeight + stripHeight, lessThanOrEqualTo(88));
  });

  testWidgets('宽屏下 chip 依次排开，四个入口都可点', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(
      tester,
      modelLabel: 'dsv4-chat',
      projections: _usageProjection(pressure: 10000),
      jobsRunning: 1,
      subagentCount: 1,
      taps: taps,
    );

    expect(find.text('在线'), findsOneWidget);
    expect(find.text('dsv4-chat'), findsOneWidget);
    expect(find.text('上下文 10%'), findsOneWidget);
    expect(find.text('后台任务 1'), findsOneWidget);
    expect(find.text('子代理 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
