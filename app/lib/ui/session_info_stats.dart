/// 会话信息面板的本地统计（纯函数、零网络请求，便于单测）。
///
/// 单独成文件的理由：宪法 §7 单文件 ≤500 行，且数据口径与渲染分离——
/// 面板只管布局，这里负责「每个数字从哪来」。
library;

import 'dart:convert';

import '../bridge/history_page.dart';
import '../bridge/tool_call.dart';
import 'tool_titles.dart';
import 'work_steps.dart';

/// 面板里用到的本地统计（纯函数产物，便于单测）。
class SessionInfoStats {
  const SessionInfoStats({
    required this.turns,
    required this.steps,
    required this.running,
    required this.changedFiles,
    this.elapsedMs,
  });

  /// 轮数（user 消息条数）。
  final int turns;

  /// 工具调用条数。
  final int steps;

  /// 是否有轮仍在运行（轮尾行显示「进行中」）。
  final bool running;

  /// 出现过的不同改动文件数（edit/write，去掉 failed）；
  /// null = 有 edit/write 调用拿不到路径 → 面板宁可不显示这一列，也不写 0。
  final int? changedFiles;

  /// 已完成轮的用时合计；null = 没有任何一轮拿得到真实起止。
  final int? elapsedMs;
}

/// 由已加载消息计算面板统计（零网络请求）。
SessionInfoStats sessionInfoStatsOf(
  List<ChatMessage> messages, {
  required bool streaming,
}) {
  final turns = turnsOf(messages);
  var steps = 0;
  var running = false;
  final files = <String>{};
  var filesKnown = true;
  for (final turn in turns) {
    if (turnIsRunning(messages, turn, streaming)) running = true;
  }
  for (final m in messages) {
    steps += m.toolCalls.length;
    for (final call in m.toolCalls) {
      if (!_isEditLike(call)) continue;
      final path = _pathOfEdit(call);
      if (path == null) {
        filesKnown = false;
      } else {
        files.add(path);
      }
    }
  }
  var elapsed = 0;
  var hasElapsed = false;
  for (final turn in turns) {
    if (turnIsRunning(messages, turn, streaming)) continue;
    final ms = _turnElapsedMs(messages, turn);
    if (ms == null) continue;
    elapsed += ms;
    hasElapsed = true;
  }
  return SessionInfoStats(
    turns: turns.length,
    steps: steps,
    running: running,
    changedFiles: filesKnown ? files.length : null,
    elapsedMs: hasElapsed ? elapsed : null,
  );
}

/// 一轮的真实用时：优先轮级起止（装配层只填在该轮最后一条消息上），
/// 老数据缺失时退回轮内过程组的 startedAt/finishedAt（同 turnEndInfoOf）。
int? _turnElapsedMs(List<ChatMessage> messages, TurnRange turn) {
  int? start;
  int? end;
  int? groupStart;
  int? groupEnd;
  for (var i = turn.start; i < turn.end; i++) {
    final m = messages[i];
    final s = m.turnStartedAt;
    if (s != null && (start == null || s < start)) start = s;
    final e = m.turnFinishedAt;
    if (e != null && (end == null || e > end)) end = e;
    if (!m.isProcess) continue;
    final gs = m.startedAt;
    if (gs != null && (groupStart == null || gs < groupStart)) groupStart = gs;
    final ge = m.finishedAt;
    if (ge != null && (groupEnd == null || ge > groupEnd)) groupEnd = ge;
  }
  if (start != null && end != null && end > start) return end - start;
  if (groupStart != null && groupEnd != null && groupEnd > groupStart) {
    return groupEnd - groupStart;
  }
  // 最后一档：REST 历史常常不带 turn/start（老数据），但每条消息都带
  // 事件时间——用轮内消息首末差当「用时」，仍然是真实观测值。
  int? first;
  int? last;
  for (var i = turn.start; i < turn.end; i++) {
    final t = messages[i].startedAt;
    if (t == null) continue;
    if (first == null || t < first) first = t;
    if (last == null || t > last) last = t;
  }
  if (first != null && last != null && last > first) return last - first;
  return null;
}

/// 是否算「改动文件」的工具调用（edit/write 且没失败）。
bool _isEditLike(ToolCallInfo call) {
  if (call.failed) return false;
  final name = bareToolName(call.name);
  return name == 'edit' || name == 'write';
}

/// edit/write 调用改到的第一个路径（meta 优先，老桥退回参数）；拿不到返回 null。
String? _pathOfEdit(ToolCallInfo call) {
  final meta = call.meta;
  final direct = meta?['path'];
  if (direct is String && direct.isNotEmpty) return direct;
  final diffs = meta?['diffs'];
  if (diffs is List) {
    for (final d in diffs) {
      if (d is! Map) continue;
      final p = d['path'];
      if (p is String && p.isNotEmpty) return p;
    }
  }
  final args = _decodeArgs(call.rawArguments);
  final p = args?['file_path'] ?? args?['path'];
  return p is String && p.isNotEmpty ? p : null;
}

Map<String, dynamic>? _decodeArgs(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final v = jsonDecode(raw);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } on FormatException {
    return null;
  }
}
