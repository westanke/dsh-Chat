/// bridge 协议模型（显式 fromJson/toJson，宪法 §7）。
/// 形状依据 dsh-remote-bridge v2.10.0：docs/api/openapi.yaml、asyncapi.yaml、
/// docs/project/API.md 与姊妹仓 dsh-companion 的历史事件映射（ChatHistoryMapping.kt）。
///
/// 历史装配四件套（SessionEvent / DeliverableFile / ChatMessage / HistoryPage）
/// 已拆到 history_page.dart（宪法 §7 单文件 ≤500 行），经下方 export 继续暴露。
library;

export 'content.dart';
export 'history_page.dart';
export 'tool_call.dart';

/// ChatSession（openapi §ChatSession）。
class DshSession {
  const DshSession({
    required this.id,
    required this.rootId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    this.title,
    this.workspaceId,
    this.workspaceTitle,
    this.cwd = '',
    this.cwdAbsolute,
  });

  final String id;
  final String rootId;
  final int updatedAt;
  final bool running;
  final bool blank;
  final String? title;
  final String? workspaceId;

  /// 所属工作区名（chat-adapter.ts:273,498 随会话视图一起下发）；
  /// 抽屉按它分组（真机反馈 2026-11-04 第 7 项），空 = 「未分组」。
  final String? workspaceTitle;

  /// 会话工作目录绝对路径（chat-adapter.ts:494，给手机端拼 @绝对路径 用；
  /// 真机反馈 2026-11-04 第 3 项的 @ 补全数据源）。
  final String? cwdAbsolute;

  /// 会话工作目录，授权根内相对路径（openapi §ChatSession.required，
  /// WirePath 语义；'' = 会话目录就是授权根本身）。
  /// 新建会话目录选择（2026-11-15 反馈）用它做「最近使用」候选。
  final String cwd;

  factory DshSession.fromJson(Map<String, dynamic> j) => DshSession(
    id: (j['id'] ?? '') as String,
    rootId: (j['rootId'] ?? '') as String,
    updatedAt: (j['updatedAt'] ?? 0) as int,
    running: (j['running'] ?? false) as bool,
    blank: (j['blank'] ?? false) as bool,
    title: j['title'] as String?,
    workspaceId: j['workspaceId'] as String?,
    workspaceTitle: j['workspaceTitle'] as String?,
    cwd: (j['cwd'] ?? '') as String,
    cwdAbsolute: j['cwdAbsolute'] as String?,
  );

  String get displayTitle {
    final t = title;
    if (t != null && t.isNotEmpty) return t;
    return blank ? '新对话' : '会话 $id';
  }
}

/// ChatWorkspace（openapi §ChatWorkspace）。
class DshWorkspace {
  const DshWorkspace({
    required this.id,
    required this.title,
    required this.rootId,
    required this.path,
  });

  final String id;
  final String title;
  final String rootId;
  final String path;

  factory DshWorkspace.fromJson(Map<String, dynamic> j) => DshWorkspace(
    id: (j['id'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    rootId: (j['rootId'] ?? '') as String,
    path: (j['path'] ?? '') as String,
  );
}

/// 实时推送 chat.message.delta（asyncapi §ChatMessageDelta）。
class MessageDelta {
  const MessageDelta({
    required this.sessionId,
    required this.turn,
    required this.step,
    required this.index,
    required this.kind,
    required this.text,
  });

  final String sessionId;
  final int turn;
  final int step;
  final int index;
  final String kind; // 'text' | 'reasoning'
  final String text;

  factory MessageDelta.from(Map<String, dynamic> d) => MessageDelta(
    sessionId: (d['sessionId'] ?? '') as String,
    turn: (d['turn'] ?? 0) as int,
    step: (d['step'] ?? 0) as int,
    index: (d['index'] ?? 0) as int,
    kind: (d['kind'] ?? 'text') as String,
    text: (d['text'] ?? '') as String,
  );
}

/// 实时推送 chat.message.committed（asyncapi §ChatMessageCommitted）。
class MessageCommitted {
  const MessageCommitted({
    required this.sessionId,
    required this.role,
    required this.seq,
    required this.turn,
    required this.step,
  });

  final String sessionId;
  final String role; // 'user' | 'assistant'
  final int seq;
  final int turn;
  final int step;

  factory MessageCommitted.from(Map<String, dynamic> d) => MessageCommitted(
    sessionId: (d['sessionId'] ?? '') as String,
    role: (d['role'] ?? 'assistant') as String,
    seq: (d['seq'] ?? 0) as int,
    turn: (d['turn'] ?? 0) as int,
    step: (d['step'] ?? 0) as int,
  );
}

/// 新建会话的待定工作目录（2026-11-15 反馈「新建会话可选工作目录」）。
/// 发送首条消息前可选；[rootId] 空 = 首个授权根（session-create 语义），
/// [cwd] 是授权根内相对路径（WirePath），'' = 会话目录就是根。
/// [label] 仅 UI 显示（sheet 候选组装），协议层不解释。
class SessionLocation {
  const SessionLocation({
    this.rootId,
    required this.cwd,
    required this.label,
  });

  final String? rootId;
  final String cwd;
  final String label;
}

/// file-list 应答条目（ws-files.ts handleFileList；openapi §FileEntry）。
/// [kind] ∈ file|directory|symlink|other；目录选择浏览器只消费 directory。
class DshFileEntry {
  const DshFileEntry({
    required this.name,
    required this.path,
    required this.kind,
  });

  final String name;
  final String path;
  final String kind;

  factory DshFileEntry.fromJson(Map<String, dynamic> j) => DshFileEntry(
    name: (j['name'] ?? '') as String,
    path: (j['path'] ?? '') as String,
    kind: (j['kind'] ?? 'file') as String,
  );
}

/// file-list 应答页（ws-files.ts 应答 data{rootId,...page}；openapi §DirectoryPage）。
class DshDirectoryPage {
  const DshDirectoryPage({
    required this.rootId,
    required this.path,
    required this.entries,
    this.nextCursor,
  });

  final String rootId;
  final String path;
  final List<DshFileEntry> entries;
  final String? nextCursor;

  factory DshDirectoryPage.fromJson(Map<String, dynamic> j) =>
      DshDirectoryPage(
        rootId: (j['rootId'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        nextCursor: j['nextCursor'] as String?,
        entries: (j['entries'] as List? ?? const [])
            .map(
              (e) => DshFileEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
}

