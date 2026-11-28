/// 会话抽屉组织能力里可复用的行/标题组件：置顶与归档分组标题、日期分组头、
/// 带未读点与多选勾选的会话行、多选底部操作条。
///
/// 与 drawer_org.dart 拆开是为了守住宪法 §7 的 500 行上限；这里只有绘制，
/// 状态与动作一律由调用方传入。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'session_groups.dart';
import 'sessions_drawer_item.dart';

/// 抽屉里的分组标题（「置顶」「已归档」）：左标题 + 右条数，可带小图标。
class DrawerOrgHeader extends StatelessWidget {
  const DrawerOrgHeader({
    super.key,
    required this.label,
    required this.count,
    required this.colors,
    this.icon,
  });

  final String label;
  final int count;
  final DsColors colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupPadV,
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupGap,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.drawerGroupLabel),
            const SizedBox(width: DsSpacing.drawerSearchIconGap),
          ],
          Expanded(
            child: Text(
              label,
              style: DsTypography.small.copyWith(
                color: colors.drawerGroupLabel,
              ),
            ),
          ),
          Text(
            '$count 条',
            style: DsTypography.caption.copyWith(color: colors.labelTertiary),
          ),
        ],
      ),
    );
  }
}

/// 日期分组标题：「更早」右侧显示「N 条 · 展开/收起」并整行可点切换；
/// 普通分组保持官方 tune 图标样式（与历史版本逐像素一致）。
class DrawerGroupHeader extends StatelessWidget {
  const DrawerGroupHeader({
    super.key,
    required this.group,
    required this.colors,
    required this.expanded,
    required this.onToggle,
  });

  final SessionGroup group;
  final DsColors colors;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            group.label,
            style: DsTypography.small.copyWith(color: colors.drawerGroupLabel),
          ),
        ),
        if (group.collapsible)
          Text(
            '${group.count} 条 · ${expanded ? '收起' : '展开'}',
            style: DsTypography.caption.copyWith(color: colors.labelTertiary),
          )
        else
          Icon(Icons.tune, size: 16, color: colors.drawerGroupLabel),
      ],
    );
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupPadV,
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupGap,
      ),
      child: row,
    );
    if (!group.collapsible) return padded;
    return InkWell(onTap: onToggle, child: padded);
  }
}

/// 一个会话行 = 既有 [SessionsDrawerItem] + 两件本任务新增的装饰：
/// 行尾未读小圆点（仅在没有「待回答/待审批」角标、也不在运行中时显示，
/// 优先级 badge > running > unread）和多选勾选框（勾选框在行首，不挤占标题）。
class SessionOrgRow extends StatelessWidget {
  const SessionOrgRow({
    super.key,
    required this.session,
    required this.colors,
    required this.selected,
    required this.running,
    required this.badge,
    required this.unread,
    required this.selecting,
    required this.checked,
    required this.onTap,
    this.onLongPress,
  });

  final DshSession session;
  final DsColors colors;
  final bool selected;
  final bool running;
  final String? badge;
  final bool unread;
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    Widget item = SessionsDrawerItem(
      session: session,
      selected: selected,
      running: running,
      badge: badge,
      colors: colors,
      onTap: onTap,
      onLongPress: onLongPress,
    );
    if (unread) {
      item = Stack(
        children: [
          item,
          Positioned(
            right: DsSpacing.drawerItemPadH - DsSpacing.drawerStatusDot,
            top: 0,
            bottom: 0,
            child: Center(
              child: Semantics(
                label: '未读',
                child: Container(
                  width: DsSpacing.drawerStatusDot,
                  height: DsSpacing.drawerStatusDot,
                  decoration: BoxDecoration(
                    color: colors.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!selecting) return item;
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: DsSpacing.drawerSearchInset),
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: checked ? colors.brand : colors.labelTertiary,
          ),
        ),
        Expanded(child: item),
      ],
    );
  }
}

/// 多选态底部操作条：已选 N 项 + 取消 + 「归档 N 项」。
class DrawerSelectionBar extends StatelessWidget {
  const DrawerSelectionBar({
    super.key,
    required this.colors,
    required this.count,
    required this.busy,
    required this.onCancel,
    required this.onArchive,
  });

  final DsColors colors;
  final int count;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerFooterPadH,
        DsSpacing.drawerItemPadV,
        DsSpacing.drawerFooterPadH,
        DsSpacing.drawerItemPadV,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已选 $count 项',
              style: DsTypography.small.copyWith(color: colors.labelSecondary),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onCancel,
            child: Text(
              '取消',
              style: DsTypography.small.copyWith(color: colors.labelSecondary),
            ),
          ),
          const SizedBox(width: DsSpacing.drawerSearchIconGap),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.brand,
              foregroundColor: colors.onBrand,
            ),
            onPressed: count == 0 || busy ? null : onArchive,
            child: Text(busy ? '归档中…' : '归档 $count 项'),
          ),
        ],
      ),
    );
  }
}
