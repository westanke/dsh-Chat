/// 移动端 WS 帧的协议模型与纯函数：会话任务投影 / 订阅快照基线。
///
/// 帧形状权威（dsh-remote-bridge，2026-11-28 HEAD）：
/// - `tasks` 应答（`src/host/ws-goals.ts` readProjection）：
///   `data{sessionId, asOfSeq?, todos?}`；`todos` 键缺席或为 `null` = 内核还没给
///   todos 投影，**不是**「清单为空」。todos 元素只认 `{content,status}`。
/// - `chat.session.snapshot` 事件（`src/host/chat/access.ts:249`）：
///   `data{sessionId, cursor?, hasMore?, recordCount?}`；`cursor` 是持久事件序号
///   切点，只用于断档判定，不带事件正文。
///
/// 能力位见 `src/host/capabilities.ts`；`<能力>-vN` 只增不撤，帧名不随传输换名。
/// 本文件零 Flutter 依赖（纯 Dart），便于直接单测。
library;

import 'projections.dart';

/// WS `tasks` 帧：读会话 todos 投影（只读）。
const String tasksCapability = 'mobile-tasks-v1';

/// WS `history` 帧的 `compact:true` 参数：超长字符串压成摘要。
const String historyCompactCapability = 'history-compact-v1';

/// `chat.session.snapshot` 推送：订阅基线（持久 seq 切点）。
const String sessionSnapshotCapability = 'session-snapshot-v1';

/// `tasks` 帧应答的客户端模型。
class SessionTasks {
  const SessionTasks({
    required this.sessionId,
    this.asOfSeq,
    this.todos = const <TodoItem>[],
    this.hasTodosProjection = false,
  });

  final String sessionId;

  /// 投影基线的事件序号；应答缺席时为 null。
  final int? asOfSeq;

  /// 与 `todoItems(projections)` 同源的解析结果（坏条目已丢弃）。
  final List<TodoItem> todos;

  /// 应答里 `todos` 是否为**数组**：false = 键缺席/为 null，表示「没有权威清单」，
  /// 此时不能拿空表覆盖客户端已有的投影推导。
  final bool hasTodosProjection;

  factory SessionTasks.fromJson(Map<String, dynamic> json) {
    final raw = json['todos'];
    return SessionTasks(
      sessionId: json['sessionId'] is String ? json['sessionId'] as String : '',
      asOfSeq: json['asOfSeq'] is int ? json['asOfSeq'] as int : null,
      todos: todoItemsFromRaw(raw),
      hasTodosProjection: raw is List,
    );
  }

  /// 显式序列化（宪法 §7：每帧模型可 round-trip）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'sessionId': sessionId,
    if (asOfSeq != null) 'asOfSeq': asOfSeq,
    'todos': hasTodosProjection
        ? <Map<String, dynamic>>[for (final t in todos) t.toJson()]
        : null,
  };
}

/// `chat.session.snapshot` 事件的客户端模型（无事件正文）。
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    this.cursor,
    this.hasMore = false,
    this.recordCount,
  });

  final String sessionId;

  /// 服务端已投递到的持久事件序号切点。
  final int? cursor;

  /// 服务端还有更早记录没推（有积压 → 不能凭 cursor 判定「没进展」）。
  final bool hasMore;

  /// 快照覆盖的记录条数（诊断用，可为 null）。
  final int? recordCount;

  factory SessionSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => SessionSnapshot(
    sessionId: json['sessionId'] is String ? json['sessionId'] as String : '',
    cursor: json['cursor'] is int ? json['cursor'] as int : null,
    hasMore: json['hasMore'] == true,
    recordCount: json['recordCount'] is int ? json['recordCount'] as int : null,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sessionId': sessionId,
    'cursor': cursor,
    'hasMore': hasMore,
    'recordCount': recordCount,
  };
}

/// resync 后能否跳过整页重拉：**已有基线且 cursor 未前进**才算。
///
/// 判定刻意保守：任一侧缺席、会话不同、cursor 前进、或服务端还有积压
/// （hasMore）都返回 false。实际接入也保守（见 chat_state_events.dart 的
/// ResyncEvent 分支：先记判定结果，仍重拉）。
bool shouldSkipSessionResync(
  SessionSnapshot? baseline,
  SessionSnapshot? latest,
) {
  if (baseline == null || latest == null) return false;
  if (baseline.sessionId != latest.sessionId) return false;
  final base = baseline.cursor;
  final next = latest.cursor;
  if (base == null || next == null) return false;
  if (latest.hasMore) return false;
  return next <= base;
}

/// 把权威 todos 合并进 history 投影（页面读 `todoItems(state.projections)`，
/// 所以权威结果必须写回同一形状才能被现有 UI 看到）。
///
/// - `hasTodosProjection == false`（内核没给 todos）→ 原样返回，不覆盖推导结果；
/// - projections 为 null → 生成最小 `{values:{todos:[...]}}`。
Map<String, dynamic>? projectionsWithTodos(
  Map<String, dynamic>? projections,
  SessionTasks tasks,
) {
  if (!tasks.hasTodosProjection) return projections;
  final base = projections ?? const <String, dynamic>{};
  final rawValues = base['values'];
  final values = rawValues is Map
      ? Map<String, dynamic>.from(rawValues)
      : <String, dynamic>{};
  values['todos'] = <Map<String, dynamic>>[
    for (final item in tasks.todos) item.toJson(),
  ];
  return <String, dynamic>{...base, 'values': values};
}
