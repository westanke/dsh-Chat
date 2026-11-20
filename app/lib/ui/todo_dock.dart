/// 输入条上方的任务条（移植 dsh-go 的 `dock/todo_bar.dart`）：
/// 一行摘要「3/7 · 正在：跑测试」+ 进度线，点一下在卡内展开整张清单。
///
/// 数据源是本仓已有的会话投影（`todoItems(state.projections)`），不额外请求
/// 内核；代理每写一次 todo 投影就更新，条子跟着变。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/projections.dart';
import '../design/tokens.dart';

/// 任务条摘要（纯逻辑，单测直接构造 TodoItem 断言）。
///
/// 与 dsh-go `TodoDockSummary.of` 同口径：
/// - 没有清单 → null（条子不显示）；
/// - `current` 取第一个进行中，否则第一个未完成；
/// - 全部完成 → 「全部完成」；运行中且当前项进行中 → 「正在：…」；
///   否则 → 「下一步：…」。
class TodoDockSummary {
  const TodoDockSummary({
    required this.total,
    required this.done,
    required this.current,
    required this.label,
    required this.isComplete,
  });

  final int total;
  final int done;

  /// 当前关注项（全完成时为 null）。
  final TodoItem? current;

  /// 摘要文案的正文部分（不含 `done/total`）。
  final String label;

  final bool isComplete;

  double get fraction => total == 0 ? 0 : done / total;

  String get count => '$done/$total';

  static TodoDockSummary? of(List<TodoItem> todos, {required bool running}) {
    if (todos.isEmpty) return null;
    final done = todos.where((t) => t.isCompleted).length;
    TodoItem? current;
    for (final t in todos) {
      if (t.isInProgress) {
        current = t;
        break;
      }
    }
    if (current == null) {
      for (final t in todos) {
        if (!t.isCompleted) {
          current = t;
          break;
        }
      }
    }
    final complete = done == todos.length;
    final label = complete
        ? '全部完成'
        : running && current != null && current.isInProgress
        ? '正在：${current.content}'
        : '下一步：${current?.content ?? '继续'}';
    return TodoDockSummary(
      total: todos.length,
      done: done,
      current: current,
      label: label,
      isComplete: complete,
    );
  }
}

/// 任务条本体：摘要行 + 进度线；点摘要行原地展开清单（不弹层）。
class TodoDockBar extends StatefulWidget {
  const TodoDockBar({
    super.key,
    required this.summary,
    required this.todos,
    required this.colors,
  });

  final TodoDockSummary summary;
  final List<TodoItem> todos;
  final DsColors colors;

  @override
  State<TodoDockBar> createState() => _TodoDockBarState();
}

class _TodoDockBarState extends State<TodoDockBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final s = widget.summary;
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
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.bgLayer1,
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              border: Border.all(color: c.borderL2, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      s.isComplete
                          ? Icons.task_alt
                          : Icons.checklist_rtl_outlined,
                      size: DsSpacing.chipIconSize,
                      color: s.isComplete ? c.diffAdd : c.brand,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.count,
                      style: DsTypography.smallStrong.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.caption.copyWith(
                          color: c.labelPrimary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.expand_more,
                        size: DsSpacing.chipIconSize,
                        color: c.labelTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: s.fraction,
                    minHeight: 2,
                    backgroundColor: c.borderL2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      s.isComplete ? c.diffAdd : c.brand,
                    ),
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 168),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final t in widget.todos)
                            _TodoRow(item: t, colors: c),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 清单单行：完成=成功色带勾、进行中=品牌色加粗、未开始=第三级文字。
class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.item, required this.colors});

  final TodoItem item;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final (icon, color) = item.isCompleted
        ? (Icons.check_circle, c.diffAdd)
        : item.isInProgress
        ? (Icons.radio_button_checked, c.brand)
        : (Icons.radio_button_unchecked, c.labelTertiary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.content,
              style:
                  (item.isInProgress
                          ? DsTypography.smallStrong
                          : DsTypography.small)
                      .copyWith(
                        color: item.isCompleted
                            ? c.labelTertiary
                            : item.isInProgress
                            ? c.labelPrimary
                            : c.labelSecondary,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
