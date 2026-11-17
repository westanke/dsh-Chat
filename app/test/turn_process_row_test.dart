/// turn_process_row.dart 纯函数单测（官方 TurnProcessNodeView 对照）：
/// formatRunDuration（zh 单位拼接）与 turnEndInfoOf（轮内聚合/展开态/
/// error 卡/无过程轮）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/turn_process_row.dart';
import 'package:dshchat/ui/work_steps.dart';

ChatMessage _user(int seq) => ChatMessage(role: 'user', text: '问', seq: seq);

ChatMessage _process(
  int seq, {
  String callId = 'c1',
  int? startedAt,
  int? finishedAt,
}) => ChatMessage(
  role: 'process',
  text: '',
  seq: seq,
  startedAt: startedAt,
  finishedAt: finishedAt,
  toolCalls: [
    ToolCallInfo(callId: callId, name: 'bash', phrases: ['执行了命令']),
  ],
);

void main() {
  group('formatRunDuration', () {
    test('不足一分钟只出秒', () {
      expect(formatRunDuration(5000), '5秒');
      expect(formatRunDuration(0), '0秒');
      expect(formatRunDuration(-1), '0秒');
    });
    test('满一分钟出分+秒', () {
      expect(formatRunDuration(62000), '1分2秒');
      expect(formatRunDuration(60000), '1分0秒');
    });
    test('满一小时出小时+分+秒', () {
      expect(formatRunDuration(3723000), '1小时2分3秒');
      expect(formatRunDuration(3600000), '1小时0分0秒');
    });
  });

  group('turnEndInfoOf', () {
    test('轮内无过程组 → null（轮尾行不渲染）', () {
      final messages = [
        _user(1),
        ChatMessage(role: 'assistant', text: '答', seq: 2),
      ];
      expect(
        turnEndInfoOf(
          messages,
          const TurnRange(0, 2),
          canCollapse: true,
          isGroupExpanded: (_) => false,
        ),
        isNull,
      );
    });
    test('两端时间齐全 → 用时段；缺端 → 已完成', () {
      final messages = [
        _user(1),
        _process(2, startedAt: 1000, finishedAt: 3000),
      ];
      final info = turnEndInfoOf(
        messages,
        const TurnRange(0, 2),
        canCollapse: true,
        isGroupExpanded: (_) => false,
      )!;
      expect(info.hasProcess, isTrue);
      expect(info.durationMs, 2000);
      expect(info.label, '已完成，用时 2秒');
      expect(info.canCollapse, isTrue);
      expect(info.expanded, isFalse);

      final oneSided = [_user(1), _process(2, startedAt: 1000)];
      expect(
        turnEndInfoOf(
          oneSided,
          const TurnRange(0, 2),
          canCollapse: true,
          isGroupExpanded: (_) => false,
        )!.label,
        '已完成',
      );
    });
    test('轮内 error 卡 → 处理失败；canCollapse=false 透传', () {
      final messages = [
        _user(1),
        _process(2),
        ChatMessage(role: 'error', text: 'boom', seq: 3),
      ];
      final info = turnEndInfoOf(
        messages,
        const TurnRange(0, 3),
        canCollapse: false,
        isGroupExpanded: (_) => false,
      )!;
      expect(info.error, isTrue);
      expect(info.label, '处理失败');
      expect(info.canCollapse, isFalse);
    });
    test('展开态按组 key 聚合（首个 callId）', () {
      final messages = [
        _user(1),
        _process(2, callId: 'a'),
        _process(3, callId: 'b'),
      ];
      final info = turnEndInfoOf(
        messages,
        const TurnRange(0, 3),
        canCollapse: true,
        isGroupExpanded: (key) => key == 'a',
      )!;
      expect(info.expanded, isTrue);
    });
  });
}
