/// 会话信息面板的冒烟渲染：标题 / 轮数 / 三元统计 / 三行信息 / 插件空态。
///
/// 这里刻意用真 ChatState + 真 GatewayClient（指向不可达的本地端口），
/// 验证「models 帧拿不到时模型行直接消失」这条降级路径不会炸。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/session_info_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String text, int seq) =>
    ChatMessage(role: 'user', text: text, seq: seq);

ChatMessage _editTurn() => ChatMessage(
  role: 'process',
  text: '',
  seq: 2,
  toolCalls: <ToolCallInfo>[
    const ToolCallInfo(
      callId: 'c1',
      name: 'edit',
      phrases: <String>['编辑文件'],
      meta: <String, dynamic>{'path': 'lib/a.dart'},
    ),
  ],
);

void main() {
  testWidgets('渲染标题/轮数/统计/主机，切到「插件」是空态', (tester) async {
    final gateway = GatewayClient(baseUrl: 'http://127.0.0.1:9');
    final state = ChatState(gateway);
    state.sessionId = 's1';
    state.sessions = <DshSession>[
      const DshSession(
        id: 's1',
        rootId: 'r1',
        updatedAt: 0,
        running: false,
        blank: false,
        title: '会话标题',
        workspaceTitle: 'dsh-Chat',
      ),
    ];
    final done = _editTurn()
      ..turnStartedAt = 1000
      ..turnFinishedAt = 61000;
    state.messages = <ChatMessage>[_user('问', 1), done];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSessionInfoSheet(
                  context,
                  state,
                  const DsColors(false),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('会话标题'), findsOneWidget);
    expect(find.text('共 1 轮'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget); // 用时 60s → 01:00
    expect(find.text('用时'), findsOneWidget);
    expect(find.text('步骤'), findsOneWidget);
    expect(find.text('改动文件'), findsOneWidget);
    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('dsh-Chat'), findsOneWidget);
    // models 帧拉不到（端口不可达）→ 模型行不显示。
    expect(find.text('模型'), findsNothing);
    expect(find.text('主机'), findsOneWidget);
    expect(find.text('DSH Bridge · 本机'), findsOneWidget);

    await tester.tap(find.text('插件'));
    await tester.pumpAndSettle();
    expect(find.text('这个会话没有插件'), findsOneWidget);
    expect(find.text('当前客户端还没有接入插件面板。'), findsOneWidget);
    expect(find.text('共 1 轮'), findsNothing);

    expect(tester.takeException(), isNull);
    state.dispose();
  });
}
