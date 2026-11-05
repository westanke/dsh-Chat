part of 'composer.dart';

/// Composer 的私有小组件（宪法 §7 单文件 ≤500 行：chip / 圆形按钮 /
/// 斜杠命令建议面板 / @ 文件引用面板从 composer.dart 拆出）。

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

/// 斜杠命令建议面板（真机反馈 2026-11-04 第 3 项；第六轮 m03878：
/// 超过面板高度时可上下滚动，键盘上下键移动高亮行，回车选中）。
class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.colors,
    required this.matches,
    required this.onPick,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final List<SlashCommand> matches;
  final ValueChanged<SlashCommand> onPick;
  final int highlighted;
  final ValueChanged<int>? onHighlightChanged;

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
      // 超过约 5 行高度可滚动（m03878：命令要能上下滑动选择）。
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < matches.length; i++)
              InkWell(
                onTap: () => onPick(matches[i]),
                onHover: onHighlightChanged == null
                    ? null
                    : (h) {
                        if (h) onHighlightChanged!(i);
                      },
                borderRadius: BorderRadius.circular(
                  DsSpacing.settingsCardRadius,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DsSpacing.settingsCardPadH,
                    vertical: DsSpacing.settingsCardPadV + 2,
                  ),
                  decoration: BoxDecoration(
                    color: i == highlighted
                        ? colors.chipSelectedBg
                        : colors.none,
                    borderRadius: BorderRadius.circular(
                      DsSpacing.settingsCardRadius,
                    ),
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
                              '/${matches[i].name}',
                              style: DsTypography.baseStrong.copyWith(
                                color: colors.labelPrimary,
                              ),
                            ),
                            if (matches[i].description.isNotEmpty)
                              Text(
                                matches[i].description,
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
      ),
    );
  }
}

/// @ 文件引用面板（第六轮反馈 m03878）：输入 `@` 时浮层列出当前目录
/// （首个授权根）条目，按查询片段过滤；目录可点继续下钻，文件点选回填
/// `@label/path `。同样支持滚动 + 高亮。
class _AtFilePanel extends StatelessWidget {
  const _AtFilePanel({
    required this.colors,
    required this.entries,
    required this.query,
    required this.rootLabel,
    required this.loading,
    required this.onPick,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final List<GatewayEntry> entries;
  final String query;
  final String rootLabel;
  final bool loading;
  final ValueChanged<GatewayEntry> onPick;
  final int highlighted;
  final ValueChanged<int>? onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final visible = entries
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
        .toList();
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
      constraints: const BoxConstraints(maxHeight: 320),
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
              child: Text(
                loading ? '正在加载目录…' : '没有匹配的文件或目录',
                style: DsTypography.caption.copyWith(
                  color: colors.labelTertiary,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DsSpacing.settingsCardPadH,
                      DsSpacing.settingsCardPadV,
                      DsSpacing.settingsCardPadH,
                      0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 13,
                          color: colors.labelTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            rootLabel.isEmpty ? '/' : rootLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.caption.copyWith(
                              color: colors.labelTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < visible.length; i++)
                    InkWell(
                      onTap: () => onPick(visible[i]),
                      onHover: onHighlightChanged == null
                          ? null
                          : (h) {
                              if (h) onHighlightChanged!(i);
                            },
                      borderRadius: BorderRadius.circular(
                        DsSpacing.settingsCardRadius,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: DsSpacing.settingsCardPadH,
                          vertical: DsSpacing.settingsCardPadV,
                        ),
                        decoration: BoxDecoration(
                          color: i == highlighted
                              ? colors.chipSelectedBg
                              : colors.none,
                          borderRadius: BorderRadius.circular(
                            DsSpacing.settingsCardRadius,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              visible[i].isDirectory
                                  ? Icons.folder
                                  : Icons.insert_drive_file,
                              size: DsSpacing.chipIconSize,
                              color: visible[i].isDirectory
                                  ? colors.chipSelectedFg
                                  : colors.labelSecondary,
                            ),
                            const SizedBox(width: DsSpacing.chipIconGap + 4),
                            Expanded(
                              child: Text(
                                visible[i].isDirectory
                                    ? '${visible[i].name}/'
                                    : visible[i].name,
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
              ),
            ),
    );
  }
}
