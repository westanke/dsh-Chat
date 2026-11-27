/// 会话队列动作（从 chat_state.dart 拆出，宪法 §7 ≤500 行）：
/// bridge `mobile-queue-v1` 的读快照、撤回 / 改插话 / 改写。
/// 协议事实见 `bridge/queue.dart` 文件头（IKX2AE）。
library;

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/queue.dart';
import 'chat_state.dart';

/// 拉队列快照（`session-queues`）：未协商能力位时不发帧（老桥回
/// UNKNOWN_TYPE，整块 UI 也隐藏）。
Future<void> loadChatQueue(ChatState state) async {
  final id = state.sessionId;
  if (id == null || !state.queueSupported) return;
  try {
    applyChatQueue(state, await state.gateway.fetchQueue(id));
  } on RequestException catch (e) {
    DshLog.w('ui queue fetch failed sid=$id ${e.code}');
  }
}

/// 用服务端快照替换队列，并摘掉文本相同的本地乐观气泡——
/// 队列项由「排队」管理面板统一展示，避免同一条文字出现两份。
void applyChatQueue(ChatState state, List<QueueEntry> next) {
  state.queue = next;
  final texts = {for (final e in next) e.text.trim()}..remove('');
  if (texts.isNotEmpty) {
    state.messages = [
      for (final m in state.messages)
        if (!(m.role == 'user' && m.seq < 0 && texts.contains(m.text.trim())))
          m,
    ];
  }
  state.notifyUi();
}

/// 撤回一条排队输入（queue-update action=remove）。
Future<void> removeQueued(ChatState state, String inboxId) =>
    _queueWrite(state, inboxId, 'remove');

/// 把排队项改成下一步插话（action=steer）。
Future<void> steerQueued(ChatState state, String inboxId) =>
    _queueWrite(state, inboxId, 'steer');

/// 改写排队项文本（action=edit；带图项 resendable=false，UI 不给入口）。
Future<void> editQueued(ChatState state, String inboxId, String text) =>
    _queueWrite(state, inboxId, 'edit', text: text);

Future<void> _queueWrite(
  ChatState state,
  String inboxId,
  String action, {
  String? text,
}) async {
  final id = state.sessionId;
  if (id == null) return;
  state.lastError = null;
  try {
    final next = await state.gateway.updateQueue(
      id,
      inboxId,
      action,
      text: text,
    );
    // queue=null 表示写成功但重读失败：再发一次读帧拿快照。
    if (next != null) {
      applyChatQueue(state, next);
    } else {
      await loadChatQueue(state);
    }
  } on RequestException catch (e) {
    // QUEUE_TOO_LATE / TURN_ENDED 原样透传（桥 IKX2AE）。
    state.reportError(
      '队列操作失败',
      e,
      retry: () => _queueWrite(state, inboxId, action, text: text),
    );
    state.notifyUi();
  }
}
