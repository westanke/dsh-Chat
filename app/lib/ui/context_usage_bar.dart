/// 上下文用量条（输入条上方一行）：小圆环 + 「上下文 42% · 61k / 1M」。
///
/// 数据来自 `context-usage` 帧；点开面板列实际占用、下次预估与窗口大小。
/// 刷新时机由本组件自己判断（切会话 / 一轮从「运行中」变「结束」），
/// 不往 ChatState（已 506 行）里加字段。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/context_usage.dart';
import '../bridge/gateway.dart';
import '../design/tokens.dart';

class ContextUsageBar extends StatefulWidget {
  const ContextUsageBar({
    super.key,
    required this.gateway,
    required this.sessionId,
    required this.streaming,
    required this.colors,
  });

  final GatewayClient gateway;
  final String? sessionId;
  final bool streaming;
  final DsColors colors;

  @override
  State<ContextUsageBar> createState() => _ContextUsageBarState();
}

class _ContextUsageBarState extends State<ContextUsageBar> {
  ContextUsage? _value;
  String? _loadedFor;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) _load(widget.sessionId!);
  }

  @override
  void didUpdateWidget(ContextUsageBar old) {
    super.didUpdateWidget(old);
    final sid = widget.sessionId;
    if (sid == null) {
      if (_value != null) setState(() => _value = null);
      _loadedFor = null;
      return;
    }
    // 切了会话，或这一轮刚跑完（用量只在轮末才变）→ 重拉。
    final turnJustEnded = old.streaming && !widget.streaming;
    if (sid != _loadedFor || turnJustEnded) _load(sid);
  }

  Future<void> _load(String sid) async {
    if (_loading && _loadedFor == sid) return;
    _loading = true;
    _loadedFor = sid;
    try {
      final r = await widget.gateway.contextUsage(sid);
      if (!mounted || widget.sessionId != sid) return;
      setState(() => _value = ContextUsage.fromProjections(r));
    } catch (_) {
      // 老桥没有该帧（UNKNOWN_TYPE）或网络抖动：保持旧值，不报错。
    } finally {
      if (widget.sessionId == sid) _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = _value;
    if (usage == null || usage.contextWindow <= 0) {
      return const SizedBox.shrink();
    }
    final c = widget.colors;
    final fraction = usage.fraction ?? 0;
    // 80% 以上转警示色：与桌面端「上下文快满了」的口径一致。
    final ringColor = fraction >= 0.8 ? c.chatStatusWarn : c.brand;
    final percent = usage.percent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        DsSpacing.blockGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
          onTap: () => _openSheet(usage),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: c.bgLayer1,
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              border: Border.all(color: c.borderL2, width: 1),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 2.4,
                    color: ringColor,
                    backgroundColor: c.borderL2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  percent == null ? '上下文' : '上下文 $percent%',
                  style: DsTypography.smallStrong.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${ContextUsage.short(usage.pressureTokens)} / '
                    '${ContextUsage.short(usage.contextWindow)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: DsSpacing.chipIconSize,
                  color: c.labelTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSheet(ContextUsage usage) =>
      showContextUsageSheet(context, widget.colors, usage);
}

/// 上下文用量明细（输入条的环和流里的条共用这一个 sheet）。
Future<void> showContextUsageSheet(
  BuildContext context,
  DsColors c,
  ContextUsage usage,
) {
  return showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bgBase,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '上下文用量',
                style: DsTypography.h4.copyWith(color: c.labelPrimary),
              ),
              const SizedBox(height: 16),
              _usageRow('本次占用', ContextUsage.short(usage.pressureTokens), c),
              const SizedBox(height: 10),
              _usageRow('含新增预估', ContextUsage.short(usage.projectedTokens), c),
              const SizedBox(height: 10),
              _usageRow('窗口大小', ContextUsage.short(usage.contextWindow), c),
              const SizedBox(height: 10),
              _usageRow('占比', usage.percent == null ? '未知' : '${usage.percent}%', c),
              const SizedBox(height: 16),
              Text(
                '占用超过 80% 后内核会开始压缩历史；长期会话建议及时开新会话。',
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ],
          ),
        ),
      ),
    );
}

Widget _usageRow(String label, String value, DsColors c) {
  return Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: DsTypography.small.copyWith(color: c.labelSecondary),
        ),
      ),
      Text(
        value,
        style: DsTypography.smallStrong.copyWith(color: c.labelPrimary),
      ),
    ],
  );
}
