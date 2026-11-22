import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 进行中思考行的多行滚动预览（dsh-go `thinking_pill.dart` 的 ticker）。
///
/// 官方行为：思考进行中不只显示一行摘要，而是把已生成的思考文本按行排放，
/// 最多露出 3 行；新行到来时整块上移一行（160ms 线性），右端渐隐。本文件只
/// 负责这块预览文字，标题与图形列仍由过程组渲染。
class ThinkingTicker extends StatefulWidget {
  const ThinkingTicker({
    super.key,
    required this.colors,
    required this.text,
    this.maxRows = 3,
    this.fontSize = 13,
    this.lineHeightFactor = 1.3,
  });

  final DsColors colors;
  final String text;

  /// 同时可见的行数（官方 `rows = 3`）。
  final int maxRows;
  final double fontSize;
  final double lineHeightFactor;

  @override
  State<ThinkingTicker> createState() => _ThinkingTickerState();
}

class _ThinkingTickerState extends State<ThinkingTicker>
    with SingleTickerProviderStateMixin {
  // 官方 ticker 是 AnimatedContainer(160ms, linear)。
  late final AnimationController _shift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// 每行切多少字（按宽度近似，避免每次 build 都跑 TextPainter）。
  int _perLine = 24;

  double get _lineHeight => widget.fontSize * widget.lineHeightFactor;

  @override
  void didUpdateWidget(covariant ThinkingTicker old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final before = _split(old.text).length;
    final now = _split(widget.text).length;
    if (now > before) _shift.forward(from: 0);
  }

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  List<String> _split(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return const [];
    final out = <String>[];
    for (var i = 0; i < flat.length; i += _perLine) {
      out.add(flat.substring(i, (i + _perLine).clamp(0, flat.length)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 每行可用宽度 ≈ 屏宽减去图形列 24、间距 8、左右边距与右侧渐隐余量。
    final usable = (width * 0.6).clamp(160.0, 480.0);
    _perLine = (usable / (widget.fontSize * 0.62)).floor().clamp(12, 90);

    final lines = _split(widget.text);
    if (lines.isEmpty) return const SizedBox.shrink();
    final visible = lines.length > widget.maxRows
        ? lines.sublist(lines.length - widget.maxRows)
        : lines;
    final entering = lines.length > widget.maxRows
        ? lines[lines.length - widget.maxRows - 1]
        : null;
    final style = DsTypography.small.copyWith(
      fontSize: widget.fontSize,
      height: widget.lineHeightFactor,
      color: widget.colors.labelTertiary,
    );

    Widget row(String text) => SizedBox(
      height: _lineHeight,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: style,
      ),
    );

    return SizedBox(
      height: _lineHeight * widget.maxRows,
      child: ShaderMask(
        // 右端渐隐：文字滑到可视区外不要硬切（官方同款处理）。
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, 0.82, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ClipRect(
          // 待滚入的那一行会暂时超出可视高度，用 OverflowBox 让它排出来、
          // 再由外层 ClipRect 裁掉，避免 Flex 溢出报错。
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: AnimatedBuilder(
            animation: _shift,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -_shift.value * _lineHeight),
              child: child,
            ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entering != null) row(entering),
                  for (final line in visible) row(line),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
