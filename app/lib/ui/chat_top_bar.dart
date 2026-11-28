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
export 'chat_header_chips.dart' show ChatStatusDot, statusDotColor;

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

    final chips = <Widget>[
      if (running > 0)
        ChatJobsChip(colors: c, running: running, onTap: onOpenJobs),
    ];

    return ColoredBox(
      color: c.bgBase,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 顶栏与输入条同一浮层列（§4.16）：比正文列窄两侧各 chatFloatInset。
            // 宽度取实际拿到的布局宽度——抽屉打开时页面变窄，顶栏跟着收。
            final columnMax = floatingColumnWidth(constraints.maxWidth);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: columnMax),
                child: SizedBox(
                  height: DsSpacing.topBarHeight +
                      (chips.isEmpty ? 0 : DsSpacing.chipHeight),
                  child: Column(
                    children: [
                      SizedBox(
                        height: DsSpacing.topBarHeight,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.menu),
                              color: c.labelPrimary,
                              onPressed: onMenu,
                            ),
                            const SizedBox(width: 4),
                            // 标题胶囊：单行会话名（超长省略）+ 定时任务入口。
                            // 状态已挪到第二行 chip 带，胶囊不再撑两行。
                            Expanded(
                              child: _TitleCapsule(
                                colors: c,
                                title: heading,
                                status: status,
                                onOpenSchedule: openSchedule,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (onOpenTeam != null) ...[
                              _RoundAction(
                                colors: c,
                                icon: Icons.groups_outlined,
                                tooltip: '成员',
                                onTap: onOpenTeam!,
                              ),
                              const SizedBox(width: 6),
                            ],
                            _NewChatSquare(colors: c, onTap: onNewChat),
                            trailing,
                            const SizedBox(width: DsSpacing.screenPad),
                          ],
                        ),
                      ),
                      if (chips.isNotEmpty)
                        ChatHeaderChipStrip(chips: chips),
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

/// 标题胶囊：单行会话名 + 尾端定时任务入口，圆角浮层底。
///
/// 状态文案不再画在这里（已拆到 [ChatStatusChip]），所以胶囊只保留一行；
/// 高度仍用 topBarCapsuleHeight（44），与菜单 / 新对话按钮同一视觉基准。
class _TitleCapsule extends StatelessWidget {
  const _TitleCapsule({
    required this.colors,
    required this.title,
    required this.status,
    this.onOpenSchedule,
  });

  final DsColors colors;
  final String title;

  /// 只用于无障碍朗读（标题 + 当前状态一句说完）。
  final ChatHeaderStatus status;

  final VoidCallback? onOpenSchedule;

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
            if (onOpenSchedule != null) ...[
              const SizedBox(width: 6),
              _ScheduleAction(colors: c, onTap: onOpenSchedule!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 标题胶囊尾端的定时任务入口（dsh-go HeaderScheduleCap 同位置）。
class _ScheduleAction extends StatelessWidget {
  const _ScheduleAction({required this.colors, required this.onTap});

  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Tooltip(
      message: '定时任务',
      child: Semantics(
        button: true,
        label: '定时任务',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: DsSpacing.topBarNewChatSize,
              height: DsSpacing.topBarNewChatSize,
              child: Icon(
                Icons.schedule,
                size: DsSpacing.chipIconSize + 4,
                color: c.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「新对话」方形描边钮（dsh-go 顶栏最右那枚）。
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
