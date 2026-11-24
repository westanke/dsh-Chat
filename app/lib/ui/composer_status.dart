/// 输入条右侧的状态小件（2026-11-22 对齐 dsh-go 输入条）：
/// 模型 chip（显示当前模型，点开模型选择）+ 上下文环形（点开用量明细）。
///
/// 上下文环形自己按 sessionId 拉一次数据、轮末刷新，不占 ChatState：
/// `gateway.contextUsage(sid)` → `ContextUsage.fromProjections`。
///
/// 模型 chip 的文案由 ChatState 持有（`modelLabel`，服务端 models 帧的
/// current.model）：以前 chip 自己拉一次并按会话号短路
/// （`if (_loadedFor == sid) return;`），同会话内切完模型界面永远不更新
/// （问题2：框里显示的模型与实际运行的不一致）。现在切完模型立刻重读一次，
/// 显示的就是服务端在跑的那个。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/context_usage.dart';
import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'context_usage_bar.dart';

/// 模型 chip：一个安静胶囊，显示当前模型名，点击交给上层打开模型选择。
class ComposerModelChip extends StatelessWidget {
  const ComposerModelChip({
    super.key,
    required this.colors,
    required this.modelLabel,
    required this.onTap,
    this.enabled = true,
  });

  final DsColors colors;

  /// 当前模型名（由 ChatState 持有；空 = 不显示 chip）。
  final String? modelLabel;

  /// 点一下：上层打开模型选择（`showModelSheet`）。
  final VoidCallback onTap;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final name = modelLabel;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: DsSpacing.composerButtonGap),
      child: Semantics(
      button: true,
      label: '模型 $name',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
          child: Container(
            height: DsSpacing.chipHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.chipPadH,
            ),
            decoration: BoxDecoration(
              color: c.inputFill,
              borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
              border: Border.all(color: c.inputBorder),
            ),
            child: Center(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.chipLabel.copyWith(color: c.labelPrimary),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// 上下文环形：22 号圆环 + 百分比，点开用量明细（与流里那条 bar 同一个 sheet）。
class ComposerUsageRing extends StatefulWidget {
  const ComposerUsageRing({
    super.key,
    required this.colors,
    required this.gateway,
    required this.sessionId,
    this.streaming = false,
  });

  final DsColors colors;
  final GatewayClient? gateway;
  final String? sessionId;

  /// 轮末（streaming 由真变假）时重拉：用量只在轮末变。
  final bool streaming;

  @override
  State<ComposerUsageRing> createState() => _ComposerUsageRingState();
}

class _ComposerUsageRingState extends State<ComposerUsageRing> {
  ContextUsage? _value;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ComposerUsageRing old) {
    super.didUpdateWidget(old);
    final sid = widget.sessionId;
    if (sid == null) {
      _loadedFor = null;
      if (_value != null) setState(() => _value = null);
      return;
    }
    final turnJustEnded = old.streaming && !widget.streaming;
    if (sid != _loadedFor || turnJustEnded) _load();
  }

  Future<void> _load() async {
    final gw = widget.gateway;
    final sid = widget.sessionId;
    if (gw == null || sid == null) return;
    _loadedFor = sid;
    try {
      final r = await gw.contextUsage(sid);
      if (!mounted || widget.sessionId != sid) return;
      setState(() => _value = ContextUsage.fromProjections(r));
    } catch (_) {
      // 老桥没有该帧：不画环（与 context_usage_bar 同口径）。
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final usage = _value;
    if (usage == null || usage.contextWindow <= 0) return const SizedBox.shrink();
    final fraction = usage.fraction ?? 0;
    final percent = usage.percent;
    final ringColor = fraction >= 0.8 ? c.chatStatusWarn : c.brand;
    return Semantics(
      button: true,
      label: percent == null ? '上下文用量' : '上下文 $percent%',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DsSpacing.composerButtonSize / 2),
        onTap: () => showContextUsageSheet(context, c, usage),
        child: Padding(
          padding: const EdgeInsets.only(
            left: DsSpacing.composerButtonGap,
            right: 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 2.6,
                  color: ringColor,
                  backgroundColor: c.borderL2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                percent == null ? '上下文' : '$percent%',
                style: DsTypography.smallStrong.copyWith(
                  color: c.labelSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
