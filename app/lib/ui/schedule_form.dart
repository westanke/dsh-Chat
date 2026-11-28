/// 定时任务新建 / 编辑表单（底部 sheet）。
///
/// 只负责收集「标题 / 指令 / 重复规则」，wire 形状交给
/// `bridge/schedule_timing.dart` 的 `buildScheduleCreateRequest` /
/// `buildScheduleEditRequest`，UI 里不拼协议字段。
///
/// 编辑入口从 `schedule_sheet.dart` 的详情页进来，复用同一个表单。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/device.dart';
import '../bridge/gateway.dart';
import '../bridge/gateway_schedule.dart';
import '../bridge/schedule_timing.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'window_class.dart';

/// 打开表单；新建成功/编辑保存后返回 `true`（调用方据此刷新列表）。
Future<bool?> showScheduleForm(
  BuildContext context,
  ChatState state,
  DsColors colors, {
  ScheduleTask? task,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (_) => ScheduleForm(state: state, colors: colors, task: task),
  );
}

/// 表单本体（公开给测试 pump）。
class ScheduleForm extends StatefulWidget {
  const ScheduleForm({
    super.key,
    required this.state,
    required this.colors,
    this.task,
  });

  final ChatState state;
  final DsColors colors;

  /// 为空时是新建；非空时是编辑。
  final ScheduleTask? task;

  @override
  State<ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<ScheduleForm> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _interval;
  late final TextEditingController _cron;
  late ScheduleTiming _timing;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  DsColors get _c => widget.colors;
  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _prompt = TextEditingController(text: task?.prompt ?? '');
    _timing = task == null
        ? const ScheduleTiming(repeat: ScheduleRepeat.daily)
        : ScheduleTiming.fromTask(task);
    _interval = TextEditingController(text: '${_timing.everyMinutes}');
    _cron = TextEditingController(text: _timing.cron);
    _date = _timing.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _interval.dispose();
    _cron.dispose();
    super.dispose();
  }

  void _setRepeat(ScheduleRepeat repeat) {
    setState(() {
      _timing = ScheduleTiming(
        repeat: repeat,
        hour: _timing.hour,
        minute: _timing.minute,
        weekdays: _timing.weekdays,
        everyMinutes: _timing.everyMinutes,
        cron: _cron.text,
        date: _timing.repeat == ScheduleRepeat.at ? _date : null,
      );
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _timing.hour, minute: _timing.minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _timing = ScheduleTiming(
        repeat: _timing.repeat,
        hour: picked.hour,
        minute: picked.minute,
        weekdays: _timing.weekdays,
        everyMinutes: _timing.everyMinutes,
        cron: _timing.cron,
        date: _timing.date,
      );
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _timing = ScheduleTiming(
        repeat: _timing.repeat,
        hour: _timing.hour,
        minute: _timing.minute,
        weekdays: _timing.weekdays,
        everyMinutes: _timing.everyMinutes,
        cron: _timing.cron,
        date: picked,
      );
    });
  }

  void _toggleWeekday(int day) {
    final next = [..._timing.weekdays];
    if (next.contains(day)) {
      next.remove(day);
    } else {
      next.add(day);
    }
    next.sort();
    setState(() {
      _timing = ScheduleTiming(
        repeat: _timing.repeat,
        hour: _timing.hour,
        minute: _timing.minute,
        weekdays: next,
        everyMinutes: _timing.everyMinutes,
        cron: _timing.cron,
        date: _timing.date,
      );
      _error = null;
    });
  }

  void _syncInterval() {
    final minutes = int.tryParse(_interval.text.trim());
    setState(() {
      _timing = ScheduleTiming(
        repeat: _timing.repeat,
        hour: _timing.hour,
        minute: _timing.minute,
        weekdays: _timing.weekdays,
        everyMinutes: minutes ?? 0,
        cron: _timing.cron,
        date: _timing.date,
      );
      _error = null;
    });
  }

  void _syncCron() {
    setState(() {
      _timing = ScheduleTiming(
        repeat: _timing.repeat,
        hour: _timing.hour,
        minute: _timing.minute,
        weekdays: _timing.weekdays,
        everyMinutes: _timing.everyMinutes,
        cron: _cron.text,
        date: _timing.date,
      );
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final title = _title.text.trim();
    final prompt = _prompt.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    if (prompt.isEmpty) {
      setState(() => _error = '指令不能为空');
      return;
    }
    final timingError = _timing.validate();
    if (timingError != null) {
      setState(() => _error = timingError);
      return;
    }
    final sid = widget.state.sessionId;
    if (sid == null || sid.isEmpty) {
      setState(() => _error = '当前还没有会话，无法创建定时任务');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final zone = DshDevice.ianaZone;
    try {
      final task = widget.task;
      if (task == null) {
        await widget.state.gateway.scheduleCreate(
          buildScheduleCreateRequest(
            title: title,
            prompt: prompt,
            sessionId: sid,
            timing: _timing,
            timeZone: zone,
          ),
        );
      } else {
        await widget.state.gateway.scheduleEdit(
          buildScheduleEditRequest(
            task: task,
            title: title,
            prompt: prompt,
            timing: _timing,
            timeZone: zone,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = scheduleErrorMessage(e.code, e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.screenPad,
            DsSpacing.liGap,
            DsSpacing.screenPad,
            DsSpacing.blockGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? '编辑定时任务' : '新建定时任务',
                      style: DsTypography.h4.copyWith(color: c.labelPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    color: c.labelSecondary,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: DsSpacing.liGap),
              TextField(
                key: const ValueKey('schedule-form-title'),
                controller: _title,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '例如：每天站会提醒',
                ),
              ),
              const SizedBox(height: DsSpacing.liGap),
              TextField(
                key: const ValueKey('schedule-form-prompt'),
                controller: _prompt,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '指令',
                  hintText: '到点后发给这个会话的内容',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: DsSpacing.blockGap),
              Text(
                '重复',
                style: DsTypography.smallStrong.copyWith(
                  color: c.labelSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _repeatChip(ScheduleRepeat.daily, '每天'),
                  _repeatChip(ScheduleRepeat.weekly, '每周'),
                  _repeatChip(ScheduleRepeat.every, '间隔'),
                  _repeatChip(ScheduleRepeat.cron, 'Cron'),
                  _repeatChip(ScheduleRepeat.at, '一次'),
                ],
              ),
              const SizedBox(height: DsSpacing.blockGap),
              ..._timingFields(),
              const SizedBox(height: DsSpacing.liGap),
              _preview(),
              if (_error != null) ...[
                const SizedBox(height: DsSpacing.liGap),
                Text(
                  _error!,
                  key: const ValueKey('schedule-form-error'),
                  style: DsTypography.small.copyWith(color: c.danger),
                ),
              ],
              const SizedBox(height: DsSpacing.blockGap),
              FilledButton(
                key: const ValueKey('schedule-form-submit'),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_editing ? '保存' : '创建'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _repeatChip(ScheduleRepeat repeat, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _timing.repeat == repeat,
      onSelected: (_) => _setRepeat(repeat),
    );
  }

  List<Widget> _timingFields() {
    final c = _c;
    switch (_timing.repeat) {
      case ScheduleRepeat.daily:
        return [_timeRow('执行时间')];
      case ScheduleRepeat.weekly:
        return [
          _timeRow('执行时间'),
          const SizedBox(height: DsSpacing.liGap),
          Text(
            '星期几',
            style: DsTypography.smallStrong.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(const ['一', '二', '三', '四', '五', '六', '日'][day - 1]),
                  selected: _timing.weekdays.contains(day),
                  onSelected: (_) => _toggleWeekday(day),
                ),
            ],
          ),
        ];
      case ScheduleRepeat.every:
        return [
          TextField(
            key: const ValueKey('schedule-form-interval'),
            controller: _interval,
            keyboardType: TextInputType.number,
            onChanged: (_) => _syncInterval(),
            decoration: const InputDecoration(
              labelText: '间隔（分钟）',
              hintText: '至少 1 分钟',
            ),
          ),
        ];
      case ScheduleRepeat.cron:
        return [
          TextField(
            key: const ValueKey('schedule-form-cron'),
            controller: _cron,
            onChanged: (_) => _syncCron(),
            decoration: const InputDecoration(
              labelText: 'cron 表达式',
              hintText: '0 9 * * *',
              helperText: '五段：分 时 日 月 周',
            ),
          ),
        ];
      case ScheduleRepeat.at:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    '${_date.year}-${_two(_date.month)}-${_two(_date.day)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text(
                    '${_two(_timing.hour)}:${_two(_timing.minute)}',
                  ),
                ),
              ),
            ],
          ),
        ];
    }
  }

  Widget _timeRow(String label) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: DsTypography.smallStrong.copyWith(color: _c.labelSecondary),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('schedule-form-time'),
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule_outlined, size: 18),
          label: Text('${_two(_timing.hour)}:${_two(_timing.minute)}'),
        ),
      ],
    );
  }

  Widget _preview() {
    final c = _c;
    return Container(
      padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
      decoration: BoxDecoration(
        color: c.settingsSurface,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        border: Border.all(color: c.borderL1),
      ),
      child: Row(
        children: [
          Icon(Icons.event_repeat, size: 16, color: c.labelTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_timing.describe()} · ${DshDevice.ianaZone}',
              style: DsTypography.small.copyWith(color: c.labelSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
