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

/// 后台任务小胶囊：绿色实底，放在状态栏右侧；没有任务时不渲染。
///
/// 2026-11-28 二次收口后，顶栏不再有整行 chip 带，只在有后台任务时显示这枚
/// 20dp 高的小胶囊（点开后台任务面板），标题胶囊因此保持最长。
class ChatJobsPill extends StatelessWidget {
  const ChatJobsPill({
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
    final c = colors;
    return Semantics(
      button: true,
      label: '后台任务 $running 个，点击查看',
      excludeSemantics: true,
      child: Material(
        color: c.chatStatusOk.withValues(
          alpha: DsSpacing.statusTintAlpha,
        ),
        borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: DsSpacing.jobsPillHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.jobsPillPadH,
            ),
            alignment: Alignment.center,
            child: Text(
              '后台 $running',
              style: DsTypography.chipLabel.copyWith(
                color: c.chatStatusOk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
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
