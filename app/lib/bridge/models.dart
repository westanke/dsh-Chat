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
    this.agentPreset,
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

  /// 会话的 Agent 预设 id（openapi §ChatSession.agentPreset 可选；
  /// 空白会话可通过 PUT /chat/sessions/{sid}/agent-preset 切换，
  /// 首条消息后桥端锁定）。
  final String? agentPreset;

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
    agentPreset: j['agentPreset'] as String?,
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
/// kind 除 'text'|'reasoning' 外还有工具调用帧（桥 fdb85da 起，官方 preparing
/// 态数据源）：'tool-call'=参数流式生成中、'tool-call-end'=参数定稿边界；
/// 客户端契约：**未知 kind 忽略，不得当文本渲染**。
class MessageDelta {
  const MessageDelta({
    required this.sessionId,
    required this.turn,
    required this.step,
    required this.index,
    required this.kind,
    required this.text,
    this.callId,
    this.name,
    this.argumentsDelta,
    this.arguments,
  });

  final String sessionId;
  final int turn;
  final int step;
  final int index;
  final String kind; // 'text' | 'reasoning' | 'tool-call' | 'tool-call-end'
  final String text;

  /// 工具调用帧（tool-call/tool-call-end）：callId 宽容透传（首包可能缺，
  /// 续包只带 index+argumentsDelta）。
  final String? callId;
  final String? name;

  /// 参数流式增量（tool-call）；[arguments] 是 tool-call-end 的定稿参数。
  final String? argumentsDelta;
  final String? arguments;

  factory MessageDelta.from(Map<String, dynamic> d) => MessageDelta(
    sessionId: (d['sessionId'] ?? '') as String,
    turn: (d['turn'] ?? 0) as int,
    step: (d['step'] ?? 0) as int,
    index: (d['index'] ?? 0) as int,
    kind: (d['kind'] ?? 'text') as String,
    text: (d['text'] ?? '') as String,
    callId: d['callId'] is String && (d['callId'] as String).isNotEmpty
        ? d['callId'] as String
        : null,
    name: d['name'] is String && (d['name'] as String).isNotEmpty
        ? d['name'] as String
        : null,
    argumentsDelta: d['argumentsDelta'] is String ? d['argumentsDelta'] as String : null,
    arguments: d['arguments'] is String ? d['arguments'] as String : null,
  );
}

/// 实时推送 chat.tool.call：工具开始执行（参数已定稿，覆盖 preparing 行；
/// 按 callId 去重，后到帧覆盖前态）。
class ToolCallStarted {
  const ToolCallStarted({
    required this.sessionId,
    required this.callId,
    required this.name,
    this.arguments,
    this.turn = 0,
    this.step = 0,
  });

  final String sessionId;
  final String callId;
  final String name;
  final String? arguments;
  final int turn;
  final int step;

  factory ToolCallStarted.from(Map<String, dynamic> d) => ToolCallStarted(
    sessionId: (d['sessionId'] ?? '') as String,
    callId: (d['callId'] ?? d['id'] ?? '') as String,
    name: (d['name'] ?? '') as String,
    arguments: d['arguments'] is String ? d['arguments'] as String : null,
    turn: (d['turn'] ?? 0) as int,
    step: (d['step'] ?? 0) as int,
  );
}

/// 实时推送 chat.tool.result：工具结果。error.code 是**内核失败分类**
/// （不是桥的枚举）：'interrupted'=已停止、ask 工具的 'ASK_CANCELLED'=已取消，
/// 其余（含未知值）降级为失败态；exit code 不是协议字段，从结果文本尾部解析。
class ToolCallOutcome {
  const ToolCallOutcome({
    required this.sessionId,
    required this.callId,
    required this.isError,
    required this.resultText,
    this.errorCode,
    this.turn = 0,
    this.step = 0,
  });

  final String sessionId;
  final String callId;
  final bool isError;
  final String resultText;
  final String? errorCode;
  final int turn;
  final int step;

  factory ToolCallOutcome.from(Map<String, dynamic> d) {
    final message = d['message'] is Map ? d['message'] as Map<String, dynamic> : const {};
    final callId = () {
      final direct = d['callId'];
      if (direct is String && direct.isNotEmpty) return direct;
      final source = message['source'] is Map
          ? (message['source'] as Map)['callId']
          : null;
      return source is String ? source : (message['toolCallId'] ?? '') as String;
    }();
    final error = d['error'] is Map ? d['error'] as Map : const {};
    final code = error['code'];
    var result = '';
    final content = message['content'];
    if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          if (result.isNotEmpty) result += '\n';
          result += part['text'] as String;
        }
      }
    }
    return ToolCallOutcome(
      sessionId: (d['sessionId'] ?? '') as String,
      callId: callId,
      isError: message['isError'] == true,
      resultText: result,
      errorCode: code is String && code.isNotEmpty ? code : null,
      turn: (d['turn'] ?? 0) as int,
      step: (d['step'] ?? 0) as int,
    );
  }
}

/// 实时推送 chat.message.committed（asyncapi §ChatMessageCommitted）。
class MessageCommitted {
  const MessageCommitted({
    required this.sessionId,
    required this.role,
    required this.seq,
    required this.turn,
    required this.step,
    this.hasReplyContent = true,
  });

  final String sessionId;
  final String role; // 'user' | 'assistant'
  final int seq;
  final int turn;
  final int step;

  /// 这条 assistant 消息是否真有正文。桥 e08b6b5 起 committed 帧携带：
  /// 内核（dsh-agent-loop lib/index.js:941-955）会在工具执行前先提交一条
  /// 只含 tool-call 块、无 text 块的 assistant 消息（false）——客户端不能
  /// 把它当成「回答已结束」。老桥不带该字段 → 缺省 true 兼容。
  final bool hasReplyContent;

  factory MessageCommitted.from(Map<String, dynamic> d) => MessageCommitted(
    sessionId: (d['sessionId'] ?? '') as String,
    role: (d['role'] ?? 'assistant') as String,
    seq: (d['seq'] ?? 0) as int,
    turn: (d['turn'] ?? 0) as int,
    step: (d['step'] ?? 0) as int,
    hasReplyContent: d['hasReplyContent'] is bool
        ? d['hasReplyContent'] as bool
        : true,
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

/// session-waited 应答的 wait 体（DSH 0.2.2 session/wait，桥 API.md:791 /
/// openapi §waitChatSession；issue #1 适配）。
/// REST 与 WS 两通道的 wait 结构同构：
/// `{reason, state, output}` —— reason ∈ idle|input-required|timeout；
/// state 为唤醒时会话状态（cursor/active/queue/pendingInput）；
/// output 为等待期间观察到的事件（records/truncated）。
class SessionWaitResult {
  const SessionWaitResult({
    required this.reason,
    required this.state,
    required this.output,
  });

  /// 结束原因：'idle'（静止）|'input-required'（有待输入）|'timeout'。
  final String reason;

  /// 唤醒时的会话状态（cursor / active / queue / pendingInput，字段随
  /// 协议演进，宽容保留原始 map）。
  final Map<String, dynamic> state;

  /// 等待期间观察到的事件（records 事件帧数组，老→新；truncated 窗口截断）。
  final Map<String, dynamic> output;

  factory SessionWaitResult.fromJson(Map<String, dynamic> j) =>
      SessionWaitResult(
        reason: (j['reason'] ?? 'idle') as String,
        state: Map<String, dynamic>.from(j['state'] as Map? ?? const {}),
        output: Map<String, dynamic>.from(j['output'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
    'reason': reason,
    'state': state,
    'output': output,
  };
}
