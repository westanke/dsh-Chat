// 会话页顶栏：标题 + 状态行。
//
// 结构借自 dsh-go 的 chat_header.dart（标题下面一行状态），配色和控件仍用本仓 token：
// 状态点颜色只是辅助，状态永远带文字。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'window_class.dart';
import 'chat_header_status.dart';

/// 顶栏：左菜单 + 会话名 + 新对话 + 右侧溢出菜单，下面一行状态。
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
                  height: DsSpacing.topBarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.menu),
                        color: c.labelPrimary,
                        onPressed: onMenu,
                      ),
                      const SizedBox(width: 4),
                      // 标题胶囊（2026-11-22 对齐 dsh-go chat_header）：两行——
                      // 上行会话名，下行状态点 + 一句人话，整体一个圆角容器。
                      Expanded(
                        child: _TitleCapsule(
                          colors: c,
                          title: title,
                          status: status,
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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 标题胶囊：会话名 + 状态行（状态点 + 人话），圆角浮层底。
class _TitleCapsule extends StatelessWidget {
  const _TitleCapsule({
    required this.colors,
    required this.title,
    required this.status,
  });

  final DsColors colors;
  final String title;
  final ChatHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Semantics(
      label: '$title，${status.spokenLabel}',
      excludeSemantics: true,
      child: Container(
        height: DsSpacing.topBarCapsuleHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: c.chipSelectedBg,
          borderRadius: BorderRadius.circular(DsSpacing.topBarCapsuleRadius),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
            ),
            Row(
              children: [
                ChatStatusDot(
                  color: statusDotColor(c, status.tone),
                  pulsing: status.tone == ChatStatusTone.busy,
                ),
                const SizedBox(width: DsSpacing.chatStatusDotGap),
                Expanded(
                  child: Text(
                    status.spokenLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                size: 18,
                color: c.labelPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态点颜色：颜色只是辅助，旁边的文字才是状态本身。
Color statusDotColor(DsColors c, ChatStatusTone tone) => switch (tone) {
  ChatStatusTone.ok => c.chatStatusOk,
  ChatStatusTone.busy => c.brand,
  ChatStatusTone.warn => c.chatStatusWarn,
  ChatStatusTone.error => c.danger,
  ChatStatusTone.idle => c.labelTertiary,
};

/// 状态点：busy 时呼吸（淡入淡出），其余静态。
class ChatStatusDot extends StatefulWidget {
  const ChatStatusDot({super.key, required this.color, this.pulsing = false});

  final Color color;

  /// 是否呼吸（连接中 / 生成中）。
  final bool pulsing;

  @override
  State<ChatStatusDot> createState() => _ChatStatusDotState();
}

class _ChatStatusDotState extends State<ChatStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DsMotion.statusPulse,
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ChatStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing == oldWidget.pulsing) return;
    if (widget.pulsing) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: DsSpacing.chatStatusDot,
      height: DsSpacing.chatStatusDot,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulsing) return dot;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: dot,
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
