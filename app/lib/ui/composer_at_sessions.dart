// @ 面板的「对话」分组（@ 面板的会话候选）。
//
// 与 composer_panels.dart 同库 part：选中的会话由 _ComposerState 负责插入
// mention 文本，这里只负责渲染「对话」标题与命中列表。
part of 'composer.dart';

class _AtSessionPanel extends StatelessWidget {
  const _AtSessionPanel({
    required this.colors,
    required this.sessions,
    required this.onPick,
  });

  final DsColors colors;
  final List<DshSession> sessions;
  final ValueChanged<DshSession> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.chipIconGap),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        boxShadow: [
          BoxShadow(
            color: colors.bgBase.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: DsSpacing.chipIconSize,
                  color: colors.labelTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  '对话',
                  style: DsTypography.caption.copyWith(
                    color: colors.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          ...[
            for (final s in sessions)
              InkWell(
                onTap: () => onPick(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: DsSpacing.chipIconSize,
                        color: colors.brand,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.title ?? s.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsTypography.base.copyWith(
                            color: colors.labelPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
