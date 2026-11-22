/// 斜杠命令与「重新生成 / 重试」（从 chat_state.dart 拆出，宪法 §7 单文件
/// ≤500 行）：只读写 ChatState 的 public 成员，UI 调用点仍走 chat_state 的
/// 同名薄转发。
library;

import '../bridge/gateway.dart'; // RequestException
import '../bridge/models.dart'; // ChatMessage
import 'chat_state.dart';

/// 执行斜杠命令：`/xxx args` 整行走 command-execute 帧，不进用户气泡。
/// 回执以本地「命令卡」（role=='command'，seq=-1）注入会话流（m03878）；
/// 重拉历史后由 chat_history_actions 的 merge 逻辑保留。
Future<void> runChatCommand(ChatState state, String line) async {
  state.lastError = null;
  // 先上屏命令卡（用户立刻看到「收到了这条命令」），再去建会话/执行——
  // 新对话里建会话有一次网络往返，等回来再出卡就成了「点了没反应」（IKX5MV）。
  final card = ChatMessage(
    role: 'command',
    text: line,
    startedAt: DateTime.now().millisecondsSinceEpoch,
  );
  state.messages = [...state.messages, card];
  state.notifyUi();
  // 新对话没有 sessionId：先 session-create 再派发，别把 `/xxx` 当正文发。
  final id = await state.ensureSessionOpen();
  if (id == null) {
    final text = state.lastError ?? '建立会话失败';
    card.text = '$line\n✗ $text，命令未执行';
    state.lastError = text;
    state.notifyUi();
    return;
  }
  try {
    final r = await state.gateway.executeCommand(sessionId: id, line: line);
    final result = r['result'];
    final kind = result is Map ? (result['kind'] ?? '') as String : '';
    if (kind == 'error') {
      final text = result is Map && result['text'] is String
          ? result['text'] as String
          : '命令执行失败';
      card.text = '$line\n✗ $text';
      state.lastError = text;
      state.notifyUi();
      return;
    }
    final detail = result is Map && result['text'] is String
        ? (result['text'] as String).trim()
        : '';
    card.text = detail.isEmpty ? '$line\n✓ 已执行' : '$line\n✓ $detail';
    // 成功的命令大多自带落盘事件（如 /model 走 session 事件）；保险起见
    // 重拉一次历史，把命令效果落到 UI。
    await state.reloadHistory();
    state.notifyUi();
  } on RequestException catch (e) {
    card.text = '$line\n✗ ${e.message}';
    state.lastError = '命令执行失败：${e.message}';
    state.notifyUi();
  }
}

/// 「重新生成」：重发指定助手消息之前（含）最后一条有正文的用户消息。
/// 协议没有 regenerate 帧，采用「重新提问」语义（对照 companion ChatRetry.kt：
/// 排除只有图片 / 空正文的用户消息）。
Future<void> regenerateChatAt(ChatState state, int index) async {
  if (state.streaming) return;
  final last = lastUserTextBefore(state.messages, index);
  if (last == null) return;
  await state.send(last);
}

/// 失败重试：重发历史里最后一条有正文的用户消息。
Future<void> retryChatLast(ChatState state) =>
    regenerateChatAt(state, state.messages.length - 1);
