/// 会话信息面板的本地统计口径：每个数字都必须有真实来源，
/// 用时取不到真实起止时必须是 null（面板整列不显示），不能落成 0。
library;

import 'package:dshchat/bridge/history_page.dart';
import 'package:dshchat/bridge/tool_call.dart';
import 'package:dshchat/ui/session_info_stats.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallInfo _call(
  String name, {
  bool failed = false,
  Map<String, dynamic>? meta,
  String? rawArguments,
}) {
  final path = meta?['path'];
  return ToolCallInfo(
    callId: 'c-$name-$failed-$path',
    name: name,
    phrases: const <String>['工具'],
    failed: failed,
    meta: meta,
    rawArguments: rawArguments,
  );
}

void main() {
  test('空会话：0 轮 0 步 0 文件，用时没有来源（null）', () {
    final stats = sessionInfoStatsOf(const <ChatMessage>[], streaming: false);
    expect(stats.turns, 0);
    expect(stats.steps, 0);
    expect(stats.changedFiles, 0);
    expect(stats.elapsedMs, isNull);
    expect(stats.running, isFalse);
  });

  test('轮数=user 条数，步骤=工具调用条数，用时只算已完成轮', () {
    final user1 = ChatMessage(role: 'user', text: '第一问', seq: 1);
    final done = ChatMessage(
      role: 'process',
      text: '',
      seq: 3,
      toolCalls: <ToolCallInfo>[
        _call('edit', meta: <String, dynamic>{'path': 'lib/a.dart'}),
        _call('edit', failed: true, meta: <String, dynamic>{'path': 'lib/b.dart'}),
      ],
    )..turnStartedAt = 1000
     ..turnFinishedAt = 4000;
    final user2 = ChatMessage(role: 'user', text: '第二问', seq: 4);
    final live = ChatMessage(
      role: 'process',
      text: '',
      seq: -1,
      toolCalls: <ToolCallInfo>[
        _call('write', meta: <String, dynamic>{'path': 'lib/c.dart'}),
      ],
    );
    final stats = sessionInfoStatsOf(
      <ChatMessage>[user1, done, user2, live],
      streaming: true,
    );
    expect(stats.turns, 2);
    expect(stats.steps, 3);
    // failed 的不算；lib/a 与 lib/c 两条不同路径。
    expect(stats.changedFiles, 2);
    // 只有第一轮完成：4s；运行中的第二轮不计「用时」。
    expect(stats.elapsedMs, 3000);
    expect(stats.running, isTrue);
  });

  test('轮级时间戳缺失时退回过程组首尾（老数据）', () {
    final user = ChatMessage(role: 'user', text: '问', seq: 1);
    final group = ChatMessage(
      role: 'process',
      text: '',
      seq: 2,
      startedAt: 5000,
      finishedAt: 9500,
    );
    final stats = sessionInfoStatsOf(
      <ChatMessage>[user, group],
      streaming: false,
    );
    expect(stats.turns, 1);
    expect(stats.elapsedMs, 4500);
  });

  test('edit 拿不到路径时 changedFiles 为 null（宁可不显示也不写 0）', () {
    final user = ChatMessage(role: 'user', text: '问', seq: 1);
    final group = ChatMessage(
      role: 'process',
      text: '',
      seq: 2,
      toolCalls: <ToolCallInfo>[_call('edit')],
    );
    final stats = sessionInfoStatsOf(
      <ChatMessage>[user, group],
      streaming: false,
    );
    expect(stats.changedFiles, isNull);
  });

  test('edit 的路径可从 arguments 兜底（meta 缺失的桥）', () {
    final user = ChatMessage(role: 'user', text: '问', seq: 1);
    final group = ChatMessage(
      role: 'process',
      text: '',
      seq: 2,
      toolCalls: <ToolCallInfo>[
        _call('edit', rawArguments: '{"file_path":"lib/d.dart"}'),
      ],
    );
    final stats = sessionInfoStatsOf(
      <ChatMessage>[user, group],
      streaming: false,
    );
    expect(stats.changedFiles, 1);
  });
}
