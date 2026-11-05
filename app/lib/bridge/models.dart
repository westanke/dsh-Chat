/// bridge 协议模型（显式 fromJson/toJson，宪法 §7）。
/// 形状依据 dsh-remote-bridge v2.10.0：docs/api/openapi.yaml、asyncapi.yaml、
/// docs/project/API.md 与姊妹仓 dsh-companion 的历史事件映射（ChatHistoryMapping.kt）。
library;

import 'content.dart';
import 'tool_call.dart';

export 'content.dart';
export 'tool_call.dart';

/// 内核历史事件（原样透传）。
/// SessionEvent：{type, seq, time, data}；HistoryEntry：{event, view?}。
class SessionEvent {
  const SessionEvent({
    required this.type,
    required this.seq,
    required this.time,
    required this.data,
  });

  final String type;
  final int seq;
  final int time; // epoch ms
  final Map<String, dynamic> data;

  factory SessionEvent.fromJson(Map<String, dynamic> j) => SessionEvent(
    type: (j['type'] ?? '') as String,
    seq: (j['seq'] ?? 0) as int,
    time: (j['time'] ?? 0) as int,
    data: j['data'] is Map
        ? Map<String, dynamic>.from(j['data'] as Map)
        : const {},
  );
}

/// ContentParts / ContentImageRef / PromptPart 已拆到 content.dart
/// （宪法 §7 单文件 ≤500 行），经上方 export 继续暴露。

/// 文件卡（第四轮反馈 6）：`deliverables/presented` 事件的 files 项。
/// 协议（asyncapi.yaml:391-410 / chat-adapter.ts:1575-1591）原样透传
/// path/description，无 size/mime。
class DeliverableFile {
  DeliverableFile({required this.path, this.description});

  factory DeliverableFile.fromJson(Map<String, dynamic> j) => DeliverableFile(
        path: (j['path'] ?? '') as String,
        description: j['description'] as String?,
      );

  final String path;
  final String? description;

  /// 文件名（路径最后一段），UI 主标题。
  String get name => path.split('/').last;
}

/// 聊天 UI 消息（由历史事件或实时流装配）。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.reasoning = '',
    this.images = const [],
    this.files = const [],
    this.seq = -1,
    this.streaming = false,
    this.toolCalls = const [],
    this.startedAt,
    this.finishedAt,
  });

  final String role; // 'user' | 'assistant' | 'process' | 'error' | 'files'
  String text;
  String reasoning;

  /// content 里的图片引用（历史形状：attachment 引用，无字节；真机反馈
  /// 2026-11-04 第 1 项：手机端要显示历史图片）。
  final List<ContentImageRef> images;

  /// role == 'files' 时：本组交付文件（文件卡，第四轮反馈 6）。
  final List<DeliverableFile> files;
  int seq; // -1 = 尚未 committed（流式中的临时消息）
  bool streaming;

  /// role == 'process' 时：本组内的工具调用（按时间顺序）。
  final List<ToolCallInfo> toolCalls;

  /// 过程组的墙钟起止（epoch ms，可能缺一端）。
  final int? startedAt;
  final int? finishedAt;

  bool get isUser => role == 'user';
  bool get isProcess => role == 'process';
  bool get isError => role == 'error';

  /// 组头耗时（毫秒）；两端齐全且为正才算，否则 null（时钟倒退/同毫秒不算）。
  int? get durationMs {
    final s = startedAt;
    final e = finishedAt;
    if (s == null || e == null) return null;
    final span = e - s;
    return span > 0 ? span : null;
  }

  /// 组头短语：去重后按出现顺序取前三个，用「，」连接。
  String get phraseText {
    final out = <String>[];
    for (final t in toolCalls) {
      for (final p in t.phrases) {
        if (!out.contains(p)) out.add(p);
      }
    }
    if (out.isEmpty) return '思考中';
    final head = out.take(3).join('，');
    return out.length > 3 ? '$head 等' : head;
  }
}

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

  factory DshSession.fromJson(Map<String, dynamic> j) => DshSession(
    id: (j['id'] ?? '') as String,
    rootId: (j['rootId'] ?? '') as String,
    updatedAt: (j['updatedAt'] ?? 0) as int,
    running: (j['running'] ?? false) as bool,
    blank: (j['blank'] ?? false) as bool,
    title: j['title'] as String?,
    workspaceId: j['workspaceId'] as String?,
    workspaceTitle: j['workspaceTitle'] as String?,
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

/// 历史响应（REST 与 WS history 同源）：{events, hasMore, projections?}。
class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.hasMore,
    this.rawEvents = const [],
    this.projections,
  });

  /// 已装配为 UI 消息（user/assistant/process；tool/turn 等装配进 process）。
  final List<ChatMessage> items;
  final bool hasMore;

  /// 原始事件（已剥掉 REST `{event:...}` 外包装，保留 `{type,seq,time,data}`）。
  /// 轨迹 Sheet 由客户端本地分组用，不参与消息流装配（对照 companion
  /// `Trajectory.kt:98-127`：只读 `entry.event`，不读 view）。
  final List<Map<String, dynamic>> rawEvents;

  /// 服务端算好的投影（团队 / TODO / 权限 / token 等）。**可选**：内核没给基线时
  /// 整个字段缺席（不是空对象），且只在 history 首屏应答带、翻页不带
  /// （bridge `docs/project/API.md:165,766`）。UI 必须容忍 null/缺席，不能把
  /// 「读不到投影」当成「没有这个功能」（v2.2.44 真机踩过）。
  /// 形状：`{asOfSeq?, kind?, values: {...}}`。
  final Map<String, dynamic>? projections;

  /// 从 REST events / WS history 的 events 数组装配。
  ///
  /// content 位置实测（bridge v2.10 内核透传）：user/message 在 data.content，
  /// assistant/message 在 data.message.content（turn/step/message 包裹）——两处都兜底。
  ///
  /// 分组规则（对齐官方 App 观感）：
  /// 1. 一条 `assistant/message` 里只有 reasoning/tool-call、没有正文 → 不算消息，
  ///    把它的工具调用塞进「当前过程组」（否则连续工具调用会被零高度空消息劈成几十段）；
  /// 2. 相邻的 `tool/call` + `tool/result` 按 callId 合并进同一个过程组；
  /// 3. 出现真正有正文的 assistant 消息时，先把当前过程组 flush 掉，再追加正文消息；
  /// 4. 过程组内只有 1 次工具调用时照样产出一组，折不折由 UI 决定（官方折叠态同理）。
  factory HistoryPage.fromEvents(
    List<dynamic> rawEvents, {
    Map<String, dynamic>? projections,
    bool hasMore = false,
  }) {
    final items = <ChatMessage>[];
    final normalized = <Map<String, dynamic>>[];

    // 当前过程组的累积缓冲。
    final groupCalls = <ToolCallInfo>[];
    final pending = <String, RawToolCall>{}; // callId → 调用信息（等 result 补全）
    int? groupStart;
    int? groupEnd;

    void flushGroup() {
      if (groupCalls.isEmpty) return;
      items.add(
        ChatMessage(
          role: 'process',
          text: '',
          seq: -1,
          toolCalls: List<ToolCallInfo>.unmodifiable(groupCalls),
          startedAt: groupStart,
          finishedAt: groupEnd,
        ),
      );
      groupCalls.clear();
      pending.clear();
      groupStart = null;
      groupEnd = null;
    }

    for (final e in rawEvents) {
      // REST 返回 {event:{...}} 包装；WS history 同构。容错：直接给事件体也收。
      final Map<String, dynamic> ev = e is Map && e['event'] is Map
          ? Map<String, dynamic>.from(e['event'] as Map)
          : Map<String, dynamic>.from(e as Map);
      final event = SessionEvent.fromJson(ev);
      // 保留归一化后的原始事件（剥掉 REST 外包装），轨迹 Sheet 用它分组。
      // data 用 SessionEvent.fromJson 已做过的 Map<String,dynamic> 转换结果。
      normalized.add(<String, dynamic>{
        'type': event.type,
        'seq': event.seq,
        'time': event.time,
        'data': event.data,
      });
      final content = () {
        final inner = event.data['message'];
        if (inner is Map && inner['content'] != null) return inner['content'];
        return event.data['content'];
      }();

      switch (event.type) {
        case 'user/message':
          // 只显示真实用户输入。DSH 会把 runtime-context / skill-catalog /
          // time-context 等注入内容也记成 user/message（data.source.kind 区分），
          // 官方 App 一律不显示 —— 我们也过滤掉，否则每条回复前都被巨长上下文淹没。
          final src = event.data['source'];
          final kind = src is Map ? src['kind'] : null;
          if (kind != null && kind != 'user') break;
          final parts = ContentParts.from(content);
          // 纯图无文字也要上屏（真机反馈 2026-11-04 第 1 项）。
          if (parts.text.isNotEmpty || parts.images.isNotEmpty) {
            flushGroup();
            items.add(
              ChatMessage(
                role: 'user',
                text: parts.text,
                images: parts.images,
                seq: event.seq,
              ),
            );
          }

        case 'assistant/message':
          // 一条 assistant/message 可能同时含正文与工具调用（content 数组混排）。
          final parts = ContentParts.from(content);
          final calls = extractToolCalls(content);
          if (parts.text.isEmpty && parts.reasoning.isEmpty && calls.isEmpty) {
            break;
          }
          if (parts.text.isEmpty) {
            // 没有正文：这是「过程」，不进消息流。工具调用进当前过程组。
            //
            // 注意去重：内核对同一次调用会**发两遍** —— 一次内嵌在
            // assistant/message 的 content 里（type=tool-call），一次是独立的
            // `tool/call` 事件（带 callId + arguments）。以独立事件为准，
            // 这里只记「有调用发生」，明细等 tool/call 事件补全。
            for (final c in calls) {
              pending[c.callId] = c;
              if (!groupCalls.any((g) => g.callId == c.callId)) {
                groupCalls.add(c.toInfo());
              }
              groupStart ??= event.time;
              groupEnd = event.time;
            }
            break;
          }
          flushGroup();
          items.add(
            ChatMessage(
              role: 'assistant',
              text: parts.text,
              reasoning: parts.reasoning,
              seq: event.seq,
            ),
          );

        case 'tool/call':
          final name = (event.data['name'] ?? '') as String;
          final args = event.data['arguments'] as String?;
          final callId = (event.data['callId'] ?? '') as String;
          if (callId.isEmpty) break;
          final raw = RawToolCall(
            callId: callId,
            name: name,
            arguments: args,
            time: event.time,
          );
          pending[callId] = raw;
          // 同一 callId 可能已被 assistant/message 内嵌块登记过 → 就地升级明细，
          // 不重复追加（否则展开后会看到两条一模一样的调用）。
          final dup = groupCalls.indexWhere((g) => g.callId == callId);
          if (dup >= 0) {
            groupCalls[dup] = raw.toInfo();
          } else {
            groupCalls.add(raw.toInfo());
          }
          groupStart ??= event.time;
          groupEnd = event.time;

        case 'tool/result':
          final msg = event.data['message'];
          final callId =
              (msg is Map
                      ? (msg['toolCallId'] ??
                            (msg['source'] is Map
                                ? (msg['source'] as Map)['callId']
                                : null))
                      : null)
                  as String?;
          if (callId == null || callId.isEmpty) break;
          final raw = pending[callId];
          if (raw == null) break;
          final idx = groupCalls.indexWhere((c) => c.callId == callId);
          if (idx < 0) break;
          final failed = (msg is Map && msg['isError'] == true);
          raw
            ..failed = failed
            ..resultText = toolResultText(msg is Map ? msg['content'] : null);
          final info = ToolCallInfo(
            callId: callId,
            name: raw.name,
            phrases: toolPhrases(raw.name, raw.arguments),
            summary: toolSummary(raw.arguments),
            failed: failed,
            durationMs: event.time - raw.time > 0
                ? event.time - raw.time
                : null,
            resultText: raw.resultText,
            rawArguments: raw.arguments,
          );
          groupCalls[idx] = info;
          groupEnd = event.time;

        case 'deliverables/presented':
          // 文件卡（第四轮反馈 6）：内核 present 工具交付的文件。
          // files 原样透传 [{path, description}]；连续多个事件不合并，
          // 一事件一卡组（与官方 App 一致）。
          final rawFiles = event.data['files'];
          if (rawFiles is! List || rawFiles.isEmpty) break;
          final files = rawFiles
              .whereType<Map>()
              .map((f) => DeliverableFile.fromJson(
                  Map<String, dynamic>.from(f)))
              .where((f) => f.path.isNotEmpty)
              .toList();
          if (files.isEmpty) break;
          flushGroup();
          items.add(
            ChatMessage(
              role: 'files',
              text: '',
              files: List<DeliverableFile>.unmodifiable(files),
              seq: event.seq,
              startedAt: event.time,
            ),
          );

        case 'turn/end':
          // 一轮 turn 失败（如模型限流 / 额度耗尽）：内核只在 turn/end 的
          // reason 里给结论，没有 assistant/message 正文 —— 不解析就会表现成
          // 「用户发完消息、界面什么都没有」。官方 App 是红色错误提示，我们
          // 用同一套 role=error 消息渲染（见 ui/chat_page.dart）。
          final reason = event.data['reason'];
          if (reason is! Map || reason['kind'] != 'error') break;
          final err = reason['error'];
          final msg = err is Map ? (err['message'] ?? '') as String : '';
          if (msg.isEmpty) break;
          flushGroup();
          items.add(ChatMessage(role: 'error', text: msg, seq: event.seq));
      }
    }
    flushGroup();
    return HistoryPage(
      items: items,
      // 真机反馈 2026-11-04 第 5 项：hasMore 由调用方从应答传入
      // （REST openapi.yaml:944-1009 / WS history 帧都带）。
      hasMore: hasMore,
      rawEvents: normalized,
      projections: projections,
    );
  }
}
