/// 空态品牌标记的尺寸契约（对齐官方空态实测 38.7x29.3dp）。
library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('品牌标记按 token 尺寸绘制', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DsBrandMark(
              color: Color(0xFF426EFE),
              bellyColor: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
    final box = tester.getSize(find.byType(DsBrandMark));
    expect(box.width, DsSpacing.brandMarkWidth);
    expect(box.height, DsSpacing.brandMarkHeight);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
