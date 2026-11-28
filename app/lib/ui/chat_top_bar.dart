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
import 'chat_state.dart';
import 'schedule_sheet.dart';

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
    this.state,
    this.jobsRunning,
    this.onOpenJobs,
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

  /// 会话状态：定时任务入口、模型名、上下文用量都要从这里读。
  /// 传 null 时这些入口退化（定时任务不渲染、模型显示「模型」、用量 chip 不显示）。
  final ChatState? state;

  /// 正在跑的后台任务数；null / 0 时不渲染 jobs chip。
  final int? jobsRunning;

  /// 点 jobs chip 打开后台任务面板；null 时 chip 只展示数量。
  final VoidCallback? onOpenJobs;

  /// 右侧溢出菜单（由会话页提供，避免这里依赖各面板）。
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final st = state;
    final openSchedule = st != null && scheduleEntryVisible(st)
        ? () => showScheduleSheet(context, st, c)
        : null;
    final running = jobsRunning ?? 0;

    // 新对话还没有标题时，胶囊沿用旧顶栏的做法显示主机名，避免一条空白药丸。
    final heading = title.trim().isEmpty ? status.label : title;

    // 有后台任务时整行略收 4dp，右侧多一枚绿色小胶囊；没有任务时不占位。
    final rowHeight = running > 0
        ? DsSpacing.topBarHeight - 4
        : DsSpacing.topBarHeight;

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
                  height: rowHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: DsSpacing.screenPad),
                      // 标题胶囊吃掉全部剩余宽度：菜单 / 新会话 / 团队 / 定时
                      // 任务都收到右侧，标题能显示更多字。
                      Expanded(
                        child: _TitleCapsule(
                          colors: c,
                          title: heading,
                          status: status,
                        ),
                      ),
                      if (running > 0) ...[
                        const SizedBox(width: DsSpacing.chipIconGap),
                        ChatJobsPill(
                          colors: c,
                          running: running,
                          onTap: onOpenJobs,
                        ),
                      ],
                      const SizedBox(width: DsSpacing.chipIconGap),
                      if (openSchedule != null)
                        _RoundAction(
                          colors: c,
                          icon: Icons.schedule_outlined,
                          tooltip: '定时任务',
                          onTap: openSchedule,
                        ),
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
                      IconButton(
                        icon: Icon(Icons.menu),
                        color: c.labelPrimary,
                        tooltip: '会话列表',
                        onPressed: onMenu,
                      ),
                      const SizedBox(width: DsSpacing.screenPad - 8),
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
