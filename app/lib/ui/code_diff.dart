/// 「代码工作视图 · 本轮代码差异」纯函数（对照官方 App 2026-11-16 批次 · D 项）。
///
/// 从当前轮（最后一条 user 之后）的 process 组里取出 edit / write 工具调用，
/// 把参数渲染成行级差异：
/// - edit（`file_path`/`old_string`/`new_string`）→ 公共前后缀标为上下文行，
///   中间段逐行 -old / +new（不做全量 LCS，前后缀裁剪已足够可读）；
/// - write（`file_path`/`content`）→ 全部为 + 行。
///
/// 工具名与参数键名以 lib/bridge/tool_call.dart 为准（rawArguments 是 JSON
/// 字符串；桥侧对 run_code 内嵌调用可能用 `tools.edit`/`tools.write` 前缀）。
library;

import 'dart:convert';

import '../bridge/models.dart';
import 'work_steps.dart';

/// diff 行类型：新增（+）/ 删除（-）/ 上下文（公共前后缀）。
enum CodeDiffLineType { add, del, ctx }

/// 一行差异。
class CodeDiffLine {
  const CodeDiffLine(this.type, this.text);

  final CodeDiffLineType type;
  final String text;
}

/// 一个文件的差异块。
class CodeDiff {
  const CodeDiff({required this.path, required this.kind, required this.lines});

  /// 相对路径（rawArguments 的 file_path）。
  final String path;

  /// 'edit'（修改）/ 'write'（新建或全量写入）。
  final String kind;
  final List<CodeDiffLine> lines;
}

/// 解析单个工具调用的参数为差异块；非 edit/write 工具或参数缺失返回 null。
CodeDiff? codeDiffOfCall(String name, String? rawArguments) {
  final bare = name.startsWith('tools.') ? name.substring(6) : name;
  final kind = switch (bare) {
    'edit' => 'edit',
    'write' => 'write',
    _ => null,
  };
  if (kind == null || rawArguments == null || rawArguments.trim().isEmpty) {
    return null;
  }
  final Object? parsed;
  try {
    parsed = jsonDecode(rawArguments);
  } on FormatException {
    return null;
  }
  if (parsed is! Map) return null;
  final path = parsed['file_path'];
  if (path is! String || path.isEmpty) return null;
  if (kind == 'edit') {
    final oldText = parsed['old_string'];
    final newText = parsed['new_string'];
    if (oldText is! String || newText is! String) return null;
    return CodeDiff(
      path: path,
      kind: kind,
      lines: _diffEdit(oldText, newText),
    );
  }
  final content = parsed['content'];
  if (content is! String) return null;
  return CodeDiff(
    path: path,
    kind: kind,
    lines: [for (final l in _splitLines(content)) CodeDiffLine(CodeDiffLineType.add, l)],
  );
}

/// 当前轮（最后一条 user 之后）的文件差异列表，按工具调用顺序排列。
List<CodeDiff> codeDiffsOfTurn(List<ChatMessage> messages) {
  final turn = lastTurnOf(messages);
  if (turn == null) return const [];
  final diffs = <CodeDiff>[];
  for (var i = turn.start + 1; i < turn.end; i++) {
    final m = messages[i];
    if (!m.isProcess) continue;
    for (final call in m.toolCalls) {
      final diff = codeDiffOfCall(call.name, call.rawArguments);
      if (diff != null) diffs.add(diff);
    }
  }
  return diffs;
}

/// edit → 公共前后缀标 ctx，中间段逐行 -old / +new。
List<CodeDiffLine> _diffEdit(String oldText, String newText) {
  final oldLines = _splitLines(oldText);
  final newLines = _splitLines(newText);
  var prefix = 0;
  while (prefix < oldLines.length &&
      prefix < newLines.length &&
      oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldLines.length - prefix &&
      suffix < newLines.length - prefix &&
      oldLines[oldLines.length - 1 - suffix] ==
          newLines[newLines.length - 1 - suffix]) {
    suffix++;
  }
  final lines = <CodeDiffLine>[
    for (var i = 0; i < prefix; i++) CodeDiffLine(CodeDiffLineType.ctx, oldLines[i]),
    for (var i = prefix; i < oldLines.length - suffix; i++)
      CodeDiffLine(CodeDiffLineType.del, oldLines[i]),
    for (var i = prefix; i < newLines.length - suffix; i++)
      CodeDiffLine(CodeDiffLineType.add, newLines[i]),
    for (var i = oldLines.length - suffix; i < oldLines.length; i++)
      CodeDiffLine(CodeDiffLineType.ctx, oldLines[i]),
  ];
  return lines;
}

/// 按行切分；结尾换行产生的末尾空元素丢弃（与常见 diff 工具一致）。
List<String> _splitLines(String text) {
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty && text.endsWith('\n')) {
    lines.removeLast();
  }
  return lines;
}
