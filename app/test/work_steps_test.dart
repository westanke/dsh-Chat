// 「收起后显示的回复」过滤纯函数单测（C 项 · work_steps.dart）。
import 'package:dshchat/bridge/models.dart'; // re-export history_page.dart
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/ui/work_steps.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String text, [int seq = 10]) =>
    ChatMessage(role: 'user', text: text, seq: seq);

ChatMessage _assistant(
  String text, {
  int seq = 11,
  List<ToolCallInfo> toolCalls = const [],
}) =>
    ChatMessage(role: 'assistant', text: text, seq: seq, toolCalls: toolCalls);

ChatMessage _process({int seq = 12, List<ToolCallInfo>? calls}) => ChatMessage(
  role: 'process',
  text: '',
  seq: seq,
  toolCalls:
      calls ??
      const [
        ToolCallInfo(callId: 'c1', name: 'bash', phrases: ['执行了命令']),
      ],
);

void main() {
  group('turnsOf', () {
    test('每条 user 开启一轮，到下一条 user 前；首条 user 前为轮次之间', () {
      final messages = <ChatMessage>[
        ChatMessage(role: 'files', text: ' hello', files: const []), // 前导段
        _user('第一问'),
        _assistant('答一'),
        _user('第二问'),
        _assistant('答二'),
      ];
      final turns = turnsOf(messages);
      expect(turns.length, 2);
      expect(turns[0].start, 1);
      expect(turns[0].end, 3);
      expect(turns[1].start, 3);
      expect(turns[1].end, 5);
      expect(lastTurnOf(messages)!.start, 3);
    });

    test('无 user 消息时不产生轮次', () {
      final turns = turnsOf([_assistant('只有助手')]);
      expect(turns, isEmpty);
      expect(lastTurnOf([_assistant('只有助手')]), isNull);
    });
  });

  group('visibleMessagesOf', () {
    test('all / 流式中：全部可见', () {
      final messages = <ChatMessage>[_user('问'), _process(), _assistant('答')];
      expect(
        visibleMessagesOf(messages, FoldedReplies.finalOnly, false).length,
        3,
      );
      expect(visibleMessagesOf(messages, FoldedReplies.all, true).length, 3);
      // 流式中永不过滤
      expect(
        visibleMessagesOf(messages, FoldedReplies.finalOnly, true).length,
        3,
      );
    });

    test('finalOnly 完成轮：只留最后一条合格助手回复，process 组保留折叠行', () {
      final messages = <ChatMessage>[
        _user('问'),
        _process(),
        _assistant('中间稿'), // 无工具调用、有正文 → 合格但不是最后一条
        _assistant(
          '',
          seq: 13,
          toolCalls: [
            const ToolCallInfo(callId: 'c2', name: 'bash', phrases: ['x']),
          ],
        ), // 空正文 → 不合格
        _assistant('最终回答', seq: 14),
      ];
      final visible = visibleMessagesOf(
        messages,
        FoldedReplies.finalOnly,
        false,
      );
      // process 组的折叠行不被列表隐藏（收起态由展开态逻辑管）。
      expect(visible.map((m) => m.role).toList(), [
        'user',
        'process',
        'assistant',
      ]);
      expect(visible.last.text, '最终回答');
    });

    test('finalOnly 轮内无合格助手消息 → 该轮助手全显示（不猜）', () {
      final messages = <ChatMessage>[
        _user('问'),
        _process(),
        _assistant(
          '',
          toolCalls: [
            const ToolCallInfo(callId: 'c2', name: 'bash', phrases: ['x']),
          ],
        ),
        _assistant('', seq: 13),
      ];
      final visible = visibleMessagesOf(
        messages,
        FoldedReplies.finalOnly,
        false,
      );
      expect(visible.map((m) => m.role).toList(), [
        'user',
        'process',
        'assistant',
        'assistant',
      ]);
    });

    test('轮运行中（seq<0 未 committed 或末轮流式）→ 全部可见', () {
      final completed = <ChatMessage>[_user('一'), _assistant('答一')];
      final running = <ChatMessage>[
        ...completed,
        _user('二'),
        _process(seq: -1),
        _assistant(
          '',
          seq: -1,
          toolCalls: [
            const ToolCallInfo(callId: 'c3', name: 'bash', phrases: ['x']),
          ],
        ),
        _assistant('', seq: -1),
      ];
      expect(
        visibleMessagesOf(running, FoldedReplies.finalOnly, false).length,
        running.length,
      );
      final streaming = <ChatMessage>[
        _user('问', 20),
        _process(seq: 21),
        _assistant('答', seq: 22),
      ];
      expect(
        visibleMessagesOf(streaming, FoldedReplies.finalOnly, true).length,
        3,
      );
    });

    test('files / error / command 卡始终可见；正文带工具调用的助手不猜不隐藏', () {
      final messages = <ChatMessage>[
        _user('问'),
        ChatMessage(role: 'files', text: '', files: const []),
        ChatMessage(role: 'command', text: '/stats\n✓ 已执行'),
        ChatMessage(role: 'error', text: '失败'),
        _assistant(
          '有正文',
          toolCalls: [
            const ToolCallInfo(callId: 'c4', name: 'bash', phrases: ['x']),
          ],
        ),
      ];
      final visible = visibleMessagesOf(
        messages,
        FoldedReplies.finalOnly,
        false,
      );
      // 该轮唯一助手正文带工具调用 → 无合格最终回答 → 助手全显示（不猜）。
      expect(visible.map((m) => m.role).toList(), [
        'user',
        'files',
        'command',
        'error',
        'assistant',
      ]);
    });
  });
}
