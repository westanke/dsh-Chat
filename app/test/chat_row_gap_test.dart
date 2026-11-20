// 会话列表行间距规则的测试。
//
// 规则见 ui/chat_row_gap.dart：间距只由行框给一次，行内组件不再自带顶距。

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_rows.dart';
import 'package:dshchat/ui/chat_row_gap.dart';
import 'package:dshchat/ui/work_steps.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String text, {int seq = 10}) => ChatMessage(
  role: 'user',
  text: text,
  seq: seq,
);

ChatMessage _assistant(String text, {int seq = 11}) => ChatMessage(
  role: 'assistant',
  text: text,
  seq: seq,
);

ChatMessage _process({int seq = 12, String callId = 'c1'}) => ChatMessage(
  role: 'process',
  text: '',
  seq: seq,
  toolCalls: [
    ToolCallInfo(
      callId: callId,
      name: 'bash',
      phrases: const ['执行了命令'],
    ),
  ],
);

ChatRow _userRow(ChatMessage m) => UserRow(m, index: 0);
ChatRow _assistantRow(ChatMessage m) => AssistantRow(m, index: 0);
ChatRow _processRow(ChatMessage m) => ProcessRow(m, index: 0);

void main() {
  group('chatRowGapBefore', () {
    test('列表第一行不留上方空', () {
      expect(chatRowGapBefore(_userRow(_user('a')), null), 0);
      expect(chatRowGapBefore(_assistantRow(_assistant('b')), null), 0);
    });

    test('用户消息换轮留 24，同段连发留 8', () {
      final user = _userRow(_user('a'));
      final assistant = _assistantRow(_assistant('b'));
      // 助手之后来用户消息 = 换轮。
      expect(chatRowGapBefore(user, assistant), DsSpacing.chatGapNewTurn);
      // 紧接着又是用户消息 = 同一段话。
      expect(chatRowGapBefore(user, user), DsSpacing.chatGapSameTurn);
    });

    test('相邻过程行之间不留空', () {
      final process = _processRow(_process());
      expect(chatRowGapBefore(process, process), DsSpacing.chatGapProcess);
      // 流式工具组紧跟工具组也按过程算。
      final group = StreamingProcessRow(_process());
      expect(chatRowGapBefore(group, process), DsSpacing.chatGapProcess);
    });

    test('同轮正文之间留 8', () {
      final assistant = _assistantRow(_assistant('b'));
      expect(
        chatRowGapBefore(assistant, _assistantRow(_assistant('c'))),
        DsSpacing.chatGapSameTurn,
      );
    });

    test('文件卡离上下内容远一些：12', () {
      final files = FilesRow(
        ChatMessage(role: 'files', text: '', seq: 20),
        index: 0,
      );
      expect(
        chatRowGapBefore(files, _assistantRow(_assistant('b'))),
        DsSpacing.chatGapCard,
      );
    });

    test('轮尾脚注贴着上面的过程组：4', () {
      final turn = const TurnRange(0, 2);
      final end = TurnEndRow(turn, hasProcess: true);
      expect(
        chatRowGapBefore(end, _processRow(_process())),
        DsSpacing.chatGapFootnote,
      );
    });

    test('非零间距都是 4 的倍数', () {
      final user = _userRow(_user('a'));
      final assistant = _assistantRow(_assistant('b'));
      final process = _processRow(_process());
      final gaps = <double>[
        chatRowGapBefore(user, assistant),
        chatRowGapBefore(user, user),
        chatRowGapBefore(assistant, user),
        chatRowGapBefore(process, assistant),
        chatRowGapBefore(process, process),
      ];
      for (final gap in gaps) {
        expect(gap % 4, 0, reason: '间距应是 4 的倍数：$gap');
      }
      expect(gaps.contains(DsSpacing.chatGapProcess), isTrue);
    });
  });

  group('isUserRow / isProcessRow', () {
    test('只认用户消息', () {
      expect(isUserRow(_userRow(_user('a'))), isTrue);
      expect(isUserRow(_assistantRow(_assistant('b'))), isFalse);
      expect(isUserRow(null), isFalse);
    });

    test('过程组、命令回执、流式正文都算过程', () {
      expect(isProcessRow(_processRow(_process())), isTrue);
      expect(
        isProcessRow(
          CommandRow(
            ChatMessage(role: 'command', text: '/help', seq: 5),
            index: 0,
          ),
        ),
        isTrue,
      );
      expect(isProcessRow(const StreamingTextRow()), isTrue);
      expect(isProcessRow(_userRow(_user('a'))), isFalse);
    });
  });
}
