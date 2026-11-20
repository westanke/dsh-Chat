// 会话页顶栏：标题 + 状态行。
//
// 结构借自 dsh-go 的 chat_header.dart（标题下面一行状态），配色和控件仍用本仓 token：
// 状态点颜色只是辅助，状态永远带文字。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
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
    required this.trailing,
  });

  final DsColors colors;
  final String title;
  final ChatHeaderStatus status;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  /// 右侧溢出菜单（由会话页提供，避免这里依赖各面板）。
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ColoredBox(
      color: c.bgBase,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 18),
                  Tooltip(
                    message: '新建对话',
                    child: InkResponse(
                      radius: 20,
                      onTap: onNewChat,
                      child: Icon(
                        Icons.add_circle_outline,
                        size: 24,
                        color: c.labelPrimary,
                      ),
                    ),
                  ),
                  trailing,
                  const SizedBox(width: DsSpacing.screenPad),
                ],
              ),
            ),
            _StatusLine(colors: c, status: status),
          ],
        ),
      ),
    );
  }
}

/// 状态行：状态点 + 一句人话。
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.colors, required this.status});

  final DsColors colors;
  final ChatHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      // 与标题左对齐：菜单键 48 + 间距 8。
      padding: const EdgeInsets.only(left: 56, bottom: 4),
      child: SizedBox(
        height: DsSpacing.chatStatusRowHeight,
        child: Row(
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
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ),
          ],
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
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
      ),
    );
    if (!widget.pulsing) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}
