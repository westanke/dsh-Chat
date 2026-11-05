// 斜杠命令面板与 @ 文件引用面板（从 composer_widgets.dart 拆出，
// 宪法 §7 单文件 ≤500 行）。同为 composer.dart 的 part。
part of 'composer.dart';

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

/// @ 文件引用面板（第六轮反馈 m03878）：输入 `@` 时浮层列出当前授权根的
/// 目录条目（多根合并），按查询片段过滤；目录可点继续下钻，文件点选回填
/// `@label/path `。同样支持滚动 + 高亮。失败态显示错误行 + 点按重试（m04149）。
class _AtFilePanel extends StatelessWidget {
  const _AtFilePanel({
    required this.colors,
    required this.entries,
    required this.query,
    required this.rootLabel,
    required this.loading,
    required this.onPick,
    this.failed = false,
    this.onRetry,
    this.highlighted = -1,
    this.onHighlightChanged,
  });

  final DsColors colors;
  final List<GatewayEntry> entries;
  final String query;
  final String rootLabel;
  final bool loading;

  /// 目录页拉取失败（m04149）：显示错误行 + 点按重试，而不是假装「没有匹配」。
  final bool failed;
  final VoidCallback? onRetry;
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
              child: InkWell(
                onTap: failed && !loading ? onRetry : null,
                borderRadius: BorderRadius.circular(
                  DsSpacing.settingsCardRadius,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loading
                            ? '正在加载目录…'
                            : failed
                                ? '目录加载失败，点按重试'
                                : '没有匹配的文件或目录',
                        style: DsTypography.caption.copyWith(
                          color: failed && !loading
                              ? colors.danger
                              : colors.labelTertiary,
                        ),
                      ),
                    ),
                    if (failed && !loading)
                      Icon(
                        Icons.refresh,
                        size: 16,
                        color: colors.labelTertiary,
                      ),
                  ],
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

/// 多根 @ 目录拉取合并（m04149）：此前只取第一个根，若它恰好是空目录
/// （如 default-workspace）面板就永远为空。逐根拉取；多根时条目名加
/// `label/` 前缀防撞，单根保持原名。
Future<List<GatewayEntry>> fetchAtEntries(
  GatewayClient gw,
  List<GatewayRoot> roots,
  String dir,
) async {
  var merged = const <GatewayEntry>[];
  for (final root in roots) {
    final entries = await gatewayListEntries(gw, root.id, dir);
    if (roots.length > 1) {
      merged = [
        ...merged,
        ...entries.map(
          (e) => GatewayEntry(
            name: '${root.label}/${e.name}',
            path: '${root.label}/${e.path}',
            kind: e.kind,
          ),
        ),
      ];
    } else {
      merged = entries;
    }
  }
  return merged;
}
