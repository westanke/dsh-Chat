/// 空态品牌标记（原创绘制的鲸形图形，不复用任何官方素材）。
///
/// 尺寸取自官方 App 空态实测：logo 116x88px / 3.0 ≈ 38.7x29.3dp，
/// 水平居中，与下方问候语间隔 66px ≈ 22dp。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 原创鲸形标记。颜色与腹部镂空色都由调用方按主题给出。
class DsBrandMark extends StatelessWidget {
  const DsBrandMark({
    super.key,
    required this.color,
    required this.bellyColor,
    this.width = DsSpacing.brandMarkWidth,
    this.height = DsSpacing.brandMarkHeight,
  });

  /// 主体色（浅色=官方品牌蓝，深色=深色主题品牌蓝）。
  final Color color;

  /// 腹部镂空色（= 页面底色，形成负形）。
  final Color bellyColor;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _WhalePainter(color: color, bellyColor: bellyColor),
    ),
  );
}

class _WhalePainter extends CustomPainter {
  const _WhalePainter({required this.color, required this.bellyColor});

  final Color color;
  final Color bellyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;

    // 原创鲸鱼标记（不使用官方素材）：近圆身体 + 右上双瓣尾鳍 +
    // 左下半月腹部留白 + 右侧眼睛。比例参照官方空态标记的实测外接框。

    // 尾鳍：上瓣窄高、下瓣宽展，中间深 V 缺口。
    final tail = Path()
      ..moveTo(0.56 * w, 0.34 * h)
      // 上瓣左缘 → 尖端
      ..cubicTo(0.63 * w, 0.20 * h, 0.67 * w, 0.08 * h, 0.70 * w, 0.02 * h)
      // 上瓣右缘 → 缺口
      ..cubicTo(0.75 * w, 0.10 * h, 0.79 * w, 0.16 * h, 0.82 * w, 0.22 * h)
      // 缺口 → 下瓣 → 右尖
      ..cubicTo(0.88 * w, 0.15 * h, 0.94 * w, 0.11 * h, 1.0 * w, 0.10 * h)
      // 下瓣外缘回落
      ..cubicTo(0.96 * w, 0.21 * h, 0.91 * w, 0.30 * h, 0.84 * w, 0.38 * h)
      ..close();
    canvas.drawPath(tail, body);

    // 身体：圆盘状，右下略收。
    final torso = Path()
      ..moveTo(0.46 * w, 0.06 * h)
      ..cubicTo(0.68 * w, 0.07 * h, 0.82 * w, 0.26 * h, 0.83 * w, 0.50 * h)
      ..cubicTo(0.84 * w, 0.74 * h, 0.68 * w, 0.95 * h, 0.44 * w, 0.97 * h)
      ..cubicTo(0.20 * w, 0.99 * h, 0.01 * w, 0.82 * h, 0.0 * w, 0.56 * h)
      ..cubicTo(0.0 * w, 0.30 * h, 0.22 * w, 0.05 * h, 0.46 * w, 0.06 * h)
      ..close();
    canvas.drawPath(torso, body);

    // 腹部月牙留白。
    final belly = Path()
      ..moveTo(0.07 * w, 0.40 * h)
      ..cubicTo(0.28 * w, 0.38 * h, 0.48 * w, 0.52 * h, 0.54 * w, 0.78 * h)
      ..cubicTo(0.38 * w, 0.88 * h, 0.18 * w, 0.82 * h, 0.10 * w, 0.66 * h)
      ..cubicTo(0.06 * w, 0.57 * h, 0.06 * w, 0.47 * h, 0.07 * w, 0.40 * h)
      ..close();
    canvas.drawPath(belly, Paint()..color = bellyColor);

    // 眼睛：白圈 + 蓝瞳。
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0.60 * w, 0.47 * h),
        width: 0.13 * w,
        height: 0.14 * h,
      ),
      Paint()..color = bellyColor,
    );
    canvas.drawCircle(
      Offset(0.585 * w, 0.47 * h),
      0.022 * w,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_WhalePainter old) =>
      old.color != color || old.bellyColor != bellyColor;
}
