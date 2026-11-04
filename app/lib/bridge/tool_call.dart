/// 工具调用相关的模型与措辞表（从 models.dart 拆出，宪法 §7 单文件 ≤500 行）。
///
/// 措辞对齐官方（与 dsh-companion 的 ChatToolPresentation 同源）：内核的
/// `tool/call` 没有结构化 summary 字段（已逐条核实），只能按工具名与参数近似还原；
/// `run_code` 的 arguments 里会内嵌 `tools.bash` 等名字，扫一遍即可得到
/// 「运行了代码，执行了命令」这类组合。
library;

import 'dart:convert';

/// 一次工具调用（`tool/call` + `tool/result` 按 callId 合并后的展示形态）。
class ToolCallInfo {
  const ToolCallInfo({
    required this.callId,
    required this.name,
    required this.phrases,
    this.summary,
    this.failed = false,
    this.durationMs,
    this.resultText,
    this.rawArguments,
  });

  final String callId;
  final String name;

  /// 动作短语，如 `['运行了代码', '执行了命令']`（措辞对齐官方）。
  final List<String> phrases;

  /// 参数摘要（description / path / command / query 的首行）。
  final String? summary;
  final bool failed;
  final int? durationMs;

  /// 执行结果正文（tool/result 的 text 段拼接；图片段一行占位）。
  /// 详情展开用，companion ChatToolPresentation 的 toolResultText 口径。
  final String? resultText;

  /// arguments 原串（JSON 字符串），详情展开用（models.dart 组装时带上）。
  final String? rawArguments;

  /// 折叠行用的主短语（run_code 取第一个，其余就是唯一那个）。
  String get phrase => phrases.isEmpty ? name : phrases.first;
}

/// 工具名 → 动作短语（对齐官方措辞，与 dsh-companion ChatToolPresentation 同源）。
///
/// 内核的 `tool/call` 没有结构化 summary 字段（已逐条核实），只能按工具名与
/// 参数近似还原；`run_code` 的 arguments 里会内嵌 `tools.bash` 等名字，扫一遍即可
/// 得到「运行了代码，执行了命令」这类组合。
const List<(String, String)> innerToolActions = [
  ('tools.edit', '修改了文件'),
  ('tools.write', '已写入文件'),
  ('tools.read', '读取了文件'),
  ('tools.bash', '执行了命令'),
  ('tools.grep', '搜索了内容'),
  ('tools.glob', '搜索了文件'),
];

const Map<String, String> toolPhraseByName = {
  'bash': '执行了命令',
  'pwsh': '执行了命令',
  'read': '读取了文件',
  'read_image': '读取了图片',
  'write': '已写入文件',
  'edit': '修改了文件',
  'grep': '搜索了内容',
  'glob': '搜索了文件',
  'web_fetch': '已访问网页',
  'web_search': '已搜索网页',
  'memory': '记录了记忆',
  'job_output': '查看了任务输出',
  'job_kill': '停止了任务',
  'adb_ui': '检查了手机界面',
  'working_directory': '切换了工作目录',
  'todo_write': '更新了任务清单',
  'wait_agent': '等待了子任务',
  'update_goal': '更新了目标',
  'compress': '压缩了上下文',
  'workflow': '编排了子任务',
  'send_message': '发送了消息',
  'lead': '调度了团队',
  'skill': '调用了技能',
  'schedule_create': '创建了定时任务',
  'schedule_list': '查看了定时任务',
  'schedule_delete': '删除了定时任务',
  'schedule_update': '修改了定时任务',
  'team_task_create': '创建了团队任务',
  'team_task_list': '查看了团队任务',
  'team_task_get': '查看了任务详情',
  'team_task_update': '更新了团队任务',
  'subagent': '派出了子任务',
  'ask_user_question': '向用户提问',
};

List<String> toolPhrases(String name, String? arguments) {
  final raw = arguments ?? '';
  if (name == 'run_code') {
    final out = <String>['运行了代码'];
    for (final (needle, phrase) in innerToolActions) {
      if (raw.contains(needle) && !out.contains(phrase)) out.add(phrase);
    }
    return out;
  }
  final byName = toolPhraseByName[name];
  if (byName != null) return [byName];
  if (name.startsWith('mcp__')) {
    return ['调用了 ${name.substring(5).replaceAll('__', ' · ')}'];
  }
  return [name.isEmpty ? '工具' : name];
}

/// 从 arguments JSON 里挑一个最能说明「在干什么」的字段首行。
String? toolSummary(String? arguments) {
  if (arguments == null || arguments.trim().isEmpty) return null;
  try {
    final parsed = jsonDecode(arguments);
    if (parsed is Map) {
      for (final key in const [
        'description',
        'path',
        'file_path',
        'query',
        'pattern',
        'url',
        'command',
        'name',
        'package',
      ]) {
        final v = parsed[key];
        if (v is String && v.trim().isNotEmpty) {
          return v.split('\n').first;
        }
      }
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// 从 tool/result 的 content 数组提取正文（companion toolResultText 口径）：
/// text 段直接拼接，image 段一行占位（字节在服务端附件存储，拿不到）。
String? toolResultText(dynamic content) {
  if (content is String) {
    final s = content.trim();
    return s.isEmpty ? null : s;
  }
  if (content is! List) return null;
  final buf = StringBuffer();
  var hasImage = false;
  for (final block in content) {
    if (block is! Map) continue;
    final type = (block['type'] ?? '') as String;
    if (type == 'image') {
      hasImage = true;
    } else if (block['text'] is String) {
      final t = (block['text'] as String).trim();
      if (t.isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.write(t);
      }
    }
  }
  var out = buf.toString().trim();
  if (out.isEmpty && hasImage) out = '[图片]';
  return out.isEmpty ? null : out;
}

/// 解析中的工具调用（result 还没到）。
class RawToolCall {
  RawToolCall({
    required this.callId,
    required this.name,
    required this.arguments,
    required this.time,
    this.resultText,
    this.failed = false,
  });

  final String callId;
  final String name;
  final String? arguments;
  final int time;

  /// tool/result 的正文（text 段拼接 + 图片一行占位），到达时补上。
  String? resultText;
  bool failed;

  ToolCallInfo toInfo() => ToolCallInfo(
    callId: callId,
    name: name,
    phrases: toolPhrases(name, arguments),
    summary: toolSummary(arguments),
    failed: failed,
    resultText: resultText,
    rawArguments: arguments,
  );
}

/// 从 assistant content 数组里抽出内嵌的 tool-call 块。
List<RawToolCall> extractToolCalls(dynamic content) {
  final out = <RawToolCall>[];
  if (content is! List) return out;
  for (final block in content) {
    if (block is! Map) continue;
    if (block['type'] != 'tool-call') continue;
    final id = (block['id'] ?? '') as String;
    if (id.isEmpty) continue;
    out.add(
      RawToolCall(
        callId: id,
        name: (block['name'] ?? '') as String,
        arguments: block['arguments'] as String?,
        time: 0,
      ),
    );
  }
  return out;
}
