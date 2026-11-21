/// 轮尾行（官方 TurnProcessNodeView 对齐，task-5「以官方为准」批次）。
///
/// 官方行为：轮 status=='closed' 且轮尾有过程内容（外部过程组/轮内过程行）
/// 时渲染一行摘要——`已停止`/`处理失败`/`已完成`/`已完成，用时 N小时N分N秒`
/// （formatRunDuration zh），整行可点开合该轮过程（!canCollapse 禁用）；
/// reason ∈ {aborted, interrupted, error} 的轮不可折叠。样式：行高 33px、
/// 底部 0.5px 分隔线、色 label-tertiary（hover 升 label-secondary）、标题在
/// 左 chevron 紧随其后、chevron 14px open 时旋转 180°。
///
/// 偏差记录：官方轮尾行的 start/end 来自桥 TurnProcessNode。App 侧在装配
/// 历史时把轮真实起止（user/message → turn/end 的 time）挂到本轮最后一条
/// 消息的 `turnStartedAt/turnFinishedAt`，轮尾行优先用它；老历史/实时中途
/// 缺轮起止时，退回轮内过程组 startedAt/finishedAt 的最小/最大值近似（两端
/// 不齐时不出「用时」段）；stopped（aborted/interrupted）在 App 侧不可靠
/// 区分，仅 error 卡可判定「处理失败」。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_expand_state.dart';
import 'work_steps.dart';

/// 官方 `formatRunDuration(ms, t)` zh 词值实现：
/// total=max(0, floor(ms/1000))；h>0 → 'N'+'小时'；total>=60 → 'N'+'分'；
/// 末尾总是 'N'+'秒'。
String formatRunDuration(int ms) {
  var total = (ms / 1000).floor();
  if (total < 0) total = 0;
  final h = total ~/ 3600;
  final m = (total ~/ 60) % 60;
  final s = total % 60;
  final parts = <int>[];
  if (h > 0) parts.add(h);
  if (total >= 60) parts.add(m);
  parts.add(s);
  final units = <String>[];
  if (h > 0) units.add('小时');
  if (total >= 60) units.add('分');
  units.add('秒');
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    buffer.write('${parts[i]}${units[i]}');
  }
  return buffer.toString();
}

/// 轮尾行的纯数据（装配层与测试共用）。
class TurnEndInfo {
  const TurnEndInfo({
    required this.error,
    required this.durationMs,
    required this.hasProcess,
    required this.canCollapse,
    required this.expanded,
  });

  /// 轮内有 error 卡（官方 reason.kind=='error'）→「处理失败」。
  final bool error;

  /// 轮用时（毫秒）：优先轮真实起止（turnStartedAt→turnFinishedAt），
  /// 缺失时退回轮内过程组首尾；两端不齐为 null → 不出「用时」段。
  final int? durationMs;

  /// 轮内是否有过程组（官方 hasContent；无过程轮尾行不渲染）。
  final bool hasProcess;

  /// 是否可折叠（官方 canCollapse；verbose/无内容轮为 false）。
  final bool canCollapse;

  /// 折叠行当前是否展开（轮内过程组的展开态聚合）。
  final bool expanded;

  /// 展示文案（stop/error/duration 已合成）。
  String get label {
    if (error) return '处理失败';
    final ms = durationMs;
    if (ms == null) return '已完成';
    return '已完成，用时 ${formatRunDuration(ms)}';
  }
}

/// 轮尾行信息推导：轮内过程组聚合 + error 卡判定 + 展开态。
/// 无过程组的轮返回 null（官方 processHidden：foldCompleted 且不可折叠时
/// 隐藏轮尾行）。[groupKeys]=轮内各组 key（展开态聚合与回调用）。
TurnEndInfo? turnEndInfoOf(
  List<ChatMessage> messages,
  TurnRange turn, {
  required bool canCollapse,
  required bool Function(String key) isGroupExpanded,
}) {
  int? start;
  int? end;
  int? turnStart;
  int? turnEnd;
  var hasProcess = false;
  var error = false;
  var expanded = false;
  final keys = <String>[];
  for (var i = turn.start + 1; i < turn.end; i++) {
    final m = messages[i];
    if (m.isError) error = true;
    final ts = m.turnStartedAt;
    if (ts != null && (turnStart == null || ts < turnStart)) turnStart = ts;
    final te = m.turnFinishedAt;
    if (te != null && (turnEnd == null || te > turnEnd)) turnEnd = te;
    if (!m.isProcess) continue;
    hasProcess = true;
    final key = processGroupKeyOf(m);
    keys.add(key);
    if (isGroupExpanded(key)) expanded = true;
    final s = m.startedAt;
    final e = m.finishedAt;
    if (s != null && (start == null || s < start)) start = s;
    if (e != null && (end == null || e > end)) end = e;
  }
  if (!hasProcess) return null;
  int? duration;
  // 轮真实起止优先（问题 4：过程组首尾会漏掉工具之间的思考/钩子时间）。
  if (turnStart != null && turnEnd != null) {
    final span = turnEnd - turnStart;
    if (span > 0) duration = span;
  } else if (start != null && end != null) {
    final span = end - start;
    if (span > 0) duration = span;
  }
  return TurnEndInfo(
    error: error,
    durationMs: duration,
    hasProcess: true,
    canCollapse: canCollapse && keys.isNotEmpty,
    expanded: expanded,
  );
}

/// 轮尾行本体：`标题 + chevron（紧随其后）`，整行可点。
class TurnProcessRow extends StatefulWidget {
  const TurnProcessRow({
    super.key,
    required this.info,
    required this.colors,
    required this.onToggle,
  });

  final TurnEndInfo info;
  final DsColors colors;

  /// 点按回调；null 时整行禁用（官方 !canCollapse disabled）。
  final VoidCallback? onToggle;

  @override
  State<TurnProcessRow> createState() => _TurnProcessRowState();
}

class _TurnProcessRowState extends State<TurnProcessRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final info = widget.info;
    final color = _hover ? c.labelSecondary : c.labelTertiary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onToggle,
        child: Container(
          height: DsSpacing.turnRowHeight,
          padding: const EdgeInsets.only(bottom: DsSpacing.turnRowPadBottom),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.borderL2, width: 0.5)),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  info.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.small.copyWith(color: color),
                ),
              ),
              if (info.canCollapse)
                AnimatedRotation(
                  turns: info.expanded ? 0.5 : 0,
                  duration: DsMotion.scrollSettle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: DsSpacing.chipIconGap),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
