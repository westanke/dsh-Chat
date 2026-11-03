part of 'chat_page.dart';

// ---------- 消息项（从 chat_page.dart 拆出，宪法 §7 控行数） ----------

class _MessageItem extends StatelessWidget {
  const _MessageItem({
    required this.message,
    required this.colors,
    required this.index,
    required this.state,
  });

  final ChatMessage message;
  final DsColors colors;
  final int index;
  final ChatState state;

  /// 双击复制整条消息（对照 companion ChatMessageItems.kt 的
  /// combinedClickable onDoubleClick + ClipboardManager）。
  Future<void> _copyAll(BuildContext context) async {
    if (message.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制整条消息')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 工具调用过程组：折叠成一行，点开展开明细。
    if (message.isProcess) {
      return DsProcessGroup(group: message, colors: colors);
    }
    // 一轮 turn 失败（模型限流 / 额度 / 网关报错）：官方是红色错误提示，
    // 这里同样用 danger 色块呈现，而不是静默什么都不显示。
    if (message.isError) {
      return Container(
        margin: const EdgeInsets.only(top: DsSpacing.blockGap),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        ),
        child: Text(
          message.text,
          style: DsTypography.small.copyWith(color: colors.danger),
        ),
      );
    }
    // 双击复制：包在气泡/正文外，不挂 onLongPress（否则选词手柄出不来）。
    final bubble = message.role == 'user'
        ? Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(
                top: DsSpacing.blockGap,
                left: DsSpacing.hMargin,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: colors.userBubble,
                borderRadius: BorderRadius.circular(DsSpacing.bubbleRadius),
              ),
              child: Text(
                message.text,
                style: DsTypography.base.copyWith(
                  color: colors.userBubbleText,
                  height: 24 / 16,
                ),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: DsSpacing.blockGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.reasoning.isNotEmpty)
                  _ThinkBlock(text: message.reasoning, colors: colors),
                DsMarkdownView(text: message.text, colors: colors),
                DsMessageActions(
                  colors: colors,
                  text: message.text,
                  onRegenerate: () => state.regenerateAt(index),
                ),
              ],
            ),
          );
    return GestureDetector(
      onDoubleTap: () => _copyAll(context),
      child: bubble,
    );
  }
}

class _StreamingItem extends StatelessWidget {
  const _StreamingItem({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.streamReasoning.isNotEmpty)
            _ThinkBlock(text: state.streamReasoning, colors: colors),
          DsMarkdownView(
            text: state.streamText,
            colors: colors,
            streaming: true,
          ),
        ],
      ),
    );
  }
}

/// 思考流：官方「已深度思考」可折叠小字块。
class _ThinkBlock extends StatefulWidget {
  const _ThinkBlock({required this.text, required this.colors});

  final String text;
  final DsColors colors;

  @override
  State<_ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<_ThinkBlock> {
  bool _expanded = false;

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
                    _expanded ? '收起深度思考' : '已深度思考',
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
