/// 定时任务的「规则」模型与 wire 构造。
///
/// 只做纯数据：不 import Flutter，便于在 `test/` 里直接 round-trip。
/// 协议事实来源：内核 `@deepseek-ai/dsh-schedule` 的 `schedule/create`
/// 参数 schema（`timing` 七选一），桥 `schedule-create` / `schedule-edit`
/// 直通帧把 `{request: ...}` 原样交给内核。
///
/// 本文件只覆盖手机端表单会产出的五种：
/// - `daily` 每天 HH:mm；
/// - `weekly` 每周几 HH:mm；
/// - `every` 每 N 分钟；
/// - `cron` 五段 cron；
/// - `at` 指定日期时间（一次性）。
///
/// `after`（N 秒后）与 `rrule` 保留给高级场景，表单不做，但读旧任务时不会崩
/// （`fromTask` 落到默认「每天 09:00」）。
library;

import 'gateway_schedule.dart';

/// 表单可选的重复方式。
enum ScheduleRepeat { daily, weekly, every, cron, at }

/// 一条任务的定时规则（与内核 timing 的一对一投影）。
class ScheduleTiming {
  const ScheduleTiming({
    required this.repeat,
    this.hour = 9,
    this.minute = 0,
    this.weekdays = const <int>[],
    this.everyMinutes = 60,
    this.cron = '',
    this.date,
  });

  final ScheduleRepeat repeat;
  final int hour;
  final int minute;

  /// ISO 周几：周一 1 … 周日 7；按升序、去重后发给内核。
  final List<int> weekdays;
  final int everyMinutes;
  final String cron;

  /// `at` 的日期部分；`null` 表示今天。
  final DateTime? date;

  /// 从已有任务反推表单初值；无法识别的类型退回「每天 09:00」。
  factory ScheduleTiming.fromTask(ScheduleTask task) {
    final parsed = _parseTime(task.time);
    switch (task.kind) {
      case 'weekly':
        return ScheduleTiming(
          repeat: ScheduleRepeat.weekly,
          hour: parsed?.$1 ?? 9,
          minute: parsed?.$2 ?? 0,
          weekdays: _parseWeekdays(task.weekdays),
        );
      case 'every':
        final seconds = task.everySeconds ?? 3600;
        final minutes = seconds < 60 ? 1 : seconds ~/ 60;
        return ScheduleTiming(
          repeat: ScheduleRepeat.every,
          everyMinutes: minutes,
        );
      case 'cron':
        return ScheduleTiming(
          repeat: ScheduleRepeat.cron,
          cron: task.cron ?? task.expression ?? '',
        );
      case 'at':
        final at = task.nextRunAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(task.nextRunAt!);
        return ScheduleTiming(
          repeat: ScheduleRepeat.at,
          hour: at?.hour ?? parsed?.$1 ?? 9,
          minute: at?.minute ?? parsed?.$2 ?? 0,
          date: at,
        );
      case 'daily':
        return ScheduleTiming(
          repeat: ScheduleRepeat.daily,
          hour: parsed?.$1 ?? 9,
          minute: parsed?.$2 ?? 0,
        );
      default:
        return const ScheduleTiming(repeat: ScheduleRepeat.daily);
    }
  }

  /// 表单校验；`null` 表示通过。
  String? validate() {
    switch (repeat) {
      case ScheduleRepeat.daily:
      case ScheduleRepeat.at:
        return null;
      case ScheduleRepeat.weekly:
        if (weekdays.isEmpty) return '至少选一个星期几';
        return null;
      case ScheduleRepeat.every:
        if (everyMinutes < 1) return '间隔至少 1 分钟';
        return null;
      case ScheduleRepeat.cron:
        final parts = cron.trim().split(RegExp(r'\s+'));
        if (parts.length != 5) return 'cron 需要 5 段：分 时 日 月 周';
        return null;
    }
  }

  /// 人话预览（表单底部、编辑时初值）。
  String describe() {
    final hhmm = '${_two(hour)}:${_two(minute)}';
    switch (repeat) {
      case ScheduleRepeat.daily:
        return '每天 $hhmm';
      case ScheduleRepeat.weekly:
        if (weekdays.isEmpty) return '每周（未选星期）';
        return '每周${_weekdaysText(weekdays)} $hhmm';
      case ScheduleRepeat.every:
        return everyMinutes % 60 == 0
            ? '每 ${everyMinutes ~/ 60} 小时'
            : '每 $everyMinutes 分钟';
      case ScheduleRepeat.cron:
        return cron.trim().isEmpty ? 'cron（未填写）' : 'cron ${cron.trim()}';
      case ScheduleRepeat.at:
        final d = date ?? DateTime.now();
        return '${d.year}-${_two(d.month)}-${_two(d.day)} $hhmm';
    }
  }

  /// 构造内核 `timing`（`schedule/create` 的 `request.timing`）。
  ///
  /// [timeZone] 必须是 UTC 或 IANA 名；调用方传 `DshDevice.ianaZone`。
  Map<String, Object?> toWire(String timeZone) {
    final zone = timeZone.trim().isEmpty ? 'UTC' : timeZone.trim();
    final hhmmss = '${_two(hour)}:${_two(minute)}:00';
    switch (repeat) {
      case ScheduleRepeat.daily:
        return {
          'kind': 'daily',
          'daily': {'time': hhmmss, 'time_zone': zone},
        };
      case ScheduleRepeat.weekly:
        return {
          'kind': 'weekly',
          'weekly': {
            'time': hhmmss,
            'time_zone': zone,
            'weekdays': _sortedWeekdays(weekdays),
          },
        };
      case ScheduleRepeat.every:
        return {'kind': 'every', 'every_seconds': everyMinutes * 60};
      case ScheduleRepeat.cron:
        return {
          'kind': 'cron',
          'cron': {'expression': cron.trim(), 'time_zone': zone},
        };
      case ScheduleRepeat.at:
        final d = date ?? DateTime.now();
        return {
          'kind': 'at',
          'at': {
            'date': '${d.year}-${_two(d.month)}-${_two(d.day)}',
            'time': hhmmss,
            'time_zone': zone,
          },
        };
    }
  }
}

/// `schedule-create` 的 `request`（桥把它塞进 `{request}` 再给内核）。
Map<String, Object?> buildScheduleCreateRequest({
  required String title,
  required String prompt,
  required String sessionId,
  required ScheduleTiming timing,
  required String timeZone,
}) {
  return {
    'title': title.trim(),
    'prompt': prompt.trim(),
    'timing': timing.toWire(timeZone),
    'target': {'kind': 'session', 'sessionId': sessionId},
  };
}

/// `schedule-edit` 的 `request`：只改标题/指令/规则，不动 target 与启停。
///
/// `expectedUpdatedAt` 用于 compare-and-set；缺省时不带，桥按不带并发控制处理。
Map<String, Object?> buildScheduleEditRequest({
  required ScheduleTask task,
  required String title,
  required String prompt,
  required ScheduleTiming timing,
  required String timeZone,
}) {
  final patch = <String, Object?>{
    'title': title.trim(),
    'prompt': prompt.trim(),
    'timing': timing.toWire(timeZone),
  };
  return {
    'id': task.id,
    'action': 'update',
    'patch': patch,
    if (task.updatedAt != null) 'expectedUpdatedAt': task.updatedAt,
  };
}

(int, int)? _parseTime(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return (h, m);
}

List<int> _parseWeekdays(List<String> raw) {
  final out = <int>{};
  for (final item in raw) {
    final n = int.tryParse(item);
    // 桥侧老形状可能用 0 表示周日；统一折算成 ISO 1..7。
    if (n == 0) {
      out.add(7);
    } else if (n != null && n >= 1 && n <= 7) {
      out.add(n);
    }
  }
  final list = out.toList()..sort();
  return list;
}

List<int> _sortedWeekdays(List<int> raw) {
  final set = raw.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
  return set;
}

String _weekdaysText(List<int> days) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  final sorted = _sortedWeekdays(days);
  return sorted.map((d) => names[d - 1]).join('、');
}

String _two(int value) => value.toString().padLeft(2, '0');
