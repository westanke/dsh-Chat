/// 本轮改动 / 本轮生成文件：纯函数，从工具调用推导（对照 dsh-go
/// `app/lib/ui/chat/turn_summary.dart` 与 `state/artifacts.dart`）。
///
/// 为什么在客户端自己算：桥（dsh-remote-bridge 2.13.0）没有 workspace-changes
/// 查询面，会话日志里的 `workspace/changes` 事件只带 `{turn}`
/// （实测 seq 1301 data={"turn":1}），summary/diff 要通过 /api/changes.summary
/// 另取——那条 REST 还没实现。dsh-go 也是本地推导：用 `tool/result` 的
/// `data.meta.diffs`（桥原样透传），拿不到再退回 arguments。
///
/// 数据形状（本机会话日志实测）：
/// - edit：meta `{path, diffs:[{path, oldText, newText}]}`
/// - write：meta `{operation:'create'|'update', path, diffs}`
/// - bash：meta `{cwd}` —— 给「生成文件」里的相对路径当基准目录
library;

import 'dart:convert';

import '../bridge/history_page.dart';
import '../bridge/tool_call.dart';
import 'code_diff.dart';
import 'work_steps.dart';

/// 一次编辑（一次工具调用里的一个 diff 项）。
class EditHunk {
  const EditHunk({required this.index, required this.lines});

  /// 该文件在本轮里的第几次修改（1 起）。
  final int index;
  final List<CodeDiffLine> lines;
}

/// 本轮里被改的一个文件。
class FileChange {
  const FileChange({
    required this.path,
    required this.created,
    required this.hunks,
    required this.added,
    required this.removed,
  });

  /// 绝对路径（工具参数就是绝对路径）。
  final String path;

  /// 本轮新建（write create / 首次 write 且此前不存在）。
  final bool created;
  final List<EditHunk> hunks;
  final int added;
  final int removed;

  /// 改了几次（= 几个 diff 项）。
  int get edits => hunks.length;

  /// 文件名。
  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  /// 目录（卡片第二行弱化显示，超长由 Text ellipsis 截断）。
  String get directory {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '' : path.substring(0, i);
  }
}

/// 本轮全部改动。
class TurnChanges {
  const TurnChanges({required this.anchorSeq, required this.files});

  /// 该轮首条消息的 seq（行 key 用，稳定）。
  final int anchorSeq;
  final List<FileChange> files;

  bool get isEmpty => files.isEmpty;
  int get added => files.fold(0, (sum, f) => sum + f.added);
  int get removed => files.fold(0, (sum, f) => sum + f.removed);
}

/// 本轮改动；没有改动返回 null。
///
/// 只算**已完成**的轮（调用方负责不传正在跑的那轮）：工具结果没到齐时
/// 计数会一路跳，卡片也就没有意义。
TurnChanges? turnChangesOf(List<ChatMessage> messages, TurnRange turn) {
  if (turn.start < 0 || turn.end > messages.length || turn.start >= turn.end) {
    return null;
  }
  final anchorSeq = messages[turn.start].seq;
  final calls = <ToolCallInfo>[];
  for (var i = turn.start + 1; i < turn.end; i++) {
    final message = messages[i];
    if (!message.isProcess) continue;
    for (final call in message.toolCalls) {
      if (!call.failed) calls.add(call);
    }
  }
  // messages 是不可变的快照，同一实例内同轮结果必相同；用实例地址当 key，
  // 避免两轮消息数相同时互相串味（测试里就踩过）。
  final cacheKey =
      '${identityHashCode(messages)}|$anchorSeq|${turn.end}|${calls.length}';
  if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
  final result = _compute(anchorSeq, calls);
  if (_cache.length > _maxCachedTurns) _cache.clear();
  return _cache[cacheKey] = result;
}

const int _maxCachedTurns = 200;
final Map<String, TurnChanges?> _cache = <String, TurnChanges?>{};

TurnChanges? _compute(int anchorSeq, List<ToolCallInfo> calls) {
  final order = <String>[];
  final byPath = <String, _FileBuilder>{};
  for (final call in calls) {
    _applyCall(call, order, byPath);
  }
  if (order.isEmpty) return null;
  return TurnChanges(
    anchorSeq: anchorSeq,
    files: [for (final path in order) byPath[path]!.build(path)],
  );
}

void _applyCall(
  ToolCallInfo call,
  List<String> order,
  Map<String, _FileBuilder> byPath,
) {
  final name = bareToolName(call.name);
  if (name != 'edit' && name != 'write') return;
  final meta = call.meta;
  final diffs = meta?['diffs'];
  final operation = meta?['operation'] is String
      ? meta!['operation'] as String
      : null;
  if (diffs is List && diffs.isNotEmpty) {
    for (final raw in diffs) {
      if (raw is! Map) continue;
      final path = raw['path'];
      final oldText = raw['oldText'];
      final newText = raw['newText'];
      if (path is! String || path.isEmpty) continue;
      if (newText is! String) continue;
      _add(
        order,
        byPath,
        path: path,
        oldText: oldText is String ? oldText : '',
        newText: newText,
        created:
            operation == 'create' ||
            (name == 'write' && (oldText is! String || oldText.isEmpty)),
      );
    }
    return;
  }
  final args = _decodeArgs(call.rawArguments);
  if (args == null) return;
  final path = args['file_path'] ?? args['path'];
  if (path is! String || path.isEmpty) return;
  if (name == 'edit') {
    final oldText = args['old_string'] ?? args['oldText'];
    final newText = args['new_string'] ?? args['newText'];
    if (newText is! String) return;
    _add(
      order,
      byPath,
      path: path,
      oldText: oldText is String ? oldText : '',
      newText: newText,
      created: oldText is! String || oldText.isEmpty,
    );
    return;
  }
  final content = args['content'];
  if (content is! String) return;
  _add(
    order,
    byPath,
    path: path,
    oldText: '',
    newText: content,
    created: operation != 'update',
  );
}

void _add(
  List<String> order,
  Map<String, _FileBuilder> byPath, {
  required String path,
  required String oldText,
  required String newText,
  required bool created,
}) {
  final builder = byPath.putIfAbsent(path, () {
    order.add(path);
    return _FileBuilder();
  });
  if (created) builder.created = true;
  final lines = diffLinesOf(oldText, newText);
  var added = 0;
  var removed = 0;
  for (final line in lines) {
    if (line.type == CodeDiffLineType.add) {
      added++;
    } else if (line.type == CodeDiffLineType.del) {
      removed++;
    }
  }
  builder.hunks.add(EditHunk(index: builder.hunks.length + 1, lines: lines));
  builder.added += added;
  builder.removed += removed;
}

class _FileBuilder {
  bool created = false;
  int added = 0;
  int removed = 0;
  final List<EditHunk> hunks = <EditHunk>[];

  FileChange build(String path) => FileChange(
    path: path,
    created: created,
    hunks: hunks,
    added: added,
    removed: removed,
  );
}

// ---------- 本轮生成的文件 ----------

/// 文件类型（决定图标与「图片 · PNG」这类说明文字）。
enum ArtifactKind {
  image('图片'),
  pdf('PDF'),
  document('文档'),
  spreadsheet('表格'),
  slides('幻灯片'),
  archive('压缩包'),
  audio('音频'),
  video('视频'),
  web('网页'),
  markdown('Markdown'),
  text('文本'),
  other('文件');

  const ArtifactKind(this.label);

  final String label;
}

/// 本轮生成的一个文件。
class ArtifactFile {
  const ArtifactFile({required this.path, required this.kind});

  final String path;
  final ArtifactKind kind;

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  /// 「图片 · PNG」。
  String get caption {
    final i = path.lastIndexOf('.');
    final ext = i < 0 ? '' : path.substring(i + 1).toUpperCase();
    return ext.isEmpty ? kind.label : '${kind.label} · $ext';
  }
}

/// 本轮生成的文件：本轮 write 新建的文件 + 本轮最终回复里引用的图片/文件链接。
///
/// 已 `present` 交付的文件不在这里（那由 role=='files' 的交付卡渲染，
/// 两张卡同时出现就重复了）。
List<ArtifactFile> turnArtifactsOf(
  List<ChatMessage> messages,
  TurnRange turn,
) {
  if (turn.start < 0 || turn.end > messages.length || turn.start >= turn.end) {
    return const [];
  }
  final paths = <String>[];
  final seen = <String>{};
  var base = '';
  for (var i = turn.start + 1; i < turn.end; i++) {
    final message = messages[i];
    if (message.isProcess) {
      for (final call in message.toolCalls) {
        if (call.failed) continue;
        final cwd = call.meta?['cwd'];
        if (cwd is String && cwd.isNotEmpty) base = cwd;
        if (bareToolName(call.name) != 'write') continue;
        final args = _decodeArgs(call.rawArguments);
        final path = args?['file_path'] ?? args?['path'];
        if (path is! String || path.isEmpty) continue;
        final op = call.meta?['operation'];
        if (op is String && op == 'update') continue;
        if (seen.add(path)) paths.add(path);
      }
      continue;
    }
    if (message.isUser) continue;
    for (final ref in _markdownRefs(message.text)) {
      final resolved = _resolve(ref, base);
      if (resolved == null) continue;
      if (seen.add(resolved)) paths.add(resolved);
    }
  }
  return [
    for (final path in paths) ArtifactFile(path: path, kind: artifactKindOf(path)),
  ];
}

/// 工具名去掉 `tools.` 前缀（run_code 内嵌调用）。
String bareToolName(String name) =>
    name.startsWith('tools.') ? name.substring(6) : name;

/// 扩展名 → 类型。
ArtifactKind artifactKindOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return ArtifactKind.other;
  final ext = path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic' =>
      ArtifactKind.image,
    'pdf' => ArtifactKind.pdf,
    'doc' || 'docx' || 'rtf' || 'odt' => ArtifactKind.document,
    'xls' || 'xlsx' || 'csv' || 'ods' => ArtifactKind.spreadsheet,
    'ppt' || 'pptx' || 'odp' || 'key' => ArtifactKind.slides,
    'zip' || 'tar' || 'gz' || 'tgz' || '7z' || 'rar' || 'xz' => ArtifactKind.archive,
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' || 'aac' => ArtifactKind.audio,
    'mp4' || 'mov' || 'mkv' || 'webm' || 'avi' => ArtifactKind.video,
    'html' || 'htm' => ArtifactKind.web,
    'md' || 'markdown' => ArtifactKind.markdown,
    'txt' || 'log' || 'json' || 'yaml' || 'yml' || 'xml' || 'toml' ||
    'dart' || 'ts' || 'js' || 'py' || 'sh' => ArtifactKind.text,
    _ => ArtifactKind.other,
  };
}

/// 回复里的图片 / 文件引用：`![alt](path)` 与 `[text](path)` 的本地路径。
Iterable<String> _markdownRefs(String text) sync* {
  if (text.isEmpty) return;
  final pattern = RegExp(r'!?\[[^\]]*\]\(([^)\s]+)\)');
  for (final match in pattern.allMatches(text)) {
    final target = match.group(1);
    if (target == null || target.isEmpty) continue;
    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('data:') ||
        target.startsWith('#')) {
      continue;
    }
    yield target;
  }
}

/// 相对路径按本轮最后的 bash cwd 拼绝对路径；拼不出来就跳过（缩略图取不到，
/// 卡片就不该列一个点不开的路径）。
String? _resolve(String ref, String base) {
  if (ref.startsWith('/')) return ref;
  if (base.isEmpty) return null;
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return '$trimmedBase/$ref';
}

Map<String, dynamic>? _decodeArgs(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final parsed = jsonDecode(raw);
    return parsed is Map ? Map<String, dynamic>.from(parsed) : null;
  } on FormatException {
    return null;
  }
}
