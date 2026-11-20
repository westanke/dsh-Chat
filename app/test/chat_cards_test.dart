/// 本轮改动卡 / 生成文件卡 / 查看改动页的渲染冒烟测试。
library;

import 'package:dshchat/bridge/history_page.dart';
import 'package:dshchat/bridge/tool_call.dart';
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/ui/chat_rows.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_artifact_card.dart';
import 'package:dshchat/ui/chat_change_card.dart';
import 'package:dshchat/ui/chat_diff_page.dart';
import 'package:dshchat/ui/code_diff.dart';
import 'package:dshchat/ui/turn_changes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

FileChange _change(String path, {int added = 3, int removed = 1, int hunks = 1}) =>
    FileChange(
      path: path,
      created: false,
      hunks: [
        for (var i = 0; i < hunks; i++)
          EditHunk(
            index: i + 1,
            lines: const [CodeDiffLine(CodeDiffLineType.add, 'x')],
          ),
      ],
      added: added,
      removed: removed,
    );

ArtifactFile _artifact(String path) =>
    ArtifactFile(path: path, kind: ArtifactKind.image);

Widget _host(Widget child, {double width = 360}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, child: SingleChildScrollView(child: child)),
      ),
    );

ChatMessage _user(int seq) => ChatMessage(role: 'user', text: '改一下', seq: seq);

ChatMessage _process(int seq, List<ToolCallInfo> calls) =>
    ChatMessage(role: 'process', text: '', seq: seq, toolCalls: calls);

ChatMessage _assistant(int seq) =>
    ChatMessage(role: 'assistant', text: '好了', seq: seq);

void main() {
  test('行派生：一轮里既有改动又有生成文件，两张卡按序挂在轮尾', () {
    final messages = [
      _user(1),
      _process(2, [
        ToolCallInfo(
          callId: 'a',
          name: 'write',
          phrases: const [],
          summary: 'write',
          failed: false,
          rawArguments:
              '{"file_path":"/w/new.dart","content":"line1\\nline2"}',
          meta: const {'operation': 'create', 'path': '/w/new.dart', 'diffs': []},
        ),
        ToolCallInfo(
          callId: 'b',
          name: 'edit',
          phrases: const [],
          summary: 'edit',
          failed: false,
          rawArguments:
              '{"file_path":"/w/old.dart","old_string":"a","new_string":"b"}',
        ),
      ]),
      _assistant(3),
    ];
    final rows = deriveRows(
      ChatRowsInput(
        messages: messages,
        folded: FoldedReplies.all,
        streaming: false,
        hasMoreHistory: false,
        historyTruncated: false,
        streamingProcess: null,
        maxTokensNotice: false,
        linkError: null,
      ),
    );
    final kinds = rows.map((r) => r.runtimeType.toString()).toList();
    expect(kinds, contains('ChangeCardRow'));
    expect(kinds, contains('ArtifactCardRow'));
    expect(
      kinds.indexOf('ChangeCardRow') < kinds.indexOf('ArtifactCardRow'),
      isTrue,
    );
  });

  testWidgets('改动卡：标题、逐文件行、查看改动', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        ChangeCard(
          colors: DsColors(false),
          changes: TurnChanges(
            anchorSeq: 1,
            files: [
              _change('/w/app/lib/ui/window_class.dart'),
              _change('/w/app/test/hitl_width_test.dart', added: 13, removed: 9),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('改动了 2 个文件'), findsOneWidget);
    expect(find.text('window_class.dart'), findsOneWidget);
    expect(find.text('hitl_width_test.dart'), findsOneWidget);
    expect(find.text('查看改动'), findsOneWidget);
    // 合计增删（卡片右上角两个独立数字）。
    expect(find.text('+16'), findsOneWidget);
    expect(find.text('−10'), findsOneWidget);
  });

  testWidgets('改动卡：超过 3 个文件给「还有 N 个文件」', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        ChangeCard(
          colors: DsColors(false),
          changes: TurnChanges(
            anchorSeq: 1,
            files: [
              for (var i = 0; i < 5; i++) _change('/w/file_$i.dart'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('改动了 5 个文件'), findsOneWidget);
    expect(find.text('还有 2 个文件'), findsOneWidget);
    expect(find.text('file_0.dart'), findsOneWidget);
    expect(find.text('file_4.dart'), findsNothing);
  });

  testWidgets('生成文件卡：标题、行、类型说明、展开', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        ArtifactCard(
          colors: DsColors(false),
          files: [
            _artifact('/w/shot_landscape.png'),
            _artifact('/w/notes.pdf'),
            _artifact('/w/table.csv'),
            _artifact('/w/deck.pptx'),
            _artifact('/w/clip.mp4'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生成了 5 个文件'), findsOneWidget);
    expect(find.text('shot_landscape.png'), findsOneWidget);
    expect(find.text('图片 · PNG'), findsOneWidget);
    expect(find.text('全部 5 个文件'), findsOneWidget);

    await tester.tap(find.text('全部 5 个文件'));
    await tester.pumpAndSettle();
    expect(find.text('clip.mp4'), findsOneWidget);
  });

  testWidgets('查看改动页：文件 chips、路径、增删与修改次数', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatDiffPage(
          colors: DsColors(false),
          files: [
            _change('/w/app/lib/ui/window_class.dart', added: 17, removed: 7, hunks: 2),
            _change('/w/app/test/hitl_width_test.dart', added: 13, removed: 9),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本轮改动'), findsOneWidget);
    expect(find.text('2 个文件  +30 −16'), findsOneWidget);
    expect(find.text('/w/app/lib/ui/window_class.dart'), findsOneWidget);
    expect(find.text('+17  −7  修改 2 次  行号未知'), findsOneWidget);
    expect(find.text('第 1 次修改'), findsOneWidget);
  });
}
