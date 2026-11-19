/// 刷新历史与「加载更早」的合并回归（companion PITFALLS「刷新历史把加载更早的
/// 成果抹掉」+「过期响应覆盖新上下文」）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/history_page.dart';
import 'package:dshchat/ui/chat_history_actions.dart';

ChatMessage msg(int seq, [String text = 'm']) =>
    ChatMessage(role: 'user', text: text, seq: seq);

void main() {
  test('重拉保留已翻出来的更早历史（旧页 seq 更小）并前置', () {
    final previous = [msg(1), msg(2), msg(3), msg(4)]; // 用户翻到了 1..4
    final fresh = [msg(3), msg(4), msg(5)]; // 刷新只回最后一页
    final merged = mergeRefreshedHistory(previous, fresh);
    expect(merged.messages.map((m) => m.seq), [1, 2, 3, 4, 5]);
    expect(merged.keptOlder, isTrue);
  });

  test('没翻过页时（旧内容全在新页内）原样用新页', () {
    final fresh = [msg(9), msg(10)];
    // 旧内容是新页的子集 → 没有「更早」可留，结论也不是 keptOlder
    final merged = mergeRefreshedHistory([msg(9), msg(10)], fresh);
    expect(merged.messages.length, 2);
    expect(merged.keptOlder, isFalse);

    final empty = mergeRefreshedHistory([msg(1)], []);
    expect(empty.messages, isEmpty);
    expect(empty.keptOlder, isFalse);
  });

  test('命令卡（seq=-1）不被当成「更早历史」重复前置', () {
    final card = ChatMessage(role: 'command', text: '/status', seq: -1);
    final previous = [msg(1), card];
    final merged = mergeRefreshedHistory(previous, [msg(5), msg(6)]);
    // 只有 seq=1 被前置；命令卡由 reload 自己灌回尾部，不在这里重复
    expect(merged.messages.map((m) => m.seq), [1, 5, 6]);
    expect(merged.messages.where((m) => m.role == 'command'), isEmpty);
  });

  test('rawEvents 同口径合并：保留新页首条 seq 之前的事件', () {
    final previous = [
      {'seq': 1, 'type': 'a'},
      {'seq': 2, 'type': 'b'},
    ];
    final fresh = [
      {'seq': 2, 'type': 'b'},
      {'seq': 3, 'type': 'c'},
    ];
    final merged = mergeRefreshedRawEvents(previous, fresh);
    expect(merged.map((e) => e['seq']), [1, 2, 3]);
    // 空新页 → 原样（调用方据此判断是否保留）
    expect(mergeRefreshedRawEvents(previous, []), isEmpty);
  });
}
