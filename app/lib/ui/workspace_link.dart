/// 消息正文里的「链接」出口：
/// - `http/https` 交给系统浏览器（`md_view.dart` 已有逻辑，这里不重复）；
/// - 工作区文件路径（绝对路径 / 相对会话 cwd 的路径 / `file://`）→ 全屏查看页。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'chat_state.dart';
import 'md_viewer.dart';

/// 常见可读文本扩展名：命中这些才当作「工作区文件」去打开。
const List<String> kReadableExtensions = [
  '.md',
  '.markdown',
  '.txt',
  '.json',
  '.yaml',
  '.yml',
  '.dart',
  '.ts',
  '.js',
  '.py',
  '.kt',
  '.java',
  '.c',
  '.cpp',
  '.h',
  '.sh',
  '.log',
  '.csv',
  '.html',
  '.css',
  '.xml',
  '.toml',
  '.ini',
];

/// 把消息里的链接解析成「可 resolve 的工作区路径」；不是文件路径就返回 null。
///
/// 判据（顺序即优先级）：
/// 1. 带 scheme（`http://` 等）→ null，交给浏览器；
/// 2. `file://` → 去掉 scheme 当前缀；
/// 3. 以 `/` 开头 → 绝对路径直接用；
/// 4. 相对路径：**必须命中 [kReadableExtensions]**，且给了 [cwd] 才拼；
///    否则一律 null（避免把 `a/b` 这种正文片段误当文件）。
String? workspacePathOf(String raw, {String? cwd}) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // 1) 有 scheme 但不是 file:// → 不是本模块的活。
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(text);
  String path = text;
  if (scheme != null) {
    if (scheme.group(1)!.toLowerCase() != 'file') return null;
    path = Uri.tryParse(text)?.toFilePath() ?? text.substring(7);
  }
  if (path.contains('://')) return null;

  // 去掉行尾标点（句号、逗号、右括号、引号），正文里常把路径写在句子里。
  path = path.replaceAll(RegExp(r'[.,;:)\]}' "'" r']+$'), '');
  if (path.isEmpty) return null;

  final lower = path.toLowerCase();
  final readable = kReadableExtensions.any(lower.endsWith);

  // 3) 绝对路径：只要看起来有扩展名，或者本来就以 / 开头，都算。
  if (path.startsWith('/')) {
    return readable || path.contains('.') ? path : null;
  }

  // 4) 相对路径：必须有明确扩展名，且有 cwd 才能拼。
  if (!readable) return null;
  final base = cwd?.trim();
  if (base == null || base.isEmpty) return null;
  return base.endsWith('/') ? '$base$path' : '$base/$path';
}

/// 打开工作区文件（全屏查看）。返回 true 表示这次点击已被本模块消化。
Future<bool> openWorkspacePath(
  BuildContext context,
  ChatState state,
  String raw, {
  required DsColors colors,
}) async {
  final current = state.sessions.where(
    (s) => s.id == state.sessionId,
  );
  final cwd = current.isEmpty ? null : current.first.cwdAbsolute;
  final path = workspacePathOf(raw, cwd: cwd);
  if (path == null) return false;
  if (!context.mounted) return true;

  final name = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MdViewerPage(
        gateway: state.gateway,
        absolutePath: path,
        title: name,
        colors: colors,
      ),
    ),
  );
  return true;
}
