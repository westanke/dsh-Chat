/// 逐文件 diff 页：左右滑动切上一个/下一个文件（问题 5）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_diff_page.dart';
import 'package:dshchat/ui/turn_changes.dart';

FileChange _file(String name) => FileChange(
  path: '/w/$name',
  created: false,
  hunks: const [],
  added: 1,
  removed: 0,
);

Widget _host(List<FileChange> files) => MaterialApp(
  home: ChatDiffPage(files: files, colors: DsColors(false)),
);

void main() {
  testWidgets('左滑到下一个文件，右滑回上一个（问题 5）', (tester) async {
    await tester.pumpWidget(_host([_file('a.dart'), _file('b.dart')]));
    await tester.pumpAndSettle();

    PageView pageView() => tester.widget<PageView>(find.byType(PageView));
    expect(pageView().controller!.page, 0);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(pageView().controller!.page, 1);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(pageView().controller!.page, 0);
  });

  testWidgets('点顶部文件标签也能切页', (tester) async {
    await tester.pumpWidget(_host([_file('a.dart'), _file('b.dart')]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('b.dart').first);
    await tester.pumpAndSettle();
    final pv = tester.widget<PageView>(find.byType(PageView));
    expect(pv.controller!.page, 1);
  });
}
