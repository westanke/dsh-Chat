/// 输入条「单行收起 ⇄ 双行展开」与超长输入的回归（2026-11-27）。
///
/// 需求（对照 dsh-go）：会话页输入框有内容时展开，没内容时默认收缩成单行；
/// 内容多到超过输入框可见行数时，给一个「展开编辑」出口，进全屏弹层改完
/// 再写回同一条草稿。
library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:dshchat/ui/composer_drafts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    composerDrafts.clearAllDrafts();
  });

  /// 物理 1080x2400 / dpr 3 = 逻辑 360x800；键盘 inset 按物理像素传。
  Future<void> pumpComposer(
    WidgetTester tester, {
    bool streaming = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            devicePixelRatio: 3.0,
          ),
          child: Scaffold(
            body: Composer(
              colors: DsColors(false),
              onSend: (_) {},
              onSendWithImages: (_, _) {},
              onCancel: () {},
              onCommand: (_) {},
              streaming: streaming,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder composerField() => find.descendant(
    of: find.byType(Composer),
    matching: find.byType(TextField),
  );

  double dy(WidgetTester tester, Finder f) => tester.getRect(f).center.dy;

  /// 输入条的开合是 AnimationController：`forward()` 后第一帧只把 ticker 的
  /// 起始时间对齐，要再走一帧才看得到中间/结束态。
  Future<void> settleExpand(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('没有输入时收缩成单行：+ / 输入框 / 发送键在同一行', (tester) async {
    await pumpComposer(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final field = tester.getRect(composerField());
    final add = tester.getRect(find.byIcon(Icons.add));
    final send = tester.getRect(find.byIcon(Icons.graphic_eq));

    // 三者在同一行：中心线对齐（±2px）。
    expect((dy(tester, find.byIcon(Icons.add)) - field.center.dy).abs(), lessThan(2));
    expect((send.center.dy - field.center.dy).abs(), lessThan(2));
    // 文字在「+」右侧，收起态不与键行重叠。
    expect(field.left, greaterThanOrEqualTo(add.right));
    // 没有内容时不应出现「展开编辑」。
    expect(find.byIcon(Icons.open_in_full), findsNothing);
  });

  testWidgets('有文字后展开成双行：输入框占整行，+ 与发送键落到第二行', (tester) async {
    await pumpComposer(tester);
    final collapsedField = tester.getRect(composerField());

    await tester.enterText(composerField(), 'hello');
    await settleExpand(tester);

    final field = tester.getRect(composerField());
    final add = tester.getRect(find.byIcon(Icons.arrow_upward));

    // 输入框变宽（让出左右键后 → 整行）。
    expect(field.width, greaterThan(collapsedField.width));
    // 键行整体在文字下方。
    expect(add.top, greaterThanOrEqualTo(field.bottom));
    expect(dy(tester, find.byIcon(Icons.add)), greaterThan(field.bottom));
  });

  testWidgets('清空文字后回到单行', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(composerField(), 'hello');
    await settleExpand(tester);
    expect(
      dy(tester, find.byIcon(Icons.add)),
      greaterThan(tester.getRect(composerField()).bottom),
    );

    await tester.enterText(composerField(), '');
    await settleExpand(tester);

    final field = tester.getRect(composerField());
    expect((dy(tester, find.byIcon(Icons.add)) - field.center.dy).abs(), lessThan(2));
  });

  testWidgets('内容超过可见行数：出现「展开编辑」，全屏改完写回草稿', (tester) async {
    // 逻辑高 800 → 可见行数上限 6；8 行文字超过上限。
    await pumpComposer(tester);

    await tester.enterText(composerField(), '1\n2\n3\n4\n5\n6\n7\n8');
    await settleExpand(tester);

    expect(find.byIcon(Icons.open_in_full), findsOneWidget);

    await tester.tap(find.byIcon(Icons.open_in_full));
    await settleExpand(tester);

    // 弹层：标题、字数、完成按钮、整屏输入框。
    expect(find.text('编辑消息'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('15 字'), findsOneWidget);

    final editor = find.byWidgetPredicate(
      (w) => w is TextField && w.expands == true,
    );
    expect(editor, findsOneWidget);
    await tester.enterText(editor, '第一行\n第二行');
    await tester.pump();
    expect(find.text('7 字'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await settleExpand(tester);

    // 写回输入条：文字与草稿都是改后的。
    final field = tester.widget<TextField>(composerField());
    expect(field.controller!.text, '第一行\n第二行');
    expect(composerDrafts.draftOf(null).text, '第一行\n第二行');
  });

  testWidgets('短文本不出现「展开编辑」', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(composerField(), '一句话');
    await settleExpand(tester);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
  });
}
