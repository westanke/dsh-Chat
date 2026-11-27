/// 定时任务列表行与详情视图。
///
/// 从 `schedule_sheet.dart` 拆出，避免单文件超过 500 行（AGENTS.md §7）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/gateway_schedule.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

/// 单条任务卡片：标题/规则/启停/下次运行/最近结果 + 运行、详情、删除。
class ScheduleRow extends StatelessWidget {
  const ScheduleRow({
    super.key,
    required this.task,
    required this.colors,
    required this.busy,
    required this.onToggle,
    required this.onRun,
    required this.onDetail,
    required this.onDelete,
  });

  final ScheduleTask task;
  final DsColors colors;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRun;
  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final last = task.lastRunAt == null
        ? task.lastResultLabel
        : '${task.lastResultLabel} · ${_fmtWhen(task.lastRunAt)}';
    return Container(
      margin: const EdgeInsets.only(bottom: DsSpacing.liGap),
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.settingsCardPadH,
        DsSpacing.settingsCardPadV,
        DsSpacing.liGap,
        DsSpacing.settingsCardPadV,
      ),
      decoration: BoxDecoration(
        color: c.settingsSurface,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        border: Border.all(color: c.borderL1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.baseStrong.copyWith(
                        color: c.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.ruleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.small.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: ValueKey('schedule-toggle-${task.id}'),
                value: task.enabled,
                onChanged: busy ? null : onToggle,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _MetaLine(
            colors: c,
            icon: Icons.event_available,
            text: task.enabled ? '下次运行 ${_fmtWhen(task.nextRunAt)}' : '已停用',
          ),
          const SizedBox(height: 2),
          _MetaLine(colors: c, icon: Icons.history, text: last),
          const SizedBox(height: 2),
          Row(
            children: [
              _TextAction(colors: c, label: '立即运行', onTap: busy ? null : onRun),
              const SizedBox(width: 4),
              _TextAction(colors: c, label: '详情', onTap: onDetail),
              const Spacer(),
              _TextAction(
                colors: c,
                label: '删除',
                danger: true,
                onTap: busy ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.colors,
    required this.icon,
    required this.text,
  });

  final DsColors colors;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      children: [
        Icon(icon, size: 14, color: c.labelTertiary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DsTypography.caption.copyWith(color: c.labelSecondary),
          ),
        ),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.colors,
    required this.label,
    this.onTap,
    this.danger = false,
  });

  final DsColors colors;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final color = onTap == null
        ? c.labelTertiary
        : (danger ? c.danger : c.brand);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DsSpacing.inlineCodeRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          label,
          style: DsTypography.smallStrong.copyWith(color: color),
        ),
      ),
    );
  }
}

/// 任务详情：schedule-view 取最新记录 + schedule-history 取最近投递。
class ScheduleDetailView extends StatefulWidget {
  const ScheduleDetailView({
    super.key,
    required this.task,
    required this.state,
    required this.colors,
  });

  final ScheduleTask task;
  final ChatState state;
  final DsColors colors;

  @override
  State<ScheduleDetailView> createState() => _ScheduleDetailViewState();
}

class _ScheduleDetailViewState extends State<ScheduleDetailView> {
  late ScheduleTask _task = widget.task;
  ScheduleHistoryPage? _history;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    var task = _task;
    try {
      task = await widget.state.gateway.scheduleView(_task.id);
    } on RequestException {
      // 详情读失败时保留列表里的数据，不把整页打成错误态。
    }
    ScheduleHistoryPage? history;
    final sid = widget.state.sessionId;
    if (sid != null && sid.isNotEmpty) {
      try {
        history = await widget.state.gateway.scheduleHistory(
          sid,
          _task.id,
          limit: 10,
        );
      } on RequestException catch (e) {
        if (mounted) {
          setState(() => _error = scheduleErrorMessage(e.code, e.message));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _task = task;
      _history = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final history = _history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv('状态', _task.enabled ? '已启用' : '已停用'),
        _kv('规则', _task.ruleLabel),
        _kv('下次运行', _task.enabled ? _fmtWhen(_task.nextRunAt) : '—'),
        _kv('最近运行', _fmtWhen(_task.lastRunAt)),
        _kv('创建时间', _fmtWhen(_task.createdAt)),
        if (_task.updatedAt != null) _kv('更新时间', _fmtIso(_task.updatedAt)),
        if (_task.prompt.isNotEmpty) ...[
          const SizedBox(height: DsSpacing.blockGap),
          Text(
            '任务内容',
            style: DsTypography.smallStrong.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: DsSpacing.liGap),
          Container(
            padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
            decoration: BoxDecoration(
              color: c.settingsSurface,
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              border: Border.all(color: c.borderL1),
            ),
            child: Text(
              _task.prompt,
              style: DsTypography.base.copyWith(color: c.labelPrimary),
            ),
          ),
        ],
        const SizedBox(height: DsSpacing.blockGap),
        Row(
          children: [
            Text(
              '运行历史',
              style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
            ),
            const Spacer(),
            if (_loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.brand,
                ),
              ),
          ],
        ),
        const SizedBox(height: DsSpacing.liGap),
        if (_error != null)
          Text(
            _error!,
            style: DsTypography.small.copyWith(color: c.settingsWarnFg),
          )
        else if (_loading)
          Text(
            '正在读取运行历史…',
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          )
        else if (history == null || history.records.isEmpty)
          Text(
            '暂无运行历史',
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          )
        else
          for (final record in history.records)
            _HistoryRow(record: record, colors: c),
      ],
    );
  }

  Widget _kv(String label, String value) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: DsTypography.small.copyWith(color: c.labelTertiary),
            ),
            TextSpan(
              text: value,
              style: DsTypography.small.copyWith(color: c.labelPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.colors});

  final ScheduleDelivery record;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: c.chatStatusOk),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtWhen(record.deliveredAt),
                  style: DsTypography.small.copyWith(color: c.labelPrimary),
                ),
                if (record.targetSessionId != null)
                  Text(
                    '投递到 ${record.targetSessionId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本地时间格式（不引 intl）：今天/明天/昨天 HH:mm，其他 MM-dd HH:mm。
String _fmtWhen(int? epochMs) {
  if (epochMs == null) return '—';
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final hm = '${_two(t.hour)}:${_two(t.minute)}';
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '明天 $hm';
  if (diff == -1) return '昨天 $hm';
  return '${_two(t.month)}-${_two(t.day)} $hm';
}

String _fmtIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _fmtWhen(parsed.millisecondsSinceEpoch);
}

String _two(int value) => value.toString().padLeft(2, '0');
