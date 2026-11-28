// 顶栏收口（2026-11-28 用户反馈）：状态改成标题前色点；模型/上下文/子代理不再
// 在顶栏重复出现；只有后台任务在跑时多一行 chip。
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_header_status.dart';
import 'package:dshchat/ui/chat_top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Taps {
  int menu = 0;
  int newChat = 0;
}

Future<void> _pumpTopBar(
  WidgetTester tester, {
  String title = '会话标题',
  ChatHeaderStatus? status,
  _Taps? taps,
}) async {
  final t = taps ?? _Taps();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatTopBar(
          colors: const DsColors(false),
          title: title,
          status: status ?? const ChatHeaderStatus(ChatStatusTone.ok, '就绪'),
          onMenu: () => t.menu++,
          onNewChat: () => t.newChat++,
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

  testWidgets('定时任务不再出现在顶栏', (tester) async {
    await _pumpTopBar(tester);
    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });

  testWidgets('模型/上下文/子代理不在顶栏重复出现', (tester) async {
    await _pumpTopBar(tester);
    expect(find.textContaining('模型'), findsNothing);
    expect(find.textContaining('上下文'), findsNothing);
    expect(find.textContaining('子代理'), findsNothing);
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
