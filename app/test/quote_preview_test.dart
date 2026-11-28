// 引用追问单测：QuoteTarget 截断 / composeQuotedMessage 格式与折叠 /
// QuotePreview 渲染与关闭 / 操作条「引用」入口。
//
// 这些是纯展示与纯函数逻辑，不装机；离屏 widget test 覆盖交互回调。

library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/message_actions.dart';
import 'package:dshchat/ui/quote_preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteTarget _target({
  int seq = 7,
  QuoteAuthor author = QuoteAuthor.assistant,
  String text = '原文',
  String? messageId,
}) {
  return QuoteTarget(
    messageSeq: seq,
    author: author,
    text: text,
    messageId: messageId,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );
}

void main() {
  group('QuoteTarget 预览截断', () {
    test('短文本原样展示，全文保留', () {
      final t = _target(text: '短原文');
      expect(t.text, '短原文');
      expect(t.fullText, '短原文');
    });

    test('恰好 280 字不截断', () {
      final raw = List.filled(QuoteTarget.previewMaxChars, '字').join();
      final t = _target(text: raw);
      expect(t.text, raw);
      expect(t.text.endsWith('…'), isFalse);
    });

    test('超过 280 字截到 280 字 + 省略号，fullText 仍是全文', () {
      final raw = List.filled(300, '字').join();
      final t = _target(text: raw);
      expect(t.text, '${raw.substring(0, 280)}…');
      expect(t.text.length, 281);
      expect(t.fullText, raw);
    });

    test('fromRole 把 user 映射成「你」，其它角色映射成「助手」', () {
      final me = QuoteTarget.fromRole(messageSeq: 2, role: 'user', text: '问');
      final ai = QuoteTarget.fromRole(messageSeq: 3, role: 'assistant', text: '答');
      expect(me.author, QuoteAuthor.you);
      expect(me.authorLabel, '你');
      expect(ai.author, QuoteAuthor.assistant);
      expect(ai.authorLabel, '助手');
    });

    test('相同字段相等，messageId 参与比较', () {
      expect(_target(messageId: 'm1'), _target(messageId: 'm1'));
      expect(_target(messageId: 'm1'), isNot(_target(messageId: 'm2')));
    });
  });

  group('composeQuotedMessage 格式', () {
    test('单行原文 + 用户输入', () {
      final out = composeQuotedMessage(_target(seq: 7, text: '原文'), '用户输入');
      expect(out, '> 引用（#7 助手）：原文\n\n用户输入');
    });

    test('引用用户自己的话用「你」', () {
      final out = composeQuotedMessage(
        _target(seq: 4, author: QuoteAuthor.you, text: '我先前的问题'),
        '追问',
      );
      expect(out, '> 引用（#4 你）：我先前的问题\n\n追问');
    });

    test('原文多行时每行补 > 前缀', () {
      final out = composeQuotedMessage(_target(text: '第一行\n第二行'), '继续');
      expect(out, '> 引用（#7 助手）：第一行\n> 第二行\n\n继续');
    });

    test('输入为空（含全空白）只回引用块，无尾部空行', () {
      final t = _target(seq: 9, text: '原文');
      expect(composeQuotedMessage(t, ''), '> 引用（#9 助手）：原文');
      expect(composeQuotedMessage(t, '   '), '> 引用（#9 助手）：原文');
    });

    test('发送用 fullText：300 字原文不被 280 字预览截断', () {
      final raw = List.filled(300, '字').join();
      final out = composeQuotedMessage(_target(text: raw), '继续');
      expect(out, contains(raw));
      expect(out.endsWith('…\n\n继续'), isFalse);
    });
  });

  group('composeQuotedMessage 长文折叠', () {
    List<String> numbered(int n) => [for (var i = 1; i <= n; i++) '第$i行'];

    test('恰好 20 行不折叠', () {
      final out = composeQuotedMessage(_target(text: numbered(20).join('\n')), '问');
      final block = out.split('\n\n').first;
      expect(block.contains('…'), isFalse);
      expect(block.split('\n').length, 20);
    });

    test('21 行起保留首尾各 8 行，中间用 … 占一行', () {
      final out = composeQuotedMessage(_target(text: numbered(30).join('\n')), '问');
      final block = out.split('\n\n').first;
      final lines = block.split('\n');
      // 首行带「> 引用（…）：」，其余行是「> 正文」。
      expect(lines.length, 1 + (_foldHead - 1) + 1 + _foldTail);
      expect(lines.first, '> 引用（#7 助手）：第1行');
      expect(lines[7], '> 第8行');
      expect(lines[8], '> …');
      expect(lines[9], '> 第23行');
      expect(lines.last, '> 第30行');
      expect(block.contains('第9行'), isFalse);
      expect(block.contains('第22行'), isFalse);
    });
  });

  group('QuotePreview 横幅', () {
    testWidgets('渲染标题 / 两行原文 / 关闭图标，点关闭回调 onClear', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        _host(
          QuotePreview(
            quote: _target(seq: 3, text: '第一行\n第二行\n第三行'),
            colors: DsColors(false),
            onClear: () => cleared++,
          ),
        ),
      );

      expect(find.text('引用 #3 助手'), findsOneWidget);
      expect(find.text('第一行\n第二行\n第三行'), findsOneWidget);
      final body = tester.widget<Text>(find.text('第一行\n第二行\n第三行'));
      expect(body.maxLines, 2);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byTooltip('取消引用'));
      expect(cleared, 1);
    });

    testWidgets('传 onTap 时点横幅触发，点关闭只清空不触发 onTap', (tester) async {
      var tapped = 0;
      var cleared = 0;
      await tester.pumpWidget(
        _host(
          QuotePreview(
            quote: _target(seq: 5, author: QuoteAuthor.you, text: '被引用的原文'),
            colors: DsColors(false),
            onClear: () => cleared++,
            onTap: () => tapped++,
          ),
        ),
      );

      expect(find.text('引用 #5 你'), findsOneWidget);
      await tester.tap(find.text('被引用的原文'));
      expect(tapped, 1);

      await tester.tap(find.byTooltip('取消引用'));
      expect(cleared, 1);
      expect(tapped, 1);
    });
  });

  group('DsMessageActions 的「引用」入口', () {
    testWidgets('传 onQuote 出现「引用」按钮，点击回传本条消息的 QuoteTarget', (
      tester,
    ) async {
      QuoteTarget? quoted;
      await tester.pumpWidget(
        _host(
          DsMessageActions(
            colors: DsColors(false),
            text: '助手原文',
            messageSeq: 12,
            quoteAuthor: QuoteAuthor.assistant,
            messageId: 'm-12',
            onQuote: (t) => quoted = t,
          ),
        ),
      );

      // 现有动作不受影响。
      expect(find.byTooltip('复制'), findsOneWidget);
      expect(find.byTooltip('喜欢'), findsOneWidget);
      expect(find.byTooltip('朗读'), findsOneWidget);
      expect(find.byTooltip('分享'), findsOneWidget);
      expect(find.byTooltip('重新生成'), findsOneWidget);
      expect(find.byTooltip('引用'), findsOneWidget);

      await tester.tap(find.byTooltip('引用'));
      expect(quoted, isNotNull);
      expect(quoted!.messageSeq, 12);
      expect(quoted!.author, QuoteAuthor.assistant);
      expect(quoted!.text, '助手原文');
      expect(quoted!.messageId, 'm-12');
    });

    testWidgets('不传 onQuote 时不渲染「引用」', (tester) async {
      await tester.pumpWidget(
        _host(DsMessageActions(colors: DsColors(false), text: '助手原文')),
      );
      expect(find.byTooltip('引用'), findsNothing);
      expect(find.byTooltip('复制'), findsOneWidget);
    });
  });
}

// 折叠规则与实现同源的本地常量（测试里直接引用数字，避免把私有实现暴露成 API）。
const _foldHead = 8;
const _foldTail = 8;
