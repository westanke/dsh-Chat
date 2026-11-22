import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/thinking_ticker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _light = DsColors(false);

void main() {
  group('ThinkingTicker（dsh-go thinking_pill 的 ticker）', () {
    testWidgets('空文本不渲染任何行', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThinkingTicker(colors: _light, text: '   '),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('多行文本最多渲染 3 行可见 + 1 行待滚入', (tester) async {
      // 给足长度：不管每行切多少字，都能切出远超 3 行的内容。
      final text = List.filled(40, '思考内容').join(' ');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThinkingTicker(colors: _light, text: text),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      // 3 行可见 + 至多 1 行待滚入，绝不超过 4 行。
      expect(shown.length, lessThanOrEqualTo(4));
      expect(shown, isNotEmpty);
    });

    testWidgets('高度固定为 3 行行高（13 * 1.3）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThinkingTicker(colors: _light, text: '一句话的思考'),
          ),
        ),
      );
      final size = tester.getSize(find.byType(ThinkingTicker));
      expect(size.height, closeTo(13 * 1.3 * 3, 0.01));
    });
  });
}
