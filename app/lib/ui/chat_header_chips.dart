// 会话顶栏的状态点与后台任务 chip。
//
// 2026-11-28 再次收口（用户反馈）：状态文字、模型、上下文用量、子代理都已在
// 输入条或标题胶囊里有入口，顶栏不再重复展示；只保留：
// - 标题胶囊前的状态色点（绿=通、红=断、黄=连接中、绿闪=工作中、蓝=等用户）；
// - 有后台任务在跑时的一枚 chip（没有别的入口，且需要能点开面板）。
//
// 颜色 / 字号 / 间距一律取 DsColors / DsTypography / DsSpacing。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'chat_header_status.dart';

/// 顶栏 chip 带：一行、横向滚动、不换行。
class ChatHeaderChipStrip extends StatelessWidget {
  const ChatHeaderChipStrip({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DsSpacing.chipHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.screenPad),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: DsSpacing.drawerFilterGap),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 顶栏 chip 的通用外壳：29 高胶囊、单行省略、可选前置图标。
class ChatHeaderChip extends StatelessWidget {
  const ChatHeaderChip({
    super.key,
    required this.colors,
    required this.label,
    this.semanticsLabel,
    this.icon,
    this.leading,
    this.onTap,
    this.accent,
    this.maxWidth = DsSpacing.composerModelChipMaxWidth,
  });

  final DsColors colors;
  final String label;
  final String? semanticsLabel;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;
  final Color? accent;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final accentColor = accent;
    return Semantics(
      button: onTap != null,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Material(
        color: accentColor == null ? c.inputFill : c.chipSelectedBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
          side: BorderSide(color: accentColor ?? c.inputBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: DsSpacing.chipHeight,
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: DsSpacing.chipPadH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: DsSpacing.chipIconGap),
                ],
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: DsSpacing.chipIconSize,
                    color: accentColor ?? c.labelTertiary,
                  ),
                  const SizedBox(width: DsSpacing.chipIconGap),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.chipLabel.copyWith(
                      color: accentColor ?? c.labelPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 后台任务 chip：`jobsRunning` 个在跑时显示，0 / null 不显示。
class ChatJobsChip extends StatelessWidget {
  const ChatJobsChip({
    super.key,
    required this.colors,
    required this.running,
    this.onTap,
  });

  final DsColors colors;
  final int running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (running <= 0) return const SizedBox.shrink();
    return ChatHeaderChip(
      colors: colors,
      label: '后台任务 $running',
      semanticsLabel: '后台任务 $running 个，点击查看',
      icon: Icons.bolt,
      onTap: onTap,
    );
  }
}

/// 状态点的颜色 + 是否呼吸。
///
/// 标准（2026-11-28 用户定，补充两种）：
/// - 绿常亮：已连接、空闲；
/// - 绿呼吸：正在工作（生成中）；
/// - 黄常亮：正在连接 / 重连；
/// - 红常亮：断开、鉴权失败；
/// - 蓝常亮：在等用户（审批 / 回答）；
/// - 灰常亮：还没开始连接。
({Color color, bool pulsing}) statusDotVisual(
  DsColors c,
  ChatHeaderStatus status,
) {
  switch (status.tone) {
    case ChatStatusTone.ok:
      return (color: c.chatStatusOk, pulsing: false);
    case ChatStatusTone.busy:
      final working = status.label == '生成中';
      return (
        color: working ? c.chatStatusOk : c.chatStatusWarn,
        pulsing: working,
      );
    case ChatStatusTone.warn:
      // 等用户不是故障，用品牌蓝与「连接中」的黄区分开。
      return (color: c.brand, pulsing: false);
    case ChatStatusTone.error:
      return (color: c.danger, pulsing: false);
    case ChatStatusTone.idle:
      return (color: c.labelTertiary, pulsing: false);
  }
}

/// 兼容旧调用点的颜色映射。
Color statusDotColor(DsColors c, ChatStatusTone tone) => switch (tone) {
  ChatStatusTone.ok => c.chatStatusOk,
  ChatStatusTone.busy => c.chatStatusWarn,
  ChatStatusTone.warn => c.brand,
  ChatStatusTone.error => c.danger,
  ChatStatusTone.idle => c.labelTertiary,
};

/// 状态点：工作时呼吸（淡入淡出），其余静态。
class ChatStatusDot extends StatefulWidget {
  const ChatStatusDot({super.key, required this.color, this.pulsing = false});

  final Color color;
  final bool pulsing;

  @override
  State<ChatStatusDot> createState() => _ChatStatusDotState();
}

class _ChatStatusDotState extends State<ChatStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: DsMotion.statusPulse,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChatStatusDot old) {
    super.didUpdateWidget(old);
    if (old.pulsing != widget.pulsing || old.color != widget.color) _sync();
  }

  void _sync() {
    if (widget.pulsing) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        width: DsSpacing.chatStatusDot,
        height: DsSpacing.chatStatusDot,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
