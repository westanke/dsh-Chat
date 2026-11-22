/// 历史消息的拉取动作（从 chat_state.dart 拆出，宪法 §7 单文件 ≤500 行）：
/// 重拉当前会话历史 / 向上翻页加载更早消息。
///
/// 只读写 ChatState 的 public 成员（sessionId/messages/rawEvents/
/// historyHasMore/historyPageJustLoaded/oldestSeq/lastError/projections
/// 与 gateway getter），chat_state.dart 里保留同名薄转发，UI 调用点不动。
library;

import '../bridge/dlog.dart';
import '../bridge/gateway.dart'; // RequestException / HistoryPage
import '../bridge/models.dart';
import 'chat_state.dart';

/// 已加载的最小 seq（下一页 beforeSeq）；-1 = 流式中的临时消息，跳过。
/// （自 chat_state.dart 挪来：只有翻页用。）
int? oldestSeqOf(ChatState state) {
  for (final m in state.messages) {
    if (m.seq >= 0) return m.seq;
  }
  return null;
}

/// 刷新结果与「已翻出来的更早历史」合并（companion PITFALLS「刷新历史把『加载更早』
/// 的成果抹掉」）：重拉拿到的是**最后一页**，整体替换会把用户翻出来的旧页冲掉，
/// 视口停在原像素偏移上就变成一片空白。
///
/// 规则：保留新页第一条 seq **之前**的历史（旧页 seq 一定更小，不重叠）并前置，
/// 旧页结论延续（更早的确实还没读完）；新页为空或没有 seq 时原样返回新页。
({List<ChatMessage> messages, bool keptOlder}) mergeRefreshedHistory(
  List<ChatMessage> previous,
  List<ChatMessage> fresh,
) {
  // 本地已上屏、服务端还没回显的用户消息（seq<0，排队/插话都算）不能因为一次
  // 刷新丢掉：否则「排队中」气泡刚出现就被流式期间的重拉冲掉（真机 2026-11-21）。
  // 服务端回显同文本后就不再保留本地副本，避免同一句出现两次。
  final pending = previous
      .where((m) => m.role == 'user' && m.seq < 0)
      .where((p) => !fresh.any((m) => m.role == 'user' && m.text == p.text))
      .toList();
  final firstSeq = fresh.where((m) => m.seq >= 0).isEmpty
      ? null
      : fresh.firstWhere((m) => m.seq >= 0).seq;
  if (firstSeq == null) return (messages: [...fresh, ...pending], keptOlder: false);
  final older = previous.where((m) => m.seq >= 0 && m.seq < firstSeq).toList();
  if (older.isEmpty) {
    return (messages: [...fresh, ...pending], keptOlder: false);
  }
  return (messages: [...older, ...fresh, ...pending], keptOlder: true);
}

/// 原始事件同口径合并（轨迹面板依赖它，旧页事件不能丢）。
List<Map<String, dynamic>> mergeRefreshedRawEvents(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> fresh,
) {
  final firstSeq = fresh.isEmpty ? null : _seqOf(fresh.first);
  if (firstSeq == null) return fresh;
  final older = previous
      .where((e) => (_seqOf(e) ?? -1) >= 0 && _seqOf(e)! < firstSeq)
      .toList();
  return older.isEmpty ? fresh : [...older, ...fresh];
}

int? _seqOf(Map<String, dynamic> event) {
  final v = event['seq'];
  return v is int ? v : null;
}

/// 重拉当前会话历史（openSession / 事件防抖 / 命令卡 / 停止后都会调）。
Future<void> reloadChatHistory(ChatState state) async {
  final id = state.sessionId;
  if (id == null || id.isEmpty) return;
  try {
    // 首屏页从 200 降到 80（2026-11-23 真机：隧道模式下「打开会话很慢 / 加载历史超时」）。
    //
    // 200 条消息序列化后是 602 KB 级的大帧，过 quick tunnel 要好几秒；80 条把首屏压到
    // 约 1/3，配上桥侧的 permessage-deflate（约 19.5%）与隧道 90s 超时，打开会话不再卡在
    // 「等一个大帧」上。往下翻仍然一次 200 条（`loadOlderMessages`），滚动体验不变。
    final page = await state.gateway.history(id, maxMessages: 80);
    if (id != state.sessionId) return; // 过期应答：期间切了会话，整块丢弃
    DshLog.w('ui history id=$id items=${page.items.length} '
        'raw=${page.rawEvents.length} '
        'projections=${page.projections != null} '
        'hasMore=${page.hasMore} truncated=${page.truncated}');
    // 命令卡保留（第六轮反馈 m03878 / IKX5MV）：reloadHistory 重建 messages，
    // 本地命令卡（role=='command'，seq=-1）不在服务端历史里，merge 会把它丢掉。
    // 必须在 merge **之前**收集（以前放在 merge 之后取，永远拿到空表）。
    final cards =
        state.messages.where((m) => m.role == 'command' && m.seq < 0).toList();
    final merged = mergeRefreshedHistory(state.messages, page.items);
    state.messages = [...merged.messages, ...cards];
    // 去重：持久过程组已含这些工具，按 callId 从流式缓冲摘除对应行
    // （缓冲空后 streamingProcess 为 null，页面上只剩持久组）。
    state.dropPersistedToolRows();
    state.rawEvents = mergeRefreshedRawEvents(state.rawEvents, page.rawEvents);
    // 旧页还在 → 延续旧结论（更早的确实还没读完），别被「最后一页没更多」覆盖。
    state.historyHasMore = merged.keptOlder ? state.historyHasMore : page.hasMore;
    // 字节预算裁剪：只有真裁剪时服务端才带 truncated（未裁剪时字段缺席）。
    state.historyTruncated = page.truncated;
    // 命令卡保留（第六轮反馈 m03878）：已在上方 merge 前收集并拼回尾部。
    // 翻页/刷新时 projections 可能缺席：保留上一份（同会话），避免面板闪空。
    // 切会话时 newChat()/openSession() 会先清空，不会串台。
    state.projections = page.projections ?? state.projections;
    // 重连后重拉成功 → 把上一次的「加载历史失败」红条撤掉。
    // （2026-11-21 工单 1：此前成功路径不清 lastError，重连后红条一直挂着，
    // 用户看到的就是「连接正常却提示加载历史失败」。）
    if (state.lastError?.startsWith('加载历史失败') ?? false) {
      state.lastError = null;
    }
    state.notifyUi();
  } on RequestException catch (e) {
    // 断链本身不是「加载失败」：顶栏已有连接态，重连成功会自动重拉。
    // 不写错误条，避免把一次自动可恢复的抖动报成红字（2026-11-21 工单 1）。
    if (e.code == 'NOT_CONNECTED') {
      DshLog.w('ui history deferred (disconnected): ${e.message}');
      return;
    }
    state.lastError = '加载历史失败：${e.message}';
    state.notifyUi();
  }
}

/// 向上翻页加载更早消息（真机反馈 2026-11-04 第 5 项）：
/// beforeSeq = 当前已加载的最小 seq，返回的更早事件 prepend 到头部并按
/// seq 去重（防刷新窗口内重叠）。翻页应答不带 projections（API.md:766）。
///
/// 真机反馈 2026-11-04 第二轮 A：翻页成功置 historyPageJustLoaded 标记，
/// 列表层（chat_message_list.dart）据此跳过一次贴底跟随——否则用户点
/// 按钮时 _wantsBottom 仍为 true，prepend 后 maxScrollExtent 暴涨触发
/// followBottom，视觉上「新消息被冲走」。
Future<void> loadOlderMessages(ChatState state) async {
  final id = state.sessionId;
  if (id == null ||
      id.isEmpty ||
      state.loadingOlder ||
      !state.historyHasMore) {
    return;
  }
  final before = oldestSeqOf(state);
  if (before == null || before <= 0) return;
  state.loadingOlder = true;
  state.notifyUi();
  try {
    final page = await state.gateway.history(
      id,
      maxMessages: 200,
      beforeSeq: before,
    );
    DshLog.w('ui history-older id=$id before=$before '
        'items=${page.items.length} hasMore=${page.hasMore}');
    if (id != state.sessionId) return; // 翻页期间切了会话：丢弃
    final known = state.messages
        .where((m) => m.seq >= 0)
        .map((m) => m.seq)
        .toSet();
    final fresh = page.items
        .where((m) => m.seq < 0 || !known.contains(m.seq))
        .toList();
    if (fresh.isNotEmpty) {
      state.messages = [...fresh, ...state.messages];
      state.rawEvents = [...page.rawEvents, ...state.rawEvents];
      state.historyPageJustLoaded = true;
    }
    state.historyHasMore = page.hasMore;
    // 翻页也应答 truncated（从最旧端丢）：合并进同一个提示位，不覆盖。
    if (page.truncated) state.historyTruncated = true;
    state.notifyUi();
  } on RequestException catch (e) {
    state.lastError = '加载更早消息失败：${e.message}';
    state.notifyUi();
  } finally {
    state.loadingOlder = false;
    if (id == state.sessionId) state.notifyUi();
  }
}
