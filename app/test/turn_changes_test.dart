/// 本轮改动 / 生成文件推导的纯逻辑测试。
library;

import 'package:dshchat/bridge/history_page.dart';
import 'package:dshchat/bridge/tool_call.dart';
import 'package:dshchat/ui/code_diff.dart';
import 'package:dshchat/ui/turn_changes.dart';
import 'package:dshchat/ui/work_steps.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallInfo call(
  String name, {
  String callId = 'c1',
  String? arguments,
  Map<String, dynamic>? meta,
  bool failed = false,
}) => ToolCallInfo(
  callId: callId,
  name: name,
  phrases: const [],
  rawArguments: arguments,
  meta: meta,
  failed: failed,
);

ChatMessage process(List<ToolCallInfo> calls, {int seq = 2}) =>
    ChatMessage(role: 'process', text: '', toolCalls: calls, seq: seq);

ChatMessage user({int seq = 1}) =>
    ChatMessage(role: 'user', text: '改一下', seq: seq);

ChatMessage assistant(String text, {int seq = 3}) =>
    ChatMessage(role: 'assistant', text: text, seq: seq);

void main() {
  group('turnChangesOf', () {
    test('edit 的 meta.diffs 给出真实增删行数', () {
      final messages = [
        user(),
        process([
          call(
            'edit',
            meta: {
              'path': '/w/a.dart',
              'diffs': [
                {
                  'path': '/w/a.dart',
                  'oldText': 'a\nb\nc',
                  'newText': 'a\nB\nc\nd',
                },
              ],
            },
          ),
        ]),
        assistant('好了'),
      ];
      final changes = turnChangesOf(messages, const TurnRange(0, 3))!;
      expect(changes.files, hasLength(1));
      final file = changes.files.single;
      expect(file.path, '/w/a.dart');
      expect(file.name, 'a.dart');
      expect(file.directory, '/w');
      expect(file.added, 2); // B + d
      expect(file.removed, 1); // b
      expect(file.edits, 1);
      expect(changes.added, 2);
      expect(changes.removed, 1);
    });

    test('同一文件改两次：合并计数、逐次留 hunk', () {
      final messages = [
        user(),
        process([
          call(
            'edit',
            callId: 'c1',
            meta: {
              'diffs': [
                {'path': '/w/a.dart', 'oldText': 'x', 'newText': 'x\ny'},
              ],
            },
          ),
          call(
            'edit',
            callId: 'c2',
            meta: {
              'diffs': [
                {'path': '/w/a.dart', 'oldText': 'x\ny', 'newText': 'x'},
              ],
            },
          ),
        ]),
        assistant('好了'),
      ];
      final file = turnChangesOf(messages, const TurnRange(0, 3))!.files.single;
      expect(file.edits, 2);
      expect(file.hunks.map((h) => h.index), [1, 2]);
      expect(file.added, 1);
      expect(file.removed, 1);
    });

    test('没有 meta 时退回 arguments（edit 的 old_string/new_string）', () {
      final messages = [
        user(),
        process([
          call(
            'edit',
            arguments:
                '{"file_path":"/w/b.dart","old_string":"one","new_string":"one\\ntwo"}',
          ),
        ]),
        assistant('好了'),
      ];
      final file = turnChangesOf(messages, const TurnRange(0, 3))!.files.single;
      expect(file.path, '/w/b.dart');
      expect(file.added, 1);
      expect(file.removed, 0);
      expect(file.created, isFalse);
    });

    test('write create 记为新建，全文计入新增', () {
      final messages = [
        user(),
        process([
          call(
            'write',
            arguments: '{"file_path":"/w/c.md","content":"l1\\nl2\\nl3"}',
            meta: {'operation': 'create', 'path': '/w/c.md'},
          ),
        ]),
        assistant('好了'),
      ];
      final file = turnChangesOf(messages, const TurnRange(0, 3))!.files.single;
      expect(file.created, isTrue);
      expect(file.added, 3);
    });

    test('失败的工具调用不计入改动', () {
      final messages = [
        user(),
        process([
          call(
            'edit',
            failed: true,
            meta: {
              'diffs': [
                {'path': '/w/a.dart', 'oldText': 'a', 'newText': 'b'},
              ],
            },
          ),
        ]),
        assistant('失败'),
      ];
      expect(turnChangesOf(messages, const TurnRange(0, 3)), isNull);
    });

    test('没有写操作时返回 null', () {
      final messages = [
        user(),
        process([call('bash', arguments: '{"command":"ls"}')]),
        assistant('好了'),
      ];
      expect(turnChangesOf(messages, const TurnRange(0, 3)), isNull);
    });

    test('同样的输入复用缓存实例', () {
      final messages = [
        user(),
        process([
          call(
            'edit',
            meta: {
              'diffs': [
                {'path': '/w/z.dart', 'oldText': 'a', 'newText': 'b'},
              ],
            },
          ),
        ]),
        assistant('好了'),
      ];
      final first = turnChangesOf(messages, const TurnRange(0, 3));
      final second = turnChangesOf(messages, const TurnRange(0, 3));
      expect(identical(first, second), isTrue);
    });
  });

  group('diffLinesOf', () {
    test('公共前后缀保留为上下文行', () {
      final lines = diffLinesOf('a\nb\nc', 'a\nB\nc');
      expect(lines.map((l) => l.type), [
        CodeDiffLineType.ctx,
        CodeDiffLineType.del,
        CodeDiffLineType.add,
        CodeDiffLineType.ctx,
      ]);
    });
  });

  group('turnArtifactsOf', () {
    test('write 新建的文件进生成列表，update 不进', () {
      final messages = [
        user(),
        process([
          call(
            'write',
            callId: 'c1',
            arguments: '{"file_path":"/w/new.png","content":"x"}',
            meta: {'operation': 'create', 'path': '/w/new.png'},
          ),
          call(
            'write',
            callId: 'c2',
            arguments: '{"file_path":"/w/old.md","content":"y"}',
            meta: {'operation': 'update', 'path': '/w/old.md'},
          ),
        ]),
        assistant('好了'),
      ];
      final files = turnArtifactsOf(messages, const TurnRange(0, 3));
      expect(files.map((f) => f.path), ['/w/new.png']);
      expect(files.single.kind, ArtifactKind.image);
      expect(files.single.caption, '图片 · PNG');
    });

    test('回复里的图片链接按 bash cwd 拼绝对路径', () {
      final messages = [
        user(),
        process([
          call('bash', arguments: '{"command":"vim"}', meta: {'cwd': '/w'}),
        ]),
        assistant('看这张 ![截图](build/a.png) 和 [文档](/w/b.md)'),
      ];
      final files = turnArtifactsOf(messages, const TurnRange(0, 3));
      expect(files.map((f) => f.path), ['/w/build/a.png', '/w/b.md']);
      expect(files.first.kind, ArtifactKind.image);
      expect(files.last.kind, ArtifactKind.markdown);
    });

    test('没有 cwd 时相对路径不猜', () {
      final messages = [
        user(),
        process([call('bash', arguments: '{"command":"ls"}')]),
        assistant('![x](build/a.png)'),
      ];
      expect(turnArtifactsOf(messages, const TurnRange(0, 3)), isEmpty);
    });
  });

  group('artifactKindOf', () {
    test('扩展名映射', () {
      expect(artifactKindOf('a.PNG'), ArtifactKind.image);
      expect(artifactKindOf('a.pdf'), ArtifactKind.pdf);
      expect(artifactKindOf('a.xlsx'), ArtifactKind.spreadsheet);
      expect(artifactKindOf('a.md'), ArtifactKind.markdown);
      expect(artifactKindOf('a.bin'), ArtifactKind.other);
      expect(artifactKindOf('Makefile'), ArtifactKind.other);
    });
  });
}
