/// 工具调用展示纯函数（对照官方 Web client.js 逆向词表 · 2026-11-17 批次）。
///
/// 官方把内核 `tool/call` 归一成 activityKind（read/write/search/…），再由
/// kind 驱动三件事：工具行标题（toolTitle）、运行中过程组标题（「正在读取
/// 文件 · <细节>」）、完成组标题（「已读取文件并写入文件」）。本文件是该词表
/// 的 Dart 移植：全部为纯函数/常量表，UI 只做渲染。
///
/// 偏差记录（数据不可得，批次汇报已注明）：
/// - preparing 态以 rawArguments == null 近似；exit code / stopped 态没有
///   error code 数据，不渲染；
/// - 官方运行中组无参数细节时取组内 thinking 项末段；我们的过程组不携带
///   reasoning（lib/bridge/history_page.dart 组装时丢弃），改由上层传
///   reasoningHint（最近助手思考流末段）。
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';

/// 官方 activityKind：内核工具名归一后的活动类别。
enum ToolActivityKind {
  thinking,
  read,
  readImage,
  write,
  search,
  edit,
  commands,
  code,
  webSearch,
  webFetch,
  subagents,
  plan,
  questions,
  tools,
}

/// 内核工具名 → 官方 activityKind（剥 `tools.` 前缀后匹配；空名 → thinking）。
ToolActivityKind activityKind(String toolName) {
  final bare = toolName.startsWith('tools.') ? toolName.substring(6) : toolName;
  if (bare.isEmpty) return ToolActivityKind.thinking;
  if (bare == 'read') return ToolActivityKind.read;
  if (bare == 'read_image') return ToolActivityKind.readImage;
  if (bare == 'grep' || bare == 'glob' || bare.endsWith('_inspect')) {
    return ToolActivityKind.search;
  }
  if (bare == 'write') return ToolActivityKind.write;
  if (bare == 'edit' || bare == 'apply_patch') return ToolActivityKind.edit;
  if (bare == 'bash' ||
      bare == 'pwsh' ||
      bare == 'exec_command' ||
      bare == 'write_stdin' ||
      bare.startsWith('terminal_')) {
    return ToolActivityKind.commands;
  }
  if (bare == 'run_code') return ToolActivityKind.code;
  if (bare == 'web_search') return ToolActivityKind.webSearch;
  if (bare == 'web_fetch') return ToolActivityKind.webFetch;
  if (bare == 'subagent' || bare.startsWith('subagent_')) {
    return ToolActivityKind.subagents;
  }
  if (bare == 'ask_user_question') return ToolActivityKind.questions;
  if (bare == 'todo_write') return ToolActivityKind.plan;
  return ToolActivityKind.tools;
}

/// 名字精确匹配的标题特例（优先于 kind 词表，官方同款）。
const Map<String, String> _toolTitleSpecials = {
  'pwsh': 'Pwsh',
  'grep': 'Grep',
  'glob': 'Glob',
};

/// kind → 工具行标题（官方 toolTitle 词表）。
const Map<ToolActivityKind, String> _toolTitleByKind = {
  ToolActivityKind.search: '搜索',
  ToolActivityKind.read: '读取',
  ToolActivityKind.commands: 'Bash',
  ToolActivityKind.write: '写入',
  ToolActivityKind.edit: '编辑',
  ToolActivityKind.code: '代码',
  ToolActivityKind.webSearch: '搜索',
  ToolActivityKind.webFetch: '获取',
  ToolActivityKind.readImage: '读取图像',
  ToolActivityKind.subagents: '创建子智能体',
  ToolActivityKind.questions: '提问',
  ToolActivityKind.plan: '更新待办列表',
  ToolActivityKind.tools: '工具调用',
  ToolActivityKind.thinking: '思考',
};

/// 工具行标题：特例（Pwsh/Grep/Glob）优先，其余按 kind。
String toolTitle(String toolName) {
  final bare = toolName.startsWith('tools.') ? toolName.substring(6) : toolName;
  return _toolTitleSpecials[bare] ?? _toolTitleByKind[activityKind(toolName)]!;
}

/// kind → 工具行图标（官方按 kind 出图标；这里取 Material 近似形）。
IconData toolIcon(ToolActivityKind kind) => switch (kind) {
  ToolActivityKind.read => Icons.description_outlined,
  ToolActivityKind.readImage => Icons.image_outlined,
  ToolActivityKind.write => Icons.save_outlined,
  ToolActivityKind.search => Icons.search,
  ToolActivityKind.edit => Icons.edit_outlined,
  ToolActivityKind.commands => Icons.terminal,
  ToolActivityKind.code => Icons.code,
  ToolActivityKind.webSearch => Icons.travel_explore,
  ToolActivityKind.webFetch => Icons.language,
  ToolActivityKind.subagents => Icons.groups_outlined,
  ToolActivityKind.plan => Icons.checklist,
  ToolActivityKind.questions => Icons.help_outline,
  ToolActivityKind.tools => Icons.build_outlined,
  ToolActivityKind.thinking => Icons.psychology_outlined,
};

/// 「正在…」词表（运行中过程组标题，按最新 running 调用的 kind）。
const Map<ToolActivityKind, String> _runningLabel = {
  ToolActivityKind.thinking: '正在分析请求',
  ToolActivityKind.read: '正在读取文件',
  ToolActivityKind.readImage: '正在读取图片',
  ToolActivityKind.write: '正在写入文件',
  ToolActivityKind.search: '正在搜索代码',
  ToolActivityKind.edit: '正在编辑文件',
  ToolActivityKind.commands: '正在运行命令',
  ToolActivityKind.code: '正在运行代码',
  ToolActivityKind.webSearch: '正在搜索网页',
  ToolActivityKind.webFetch: '正在访问网页',
  ToolActivityKind.subagents: '正在协调子智能体',
  ToolActivityKind.plan: '正在更新计划',
  ToolActivityKind.questions: '等待你的操作',
  ToolActivityKind.tools: '正在调用工具',
};

/// preparing 词表（running 调用还没拿到 arguments 时的近似态；
/// 官方无 thinking 变体，缺项回退 [runningLabelOf]）。
const Map<ToolActivityKind, String> _preparingLabel = {
  ToolActivityKind.read: '准备读取文件',
  ToolActivityKind.readImage: '准备读取图片',
  ToolActivityKind.write: '准备写入文件',
  ToolActivityKind.search: '准备搜索代码',
  ToolActivityKind.edit: '准备编辑文件',
  ToolActivityKind.commands: '准备运行命令',
  ToolActivityKind.code: '准备运行代码',
  ToolActivityKind.webSearch: '准备搜索网页',
  ToolActivityKind.webFetch: '准备访问网页',
  ToolActivityKind.subagents: '准备协调子智能体',
  ToolActivityKind.plan: '准备更新计划',
  ToolActivityKind.questions: '准备提问',
  ToolActivityKind.tools: '准备调用工具',
};

/// done 词表（完成组标题，按 kind 聚合）。
const Map<ToolActivityKind, String> _doneLabel = {
  ToolActivityKind.thinking: '已完成分析',
  ToolActivityKind.read: '已读取文件',
  ToolActivityKind.readImage: '已读取图片',
  ToolActivityKind.write: '已写入文件',
  ToolActivityKind.search: '已搜索代码',
  ToolActivityKind.edit: '修改了文件',
  ToolActivityKind.commands: '执行了命令',
  ToolActivityKind.code: '运行了代码',
  ToolActivityKind.webSearch: '已搜索网页',
  ToolActivityKind.webFetch: '已访问网页',
  ToolActivityKind.subagents: '已协调子智能体',
  ToolActivityKind.plan: '更新了计划',
  ToolActivityKind.questions: '向用户提出了问题',
  ToolActivityKind.tools: '已调用工具',
};

/// 折叠行摘要的取参键序（官方 SUMMARY_KEYS，按 kind 挑参数）。
const Map<ToolActivityKind, List<String>> _summaryKeys = {
  ToolActivityKind.commands: ['description', 'command'],
  ToolActivityKind.read: ['path', 'file_path', 'url'],
  ToolActivityKind.readImage: ['path', 'file_path', 'url'],
  ToolActivityKind.search: ['query', 'pattern', 'url'],
  ToolActivityKind.write: ['path', 'file_path'],
  ToolActivityKind.edit: ['path', 'file_path'],
  ToolActivityKind.code: ['description'],
};

/// 运行中组标题「 · 细节」的取参键序（官方 LIVE_TOOL_DETAIL_KEYS）。
const List<String> liveToolDetailKeys = [
  'title',
  'description',
  'objective',
  'task',
  'task_name',
  'name',
  'question',
  'questions',
  'prompt',
  'message',
  'command',
  'cmd',
  'queries',
  'query',
  'pattern',
  'url',
  'uri',
  'file_path',
  'path',
  'target',
  'action',
  'status',
];

/// 运行中标题「 · 细节」的最大字符数（官方 160）。
const int liveDetailMaxChars = 160;

/// 工具行五态判定里的 running：结果未到且未失败（官方 running 态）。
bool isCallRunning(ToolCallInfo call) =>
    call.resultText == null && !call.failed && call.errorCode == null;

/// 工具折叠行呈现状态（官方 row 状态机 + preparing/stopped/cancelled 特化）。
/// 优先级：errorCode 终态（stopped/cancelled）→ failed → ok（有结果）→
/// preparing（真数据驱动：流式行 preparing 标记；历史路径 rawArguments==null
/// 近似）→ running。
enum ToolRowState { preparing, running, ok, stopped, cancelled, failed }

ToolRowState toolRowStateOf(ToolCallInfo call) {
  if (call.errorCode == 'interrupted') return ToolRowState.stopped;
  if (call.errorCode != null) {
    // 'ASK_CANCELLED' 仅 ask 工具出「已取消」（官方 ask.cancelled）；其余
    // 分类（TOOL_OUTCOME_UNKNOWN / TOOL_NOT_STARTED / 未知值）→ 失败态。
    if (call.errorCode == 'ASK_CANCELLED' &&
        activityKind(call.name) == ToolActivityKind.questions) {
      return ToolRowState.cancelled;
    }
    return ToolRowState.failed;
  }
  if (call.failed) return ToolRowState.failed;
  if (call.resultText != null) return ToolRowState.ok;
  if (call.preparing || call.rawArguments == null) {
    return ToolRowState.preparing;
  }
  return ToolRowState.running;
}

/// 行仍活着（preparing / running）：过程组标题的 running 选取、
/// 「运行中」状态字与详情区「未找到结果」兜底都用它。
bool isToolRowLive(ToolCallInfo call) {
  final state = toolRowStateOf(call);
  return state == ToolRowState.preparing || state == ToolRowState.running;
}

/// 结果文本尾部的退出状态标记（官方 parseExitStatus 同款；exit code 不是
/// 协议字段，客户端从结果文本尾部 `[exit code: N]` / `[killed by signal: X]` 解析）。
class ExitStatus {
  const ExitStatus({this.exitCode, this.signal});

  /// `[exit code: null]` → null（无数值退出码，不出徽标）。
  final int? exitCode;
  final String? signal;
}

ExitStatus? parseExitStatus(String? text) {
  if (text == null) return null;
  final exit = RegExp(r'\[exit code: (-?\d+|null)\]\s*$').firstMatch(text);
  final signal = RegExp(r'\[killed by signal: ([^\]\n]+)\]\s*$')
      .firstMatch(text);
  if (signal != null) return ExitStatus(signal: signal.group(1));
  if (exit == null) return null;
  final raw = exit.group(1);
  if (raw == null || raw == 'null') return null;
  return ExitStatus(exitCode: int.tryParse(raw));
}

/// 徽标文案（行尾展示）：`exit 2` / `signal X`。
String? exitBadgeLabel(ExitStatus? status) {
  if (status == null) return null;
  if (status.signal != null) return 'signal ${status.signal}';
  if (status.exitCode != null) return 'exit ${status.exitCode}';
  return null;
}

/// 徽标是否红色（非 0 / signal 的非正常退出）。
bool exitBadgeIsError(ExitStatus? status) =>
    status != null &&
    (status.signal != null ||
        (status.exitCode != null && status.exitCode != 0));

String? _firstLine(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  if (t.isEmpty) return null;
  return t.split('\n').first.trim();
}

Object? tryParseJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// 截断到 [max] 字符（官方 detail/detail 键值截 160）。
String clipText(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// 折叠行摘要：按 kind 的键序取参（miss → 首个字符串值首行 → 参数原文首行）。
/// search 的 queries 字符串数组 join(', ')（每项取首行）。
String? summarizeArgs(ToolActivityKind kind, String? rawArguments) {
  final parsed = tryParseJson(rawArguments);
  if (parsed is! Map) return _firstLine(rawArguments);
  for (final key in _summaryKeys[kind] ?? const <String>[]) {
    final line = _firstLine(parsed[key]);
    if (line != null) return line;
  }
  if (kind == ToolActivityKind.search) {
    final queries = parsed['queries'];
    if (queries is List && queries.isNotEmpty) {
      final parts = <String>[];
      for (final q in queries) {
        final line = _firstLine(q);
        if (line != null) parts.add(line);
      }
      if (parts.isNotEmpty) return parts.join(', ');
    }
  }
  for (final value in parsed.values) {
    final line = _firstLine(value);
    if (line != null) return line;
  }
  return _firstLine(rawArguments);
}

/// 运行中组标题的「 · 细节」：最后一个 running 调用按 [liveToolDetailKeys]
/// 取第一个命中值（字符串取首行、数组取首项首行，截 160 字符）。
String? liveDetailText(ChatMessage group) {
  ToolCallInfo? latest;
  for (final call in group.toolCalls) {
    if (isCallRunning(call)) latest = call;
  }
  if (latest == null) return null;
  final parsed = tryParseJson(latest.rawArguments);
  if (parsed is! Map) return null;
  for (final key in liveToolDetailKeys) {
    final value = parsed[key];
    if (value is String) {
      final line = _firstLine(value);
      if (line != null) return clipText(line, liveDetailMaxChars);
    }
    if (value is List && value.isNotEmpty) {
      final line = _firstLine(value.first);
      if (line != null) return clipText(line, liveDetailMaxChars);
    }
  }
  return null;
}

/// 运行中组没有可读参数细节时的兜底：最近思考流的最后一段非空文本（去 **）。
String? reasoningDetailOf(String? reasoning) {
  if (reasoning == null) return null;
  for (final line in reasoning.split('\n').reversed) {
    final t = line.trim().replaceAll('**', '');
    if (t.isNotEmpty) return clipText(t, liveDetailMaxChars);
  }
  return null;
}

/// 过程组折叠行标题：
/// - 进行中（有 running 调用）→「正在…」+ 可选「 · 细节」（[liveDetail] 开启时；
///   细节缺失回退 [reasoningHint]）；rawArguments 未到用 preparing 词表；
/// - 完成组 → 按 kind 聚合 done 词：数量降序、并列按首现序，取前 3 类；
///   两类用「并」连接（两边都以「已」开头时去掉第二个的「已」），≥3 类用
///   「，」连接，总类数 >3 末尾加「等」；无调用 →「已完成分析」。
String processGroupTitle(
  ChatMessage group, {
  required bool liveDetail,
  String? reasoningHint,
}) {
  final calls = group.toolCalls;
  if (calls.isEmpty) return _doneLabel[ToolActivityKind.thinking]!;
  ToolCallInfo? running;
  for (final call in calls) {
    if (isToolRowLive(call)) running = call;
  }
  if (running != null) {
    final kind = activityKind(running.name);
    // preparing 判定真数据驱动：流式行带 preparing 标记（桥 fdb85da）；
    // 历史路径 running 行 rawArguments==null 时保留近似回退。
    final label = running.preparing || running.rawArguments == null
        ? (_preparingLabel[kind] ?? _runningLabel[kind]!)
        : _runningLabel[kind]!;
    if (!liveDetail) return label;
    final detail = liveDetailText(group) ?? reasoningDetailOf(reasoningHint);
    return detail == null ? label : '$label · $detail';
  }
  return _completedTitle(calls);
}

String _completedTitle(List<ToolCallInfo> calls) {
  final counts = <ToolActivityKind, int>{};
  final firstIndex = <ToolActivityKind, int>{};
  final seen = <String>{};
  for (var i = 0; i < calls.length; i++) {
    final call = calls[i];
    // run_code 内嵌调用共享外层 callId：按 distinct callId 去重（官方口径）。
    if (call.callId.isEmpty || !seen.add(call.callId)) continue;
    final kind = activityKind(call.name);
    firstIndex.putIfAbsent(kind, () => i);
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  if (counts.isEmpty) return _doneLabel[ToolActivityKind.thinking]!;
  final kinds = counts.keys.toList()
    ..sort((a, b) {
      final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      if (byCount != 0) return byCount;
      return (firstIndex[a] ?? 0).compareTo(firstIndex[b] ?? 0);
    });
  final top = kinds.take(3).map((k) => _doneLabel[k]!).toList();
  String title;
  if (top.length == 1) {
    title = top.first;
  } else if (top.length == 2) {
    var second = top[1];
    if (second.startsWith('已') && top.first.startsWith('已')) {
      second = second.substring(1);
    }
    title = '${top.first}并$second';
  } else {
    title = top.join('，');
  }
  return kinds.length > 3 ? '$title等' : title;
}
