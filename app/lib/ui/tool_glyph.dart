/// 工具行左侧的彩色方块图标（2026-11-22 对齐 dsh-go 会话流）。
///
/// dsh-go 的每一行过程/工具调用左边是一个圆角方块色块 + 描线图标：
/// 思考是品牌蓝底，普通工具/命令是中性灰底，失败是红底。
/// 本仓原来是裸图标（无底色），换成色块后整列的节奏才对得上。
///
/// 2026-11-22 第三批：思考行在「进行中」时底块做呼吸（dsh-go
/// `thinking_pill.dart` 的 ThinkingOrb：active 呼吸、静止不动），
/// 这样一眼能看出这条思考还在写。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'tool_present.dart';

class ToolGlyph extends StatelessWidget {
  const ToolGlyph({
    super.key,
    required this.colors,
    required this.kind,
    this.failed = false,
    this.pulsing = false,
  });

  final DsColors colors;
  final ToolActivityKind kind;

  /// 这次调用失败：整个方块转红（对齐 dsh-go 的错误行）。
  final bool failed;

  /// 进行中：底块透明度做呼吸（dsh-go ThinkingOrb 的同款观感）。
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final (bg, fg) = failed
        ? (c.danger.withValues(alpha: 0.14), c.danger)
        : switch (kind) {
            // 思考/计划这类「脑子」动作给品牌色，和 dsh-go 的蓝底问号一致。
            ToolActivityKind.thinking => (
              c.brand.withValues(alpha: 0.14),
              c.brand,
            ),
            ToolActivityKind.plan => (
              c.brand.withValues(alpha: 0.14),
              c.brand,
            ),
            _ => (
              c.labelSecondary.withValues(alpha: 0.10),
              c.labelSecondary,
            ),
          };
    final square = Icon(
      toolIcon(kind),
      size: DsSpacing.toolGlyphIconSize,
      color: fg,
    );
    final Widget box = Container(
      width: DsSpacing.toolGlyphSize,
      height: DsSpacing.toolGlyphSize,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DsSpacing.toolGlyphRadius),
      ),
      child: square,
    );
    return Semantics(
      excludeSemantics: true,
      child: pulsing ? _Breathing(child: box) : box,
    );
  }
}

/// 底块呼吸：0.55 ↔ 1.0 透明度往返，2.4 秒一个来回
/// （dsh-go `AppMotion.breath = 2400ms`）。
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}
