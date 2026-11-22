/// 输入条上方的「当前活动」条（对齐 dsh-go `widgets/activity_strip.dart`）。
///
/// dsh-go 在会话底部浮一条胶囊，实时告诉你这一轮**正在做什么**：
/// 左边是活动图形（思考 / 工具 / 命令），中间是标题 + 一行细节，
/// 右边是从这一步开始算起的实时秒表。
///
/// 本仓数据不需要新协议：`ChatMessage.startedAt` 已经是过程组的墙钟起点
/// （`history_page.dart` 用首个事件时间填），`isToolRowLive` 判定哪条还在跑。
/// 秒表每秒刷新一次，秒数用等宽体，避免数字跳动时抖动。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/history_page.dart';
import '../bridge/tool_call.dart';
import '../design/tokens.dart';
import 'tool_present.dart';
import 'tool_titles.dart';

/// 从最新消息里找出「正在进行的活动」；没有就返回 null（条子不占位）。
///
/// 取最后一条过程组里第一条 live 的调用；组里没有 live 调用、但这一轮还在
/// 生成（`streaming`）时，退化成「思考」并把组起点当秒表起点——这正是
/// dsh-go `runActivityOf` 在 waiting/thinking 两态做的事。
LiveActivity? liveActivityOf({
  required List<ChatMessage> messages,
  required bool streaming,
}) {
  if (!streaming) return null;
  for (final m in messages.reversed) {
    if (!m.isProcess) continue;
    final rows = m.processRows.isNotEmpty
        ? m.processRows
        : <ToolCallInfo>[...m.thoughts, ...m.toolCalls];
    for (final call in rows.reversed) {
      if (!isToolRowLive(call)) continue;
      return LiveActivity(
        kind: activityKind(call.name),
        label: toolTitle(call.name),
        detail: call.summary,
        since: m.startedAt,
      );
    }
    // 组里没有 live 调用：这一轮还在生成，说明模型在思考。
    if (rows.isNotEmpty || m.reasoning.isNotEmpty) {
      return LiveActivity(
        kind: ToolActivityKind.thinking,
        label: '思考中',
        detail: null,
        since: m.startedAt,
      );
    }
  }
  return LiveActivity(
    kind: ToolActivityKind.thinking,
    label: '思考中',
    detail: null,
    since: null,
  );
}

/// 一条「正在做什么」的快照。
class LiveActivity {
  const LiveActivity({
    required this.kind,
    required this.label,
    required this.detail,
    required this.since,
  });

  final ToolActivityKind kind;
  final String label;
  final String? detail;

  /// 这一步的墙钟起点（epoch ms）；缺时间就不显示秒表，绝不假造。
  final int? since;

  /// 已用时文案：`m:ss`（超过一小时给 `h:mm:ss`）。[now] 由调用方给，
  /// 纯函数便于单测。
  String? elapsedLabel(int now) {
    final start = since;
    if (start == null) return null;
    final ms = now - start;
    if (ms < 0) return null; // 时钟倒退：不显示
    final total = ms ~/ 1000;
    final s = total % 60;
    final m = (total ~/ 60) % 60;
    final h = total ~/ 3600;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }
}

/// 输入条上方的活动条。`activity` 为 null 时不渲染（由调用方判断）。
class ActivityStrip extends StatefulWidget {
  const ActivityStrip({
    super.key,
    required this.activity,
    required this.colors,
  });

  final LiveActivity activity;
  final DsColors colors;

  @override
  State<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends State<ActivityStrip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(ActivityStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了活动（思考 → 工具）时重新起表，秒表从新活动的起点算。
    if (oldWidget.activity.since != widget.activity.since ||
        oldWidget.activity.label != widget.activity.label) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    // 没有起点就没有秒表，不必白跑定时器。
    if (widget.activity.since == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final a = widget.activity;
    final elapsed = a.elapsedLabel(DateTime.now().millisecondsSinceEpoch);
    final detail = a.detail;
    final hasDetail = detail != null && detail.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        0,
        DsSpacing.screenPad,
        DsSpacing.activityStripGap,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.activityStripPadH,
        vertical: DsSpacing.activityStripPadV,
      ),
      decoration: BoxDecoration(
        color: c.drawerSearchFill,
        borderRadius: BorderRadius.circular(DsSpacing.activityStripRadius),
      ),
      child: Row(
        children: [
          Icon(_icon(a.kind), size: DsSpacing.menuIconSize, color: c.brand),
          const SizedBox(width: DsSpacing.activityStripIconGap),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: a.label,
                    style: DsTypography.smallStrong.copyWith(
                      color: c.labelPrimary,
                    ),
                  ),
                  if (hasDetail)
                    TextSpan(
                      text: '  $detail',
                      style: DsTypography.codeBlockLabel.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (elapsed != null) ...[
            const SizedBox(width: DsSpacing.activityStripIconGap),
            Text(
              elapsed,
              style: DsTypography.codeBlockLabel.copyWith(
                color: c.labelTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _icon(ToolActivityKind kind) => switch (kind) {
    ToolActivityKind.thinking => Icons.psychology_outlined,
    ToolActivityKind.plan => Icons.checklist_rtl,
    ToolActivityKind.commands => Icons.terminal,
    ToolActivityKind.edit || ToolActivityKind.write => Icons.edit_note,
    ToolActivityKind.questions => Icons.help_outline,
    ToolActivityKind.webSearch || ToolActivityKind.webFetch => Icons.language,
    _ => Icons.build_outlined,
  };
}
