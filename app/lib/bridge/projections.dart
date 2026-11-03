/// history 应答的「本地投影」解析（纯 Dart，零 Flutter 依赖，便于单测）。
///
/// 对照 dsh-companion：
/// - 轨迹 = 客户端拿 history.events 自己分组（data/Trajectory.kt:98-127）；
/// - 团队 / TODO = 读服务端算好随首屏 history 下发的 projections.values.*
///   （data/AgentTeamProjection.kt:100-151、data/ChatPresentation.kt:77-85）。
///
/// 约束（bridge docs/project/API.md:165,167,766）：projections 可选、内核没给
/// 基线时整个字段缺席（不是空对象）、只在首屏带翻页不带。所有函数都容忍
/// null / 形状不对，返回空结构而不是抛异常；UI 不得把「读不到」当成「功能不存在」。
library;

import 'dart:convert';

/// 未带 data.turn 的事件归到 0，时间轴里永远垫底（companion 显示「轮次之间」）。
const int kUnknownTurn = 0;

enum TrajectoryNodeKind { user, assistant, tool, deliverable, turnEnd, other }

class TrajectoryNode {
  const TrajectoryNode({
    required this.seq,
    required this.time,
    required this.kind,
    required this.label,
    required this.raw,
    required this.type,
  });

  final int seq;
  final int time;
  final TrajectoryNodeKind kind;
  final String label;
  final Map<String, dynamic>? raw;

  /// 原始事件类型（other 类节点用它做标签，不臆造）。
  final String type;
}

class TrajectoryTurn {
  const TrajectoryTurn({required this.turn, required this.nodes});

  final int turn;
  final List<TrajectoryNode> nodes;

  bool get isUnknown => turn == kUnknownTurn;

  int get toolCalls =>
      nodes.where((n) => n.kind == TrajectoryNodeKind.tool).length;

  /// 按 seq 序首尾 time 差；节点不足 / 跨度非正返回 null。
  int? get durationMillis {
    if (nodes.length < 2) return null;
    final d = nodes.last.time - nodes.first.time;
    return d > 0 ? d : null;
  }
}

TrajectoryNodeKind? _trajectoryKindOf(String type) {
  switch (type) {
    case 'user/message':
      return TrajectoryNodeKind.user;
    case 'assistant/message':
      return TrajectoryNodeKind.assistant;
    case 'tool/call':
      return TrajectoryNodeKind.tool;
    case 'deliverables/presented':
      return TrajectoryNodeKind.deliverable;
    case 'turn/end':
      return TrajectoryNodeKind.turnEnd;
  }
  // 内核过程细节不进时间轴（companion Trajectory.kt:172-185 刻意丢弃）。
  if (type == 'tool/result' ||
      type == 'step/start' ||
      type == 'step/end' ||
      type == 'turn/start' ||
      type.startsWith('session-log-') ||
      type.startsWith('agent/inbox/')) {
    return null;
  }
  return TrajectoryNodeKind.other;
}

String _toolLabelOf(String type, Map<String, dynamic> data) {
  if (type != 'tool/call') return '';
  final name = data['name'];
  return name is String ? name : '';
}

/// 把归一化后的原始事件（[{type,seq,time,data}]）按 data.turn 分组成轮次时间轴。
/// 组内按 seq 升序（不按数组顺序、不按 time）；未知轮次垫底。
List<TrajectoryTurn> trajectoryOf(List<Map<String, dynamic>> events) {
  final grouped = <int, List<TrajectoryNode>>{};
  for (final e in events) {
    final type = e['type'] is String ? e['type'] as String : '';
    final kind = _trajectoryKindOf(type);
    if (kind == null) continue;
    final data = e['data'] is Map
        ? Map<String, dynamic>.from(e['data'] as Map)
        : const <String, dynamic>{};
    final turnRaw = data['turn'];
    final turn = turnRaw is int
        ? turnRaw
        : (turnRaw is num ? turnRaw.toInt() : kUnknownTurn);
    final seq = e['seq'] is int ? e['seq'] as int : 0;
    final time = e['time'] is int ? e['time'] as int : 0;
    grouped.putIfAbsent(turn, () => <TrajectoryNode>[]).add(
          TrajectoryNode(
            seq: seq,
            time: time,
            kind: kind,
            label: _toolLabelOf(type, data),
            raw: data.isEmpty ? null : data,
            type: type,
          ),
        );
  }
  final turns = grouped.keys.toList()
    ..sort((a, b) {
      final aUnknown = a == kUnknownTurn;
      final bUnknown = b == kUnknownTurn;
      if (aUnknown != bUnknown) return aUnknown ? 1 : -1;
      return a.compareTo(b);
    });
  return <TrajectoryTurn>[
    for (final t in turns)
      TrajectoryTurn(
        turn: t,
        nodes: grouped[t]!..sort((x, y) => x.seq.compareTo(y.seq)),
      ),
  ];
}

// ---------- 服务端投影：projections.values ----------

Map<String, dynamic> _values(Map<String, dynamic>? projections) {
  final p = projections;
  if (p == null) return const <String, dynamic>{};
  final v = p['values'];
  return v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
}

List<Map<String, dynamic>> _objectArray(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

String _str(Map<String, dynamic> m, String key, [String fallback = '']) {
  final v = m[key];
  return v is String ? v : fallback;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return <String>[for (final s in raw) if (s is String) s];
}

class TodoItem {
  const TodoItem({required this.content, required this.status});

  final String content;
  final String status;

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';
}

/// 只认 {content:String, status:String}；content 空白或 status 缺失丢弃。
/// 桥 fixture 的 {id,text,status} 变体同样会被丢弃（与 companion 一致）。
List<TodoItem> todoItems(Map<String, dynamic>? projections) {
  final raw = _values(projections)['todos'];
  return <TodoItem>[
    for (final item in _objectArray(raw))
      if (item['content'] is String &&
          (item['content'] as String).trim().isNotEmpty &&
          item['status'] is String)
        TodoItem(
          content: item['content'] as String,
          status: item['status'] as String,
        ),
  ];
}

class TeamMemberRow {
  const TeamMemberRow({
    required this.id,
    required this.name,
    required this.role,
    required this.phase,
    required this.error,
  });

  final String id;
  final String name;
  final String role;
  final String phase;
  final String error;

  bool get isLead => role == 'lead';
}

class TeamTaskRow {
  const TeamTaskRow({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.blockedBy,
    required this.writeScopes,
    required this.ownerName,
    required this.ready,
  });

  final String id;
  final String subject;
  final String description;
  final String status;
  final List<String> blockedBy;
  final List<String> writeScopes;
  final String ownerName;
  final bool ready;
}

class SubagentRow {
  const SubagentRow({
    required this.id,
    required this.mode,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String mode;
  final String label;
  final int? createdAt;
}

class AgentTeamProjection {
  const AgentTeamProjection({
    required this.members,
    required this.tasks,
    required this.subagents,
    required this.failure,
  });

  final List<TeamMemberRow> members;
  final List<TeamTaskRow> tasks;
  final List<SubagentRow> subagents;
  final String? failure;

  bool get hasTeam => members.isNotEmpty;
  int get completedTasks =>
      tasks.where((t) => t.status == 'completed').length;
}

/// 读 projections.values.{agentTeam,subagentCatalog}。空壳（三块都空且无
/// failure）返回 null，UI 据此显示空态；缺投影同样返回 null，但不代表功能不存在。
AgentTeamProjection? agentTeamProjectionOf(Map<String, dynamic>? projections) {
  final values = _values(projections);
  final team = values['agentTeam'] is Map
      ? Map<String, dynamic>.from(values['agentTeam'] as Map)
      : const <String, dynamic>{};
  final failure = team['failure'];
  final failureText = failure is String && failure.isNotEmpty ? failure : null;

  final members = <TeamMemberRow>[
    for (final m in _objectArray(team['members']))
      TeamMemberRow(
        id: _str(m, 'id'),
        name: _str(m, 'name', _str(m, 'id')),
        role: _str(m, 'role', 'teammate'),
        phase: _str(m, 'phase', 'active'),
        error: _str(m, 'error'),
      ),
  ];
  final tasks = <TeamTaskRow>[
    for (final t in _objectArray(team['tasks']))
      TeamTaskRow(
        id: _str(t, 'id'),
        subject: _str(t, 'subject'),
        description: _str(t, 'description'),
        status: _str(t, 'status', 'pending'),
        blockedBy: _stringList(t['blockedBy']),
        writeScopes: _stringList(t['writeScopes']),
        ownerName: _str(t, 'ownerName'),
        ready: t['ready'] is bool ? t['ready'] as bool : true,
      ),
  ];
  final subagents = <SubagentRow>[
    for (final s in _objectArray(values['subagentCatalog']))
      SubagentRow(
        // 兼容官方 id 与老夹具 sessionId，优先 id。
        id: _str(s, 'id', _str(s, 'sessionId')),
        mode: _str(s, 'mode'),
        label: _str(s, 'label'),
        createdAt: s['createdAt'] is int ? s['createdAt'] as int : null,
      ),
  ];
  if (members.isEmpty &&
      tasks.isEmpty &&
      subagents.isEmpty &&
      failureText == null) {
    return null;
  }
  return AgentTeamProjection(
    members: members,
    tasks: tasks,
    subagents: subagents,
    failure: failureText,
  );
}

/// 把任意 data map 格式化成可读 JSON，供轨迹 Sheet 展开「原始事件」。
String prettyJson(Map<String, dynamic>? data) {
  if (data == null) return '（这条事件没有载荷）';
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } on Object {
    return data.toString();
  }
}
