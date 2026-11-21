// 会话列表行模型单测（C 项 · chat_rows.dart）。
//
// 行模型是列表的地基：主键要稳定、派生顺序要可预期、收起档位要生效。
import 'package:dshchat/bridge/models.dart'; // re-export history_page.dart
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/ui/chat_rows.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String text, [int seq = 10]) =>
    ChatMessage(role: 'user', text: text, seq: seq);

ChatMessage _assistant(String text, [int seq = 11]) =>
    ChatMessage(role: 'assistant', text: text, seq: seq);

ChatMessage _process({int seq = 12, String callId = 'c1'}) => ChatMessage(
  role: 'process',
  text: '',
  seq: seq,
  toolCalls: [ToolCallInfo(callId: callId, name: 'bash', phrases: ['执行了命令'])],
);

ChatRowsInput _input(
  List<ChatMessage> messages, {
  FoldedReplies folded = FoldedReplies.all,
  bool streaming = false,
  bool hasMoreHistory = false,
  bool historyTruncated = false,
  ChatMessage? streamingProcess,
  bool maxTokensNotice = false,
  String? linkError,
}) => ChatRowsInput(
  messages: messages,
  folded: folded,
  streaming: streaming,
  hasMoreHistory: hasMoreHistory,
  historyTruncated: historyTruncated,
  streamingProcess: streamingProcess,
  maxTokensNotice: maxTokensNotice,
  linkError: linkError,
);

void main() {
  group('deriveRows · 顺序与类型', () {
    test('用户 / 助手 / 过程分别落到对应行', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ]),
      );
      expect(rows.map((r) => r.runtimeType).toList(), [
        UserRow,
        ProcessRow,
        AssistantRow,
        TurnEndRow,
      ]);
    });

    test('files / command / error 各自成行', () {
      final rows = deriveRows(
        _input([
          ChatMessage(role: 'files', text: '', files: const [], seq: 1),
          ChatMessage(role: 'command', text: '/stats', seq: 2),
          ChatMessage(role: 'error', text: '失败', seq: 3),
        ]),
      );
      expect(rows.map((r) => r.runtimeType).toList(), [
        FilesRow,
        CommandRow,
        ErrorRow,
      ]);
    });

    test('历史入口与截断提示排在最前', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
        ], hasMoreHistory: true, historyTruncated: true),
      );
      expect(rows.first, isA<HistoryMoreRow>());
      expect(rows[1], isA<HistoryTruncatedRow>());
      expect(rows[2], isA<UserRow>());
    });

    test('流式组 / 流式正文 / 截断提示 / 链路错误排在最后', () {
      final group = _process(seq: -2, callId: 'c9');
      final rows = deriveRows(
        _input([
          _user('问', 1),
        ], streaming: true, streamingProcess: group, maxTokensNotice: true, linkError: '断了'),
      );
      expect(rows.map((r) => r.runtimeType).toList(), [
        UserRow,
        StreamingProcessRow,
        StreamingTextRow,
        MaxTokensRow,
        LinkErrorRow,
      ]);
      expect((rows.last as LinkErrorRow).message, '断了');
    });
  });

  group('deriveRows · 轮尾行', () {
    test('轮内有过程组时，轮尾补一条 TurnEndRow', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ]),
      );
      expect(rows.map((r) => r.runtimeType).toList(), [
        UserRow,
        ProcessRow,
        AssistantRow,
        TurnEndRow,
      ]);
      final turnEnd = rows.last as TurnEndRow;
      expect(turnEnd.turn.start, 0);
      expect(turnEnd.turn.end, 3);
      expect(turnEnd.hasProcess, isTrue);
    });

    test('轮仍在跑时不出轮尾行（问题 4：不能显示「已完成」）', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ], streaming: true),
      );
      expect(rows.whereType<TurnEndRow>(), isEmpty);
    });

    test('轮内有未落库消息（seq<0）时也不出轮尾行', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: -2),
        ]),
      );
      expect(rows.whereType<TurnEndRow>(), isEmpty);
    });

    test('轮内没有过程组时不出轮尾行', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _assistant('答', 2),
        ]),
      );
      expect(rows.whereType<TurnEndRow>(), isEmpty);
    });

    test('两轮各出一条轮尾行，挂在各自的轮末', () {
      final rows = deriveRows(
        _input([
          _user('问一', 1),
          _process(seq: 2),
          _assistant('答一', 3),
          _user('问二', 4),
          _process(seq: 5, callId: 'c2'),
          _assistant('答二', 6),
        ]),
      );
      final turns = rows.whereType<TurnEndRow>().toList();
      expect(turns.length, 2);
      expect(turns[0].turn.start, 0);
      expect(turns[1].turn.start, 3);
      expect(turns[0].key, 'te0');
      expect(turns[1].key, 'te3');
    });
  });

  group('deriveRows · 收起档位', () {
    test('finalOnly：轮内中间回复被隐藏，最终回答保留', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _assistant('中间稿', 2),
          _assistant('最终回答', 3),
        ], folded: FoldedReplies.finalOnly),
      );
      final assistants = rows.whereType<AssistantRow>().toList();
      expect(assistants.length, 1);
      expect(assistants.single.message.text, '最终回答');
    });

    test('all：全部保留', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _assistant('中间稿', 2),
          _assistant('最终回答', 3),
        ]),
      );
      expect(rows.whereType<AssistantRow>().length, 2);
    });
  });

  group('行主键', () {
    test('已落盘的行主键由 seq 决定，与对象身份无关', () {
      final a = deriveRows(_input([_user('问', 7)]));
      final b = deriveRows(_input([_user('问', 7)]));
      expect(a.single.key, 'u7');
      expect(a.single.key, b.single.key);
    });

    test('未落盘的行主键带对象身份，两次派生不同', () {
      final rows = deriveRows(_input([_user('问', -1)]));
      expect(rows.single.key, startsWith('pu'));
      final again = deriveRows(_input([_user('问', -1)]));
      expect(again.single.key, isNot(rows.single.key));
    });

    test('过程组主键跟组内首个 callId 走（与展开态同一把钥匙）', () {
      final rows = deriveRows(_input([_process(seq: 2, callId: 'call-7')]));
      expect(rows.single.key, 'gcall-7');
    });

    test('主键在一批行里互不相同', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ]),
      );
      final keys = rows.map((r) => r.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('行属性', () {
    test('stable：已落盘的用户 / 助手行与轮尾行是稳定锚点', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ]),
      );
      expect(rows[0].stable, isTrue);
      expect(rows[2].stable, isTrue);
      expect(rows[1].stable, isFalse);
      expect(rows.last.stable, isTrue);
    });

    test('stable：未落盘的行不是锚点', () {
      final rows = deriveRows(_input([_user('问', -1)]));
      expect(rows.single.stable, isFalse);
    });

    test('index：消息行记住消息下标，非消息行取 -1', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
          _process(seq: 2),
          _assistant('答', 3),
        ]),
      );
      expect(rows[0].index, 0);
      expect(rows[1].index, 1);
      expect(rows[2].index, 2);
      expect(rows.whereType<TurnEndRow>().single.index, -1);
    });

    test('cacheable：流式行不可缓存，其余可缓存', () {
      final rows = deriveRows(
        _input([
          _user('问', 1),
        ], streaming: true, streamingProcess: _process(seq: -2)),
      );
      expect(rows.first.cacheable, isTrue);
      expect(rows.whereType<StreamingProcessRow>().single.cacheable, isFalse);
      expect(rows.whereType<StreamingTextRow>().single.cacheable, isFalse);
    });
  });

  group('ChatRowsInput.signature', () {
    test('同一批消息对象给同样的指纹', () {
      final messages = [_user('问', 1)];
      final a = _input(messages).signature;
      final b = _input(messages).signature;
      expect(a, b);
    });

    test('最后一条消息换了对象 → 指纹变', () {
      final a = _input([_user('问', 1)]).signature;
      final b = _input([_user('问', 1)]).signature;
      expect(a, isNot(b));
    });

    test('折叠档位 / 流式 / 历史入口变化 → 指纹变', () {
      final messages = [_user('问', 1)];
      final base = _input(messages).signature;
      expect(_input(messages, folded: FoldedReplies.finalOnly).signature, isNot(base));
      expect(_input(messages, streaming: true).signature, isNot(base));
      expect(_input(messages, hasMoreHistory: true).signature, isNot(base));
      expect(_input(messages, historyTruncated: true).signature, isNot(base));
      expect(_input(messages, maxTokensNotice: true).signature, isNot(base));
      expect(_input(messages, linkError: '断了').signature, isNot(base));
    });
  });
}
