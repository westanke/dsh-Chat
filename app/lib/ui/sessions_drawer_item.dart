/// 抽屉里的一行会话（从 sessions_drawer.dart 拆出，宪法 §7 控行数）。
///
/// 默认是单行条目；带 [SessionsDrawerItem.subtitle] 时下面加一行注脚（正文命中
/// 片段）。这一件被抽屉本体与「对话内容」一节共用。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';

class SessionsDrawerItem extends StatelessWidget {
  const SessionsDrawerItem({
    super.key,
    required this.session,
    required this.selected,
    this.badge,
    this.running = false,
    this.subtitle,
    required this.colors,
    this.onTap,
    this.onLongPress,
  });

  final DshSession session;
  final bool selected;

  /// 行尾状态小字（null = 不显示）。
  final String? badge;

  /// 这一条正在跑（行尾画一颗状态点；有 badge 时 badge 优先，与 dsh-go
  /// session_tile 的 pending > running > unread 优先级同序）。
  final bool running;

  /// 第二行（正文命中片段）。null = 单行条目（默认形态）。
  final String? subtitle;
  final DsColors colors;

  /// null = 这一行不可点（会话已不在列表里）。
  final VoidCallback? onTap;

  /// 长按开会话操作菜单（重命名 / 归档）。null = 不提供菜单。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      session.displayTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DsTypography.small.copyWith(
        color: selected ? colors.brand : colors.labelPrimary,
        height: DsSpacing.drawerLineHeight / 14,
      ),
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.drawerItemPadH,
          vertical: DsSpacing.drawerItemPadV,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: title),
                if (badge != null) ...[
                  const SizedBox(width: DsSpacing.drawerSearchIconGap),
                  Text(
                    badge!,
                    style: DsTypography.small.copyWith(color: colors.chatStatusWarn),
                  ),
                ] else if (running) ...[
                  const SizedBox(width: DsSpacing.drawerSearchIconGap + 4),
                  Container(
                    width: DsSpacing.drawerStatusDot,
                    height: DsSpacing.drawerStatusDot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.brand,
                    ),
                  ),
                ],
              ],
            ),
            // 正文命中片段：压一行、次级色，比标题轻——它是「为什么这条命中」的注脚。
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: DsSpacing.drawerItemSubtitleGap),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.caption.copyWith(color: colors.labelSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
