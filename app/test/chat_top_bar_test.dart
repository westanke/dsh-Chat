// 顶栏收口（2026-11-28 用户反馈）：状态改成标题前色点；模型/上下文/子代理不再
// 在顶栏重复出现；只有后台任务在跑时多一行 chip。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_header_status.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/chat_top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async => <String, dynamic>{};
}

class _Taps {
  int menu = 0;
  int newChat = 0;
  int jobs = 0;
}

Future<void> _pumpTopBar(
  WidgetTester tester, {
  String title = '会话标题',
  ChatHeaderStatus? status,
  int? jobsRunning,
  _Taps? taps,
}) async {
  final gateway = _FakeGateway();
  final state = ChatState(gateway)..sessionId = 's1';
  addTearDown(state.dispose);
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
          jobsRunning: jobsRunning,
          onOpenJobs: () => t.jobs++,
          trailing: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
}

ChatStatusDot _dot(WidgetTester tester) =>
    tester.widget<ChatStatusDot>(find.byType(ChatStatusDot));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('已连接空闲：标题前绿点常亮，不再显示「在线」文字', (tester) async {
    await _pumpTopBar(tester);
    const c = DsColors(false);
    expect(_dot(tester).color, c.chatStatusOk);
    expect(_dot(tester).pulsing, isFalse);
    expect(find.text('在线'), findsNothing);
    expect(find.text('会话标题'), findsOneWidget);
  });

  testWidgets('生成中：绿点呼吸（工作中）', (tester) async {
    await _pumpTopBar(
      tester,
      status: const ChatHeaderStatus(ChatStatusTone.busy, '生成中'),
    );
    const c = DsColors(false);
    expect(_dot(tester).color, c.chatStatusOk);
    expect(_dot(tester).pulsing, isTrue);
  });

  testWidgets('连接中：黄点常亮', (tester) async {
    await _pumpTopBar(
      tester,
      status: const ChatHeaderStatus(ChatStatusTone.busy, '连接中'),
    );
    const c = DsColors(false);
    expect(_dot(tester).color, c.chatStatusWarn);
    expect(_dot(tester).pulsing, isFalse);
  });

  testWidgets('断开：红点；等用户：蓝点', (tester) async {
    await _pumpTopBar(
      tester,
      status: const ChatHeaderStatus(ChatStatusTone.error, '已断开'),
    );
    expect(_dot(tester).color, const DsColors(false).danger);

    await _pumpTopBar(
      tester,
      status: const ChatHeaderStatus(ChatStatusTone.warn, '等待审批'),
    );
    expect(_dot(tester).color, const DsColors(false).brand);
  });

  testWidgets('新对话无标题时胶囊回退主机名', (tester) async {
    await _pumpTopBar(
      tester,
      title: '',
      status: const ChatHeaderStatus(ChatStatusTone.ok, 'DSH Chat (V2080A)'),
    );
    expect(find.text('DSH Chat (V2080A)'), findsOneWidget);
    expect(
      find.bySemanticsLabel('DSH Chat (V2080A)'),
      findsOneWidget,
    );
  });

  testWidgets('模型/上下文/子代理不在顶栏重复出现', (tester) async {
    await _pumpTopBar(
      tester,
      jobsRunning: 0,
    );
    expect(find.textContaining('模型'), findsNothing);
    expect(find.textContaining('上下文'), findsNothing);
    expect(find.textContaining('子代理'), findsNothing);
  });

  testWidgets('后台任务 >0 时右侧出绿色胶囊并可点；0 时不占高度', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(tester, jobsRunning: 2, taps: taps);
    expect(find.text('后台 2'), findsOneWidget);
    await tester.tap(find.text('后台 2'));
    await tester.pump();
    expect(taps.jobs, 1);

    await _pumpTopBar(tester, jobsRunning: 0);
    expect(find.textContaining('后台任务'), findsNothing);
    final bar = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(ChatTopBar),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(bar.height, DsSpacing.topBarHeight);
  });

  testWidgets('标题行菜单 / 新对话回调仍可点', (tester) async {
    final taps = _Taps();
    await _pumpTopBar(tester, taps: taps);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    expect(taps.menu, 1);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(taps.newChat, 1);
  });
}
