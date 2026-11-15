/// 历史消息的拉取动作（从 chat_state.dart 拆出，宪法 §7 单文件 ≤500 行）：
/// 重拉当前会话历史 / 向上翻页加载更早消息。
///
/// 只读写 ChatState 的 public 成员（sessionId/messages/rawEvents/
/// historyHasMore/historyPageJustLoaded/oldestSeq/lastError/projections
/// 与 gateway getter），chat_state.dart 里保留同名薄转发，UI 调用点不动。
library;

import '../bridge/dlog.dart';
import '../bridge/gateway.dart'; // RequestException / HistoryPage
import 'chat_state.dart';

/// 已加载的最小 seq（下一页 beforeSeq）；-1 = 流式中的临时消息，跳过。
/// （自 chat_state.dart 挪来：只有翻页用。）
int? oldestSeqOf(ChatState state) {
  for (final m in state.messages) {
    if (m.seq >= 0) return m.seq;
  }
  return null;
}

/// 重拉当前会话历史（openSession / 事件防抖 / 命令卡 / 停止后都会调）。
Future<void> reloadChatHistory(ChatState state) async {
  final id = state.sessionId;
  if (id == null || id.isEmpty) return;
  try {
    final page = await state.gateway.history(id, maxMessages: 200);
    DshLog.w('ui history id=$id items=${page.items.length} '
        'raw=${page.rawEvents.length} '
        'projections=${page.projections != null} '
        'hasMore=${page.hasMore}');
    state.messages = page.items;
    state.rawEvents = page.rawEvents;
    state.historyHasMore = page.hasMore;
    // 命令卡保留（第六轮反馈 m03878）：reloadHistory 重建 messages，
    // 本地命令卡（role=='command'，seq=-1）会被冲掉——重灌回列表尾部。
    final cards = state.messages.where((m) => m.role == 'command').toList();
    if (cards.isNotEmpty) {
      state.messages = [...state.messages, ...cards.where((m) => m.seq < 0)];
    }
    // 翻页/刷新时 projections 可能缺席：保留上一份（同会话），避免面板闪空。
    // 切会话时 newChat()/openSession() 会先清空，不会串台。
    state.projections = page.projections ?? state.projections;
    state.notifyUi();
  } on RequestException catch (e) {
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
    state.notifyUi();
  } on RequestException catch (e) {
    state.lastError = '加载更早消息失败：${e.message}';
    state.notifyUi();
  } finally {
    state.loadingOlder = false;
    if (id == state.sessionId) state.notifyUi();
  }
}
