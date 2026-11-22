/// 抽屉的状态筛选行（2026-11-22 对齐 dsh-go `drawer_filter_bar.dart`）：
/// 「全部对话 ⌄」+ 四个安静胶囊（全部 / 运行中 / 待确认 / 未读）。
///
/// 计数为 0 时不拼数字（dsh-go 同一口径：只有 >0 才写「待确认 2」）。
/// 这一行纯展示 + 回调上行，状态留在抽屉本体（`SessionsDrawerState`）。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 抽屉列表的状态筛选档位。
enum DrawerFilter {
  all('全部'),
  running('运行中'),
  pending('待确认'),
  unread('未读');

  const DrawerFilter(this.label);

  /// 胶囊上的中文。
  final String label;
}

class DrawerFilterBar extends StatelessWidget {
  const DrawerFilterBar({
    super.key,
    required this.colors,
    required this.filter,
    required this.onFilter,
    required this.runningCount,
    required this.pendingCount,
    required this.unreadCount,
    required this.scopeLabel,
    required this.onScopeTap,
  });

  final DsColors colors;
  final DrawerFilter filter;
  final ValueChanged<DrawerFilter> onFilter;

  /// 三档计数（0 = 不拼数字）。
  final int runningCount;
  final int pendingCount;
  final int unreadCount;

  /// 「全部对话」那一行当前的文字（选了某个工作区时换成它的名字）。
  final String scopeLabel;

  /// 点「全部对话」→ 选范围（全部工作区 / 某一个）。
  final VoidCallback onScopeTap;

  int _countOf(DrawerFilter f) => switch (f) {
        DrawerFilter.all => 0,
        DrawerFilter.running => runningCount,
        DrawerFilter.pending => pendingCount,
        DrawerFilter.unread => unreadCount,
      };

  String _labelOf(DrawerFilter f) {
    final n = _countOf(f);
    return n > 0 ? '${f.label} $n' : f.label;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 范围行：文字 + 下拉箭头（点开选工作区）。
        SizedBox(
          height: DsSpacing.drawerScopeRowHeight,
          child: InkWell(
            onTap: onScopeTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.drawerToolbarPadH,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 18,
                    color: colors.labelSecondary,
                  ),
                  const SizedBox(width: DsSpacing.drawerSearchIconGap),
                  Flexible(
                    child: Text(
                      scopeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.small.copyWith(
                        color: colors.labelPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: colors.labelSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 胶囊行（横向可滚，大字号时不挤爆）。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.drawerFilterPadH,
            DsSpacing.drawerFilterPadTop,
            DsSpacing.drawerFilterPadH,
            DsSpacing.drawerFilterPadBottom,
          ),
          child: Row(
            children: [
              for (final (i, f) in DrawerFilter.values.indexed) ...[
                if (i > 0) const SizedBox(width: DsSpacing.drawerFilterGap),
                _capsule(f),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _capsule(DrawerFilter f) {
    final on = f == filter;
    return Semantics(
      button: true,
      selected: on,
      label: _labelOf(f),
      excludeSemantics: true,
      child: Material(
        color: on ? colors.chipSelectedBg : colors.drawerSearchFill,
        borderRadius: BorderRadius.circular(
          DsSpacing.drawerFilterChipHeight / 2,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onFilter(f),
          child: SizedBox(
            height: DsSpacing.drawerFilterChipHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.drawerFilterChipPadH,
              ),
              child: Center(
                child: Text(
                  _labelOf(f),
                  style: DsTypography.caption.copyWith(
                    color: on ? colors.chipSelectedFg : colors.labelSecondary,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
