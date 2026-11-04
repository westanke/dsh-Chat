part of 'composer.dart';

/// Composer 的私有小组件（宪法 §7 单文件 ≤500 行：chip / 圆形按钮 /
/// 斜杠命令建议面板从 composer.dart 拆出）。


/// 胶囊 chip：未选中为白底 + 细描边，选中为浅蓝底 + 品牌色文字。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? colors.chipSelectedFg : colors.labelPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
      child: Container(
        height: DsSpacing.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.chipPadH),
        decoration: BoxDecoration(
          color: active ? colors.chipSelectedBg : colors.inputFill,
          borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
          border: Border.all(
            color: active ? colors.chipSelectedBg : colors.inputBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DsSpacing.chipIconSize, color: fg),
            const SizedBox(width: DsSpacing.chipIconGap),
            Text(label, style: DsTypography.chipLabel.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 圆形按钮：filled=品牌色实心（发送），否则细描边（+ / 语音）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.colors,
    required this.filled,
    required this.icon,
    required this.onPressed,
  });

  final DsColors colors;
  final bool filled;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DsSpacing.composerButtonSize,
      height: DsSpacing.composerButtonSize,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        color: filled ? colors.onBrand : colors.labelPrimary,
        style: IconButton.styleFrom(
          backgroundColor: filled ? colors.brand : colors.none,
          shape: CircleBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: colors.labelPrimary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

/// 斜杠命令建议面板（真机反馈 2026-11-04 第 3 项）：输入 `/` 时浮在输入条
/// 上方，列出前缀匹配的命令（最多 6 条），点选回填 `/name `。
class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.colors,
    required this.matches,
    required this.onPick,
  });

  final DsColors colors;
  final List<SlashCommand> matches;
  final ValueChanged<SlashCommand> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.chipIconGap),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final cmd in matches)
            InkWell(
              onTap: () => onPick(cmd),
              borderRadius: BorderRadius.circular(
                DsSpacing.settingsCardRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.settingsCardPadH,
                  vertical: DsSpacing.settingsCardPadV + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal,
                      size: DsSpacing.chipIconSize + 2,
                      color: colors.chipSelectedFg,
                    ),
                    const SizedBox(width: DsSpacing.chipIconGap + 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '/${cmd.name}',
                            style: DsTypography.baseStrong.copyWith(
                              color: colors.labelPrimary,
                            ),
                          ),
                          if (cmd.description.isNotEmpty)
                            Text(
                              cmd.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsTypography.caption.copyWith(
                                color: colors.labelTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
