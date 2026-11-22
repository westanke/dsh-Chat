// 当前活动条（dsh-go activity_strip 移植）的纯逻辑单测。
import 'package:dshchat/bridge/history_page.dart';
import 'package:dshchat/bridge/tool_call.dart';
import 'package:dshchat/ui/activity_strip.dart';
import 'package:dshchat/ui/tool_present.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _proc({required List<ToolCallInfo> rows, int? startedAt}) =>
    ChatMessage(
      role: 'process',
      text: '',
      toolCalls: rows,
      startedAt: startedAt,
    );

void main() {
  group('liveActivityOf', () {
    test('不在生成时返回 null', () {
      expect(
        liveActivityOf(
          messages: [_proc(rows: const [])],
          streaming: false,
        ),
        isNull,
      );
    });

    test('取最后一条 live 工具作为当前活动', () {
      final a = liveActivityOf(
        messages: [
          _proc(
            rows: const [
              ToolCallInfo(callId: 'a', name: 'bash', phrases: ['运行命令']),
            ],
            startedAt: 1000,
          ),
          _proc(
            rows: const [
              ToolCallInfo(
                callId: 'b',
                name: 'bash',
                phrases: ['运行命令'],
                preparing: true,
              ),
            ],
            startedAt: 5000,
          ),
        ],
        streaming: true,
      );
      expect(a, isNotNull);
      expect(a!.since, 5000);
    });

    test('组里没有 live 调用时退化成思考中', () {
      final a = liveActivityOf(
        messages: [
          _proc(
            rows: const [
              ToolCallInfo(
                callId: 'a',
                name: 'bash',
                phrases: ['运行命令'],
                resultText: 'done',
              ),
            ],
            startedAt: 2000,
          ),
        ],
        streaming: true,
      );
      expect(a!.label, '思考中');
      expect(a.since, 2000);
      expect(a.kind, ToolActivityKind.thinking);
    });
  });

  group('LiveActivity.elapsedLabel', () {
    const a = LiveActivity(
      kind: ToolActivityKind.thinking,
      label: 'x',
      detail: null,
      since: 10000,
    );

    test('秒级补零', () {
      expect(a.elapsedLabel(10000 + 5000), '0:05');
      expect(a.elapsedLabel(10000 + 65000), '1:05');
    });

    test('超过一小时给 h:mm:ss', () {
      expect(a.elapsedLabel(10000 + 3725000), '1:02:05');
    });

    test('没有起点不给秒表', () {
      const b = LiveActivity(
        kind: ToolActivityKind.thinking,
        label: 'x',
        detail: null,
        since: null,
      );
      expect(b.elapsedLabel(1), isNull);
    });

    test('时钟倒退不显示负值', () {
      expect(a.elapsedLabel(9000), isNull);
    });
  });
}
