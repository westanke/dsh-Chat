/// 排队（mobile-queue-v1 / IKX2AE）模型、状态合并与队列条的单测。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/bridge/queue.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_queue_actions.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/queue_dock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async => throw RequestException('NOT_CONNECTED', 'fake gateway');
}

Map<String, dynamic> _entry({
  String inboxId = 'in-1',
  String slot = 'next-turn',
  String mode = 'queue',
  String text = '排队一句',
  bool resendable = true,
}) => {
  'inboxId': inboxId,
  'requestId': inboxId,
  'slot': slot,
  'mode': mode,
  'text': text,
  'resendable': resendable,
  'sourceKind': 'user',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('QueueEntry', () {
    test('解析桥的 queue 数组（顺序原样，身份用 inboxId）', () {
      final list = QueueEntry.listFrom([
        _entry(inboxId: 'a', slot: 'next-step', mode: 'steer'),
        _entry(inboxId: 'b'),
      ]);
      expect(list.map((e) => e.inboxId), ['a', 'b']);
      expect(list.first.isNextStep, isTrue);
      expect(list.first.mode, 'steer');
      expect(list.last.isNextStep, isFalse);
      expect(queueSlotLabel(list.first), '下一步插话');
      expect(queueSlotLabel(list.last), '本轮结束后发送');
    });

    test('缺 inboxId 的项丢弃；null/非数组回空表', () {
      expect(QueueEntry.listFrom([{'text': '没有 id'}]), isEmpty);
      expect(QueueEntry.listFrom(null), isEmpty);
      expect(QueueEntry.listFrom('oops'), isEmpty);
    });

    test('resendable=false 不给「改完重发」入口', () {
      final entry = QueueEntry.listFrom([
        _entry(resendable: false),
      ]).single;
      expect(entry.resendable, isFalse);
      expect(entry.canEdit, isFalse);
    });
  });

  group('applyChatQueue', () {
    test('用服务端快照替换队列，并摘掉同文本的本地乐观气泡', () {
      final state = ChatState(_FakeGateway());
      state.sessionId = 'sid-1';
      state.messages = [
        ChatMessage(role: 'user', text: '排队一句', seq: -1),
        ChatMessage(role: 'user', text: '另一句', seq: -1),
        ChatMessage(role: 'assistant', text: '回答', seq: 3),
      ];

      applyChatQueue(state, QueueEntry.listFrom([_entry()]));

      expect(state.queue.single.inboxId, 'in-1');
      expect(state.messages.map((m) => m.text), ['另一句', '回答']);
    });

    test('空快照只清队列，不动消息', () {
      final state = ChatState(_FakeGateway());
      state.messages = [ChatMessage(role: 'user', text: '排队一句', seq: -1)];
      applyChatQueue(state, const []);
      expect(state.queue, isEmpty);
      expect(state.messages, hasLength(1));
    });
  });

  group('QueueDockBar', () {
    testWidgets('单条显示正文，点击进管理面板', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueueDockBar(
              entries: QueueEntry.listFrom([_entry()]),
              colors: DsColors(false),
              onManage: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('排队'), findsOneWidget);
      expect(find.textContaining('排队一句'), findsOneWidget);
      await tester.tap(find.text('管理'));
      expect(tapped, isTrue);
    });

    testWidgets('多条显示条数', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueueDockBar(
              entries: QueueEntry.listFrom([
                _entry(inboxId: 'a'),
                _entry(inboxId: 'b', text: '第二条'),
              ]),
              colors: DsColors(false),
              onManage: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('2 条'), findsOneWidget);
    });
  });
}
