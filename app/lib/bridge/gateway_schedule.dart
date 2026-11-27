/// 定时任务（schedule-*）帧封装。
///
/// 协议事实来源：dsh-remote-bridge `src/host/ws-schedule.ts`、
/// `docs/api/asyncapi.yaml` 与 `docs/project/API.md`「定时任务」段。
///
/// 这里刻意兼容两种线格式：
/// - `schedule-catalog` / `schedule-list` 的 app 记录：有 `sessionId`、`status`，
///   其余字段是内核 ScheduleCatalogEntry 原样透传（`scheduledAt`/`expression`/
///   `timeZone`/`lastDelivery`，没有 `cron`/`nextRunAt`/`enabled`）；
/// - 直通帧 `schedule-view` / `schedule-run` 返回的内核 entry：没有 `sessionId`，
///   会话要从 `target.sessionId` 取。
///
/// 能力位：[scheduleCapability]（bridge `src/host/capabilities.ts`）。
library;

import 'gateway.dart';

/// 桥侧「定时任务」能力位。缺席时顶栏整块入口不渲染。
const String scheduleCapability = 'chat-schedules-v1';

/// 一条定时任务。
///
/// 字段可空性与内核 `ScheduleCatalogEntry` 对齐：不同 `kind` 只带各自的
/// 定时字段（cron/expression、time/timeZone、weekdays、everySeconds、rrule）。
class ScheduleTask {
  factory ScheduleTask.fromJson(Map<String, dynamic> json) {
    final delivery = _mapOf(json['lastDelivery']);
    final status = _str(json['status']);
    final rawPrompt = _strOrNull(json['prompt']) ?? _strOrNull(json['text']);
    return ScheduleTask._(
      raw: Map<String, dynamic>.from(json),
      id: _str(json['id']),
      sessionId: _sessionIdOf(json),
      title: _strOrNull(json['title']) ?? _firstLine(rawPrompt) ?? '定时任务',
      prompt: rawPrompt ?? '',
      kind: _str(json['kind']),
      cron: _strOrNull(json['cron']),
      expression: _strOrNull(json['expression']),
      timezone: _strOrNull(json['timeZone']) ?? _strOrNull(json['timezone']),
      enabled: _enabledOf(json, status),
      status: status,
      nextRunAt: _epochOf(json['nextRunAt']) ?? _epochOf(json['scheduledAt']),
      lastRunAt:
          _epochOf(json['lastRunAt']) ?? _epochOf(delivery?['deliveredAt']),
      createdAt: _epochOf(json['createdAt']),
      updatedAt: _strOrNull(json['updatedAt']),
      everySeconds: _intOf(json['everySeconds']),
      afterSeconds: _intOf(json['afterSeconds']),
      rrule: _strOrNull(json['rrule']),
      time: _strOrNull(json['time']),
      weekdays: _weekdaysOf(json['weekdays']),
      lastDelivery: delivery,
    );
  }

  ScheduleTask._({
    required this.raw,
    required this.id,
    required this.sessionId,
    required this.title,
    required this.prompt,
    required this.kind,
    required this.cron,
    required this.expression,
    required this.timezone,
    required this.enabled,
    required this.status,
    required this.nextRunAt,
    required this.lastRunAt,
    required this.createdAt,
    required this.updatedAt,
    required this.everySeconds,
    required this.afterSeconds,
    required this.rrule,
    required this.time,
    required this.weekdays,
    required this.lastDelivery,
  });

  /// 原始 JSON，`toJson()` 原样回写（round-trip 测试用）。
  final Map<String, dynamic> raw;
  final String id;
  final String sessionId;
  final String title;
  final String prompt;
  final String kind;
  final String? cron;
  final String? expression;
  final String? timezone;
  final bool enabled;

  /// 桥侧 `active` / `inactive`；直通帧里可能是内核的 `active`/`paused`/`ended`。
  final String status;
  final int? nextRunAt;
  final int? lastRunAt;
  final int? createdAt;
  final String? updatedAt;
  final int? everySeconds;
  final int? afterSeconds;
  final String? rrule;
  final String? time;
  final List<String> weekdays;
  final Map<String, dynamic>? lastDelivery;

  /// 人话规则：cron 表达式 / 每天 09:00 / 每周一 09:00 / 每 30 分钟 …。
  String get ruleLabel {
    final tz = timezone;
    final suffix = tz == null || tz.isEmpty || tz == 'UTC' ? '' : ' ($tz)';
    switch (kind) {
      case 'cron':
        final e = cron ?? expression;
        return e == null || e.isEmpty ? 'cron$suffix' : 'cron $e$suffix';
      case 'daily':
        return '每天 ${time ?? '--:--'}$suffix';
      case 'weekly':
        final days = _weekdayText(weekdays);
        return '每周${days.isEmpty ? '' : ' $days'} ${time ?? '--:--'}$suffix';
      case 'every':
        final s = everySeconds;
        if (s == null || s <= 0) return '周期任务';
        if (s % 3600 == 0) return '每 ${s ~/ 3600} 小时';
        if (s % 60 == 0) return '每 ${s ~/ 60} 分钟';
        return '每 $s 秒';
      case 'rrule':
        final r = rrule;
        if (r == null || r.isEmpty) return '重复任务';
        return r.startsWith('RRULE:') ? r.substring(6) : r;
      case 'at':
        return '定时执行';
      case 'after':
        return '延迟执行';
      default:
        final e = cron ?? expression;
        return e == null || e.isEmpty
            ? (kind.isEmpty ? '定时任务' : kind)
            : 'cron $e$suffix';
    }
  }

  /// 最近一次投递的人话结果（列表行用）。
  String get lastResultLabel {
    final delivery = lastDelivery;
    if (delivery != null) {
      final at = _epochOf(delivery['deliveredAt']);
      return at == null ? '最近已投递' : '最近投递成功';
    }
    if (lastRunAt != null) return '最近已运行';
    if (status == 'ended' || (status.isEmpty && !enabled)) return '已结束';
    return '暂无运行记录';
  }

  /// 与请求帧同名的宽松序列化：默认原样回写，避免桥侧新增字段被吃掉。
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);
}

/// 一次定时投递记录（`schedule-history` 的 `records[]`，最新在前）。
class ScheduleDelivery {
  factory ScheduleDelivery.fromJson(Map<String, dynamic> json) =>
      ScheduleDelivery._(
        raw: Map<String, dynamic>.from(json),
        scheduledAt: _epochOf(json['scheduledAt']),
        deliveredAt: _epochOf(json['deliveredAt']),
        messageId: _strOrNull(json['messageId']),
        targetSessionId: _strOrNull(json['targetSessionId']),
        prompt: _strOrNull(json['prompt']),
      );

  ScheduleDelivery._({
    required this.raw,
    required this.scheduledAt,
    required this.deliveredAt,
    required this.messageId,
    required this.targetSessionId,
    required this.prompt,
  });

  final Map<String, dynamic> raw;
  final int? scheduledAt;
  final int? deliveredAt;
  final String? messageId;
  final String? targetSessionId;
  final String? prompt;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);
}

/// `schedule-history` 应答：内核分页结果 + 桥补的 sessionId。
class ScheduleHistoryPage {
  factory ScheduleHistoryPage.fromJson(Map<String, dynamic> json) {
    final records = <ScheduleDelivery>[];
    final list = json['records'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          records.add(ScheduleDelivery.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ScheduleHistoryPage._(
      raw: Map<String, dynamic>.from(json),
      id: _str(json['id']),
      records: records,
      earlierRecordsUnavailable: json['earlierRecordsUnavailable'] == true,
      nextBefore: _strOrNull(json['nextBefore']),
    );
  }

  ScheduleHistoryPage._({
    required this.raw,
    required this.id,
    required this.records,
    required this.earlierRecordsUnavailable,
    required this.nextBefore,
  });

  final Map<String, dynamic> raw;
  final String id;
  final List<ScheduleDelivery> records;
  final bool earlierRecordsUnavailable;
  final String? nextBefore;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);
}

extension GatewaySchedule on GatewayClient {
  /// 当前会话的定时任务（`schedule-list` 帧，ws-schedule.ts）。
  Future<List<ScheduleTask>> scheduleList(String sessionId) async {
    final r = await request('schedule-list', {'sessionId': sessionId});
    final items = r['items'];
    if (items is! List) return const [];
    final out = <ScheduleTask>[];
    for (final e in items) {
      if (e is Map) {
        out.add(ScheduleTask.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  /// 单条任务（`schedule-view` 直通帧；应答 `{ok:true,value}`）。
  Future<ScheduleTask> scheduleView(String id) async {
    final value = _unwrap(
      await request('schedule-view', {
        'request': {'id': id},
      }),
    );
    return ScheduleTask.fromJson(value);
  }

  /// 立即运行（`schedule-run` 直通帧）。内核可能回 `schedule_execution_pending`。
  Future<ScheduleTask> scheduleRun(String id) async {
    final value = _unwrap(
      await request('schedule-run', {
        'request': {'id': id},
      }),
    );
    return ScheduleTask.fromJson(value);
  }

  /// 启用/暂停。走 `schedule-edit` 直通帧（内核 patch.active），
  /// 带 `expectedUpdatedAt` 做 compare-and-set，避免多端互相覆盖。
  Future<ScheduleTask> setScheduleEnabled(
    ScheduleTask task,
    bool enabled,
  ) async {
    final value = _unwrap(
      await request('schedule-edit', {
        'request': {
          'id': task.id,
          'action': 'update',
          'patch': {'active': enabled},
          'expectedUpdatedAt': ?task.updatedAt,
        },
      }),
    );
    return ScheduleTask.fromJson(value);
  }

  /// 删除（旧五帧 `schedule-delete`；桥会无条件转内核 delete）。
  Future<void> deleteSchedule(String sessionId, String id) async {
    final r = await request('schedule-delete', {
      'sessionId': sessionId,
      'id': id,
    });
    if (r['deleted'] != true) {
      final code = _str(r['code']);
      throw RequestException(
        code.isEmpty ? 'SCHEDULE_DELETE_FAILED' : code,
        '删除定时任务失败',
      );
    }
  }

  /// 运行历史（`schedule-history` 帧，最新在前）。
  Future<ScheduleHistoryPage> scheduleHistory(
    String sessionId,
    String id, {
    int limit = 20,
  }) async {
    final r = await request('schedule-history', {
      'sessionId': sessionId,
      'id': id,
      'limit': limit,
    });
    return ScheduleHistoryPage.fromJson(r);
  }
}

/// 直通帧把业务失败包成 `{ok:false,error}`，转成统一的 [RequestException]。
Map<String, dynamic> _unwrap(Map<String, dynamic> data) {
  final ok = data['ok'];
  if (ok == true) {
    final value = data['value'];
    if (value is Map) {
      final record = Map<String, dynamic>.from(value);
      // 内核业务失败（not_found / conflict / execution_pending）是「成功应答里的
      // code 字段」，桥按 ok:true 原样透传；这里统一转成 RequestException。
      final code = _str(record['code']);
      if (code.isNotEmpty) {
        throw RequestException(code, scheduleErrorMessage(code));
      }
      return record;
    }
    throw RequestException('BAD_REPLY', 'schedule 帧缺少 value');
  }
  if (ok == false) {
    final error = data['error'];
    if (error is Map) {
      final code = _str(error['code']);
      final message = _str(error['message']);
      throw RequestException(
        code.isEmpty ? 'SCHEDULE_FAILED' : code,
        message.isEmpty ? '定时任务操作失败' : message,
      );
    }
    throw RequestException('SCHEDULE_FAILED', '定时任务操作失败');
  }
  // 防御：老桥若直接回记录，也按成功处理。
  return data;
}

/// 把桥/内核错误码翻成一句人话；未知码保留服务端 message。
String scheduleErrorMessage(String code, [String? message]) {
  final text = switch (code) {
    'schedule/unavailable' => '当前桥的内核没有定时任务能力',
    'schedule_not_found' || 'SCHEDULE_NOT_FOUND' => '任务不存在或已被删除',
    'schedule_conflict' || 'SCHEDULE_CONFLICT' => '任务已被其他端修改，请刷新后重试',
    'schedule_execution_pending' => '上一次运行还没结束',
    'schedule/input-invalid' => '任务参数不合法',
    'schedule/target-archived' => '目标任务已归档',
    'ENABLED_UNSUPPORTED' => '当前内核不支持暂停/恢复',
    'SCHEDULE_ENDED' => '任务已结束，不能恢复',
    'SCHEDULE_TARGET_ARCHIVED' => '目标任务已归档',
    _ => null,
  };
  if (text != null) return text;
  if (message != null && message.isNotEmpty) return message;
  return '定时任务操作失败';
}

String _str(Object? value) => value is String ? value : '';

String? _strOrNull(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 内核时间可能是 epoch ms（REST）或 ISO 字符串（WS 透传）。
int? _epochOf(Object? value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.millisecondsSinceEpoch;
  }
  return null;
}

Map<String, dynamic>? _mapOf(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<String> _weekdaysOf(Object? value) {
  if (value is! List) return const [];
  return [for (final e in value) e.toString()];
}

bool _enabledOf(Map<String, dynamic> json, String status) {
  final enabled = json['enabled'];
  if (enabled is bool) return enabled;
  return status == 'active';
}

String _sessionIdOf(Map<String, dynamic> json) {
  final sid = json['sessionId'];
  if (sid is String && sid.isNotEmpty) return sid;
  final target = json['target'];
  if (target is Map) {
    final targetSid = target['sessionId'];
    if (targetSid is String) return targetSid;
  }
  return '';
}

String? _firstLine(String? text) {
  if (text == null || text.isEmpty) return null;
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return null;
  return line.length <= 40 ? line : '${line.substring(0, 40)}…';
}

String _weekdayText(List<String> weekdays) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final out = <String>[];
  for (final raw in weekdays) {
    final n = int.tryParse(raw);
    if (n != null && n >= 1 && n <= 7) {
      out.add(names[n - 1]);
    } else if (n == 0) {
      out.add('周日');
    } else {
      out.add(raw);
    }
  }
  return out.join('、');
}
