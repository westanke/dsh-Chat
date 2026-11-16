/// 「收起后显示的回复」过滤纯函数（对照官方 App 通用设置 · C 项）。
///
/// 轮（turn）= 每条 user 消息到下一条 user 消息之前；首条 user 之前的消息
/// 属于「轮次之间」，始终可见。过滤规则：
/// - `FoldedReplies.all` 或流式进行中：全部可见（流式中永不过滤）；
/// - 轮运行中（轮内有未 committed 的 seq<0，或它是末轮且正在流式）：全部可见；
/// - `FoldedReplies.finalOnly` 且轮完成：只保留该轮最后一条「有正文且无
///   工具调用」的助手消息；user / files / error / command 卡与 process 组
///   （折叠行）始终可见，process 组的收起由展开态逻辑负责；轮内无合格
///   助手消息则该轮助手消息全部显示（不猜）。
library;

import '../bridge/history_page.dart';
import '../design/app_settings.dart';

/// 一个轮次在消息列表里的下标区间：[start, end)，end 为 exclusive。
class TurnRange {
  const TurnRange(this.start, this.end);

  /// 轮内首条（user 消息）下标，包含。
  final int start;

  /// 轮尾下标（exclusive）：下一条 user 消息的下标，或列表末尾。
  final int end;

  bool contains(int index) => index >= start && index < end;
}

/// 划分轮次：每条 user 消息开启一轮，到下一条 user 消息前结束。
/// 首条 user 之前的前导段不构成轮（返回区间不覆盖它）。
List<TurnRange> turnsOf(List<ChatMessage> messages) {
  final turns = <TurnRange>[];
  var start = -1;
  for (var i = 0; i < messages.length; i++) {
    if (messages[i].role != 'user') continue;
    if (start >= 0) turns.add(TurnRange(start, i));
    start = i;
  }
  if (start >= 0) turns.add(TurnRange(start, messages.length));
  return turns;
}

/// 最后一轮（最后一条 user 到列表末尾）；没有任何 user 消息时返回 null。
TurnRange? lastTurnOf(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role == 'user') return TurnRange(i, messages.length);
  }
  return null;
}

/// 轮是否仍在运行：轮内有未 committed（seq<0）的消息，或它是末轮且正在流式。
bool turnIsRunning(List<ChatMessage> messages, TurnRange turn, bool streaming) {
  for (var i = turn.start; i < turn.end; i++) {
    if (messages[i].seq < 0) return true;
  }
  return streaming && turn.end >= messages.length;
}

/// 轮内应保留的「最终回答」助手消息下标：最后一条正文非空且无工具调用的；
/// 没有合格消息时返回 null（调用方回退为该轮助手消息全显示）。
int? finalReplyIndexOf(List<ChatMessage> messages, TurnRange turn) {
  int? keep;
  for (var i = turn.start; i < turn.end; i++) {
    final m = messages[i];
    if (m.role == 'assistant' && m.text.trim().isNotEmpty && m.toolCalls.isEmpty) {
      keep = i;
    }
  }
  return keep;
}

/// 「收起后显示的回复」过滤入口：返回可见消息（保序）。
/// 返回的元素与入参是同一批对象，列表装配层用它做 contains 判断。
List<ChatMessage> visibleMessagesOf(
  List<ChatMessage> messages,
  FoldedReplies folded,
  bool streaming,
) {
  if (folded == FoldedReplies.all || streaming) return messages;
  final turns = turnsOf(messages);
  // (轮是否运行中, 应保留的最终回答下标)；运行中的轮二者都为「全可见」语义。
  final modeByTurn = <int, (bool, int?)>{};
  for (var t = 0; t < turns.length; t++) {
    final turn = turns[t];
    modeByTurn[t] = turnIsRunning(messages, turn, streaming)
        ? (true, null)
        : (false, finalReplyIndexOf(messages, turn));
  }
  var t = 0;
  final visible = <ChatMessage>[];
  for (var i = 0; i < messages.length; i++) {
    if (t >= turns.length || !turns[t].contains(i)) {
      visible.add(messages[i]); // 轮次之间：始终可见
      continue;
    }
    final m = messages[i];
    final (running, keep) = modeByTurn[t]!;
    final show = switch (m.role) {
      // 运行中或轮内无合格消息 → 助手消息全显示（不猜哪条是最终回答）。
      'assistant' => running || keep == null || keep == i,
      // process 组不在列表里隐藏：折叠行始终可见，「收起」是展开态
      // （GroupExpandState 收起时机）的事，列表过滤只管助手正文。
      'process' => true,
      _ => true, // user / files / error / command 卡始终可见
    };
    if (show) visible.add(m);
    if (i == turns[t].end - 1) t++;
  }
  return visible;
}
