/// 等待指示：三个跳动的点（对照官方 chat-demo 的 `.waiting` / `.waitingDot`）。
///
/// 官方网页版在「模型已接收请求但还没有任何输出」时显示三个依次淡入淡出
/// 的小圆点，手机端原先这一段是完全空白 —— 用户以为消息没发出去
/// （真机反馈 2026-11-25）。
///
/// 官方样式（chat-demo src/styles/chat.css）：
/// - 圆点直径 6px、间距 6px；
/// - 动画 `fading` 0.9s linear infinite；
/// - 第 2、3 个点各延迟 0.1s / 0.2s（负 delay 让动画一开始就在途中）；
/// - 透明度 0.3 → 1。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 三个跳动的等待点。
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key, required this.colors, this.size = 6});

  final DsColors colors;

  /// 圆点直径（dp）。官方 6px。
  final double size;

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots>
    with SingleTickerProviderStateMixin {
  /// 官方 `fading` 0.9s linear infinite。
  static const Duration _cycle = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _Dot(
            controller: _controller,
            delayMs: i * 100,
            size: widget.size,
            color: c.labelSecondary,
          ),
        ],
      ],
    );
  }
}

/// 单个点：透明度按 0.3 → 1 → 0.3 循环，起点错开 delayMs。
class _Dot extends StatelessWidget {
  const _Dot({
    required this.controller,
    required this.delayMs,
    required this.size,
    required this.color,
  });

  final AnimationController controller;
  final int delayMs;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 用 interval 拿到本点的相位：delay 越大，起步越晚。
    final total = controller.duration!.inMilliseconds;
    final start = (delayMs % total) / total;
    final end = (start + 1 / 3).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end == start ? 1.0 : end, curve: Curves.linear),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = anim.value;
        // 0.3 → 1 → 0.3 的三角波（官方 fading 关键帧）。
        final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
        final opacity = 0.3 + 0.7 * wave;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
