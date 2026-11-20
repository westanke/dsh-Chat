// 思考行的测试。
//
// 形态参照 dsh-go 的会话页思考行（thinking_pill.dart）：
//   - 思考中：图形列是呼吸的光点环，标签写「思考中」，下面是一个三行高的
//     实时窗口（写满一行匀速上滑一行，块高不变）。
//   - 正文开始后：收成一行摘要。
//   - 轮结束：自动收起；点一下展开全文，再点收回。

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_thinking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child, {double width = 320}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  );
}

void main() {
  group('thinkingTickerText', () {
    test('掐掉尾部空行', () {
      expect(thinkingTickerText('想一下\n\n  '), '想一下');
    });

    test('剥掉加粗标记', () {
      expect(thinkingTickerText('**先看**日志'), '先看日志');
    });

    test('连续空行压成一行', () {
      expect(thinkingTickerText('上\n\n\n下'), '上\n下');
    });

    test('长文本只留尾部一段', () {
      final long = '头' * 3000 + '尾';
      final out = thinkingTickerText(long);
      expect(out.length, lessThanOrEqualTo(2000));
      expect(out.endsWith('尾'), isTrue);
    });
  });

  testWidgets('思考中：标签写「思考中」，展开区是实时窗口', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThinkingRow(
          text: '正在读文件',
          colors: DsColors(false),
          streaming: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('思考中'), findsOneWidget);
    expect(find.text('思考'), findsNothing);
    // 实时窗口显示的是思考正文（不是摘要）。
    expect(find.text('正在读文件'), findsOneWidget);
  });

  testWidgets('正文开始后：收成一行摘要，标签写「思考」', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThinkingRow(
          text: '第一行想法\n第二行',
          colors: DsColors(false),
          streaming: true,
          answerStarted: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('思考'), findsOneWidget);
    expect(find.text('思考中'), findsNothing);
    // 收起态只剩首行摘要，正文不再整段挂在列表里。
    expect(find.text('第一行想法'), findsOneWidget);
    expect(find.text('第一行想法\n第二行'), findsNothing);
  });

  testWidgets('点一下展开全文，再点收回', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThinkingRow(
          text: '第一行想法\n第二行',
          colors: DsColors(false),
          streaming: true,
          answerStarted: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('思考'));
    await tester.pumpAndSettle();

    // 展开后全文两行都在。
    expect(find.textContaining('第二行'), findsOneWidget);

    await tester.tap(find.text('思考'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第二行'), findsNothing);
  });

  testWidgets('一轮结束：手动展开的全文自动收回', (tester) async {
    Widget build({required bool streaming}) {
      return _host(
        ThinkingRow(
          text: '第一行\n第二行',
          colors: const DsColors(false),
          streaming: streaming,
          answerStarted: true,
        ),
      );
    }

    await tester.pumpWidget(build(streaming: true));
    await tester.pump();
    await tester.tap(find.text('思考'));
    await tester.pumpAndSettle();
    // 展开后全文都在。
    expect(find.textContaining('第二行'), findsOneWidget);

    await tester.pumpWidget(build(streaming: false));
    await tester.pumpAndSettle();
    // 轮结束：展开的全文收回，只剩首行摘要。
    expect(find.textContaining('第二行'), findsNothing);
    expect(find.text('第一行'), findsOneWidget);
  });

  testWidgets('签名包裹剥空后整块不渲染', (tester) async {
    await tester.pumpWidget(
      _host(
        const ThinkingRow(
          text: '<signature>abc</signature>',
          colors: DsColors(false),
          streaming: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('思考中'), findsNothing);
    expect(find.byType(ThinkingRow), findsOneWidget);
  });
}
