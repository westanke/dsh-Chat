/// 思考行的图形件：静止态原子图标 + 思考中的呼吸光点环。
///
/// 形态参照 dsh-go 的 `app/lib/ui/chat/widgets/thinking_pill.dart`：图形列里
/// 放一个图形——思考中是缓慢呼吸的一圈光点，停下来是一枚静止的原子。
/// 两个图形都是本工程自绘，没有搬 dsh-go 的 orb 引擎，也没有复用官方图标素材。
///
/// 尺寸与色值见 docs/design-tokens.md §4.13。

library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 静止态图形：一枚原子（两道交错的轨道 + 中心点）。
///
/// 自绘的椭圆轨道，不抄任何现成图标路径。
class ThinkAtom extends StatelessWidget {
  const ThinkAtom({super.key, required this.color, this.size = DsSpacing.thinkGlyphSize});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _AtomPainter(color));
  }
}

class _AtomPainter extends CustomPainter {
  const _AtomPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.17
      ..color = color
      ..isAntiAlias = true;
    // 两道交错的轨道：同一枚椭圆，转 90° 再画一次。
    for (final angle in const [0.0, math.pi / 2]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 1.68,
          height: radius * 0.74,
        ),
        orbit,
      );
      canvas.restore();
    }
    canvas.drawCircle(center, radius * 0.24, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AtomPainter old) => old.color != color;
}

/// 思考中的图形：一圈缓慢呼吸的光点。
///
/// 一圈点沿圆周排开，整圈慢慢转；每个点按自己的相位呼吸：靠前的点更亮更大，
/// 靠后的点更暗更小——于是这一圈看上去是一颗有厚度的球在轻轻起伏。
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({super.key, required this.color, this.size = DsSpacing.thinkOrbSize});

  final Color color;
  final double size;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DsMotion.thinkingBreath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统关了动画就停着：图形停在最亮的一帧。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _OrbPainter(widget.color, _controller.value),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter(this.color, this.phase);

  final Color color;

  /// 0..1 的循环相位。
  final double phase;

  /// 圆周上的点数。
  static const int _dots = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final t = phase * 2 * math.pi;
    final base = size.width / 2 - 1.2;
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < _dots; i++) {
      final angle = 2 * math.pi * i / _dots + t * 0.24;
      // 半径的起伏：两段不同频率的波叠在一起，轮廓才不会像齿轮。
      final wobble = 0.16 * math.sin(angle * 3 - t * 1.7) +
          0.07 * math.sin(angle * 5 + t * 1.1);
      final radius = base * (1 + wobble);
      // 朝前的点更亮更大，朝后的点更暗更小。
      final depth = (math.cos(angle - t * 0.24) + 1) / 2;
      paint.color = color.withValues(alpha: 0.42 + 0.5 * depth);
      canvas.drawCircle(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        0.9 + 0.9 * depth,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.color != color || old.phase != phase;
}
