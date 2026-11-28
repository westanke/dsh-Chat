// 会话顶栏第二行的 chip 带（2026-11-28 顶栏信息架构改造）。
//
// 改造前顶栏只有标题 + 藏在标题胶囊里的「状态点 + 人话」，模型入口在输入条、
// 上下文用量在输入条右侧的圆环、后台任务与子代理没有入口。这次把状态行拆出来，
// 与模型、上下文用量、后台任务、子代理并排成一条**可横向滚动**的 chip 带：
// 窄屏（<360 逻辑宽）靠滚动而不是换行 / 压缩，顶栏总高 = topBarHeight +
// chipHeight = 85（预算 88）。
//
// 这里只做展示：数据与动作由 chat_top_bar.dart 的 ChatTopBar 注入；颜色 / 字号 /
// 间距一律取 DsColors / DsTypography / DsSpacing。

library;

import 'package:material_ui/material_ui.dart';

import '../bridge/context_usage.dart';
import '../design/tokens.dart';
import 'chat_header_status.dart';

/// 上下文用量接近上限的阈值（与 context_usage_bar.dart / composer_status.dart
/// 的 80% 同口径：≥80% 时圆环 / chip 变警示色）。
const double _contextWarnFraction = 0.8;

/// 从 ChatState.projections（`{values: {...}}`）里读上下文用量。
///
/// 口径只有一份——`ContextUsage.fromProjections`（bridge/context_usage.dart），
/// 这里只负责剥掉 history 应答的外层 `values`（与 `goalOf` / `currentPermission`
/// 同口径：`values` 缺席时把整个投影袋当 values，老桥形状也能读）。
/// 投影缺席 / 内核没给 `contextPressure` → null（chip 不显示）。
ContextUsage? contextUsageFromChatProjections(
  Map<String, dynamic>? projections,
) {
  if (projections == null) return null;
  final values = projections['values'];
  final bag = values is Map ? values : projections;
  return ContextUsage.fromProjections(Map<String, dynamic>.from(bag));
}

/// 顶栏 chip 带：一行、横向滚动、不换行。
///
/// 高度锁成 [DsSpacing.chipHeight]，与第一行（topBarHeight）拼起来正好 85。
class ChatHeaderChipStrip extends StatelessWidget {
  const ChatHeaderChipStrip({super.key, required this.chips});

  /// 依次渲染的 chip。调用方负责决定哪些入口存在：计数为 0 / 回调缺席的
  /// chip 直接不传进来（本类不做条件判断）。
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DsSpacing.chipHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // 与抽屉筛选 chip 带同一点距（drawerFilterGap = 8），比 composer 的
        // chipGap = 19 更紧，一行能多放一个入口。
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

/// 顶栏 chip 的通用外壳：29 高胶囊、单行省略、可选前置图标 / 状态点。
///
/// 视觉与输入条模型 chip 同源（inputFill 底 + inputBorder 描边 + chipRadius），
/// 保证「顶栏 chip 带」和「输入条 chip」看起来是一套控件。
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

  /// chip 上显示的一行文字（超宽省略）。
  final String label;

  /// 无障碍朗读文案；不传时用 [label]。
  final String? semanticsLabel;

  /// 前置图标（14 号，chipIconSize）。
  final IconData? icon;

  /// 前置自定义控件（如状态点）；与 [icon] 同时给时依次排列。
  final Widget? leading;

  /// 点击回调；null = 纯展示（如连接状态 chip）。
  final VoidCallback? onTap;

  /// 强调色：上下文接近上限等场景把描边与文字一起变色。
  final Color? accent;

  /// 最宽多少（模型名 / 状态文案超长时省略，不把 chip 撑爆）。
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

/// 连接 / 流式状态 chip：沿用 [ChatHeaderStatus] 的 tone 与文案
/// （`spokenLabel` 由会话页的 `chatHeaderStatus(...)` 算好，这里不另造口径）。
class ChatStatusChip extends StatelessWidget {
  const ChatStatusChip({
    super.key,
    required this.colors,
    required this.status,
  });

  final DsColors colors;
  final ChatHeaderStatus status;

  @override
  Widget build(BuildContext context) {
    // chip 上只放短状态（在线 / 生成中 / 等待审批…）；主机名留在标题胶囊与
    // 无障碍朗读里，避免 chip 被长设备名撑满后省略成「DSH Chat (V208…」。
    final label = status.tone == ChatStatusTone.ok ? '在线' : status.label;
    return ChatHeaderChip(
      colors: colors,
      label: label,
      semanticsLabel: '连接状态：${status.spokenLabel}',
      leading: ChatStatusDot(
        color: statusDotColor(colors, status.tone),
        pulsing: status.tone == ChatStatusTone.busy,
      ),
      maxWidth: DsSpacing.composerModelChipMaxWidth,
    );
  }
}

/// 模型 chip：显示当前模型短名；服务端没给 models 帧时显示「模型」占位，
/// 两种状态都可点（点击交给上层 `onPickModel` 打开模型选择）。
class ChatModelChip extends StatelessWidget {
  const ChatModelChip({
    super.key,
    required this.colors,
    required this.modelLabel,
    this.onTap,
  });

  final DsColors colors;

  /// ChatState.modelLabel（服务端 models 帧的 current.model）；null / 空 = 老桥。
  final String? modelLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = modelLabel?.trim() ?? '';
    final label = name.isEmpty ? '模型' : name;
    return ChatHeaderChip(
      colors: colors,
      label: label,
      semanticsLabel: name.isEmpty ? '选择模型' : '当前模型 $name，点击切换',
      icon: Icons.tune,
      onTap: onTap,
    );
  }
}

/// 上下文用量 chip：百分比（窗口未知时退化成 token 摘要），≥80% 变警示色。
///
/// 数据来自 [contextUsageFromChatProjections]，点开与输入条圆环同一个明细 sheet
/// （会话页负责接线，这里只收 onTap）。
class ChatContextUsageChip extends StatelessWidget {
  const ChatContextUsageChip({
    super.key,
    required this.colors,
    required this.usage,
    this.onTap,
  });

  final DsColors colors;

  /// null 时不渲染（投影缺席 / 内核没给 contextPressure）。
  final ContextUsage? usage;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final u = usage;
    if (u == null) return const SizedBox.shrink();
    final percent = u.percent;
    final label = percent != null
        ? '上下文 $percent%'
        : '上下文 ${ContextUsage.short(u.pressureTokens)}';
    final warning = u.fraction != null && u.fraction! >= _contextWarnFraction
        ? colors.chatStatusWarn
        : null;
    return ChatHeaderChip(
      colors: colors,
      label: label,
      semanticsLabel:
          '上下文已用 $label，'
          '${ContextUsage.short(u.pressureTokens)} / '
          '${ContextUsage.short(u.contextWindow)} tokens',
      onTap: onTap,
      accent: warning,
    );
  }
}

/// 后台任务 chip：`jobsRunning` 个在跑时显示，0 / null 不显示
/// （入口由会话页按需传入，不依赖 jobs 面板的具体实现）。
class ChatJobsChip extends StatelessWidget {
  const ChatJobsChip({
    super.key,
    required this.colors,
    required this.running,
    this.onTap,
  });

  final DsColors colors;

  /// 正在跑的后台任务数；≤0 不渲染。
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

/// 子代理 chip：`subagentCount` > 0 时显示，否则不渲染。
class ChatSubagentChip extends StatelessWidget {
  const ChatSubagentChip({
    super.key,
    required this.colors,
    required this.count,
    this.onTap,
  });

  final DsColors colors;

  /// 活跃子代理数；≤0 不渲染。
  final int count;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return ChatHeaderChip(
      colors: colors,
      label: '子代理 $count',
      semanticsLabel: '子代理 $count 个，点击查看',
      icon: Icons.account_tree_outlined,
      onTap: onTap,
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
