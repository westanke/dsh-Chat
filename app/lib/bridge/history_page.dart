/// 历史事件装配模型：从 models.dart 拆出（宪法 §7 单文件 ≤500 行；
/// models.dart 经由 export 继续暴露这些类型，既有 import 不受影响）。
///
/// 包含：SessionEvent（内核历史事件透传）/ DeliverableFile（文件卡）/
/// ChatMessage（聊天 UI 消息）/ HistoryPage（历史响应 + fromEvents 装配器）。
library;

import 'content.dart';
import 'tool_call.dart';

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
    this.thoughts = const [],
    this.startedAt,
    this.finishedAt,
  });

  final String role; // 'user' | 'assistant' | 'process' | 'error' | 'files' | 'command'
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

  /// role == 'process' 时：组内的推理段（伪工具名 `thinking`），排在工具行前面
  /// 渲染。与 [toolCalls] 分开存，是因为「工具调用次数」这类统计不该把思考算进去
  /// （dsh-go 折叠行的「N 次工具调用」只数真工具）。
  final List<ToolCallInfo> thoughts;

  /// 过程组的墙钟起止（epoch ms，可能缺一端）。
  final int? startedAt;
  final int? finishedAt;

  /// 轮的真实起止（epoch ms，装配层从 user/message（或 turn/start）与
  /// turn/end 事件带下来）。只在该轮的**最后一条**消息上填；轮尾行优先用
  /// 它算「用时」（问题 4：过程组首尾漏掉工具之间的模型思考时间）。
  int? turnStartedAt;
  int? turnFinishedAt;

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


/// 历史响应（REST 与 WS history 同源）：{events, hasMore, projections?}。
class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.hasMore,
    this.rawEvents = const [],
    this.projections,
    this.truncated = false,
    this.bytes,
    this.historyFormatVersion,
  });

  /// 已装配为 UI 消息（user/assistant/process；tool/turn 等装配进 process）。
  final List<ChatMessage> items;
  final bool hasMore;

  /// 服务端按**字节预算**裁掉了最旧端的事件（`history-byte-budget-v1`，
  /// bridge history-budget.ts：单次 2 MiB、单条事件 512 KiB）。真裁剪时
  /// 应答才带 `truncated:true` 与 `bytes`；未裁剪时这两个字段不出现。
  /// UI 必须明说「部分历史未显示」，否则用户把裁剪当成「对话丢了」。
  final bool truncated;

  /// 本次应答的字节数（仅 [truncated] 为真时由服务端给出）。
  final int? bytes;

  /// 历史事件**形状**版本（bridge `HISTORY_FORMAT_VERSION`，当前 1）。
  /// 只在 `/messages` 应答里；本轮只声明不校验，客户端记下来用于诊断。
  final int? historyFormatVersion;

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
    bool truncated = false,
    int? bytes,
    int? historyFormatVersion,
  }) {
    final items = <ChatMessage>[];
    final normalized = <Map<String, dynamic>>[];

    // 当前过程组的累积缓冲。
    final groupCalls = <ToolCallInfo>[];
    final groupThoughts = <ToolCallInfo>[];
    // 过程组的 seq：取收口前最后一条事件的 seq。历史过程组原先写死 -1，
    // 而 turnIsRunning 把 seq<0 当「流式未完成」，导致轮尾折叠行永不渲染
    // （2026-11-22 修）。
    var lastEventSeq = -1;
    final pending = <String, RawToolCall>{}; // callId → 调用信息（等 result 补全）
    int? groupStart;
    int? groupEnd;

    // 当前轮的真实起点：user/message 或 turn/start 的事件时间。轮尾行
    // 用它算「用时」，避免只用过程组首尾（问题 4）。
    int? turnStart;

    // 文件卡暂存（2026-11-14 反馈）：内核在 present 工具 result 成功的**当场**
    // 追加 deliverables/presented（dsh-tool-present/lib/index.js tools/result 分支），
    // seq 落在收尾正文之前 —— 按事件序内联插卡，卡片会卡在工具过程与收尾回复
    // 之间（「写入后的位置」）。官方 Web 端（dsh-client-ui-deliverables）把
    // deliverables 当**轮次局部**累积器，卡片挂在 turn-tail（收尾回复之后）；
    // 这里同样延迟到轮尾再上屏。轮尾判定：下一条 user/message（新一轮开始）、
    // turn/end 失败错误卡、或事件流末尾。
    final pendingFileCards = <ChatMessage>[];

    void flushGroup() {
      if (groupCalls.isEmpty && groupThoughts.isEmpty) return;
      items.add(
        ChatMessage(
          role: 'process',
          text: '',
          seq: lastEventSeq,
          toolCalls: List<ToolCallInfo>.unmodifiable(groupCalls),
          thoughts: List<ToolCallInfo>.unmodifiable(groupThoughts),
          startedAt: groupStart,
          finishedAt: groupEnd,
        ),
      );
      groupCalls.clear();
      groupThoughts.clear();
      pending.clear();
      groupStart = null;
      groupEnd = null;
    }

    void flushFileCards() {
      flushGroup(); // 先收口未闭合的过程组（轮尾的工具调用排在卡前）
      if (pendingFileCards.isEmpty) return;
      items.addAll(pendingFileCards);
      pendingFileCards.clear();
    }

    for (final e in rawEvents) {
      // REST 返回 {event:{...}} 包装；WS history 同构。容错：直接给事件体也收。
      final Map<String, dynamic> ev = e is Map && e['event'] is Map
          ? Map<String, dynamic>.from(e['event'] as Map)
          : Map<String, dynamic>.from(e as Map);
      final event = SessionEvent.fromJson(ev);
      if (event.seq >= 0) lastEventSeq = event.seq;
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
            // 新一轮开始：上一轮的文件卡挂尾（本轮之后、这条用户消息之前）。
            flushFileCards();
            turnStart = event.time;
            items.add(
              ChatMessage(
                role: 'user',
                text: parts.text,
                images: parts.images,
                seq: event.seq,
                // 记事件时间：轮用时在缺 turn/start 时靠消息首末差兜底
                // （2026-11-22 会话信息「用时」列）。
                startedAt: event.time,
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
            // 没有正文：这是「过程」，不进消息流。推理段 + 工具调用都进当前过程组
            // （dsh-go 把「思考 · …」和工具行混排在同一条折叠列表里，2026-11-22）。
            final thought = parts.reasoning.trim();
            if (thought.isNotEmpty) {
              final key = 'thought-${event.seq}';
              if (!groupThoughts.any((g) => g.callId == key)) {
                groupThoughts.add(
                  ToolCallInfo(
                    callId: key,
                    name: 'thinking',
                    phrases: const ['思考'],
                    summary: _thoughtSummary(thought),
                    resultText: thought,
                  ),
                );
              }
              groupStart ??= event.time;
              groupEnd = event.time;
            }
            // 工具调用进当前过程组。
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
              startedAt: event.time,
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
          final rawMeta = event.data['meta'];
          raw
            ..failed = failed
            ..resultText = toolResultText(msg is Map ? msg['content'] : null)
            ..meta = rawMeta is Map
                ? Map<String, dynamic>.from(rawMeta)
                : null;
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
            meta: raw.meta,
          );
          groupCalls[idx] = info;
          groupEnd = event.time;

        case 'deliverables/presented':
          // 文件卡（第四轮反馈 6）：内核 present 工具交付的文件。
          // files 原样透传 [{path, description}]；连续多个事件不合并，
          // 一事件一卡组。落位（2026-11-14 反馈）：不按事件序内联，先暂存，
          // 挂到本轮流尾（收尾回复之后）—— 见 pendingFileCards 注释。
          final rawFiles = event.data['files'];
          if (rawFiles is! List || rawFiles.isEmpty) break;
          final files = rawFiles
              .whereType<Map>()
              .map((f) => DeliverableFile.fromJson(
                  Map<String, dynamic>.from(f)))
              .where((f) => f.path.isNotEmpty)
              .toList();
          if (files.isEmpty) break;
          pendingFileCards.add(
            ChatMessage(
              role: 'files',
              text: '',
              files: List<DeliverableFile>.unmodifiable(files),
              seq: event.seq,
              startedAt: event.time,
            ),
          );

        case 'turn/start':
          turnStart = event.time;

        case 'turn/end':
          // 本轮到此结束（正常/失败都算）：文件卡挂在本轮流尾 —— 两轮之间
          // 未必有 user/message（目标续跑、子任务回合），turn/end 是唯一
          // 稳定的轮边界，必须在这里收口。
          flushFileCards();
          final turnEndTime = event.time;
          final turnStartedAt = turnStart;
          turnStart = null;
          // 一轮 turn 失败（如模型限流 / 额度耗尽）：内核只在 turn/end 的
          // reason 里给结论，没有 assistant/message 正文 —— 不解析就会表现成
          // 「用户发完消息、界面什么都没有」。官方 App 是红色错误提示，我们
          // 用同一套 role=error 消息渲染（见 ui/chat_page.dart）。
          final reason = event.data['reason'];
          if (reason is Map && reason['kind'] == 'error') {
            final err = reason['error'];
            final msg = err is Map ? (err['message'] ?? '') as String : '';
            if (msg.isNotEmpty) {
              items.add(ChatMessage(role: 'error', text: msg, seq: event.seq));
            }
          }
          // 轮的真实起止记到本轮最后一条消息上：轮尾行据此显示「用时」
          // （问题 4），不再用过程组首尾近似（会漏掉钩子/模型思考的时间）。
          if (items.isNotEmpty && turnStartedAt != null) {
            final last = items.last;
            last.turnStartedAt = turnStartedAt;
            last.turnFinishedAt = turnEndTime;
          }
      }
    }
    // 事件流末尾：最后一轮的文件卡挂尾。
    flushFileCards();
    return HistoryPage(
      items: items,
      // 真机反馈 2026-11-04 第 5 项：hasMore 由调用方从应答传入
      // （REST openapi.yaml:944-1009 / WS history 帧都带）。
      hasMore: hasMore,
      rawEvents: normalized,
      projections: projections,
      truncated: truncated,
      bytes: bytes,
      historyFormatVersion: historyFormatVersion,
    );
  }
}

/// 推理段的一行摘要：压掉换行、按 120 字截断（面板单行显示，详情里看全文）。
String _thoughtSummary(String text) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= 120) return oneLine;
  return '${oneLine.substring(0, 120)}…';
}
