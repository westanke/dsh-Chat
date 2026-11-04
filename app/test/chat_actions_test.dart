// 聊天页提交 B 单测：本地统计 / 发送键三态 / 重新生成选中的用户消息。
import 'package:dshchat/bridge/models.dart'; // re-export tool_call.dart
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:dshchat/ui/stats_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appSettings.setBusySendMode(BusySendMode.queue);
  });

  group('chatStatsOf', () {
    test('counts roles, tool calls and thinking blocks locally', () {
      final stats = chatStatsOf(<ChatMessage>[
        ChatMessage(role: 'user', text: '你好'),
        ChatMessage(role: 'assistant', text: '答案', reasoning: '想一想'),
        ChatMessage(
          role: 'process',
          text: '',
          toolCalls: const [
            ToolCallInfo(
              callId: 'c1',
              name: 'bash',
              phrases: ['执行了命令'],
            ),
            ToolCallInfo(
              callId: 'c2',
              name: 'read',
              phrases: ['读取了文件'],
            ),
          ],
        ),
        ChatMessage(role: 'error', text: '失败'),
      ]);
      expect(stats['消息总数'], 4);
      expect(stats['用户消息'], 1);
      expect(stats['助手回复'], 1);
      expect(stats['工具过程组'], 1);
      expect(stats['错误提示'], 1);
      expect(stats['工具调用'], 2);
      expect(stats['思考块'], 1);
    });

    test('empty history is all zeros', () {
      final stats = chatStatsOf(<ChatMessage>[]);
      expect(stats.values.every((v) => v == 0), isTrue);
    });
  });

  group('lastUserTextBefore (regenerate / retry 选中的文本)', () {
    test('picks the last non-empty user message up to end', () {
      final msgs = <ChatMessage>[
        ChatMessage(role: 'user', text: '第一问'),
        ChatMessage(role: 'assistant', text: '答 1'),
        ChatMessage(role: 'user', text: '第二问'),
        ChatMessage(role: 'assistant', text: '答 2'),
      ];
      expect(lastUserTextBefore(msgs, 3), '第二问');
      expect(lastUserTextBefore(msgs, 1), '第一问');
    });

    test('skips empty / whitespace-only user messages', () {
      final msgs = <ChatMessage>[
        ChatMessage(role: 'user', text: '真问题'),
        ChatMessage(role: 'assistant', text: '答'),
        ChatMessage(role: 'user', text: '   '),
      ];
      expect(lastUserTextBefore(msgs, 2), '真问题');
    });

    test('returns null when there is no user text', () {
      expect(lastUserTextBefore(<ChatMessage>[], 0), isNull);
      expect(
        lastUserTextBefore(
          <ChatMessage>[ChatMessage(role: 'assistant', text: '答')],
          0,
        ),
        isNull,
      );
    });

    test('clamps out-of-range end indices', () {
      final msgs = <ChatMessage>[ChatMessage(role: 'user', text: '问')];
      expect(lastUserTextBefore(msgs, 999), '问');
      expect(lastUserTextBefore(msgs, -5), '问');
    });
  });

  group('Composer send-key three states', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool streaming,
      required VoidCallback onCancel,
      required ValueChanged<String> onSend,
      String initialText = '',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Composer(
              colors: DsColors(false),
              onSend: onSend,
              onSendWithImage: (_, _) {},
              onCancel: onCancel,
              onCommand: (_) {},
              streaming: streaming,
            ),
          ),
        ),
      );
      if (initialText.isNotEmpty) {
        await tester.enterText(find.byType(TextField), initialText);
        await tester.pump();
      }
    }

    testWidgets('has text shows send (arrow_upward)', (tester) async {
      await pump(
        tester,
        streaming: false,
        onCancel: () {},
        onSend: (_) {},
        initialText: 'hello',
      );
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsNothing);
      // 加图按钮常驻（第二轮反馈 D）：有文字也在。
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('streaming + empty shows stop', (tester) async {
      var cancels = 0;
      await pump(
        tester,
        streaming: true,
        onCancel: () => cancels++,
        onSend: (_) {},
      );
      expect(find.byIcon(Icons.stop), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(cancels, 1);
    });

    testWidgets('idle + empty shows plus / voice placeholders', (tester) async {
      await pump(
        tester,
        streaming: false,
        onCancel: () {},
        onSend: (_) {},
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
    });
  });
}
