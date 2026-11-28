// 会话页顶栏：一行标题 + 可选的后台任务 chip。
//
// 2026-11-28 用户收口：状态文字、模型、上下文用量、子代理都已有输入条/面板入口，
// 不再在顶栏重复展示；连接状态改成标题胶囊前的一枚色点（绿=通、红=断、黄=连接中、
// 绿闪=工作中、蓝=等用户、灰=未连接）。只有后台任务在跑时才多一行 chip。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'window_class.dart';
import 'chat_header_chips.dart';
import 'chat_header_status.dart';

// 状态点 / chip 组件现在住在 chat_header_chips.dart；从这里转出，
// 让既有 `import 'chat_top_bar.dart'` 的调用方（含测试）不用改。
export 'chat_header_chips.dart' show ChatStatusDot;

/// 顶栏：左菜单 + 会话名 + 新对话 + 右侧溢出菜单，下面一条信息 chip 带。
class ChatTopBar extends StatelessWidget {
  const ChatTopBar({
    super.key,
    required this.colors,
    required this.title,
    required this.status,
    required this.onMenu,
    required this.onNewChat,
    this.onOpenTeam,
    required this.trailing,
  });

  final DsColors colors;
  final String title;
  final ChatHeaderStatus status;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  /// 「成员」圆钮（dsh-go chat_header 的三圆钮之一）：打开智能团队面板。
  /// 传 null 时不渲染（老调用点/离屏测试不受影响）。
  final VoidCallback? onOpenTeam;

  /// 右侧溢出菜单（由会话页提供，避免这里依赖各面板）。
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // 新对话还没有标题时，胶囊沿用旧顶栏的做法显示主机名，避免一条空白药丸。
    final heading = title.trim().isEmpty ? status.label : title;

    return ColoredBox(
      color: c.bgBase,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 顶栏与输入条同一浮层列（§4.16）：比正文列窄两侧各 chatFloatInset。
            final columnMax = floatingColumnWidth(constraints.maxWidth);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: columnMax),
                child: SizedBox(
                  height: DsSpacing.topBarHeight,
                  child: Row(
                    children: [
                      // 会话列表菜单固定在标题胶囊前面，保持可见。
                      IconButton(
                        icon: Icon(Icons.menu),
                        color: c.labelPrimary,
                        tooltip: '会话列表',
                        onPressed: onMenu,
                      ),
                      const SizedBox(width: 2),
                      // 标题胶囊吃掉剩余宽度；定时任务 / 团队 / 新建 / 更多在右。
                      Expanded(
                        child: _TitleCapsule(
                          colors: c,
                          title: heading,
                          status: status,
                        ),
                      ),
                      const SizedBox(width: DsSpacing.chipIconGap),
                      if (onOpenTeam != null) ...[
                        const SizedBox(width: 2),
                        _RoundAction(
                          colors: c,
                          icon: Icons.groups_outlined,
                          tooltip: '成员',
                          onTap: onOpenTeam!,
                        ),
                      ],
                      const SizedBox(width: 2),
                      _NewChatSquare(colors: c, onTap: onNewChat),
                      trailing,
                      const SizedBox(width: DsSpacing.screenPad),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 标题胶囊：单行会话名 + 状态点，圆角浮层底。
///
/// 定时任务入口已移到胶囊外（右侧圆钮），胶囊因此能把宽度全给标题；
/// 高度仍用 topBarCapsuleHeight（44），与右侧按钮同一视觉基准。
class _TitleCapsule extends StatelessWidget {
  const _TitleCapsule({
    required this.colors,
    required this.title,
    required this.status,
  });

  final DsColors colors;
  final String title;

  /// 只用于无障碍朗读（标题 + 当前状态一句说完）。
  final ChatHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final heading = title.trim();
    final visual = statusDotVisual(c, status);
    return Semantics(
      label: heading.isEmpty
          ? status.spokenLabel
          : (status.spokenLabel.isEmpty || status.spokenLabel == heading
              ? heading
              : '$heading，${status.spokenLabel}'),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: DsSpacing.topBarCapsuleHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: c.chipSelectedBg,
          borderRadius: BorderRadius.circular(DsSpacing.topBarCapsuleRadius),
        ),
        child: Row(
          children: [
            ChatStatusDot(
              color: visual.color,
              pulsing: visual.pulsing,
            ),
            const SizedBox(width: DsSpacing.chipIconGap),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.h4.copyWith(color: c.labelPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChatSquare extends StatelessWidget {
  const _NewChatSquare({required this.colors, required this.onTap});

  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Tooltip(
      message: '新建对话',
      child: Semantics(
        button: true,
        label: '新建对话',
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsSpacing.topBarNewChatRadius),
            side: BorderSide(color: c.inputBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: DsSpacing.topBarNewChatSize,
              height: DsSpacing.topBarNewChatSize,
              child: Icon(
                Icons.edit_outlined,
                size: DsSpacing.chipIconSize + 4,
                color: c.labelPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏圆形动作钮（对齐 dsh-go chat_header 的「成员/电话」圆钮外形）。
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final DsColors colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.drawerSearchFill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: DsSpacing.drawerRoundButtonSize,
            height: DsSpacing.drawerRoundButtonSize,
            child: Icon(
              icon,
              size: DsSpacing.chipIconSize + 4,
              color: c.labelSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
