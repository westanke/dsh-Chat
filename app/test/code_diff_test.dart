// 「本轮代码差异」纯函数单测（D 项 · code_diff.dart）。
import 'dart:convert';

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/code_diff.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String text) =>
    ChatMessage(role: 'user', text: text, seq: 10);

ChatMessage _processGroup(List<ToolCallInfo> calls) =>
    ChatMessage(role: 'process', text: '', seq: 11, toolCalls: calls);

ToolCallInfo _call(String name, Map<String, String> args) => ToolCallInfo(
  callId: 'call-1',
  name: name,
  phrases: const ['执行了命令'],
  rawArguments: jsonEncode(args),
);

void main() {
  group('codeDiffOfCall', () {
    test('edit：公共前后缀标 ctx，中间 -old/+new', () {
      final diff = codeDiffOfCall(
        'edit',
        jsonEncode({
          'file_path': 'app/main.dart',
          'old_string': 'int a = 1;\nint b = 2;\nint c = 3;\nint d = 4;',
          'new_string': 'int a = 1;\nint b = 22;\nint c = 33;\nint d = 4;',
        }),
      );
      expect(diff, isNotNull);
      expect(diff!.path, 'app/main.dart');
      expect(diff.kind, 'edit');
      final types = diff.lines.map((l) => l.type).toList();
      expect(types, [
        CodeDiffLineType.ctx,
        CodeDiffLineType.del,
        CodeDiffLineType.del,
        CodeDiffLineType.add,
        CodeDiffLineType.add,
        CodeDiffLineType.ctx,
      ]);
      expect(diff.lines[1].text, 'int b = 2;');
      expect(diff.lines[3].text, 'int b = 22;');
    });

    test('write：content 全部为 + 行，结尾换行不产生空行', () {
      final diff = codeDiffOfCall(
        'write',
        jsonEncode({'file_path': 'new.txt', 'content': 'hello\nworld\n'}),
      );
      expect(diff, isNotNull);
      expect(diff!.kind, 'write');
      expect(diff.lines.map((l) => (l.type, l.text)).toList(), [
        (CodeDiffLineType.add, 'hello'),
        (CodeDiffLineType.add, 'world'),
      ]);
    });

    test('tools. 前缀工具名等价处理', () {
      expect(
        codeDiffOfCall(
          'tools.write',
          jsonEncode({'file_path': 'a.txt', 'content': 'x'}),
        )!.kind,
        'write',
      );
    });

    test('非 edit/write / 坏 JSON / 缺 file_path → null（不抛异常）', () {
      expect(codeDiffOfCall('bash', jsonEncode({'command': 'ls'})), isNull);
      expect(codeDiffOfCall('edit', 'not-json{'), isNull);
      expect(
        codeDiffOfCall(
          'edit',
          jsonEncode({'old_string': 'a', 'new_string': 'b'}),
        ),
        isNull,
      );
      expect(codeDiffOfCall('write', null), isNull);
    });
  });

  group('codeDiffsOfTurn', () {
    test('只取最后一轮 process 组的 edit/write，按序排列', () {
      final messages = <ChatMessage>[
        _user('上一轮'),
        _processGroup([
          _call('edit', {
            'file_path': 'old.dart',
            'old_string': 'a',
            'new_string': 'b',
          }),
        ]),
        _assistantReply(),
        _user('本轮'),
        _processGroup([
          _call('tools.write', {'file_path': 'n1.txt', 'content': 'x'}),
          _call('grep', {'query': 'main'}),
          _call('edit', {
            'file_path': 'n2.dart',
            'old_string': 'a',
            'new_string': 'b',
          }),
        ]),
      ];
      final diffs = codeDiffsOfTurn(messages);
      expect(diffs.map((d) => d.path).toList(), ['n1.txt', 'n2.dart']);
    });

    test('无 user 消息 → 空列表', () {
      expect(codeDiffsOfTurn([_assistantReply()]), isEmpty);
    });
  });
}

ChatMessage _assistantReply() =>
    ChatMessage(role: 'assistant', text: '答', seq: 12);
