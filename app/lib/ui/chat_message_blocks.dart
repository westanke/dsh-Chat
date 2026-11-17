part of 'chat_page.dart';

/// 思考行（官方 ReasoningRow 逐项对齐，task-5）：
/// - 图标 Think14 + 标题常量「思考」（message.think）+ 2px 圆点分隔 +
///   13px 摘要（running 时取最后已完成段落首行，否则正文首行）；
/// - 行高 24px（thinkRowHeight）、整行可点（expandOnRowClick）、无 chevron
///   （官方 DisclosureRow 形态）；
/// - 摘要仅在 preview 为真且未展开时显示（preview = running ||
///   settledReasoningPreview；官方 TextShimmer 动画未做，偏差已登记）；
/// - 签名包裹剥除后无正文 → 整块不渲染（reasoningHidden）；
/// - 展开正文用 reasoningTextOf 剥掉 `<signature>` 包裹。
class _ThinkBlock extends StatefulWidget {
  const _ThinkBlock({
    required this.text,
    required this.colors,
    this.streaming = false,
    this.showPreview = true,
  });

  final String text;
  final DsColors colors;
  final bool streaming;

  /// 折叠态是否显示一行正文预览（默认 true）。
  final bool showPreview;

  @override
  State<_ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<_ThinkBlock> {
  late bool _expanded = widget.streaming;

  /// 折叠行摘要（官方 ReasoningRow）：running 取最后已完成段落首行，
  /// 否则正文首行；加粗标记全剥。
  String get _summary =>
      reasoningSummaryOf(widget.text, running: widget.streaming);

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    // 官方 hidden 判定：签名包裹剥除后无正文 → 整块不渲染。
    if (reasoningHidden(widget.text)) return const SizedBox.shrink();
    // preview = 未展开 && 摘要非空 && (running || 档位允许预览)。
    final showSummary =
        !_expanded &&
        _summary.isNotEmpty &&
        (widget.streaming || widget.showPreview);
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.thinkHMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: DsSpacing.thinkRowHeight,
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: c.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  // 官方标题常量「思考」（message.think），字重 400。
                  Text(
                    '思考',
                    style: DsTypography.small.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                  if (showSummary) ...[
                    // 2px 圆点分隔（官方 .separator，色 label-caption
                    // → 近似 labelTertiary）。
                    Container(
                      width: DsSpacing.sepDot,
                      height: DsSpacing.sepDot,
                      margin: const EdgeInsets.symmetric(
                        horizontal: DsSpacing.sepGap,
                      ),
                      decoration: BoxDecoration(
                        color: c.labelTertiary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.codeBlockLabel.copyWith(
                          color: c.labelTertiary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: DsSpacing.thinkHMargin),
              child: DsMarkdownView(
                text: reasoningTextOf(widget.text),
                colors: c,
                small: true,
              ),
            ),
        ],
      ),
    );
  }
}

