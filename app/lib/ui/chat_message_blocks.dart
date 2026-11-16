part of 'chat_page.dart';

/// 思考流：官方「已深度思考」可折叠小字块。
/// [streaming] 为 true 时默认展开并显示「深度思考中…」（真机反馈第五轮
/// m03759：有思考时流式展示思考过程，而非折叠藏起来）；历史消息保持折叠。
/// [showPreview]（官方 settledReasoningPreview）：折叠态在标题下显示一行
/// 正文预览（concise 档只留标题）。
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

  /// 预览行：正文首个非空行（官方 preview 口径）。
  String get _previewText {
    for (final line in widget.text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.thinkHMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 14,
                    color: c.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded
                        ? '收起深度思考'
                        : widget.streaming
                        ? '深度思考中…'
                        : '已深度思考',
                    style: DsTypography.smallStrong.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: c.labelSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (!_expanded && !widget.streaming && widget.showPreview)
            Padding(
              padding: const EdgeInsets.only(
                left: DsSpacing.thinkHMargin + DsSpacing.processIconSize,
              ),
              child: Text(
                _previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: DsSpacing.thinkHMargin),
              child: DsMarkdownView(text: widget.text, colors: c, small: true),
            ),
        ],
      ),
    );
  }
}
