/// 把品牌标记离屏渲染成 PNG，便于在宿主上快速比对形状（不装机）。
/// 用法：flutter test test/render_mark_test.dart
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dshchat/ui/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('导出品牌标记 PNG', (tester) async {
    // 放大 8 倍看清轮廓。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Transform.scale(
              scale: 8,
              child: const DsBrandMark(
                color: Color(0xFF426EFE),
                bellyColor: Color(0xFFFFFFFF),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary),
    );
    late final ByteData? bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    });
    // 输出到仓库的 ref/，用**相对路径**：`flutter test` 的工作目录是 app/，
    // 所以 ../ref 即仓库根的 ref/。早先这里写死 /media/wangke/... 绝对路径，
    // 换机器或进 CI 必然失败（那个目录在 CI 里根本不存在，writeAsBytesSync 抛异常）。
    final refDir = Directory('../ref');
    expect(refDir.existsSync(), isTrue,
        reason: 'ref/ 应随仓库分发；缺失说明 .gitignore 误伤了基准素材');
    final out = File('${refDir.path}/mark-preview.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(out.existsSync(), isTrue);
  });
}
