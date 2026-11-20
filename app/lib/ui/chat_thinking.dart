/// 思考行：形态照 dsh-go 会话页的思考行（thinking_pill.dart + stream_row.dart）。
///
/// 三种样子：
/// - 思考中：图形列里一枚呼吸的光点环，标签「思考中」有一道来回扫的亮光，
///   下面跟着一个三行高的实时窗口——正在写的话写满一行就匀速往上滑一行，
///   窗口高度从头到尾不变，列表不会跟着思考变长而抖。
/// - 正文开始后：收成一行摘要，只留思考的第一行。
/// - 轮结束：同上，点一下展开全文（Markdown），再点收回。
///
/// 颜色仍用本仓的 brand 配方，图形自绘（见 chat_thinking_glyph.dart）；
/// 结构与尺寸依据见 docs/design-tokens.md §4.13。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'chat_thinking_glyph.dart';
import 'md_view.dart';
import 'reasoning_text.dart';

/// 思考行。
///
/// [streaming] 表示思考文本还在流式输出；[answerStarted] 表示助手正文已经
/// 开始输出（= 思考阶段结束，实时窗口收成一行摘要）。
class ThinkingRow extends StatefulWidget {
  const ThinkingRow({
    super.key,
    required this.text,
    required this.colors,
    this.streaming = false,
    this.answerStarted = false,
    this.showPreview = true,
  });

  /// 思考原文（可能还包着 `<signature>`，显示前会剥掉）。
  final String text;

  final DsColors colors;

  /// 思考文本仍在流式输出。
  final bool streaming;

  /// 助手正文已开始输出。
  final bool answerStarted;

  /// 结束后是否留一行首行摘要。
  final bool showPreview;

  @override
  State<ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<ThinkingRow> {
  late bool _expanded = false;

  /// 思考进行中：还在写，正文还没出来。
  bool get _active => widget.streaming && !widget.answerStarted;

  /// 展开区可见：思考中永远有实时窗口（或用户展开的全文），结束后看用户。
  bool get _open => _active || _expanded;

  @override
  void didUpdateWidget(ThinkingRow old) {
    super.didUpdateWidget(old);
    // 一轮结束：过程收回摘要，手动展开的全文不留在外面。
    if (old.streaming && !widget.streaming) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (reasoningHidden(widget.text)) return const SizedBox.shrink();
    final c = widget.colors;
    final body = widget.text.trim().isEmpty ? '' : reasoningTextOf(widget.text);
    final summary = reasoningSummaryOf(widget.text, running: widget.streaming);
    // 思考中或展开时不留行内摘要：位置让给实时窗口或全文。
    final showPreview =
        !_open && summary.isNotEmpty && widget.showPreview;

    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.thinkHMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Lead(active: _active, colors: c),
              const SizedBox(width: DsSpacing.thinkColumnGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      active: _active,
                      colors: c,
                      preview: showPreview ? summary : '',
                      expanded: _expanded,
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                    if (_open)
                      _Thread(
                        colors: c,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: DsSpacing.thinkBodyPadTop,
                            bottom: DsSpacing.thinkBodyPadBottom,
                          ),
                          child: _expanded
                              ? DsMarkdownView(text: body, colors: c, small: true)
                              : _LiveWindow(
                                  text: body,
                                  style: DsTypography.codeBlockLabel
                                      .copyWith(color: c.labelTertiary),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图形列：思考中是呼吸的光点环，停下来是一枚原子。
class _Lead extends StatelessWidget {
  const _Lead({required this.active, required this.colors});

  final bool active;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DsSpacing.thinkLeadWidth,
      height: DsSpacing.thinkLeadWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.thinkGlyphBg,
          borderRadius:
              BorderRadius.circular(DsSpacing.thinkLeadWidth * 0.32),
        ),
        child: Center(
          child: active
              ? ThinkingOrb(color: colors.brand)
              : ThinkAtom(color: colors.brand),
        ),
      ),
    );
  }
}

/// 标题行：标签 +（收起时）首行摘要 + 展开箭头。
class _Header extends StatelessWidget {
  const _Header({
    required this.active,
    required this.colors,
    required this.preview,
    required this.expanded,
    required this.onTap,
  });

  final bool active;
  final DsColors colors;
  final String preview;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: DsSpacing.thinkRowHeight,
        child: Row(
          children: [
            _SweepLabel(
              text: active ? '思考中' : '思考',
              active: active,
              style: DsTypography.small.copyWith(color: c.labelSecondary),
              muted: c.labelTertiary,
              bright: c.labelPrimary,
            ),
            if (preview.isNotEmpty) ...[
              Container(
                width: DsSpacing.sepDot,
                height: DsSpacing.sepDot,
                margin: const EdgeInsets.symmetric(horizontal: DsSpacing.sepGap),
                decoration: BoxDecoration(
                  color: c.labelTertiary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Expanded(child: _FadedPreview(text: preview, colors: c)),
            ] else
              const Spacer(),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: c.labelTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 首行摘要：右端渐隐，长句不会硬生生切在字上。
class _FadedPreview extends StatelessWidget {
  const _FadedPreview({required this.text, required this.colors});

  final String text;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = ((rect.width - 40) / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: [colors.labelTertiary, colors.labelTertiary.withValues(alpha: 0)],
          stops: [fade, 1],
        ).createShader(rect);
      },
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DsTypography.codeBlockLabel.copyWith(color: colors.labelTertiary),
      ),
    );
  }
}

/// 标签：思考中时有一道亮光来回扫过，其余时间是静的。
class _SweepLabel extends StatefulWidget {
  const _SweepLabel({
    required this.text,
    required this.active,
    required this.style,
    required this.muted,
    required this.bright,
  });

  final String text;
  final bool active;
  final TextStyle style;
  final Color muted;
  final Color bright;

  @override
  State<_SweepLabel> createState() => _SweepLabelState();
}

class _SweepLabelState extends State<_SweepLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DsMotion.thinkingSweepPeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_SweepLabel old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  /// 扫光的开关跟着 active 走；系统关了动画就停着。
  void _sync() {
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 亮光在周期里的位置：先等一会儿（lead），再扫一遍（sweep），然后歇到下一轮。
  /// 返回 null 表示此刻不亮。
  double? _sweepValue() {
    if (!widget.active) return null;
    final elapsed = _controller.value * DsMotion.thinkingSweepPeriod.inMilliseconds;
    final lead = DsMotion.thinkingSweepLead.inMilliseconds;
    final sweep = DsMotion.thinkingSweep.inMilliseconds;
    if (elapsed < lead) return null;
    final t = (elapsed - lead) / sweep;
    if (t >= 1) return null;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(widget.text, style: widget.style);
    if (!widget.active) return label;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = _sweepValue();
          if (value == null) return child!;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => LinearGradient(
              colors: [widget.muted, widget.bright, widget.muted],
            ).createShader(
              Rect.fromLTWH(
                (2 * value - 1) * rect.width,
                0,
                rect.width,
                rect.height,
              ),
            ),
            child: child,
          );
        },
        child: label,
      ),
    );
  }
}

/// 展开区：一条 1px 细线走图形列的中线，内容从文字列起（缩进 32）。
class _Thread extends StatelessWidget {
  const _Thread({required this.colors, required this.child});

  final DsColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RailPainter(colors.borderL2),
      child: Padding(
        padding: const EdgeInsets.only(left: DsSpacing.thinkBodyIndent),
        child: child,
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = DsSpacing.thinkLeadWidth / 2;
    canvas.drawLine(
      Offset(x, 4),
      Offset(x, size.height - 4),
      Paint()
        ..color = color
        ..strokeWidth = DsSpacing.thinkRailWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.color != color;
}

/// 实时窗口：最多三行，写满一行匀速往上滑一行，高度不变。
class _LiveWindow extends StatelessWidget {
  const _LiveWindow({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final shown = thinkingTickerText(text);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          text: TextSpan(text: shown, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: width);
        final textHeight = painter.height;
        painter.dispose();
        final lineHeight =
            scaler.scale(style.fontSize ?? 13) * (style.height ?? 1.3);
        final window = lineHeight * DsSpacing.thinkTickerRows;
        final shift = (textHeight - window).clamp(0.0, double.infinity);
        return SizedBox(
          width: width,
          height: window,
          child: ClipRect(
            child: AnimatedContainer(
              duration: DsMotion.thinkingTicker,
              curve: Curves.linear,
              transform: Matrix4.translationValues(0, -shift, 0),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: SizedBox(width: width, child: Text(shown, style: style)),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 实时窗口里显示的文字：掐掉尾部的空行和加粗标记。
///
/// 只留尾部一段，长文本不会把布局拖慢。
String thinkingTickerText(String text) {
  var out = text.trimRight();
  if (out.length > _tickerChars) {
    out = out.substring(out.length - _tickerChars);
  }
  out = out.replaceAll('**', '');
  out = out.replaceAll(_blankRun, '\n');
  return out.trimLeft();
}

/// 实时窗口保留的字符数。
const int _tickerChars = 2000;

/// 连续空行压成一行。
final RegExp _blankRun = RegExp(r'\n[ \t]*(\n[ \t]*)+');
