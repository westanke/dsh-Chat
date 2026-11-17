/// StreamingToolBuffer / 工具实时帧模型单测（桥 fdb85da 工具帧消费）。
///
/// 覆盖：delta 增量累积与续包按 index 续行、callId 迁移、tool-call-end 定稿
/// 覆盖、chat.tool.call 覆盖 preparing、chat.tool.result 的 error.code 分派
/// （interrupted/ASK_CANCELLED 不算失败、其余含未知值失败）、MessageDelta /
/// ToolCallStarted / ToolCallOutcome 的 from 容错。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/streaming_tools.dart';

MessageDelta _delta({
  int index = 0,
  String? callId,
  String? name,
  String? delta,
}) => MessageDelta.from({
  'sessionId': 's1',
  'kind': 'tool-call',
  'index': index,
  'callId': ?callId,
  'name': ?name,
  'argumentsDelta': ?delta,
});

void main() {
  group('MessageDelta.from 工具帧字段', () {
    test('文本帧：可选工具字段缺省为 null', () {
      final d = MessageDelta.from({
        'sessionId': 's1',
        'kind': 'text',
        'text': 'hi',
        'index': 3,
      });
      expect(d.kind, 'text');
      expect(d.callId, isNull);
      expect(d.name, isNull);
      expect(d.argumentsDelta, isNull);
      expect(d.arguments, isNull);
    });

    test('tool-call 帧：callId/name/argumentsDelta 透传；空串视为缺省', () {
      final d = MessageDelta.from({
        'sessionId': 's1',
        'kind': 'tool-call',
        'index': 0,
        'callId': 'c1',
        'name': 'tools.bash',
        'argumentsDelta': '{"command"',
      });
      expect(d.callId, 'c1');
      expect(d.name, 'tools.bash');
      expect(d.argumentsDelta, '{"command"');

      final blank = MessageDelta.from({
        'sessionId': 's1',
        'kind': 'tool-call',
        'index': 0,
        'callId': '',
      });
      expect(blank.callId, isNull);
    });
  });

  group('ToolCallOutcome.from', () {
    test('content text 段拼接 + error.code 透传', () {
      final r = ToolCallOutcome.from({
        'sessionId': 's1',
        'turn': 1,
        'step': 2,
        'message': {
          'role': 'tool',
          'toolCallId': 't1',
          'isError': true,
          'source': {'kind': 'tool', 'callId': 'c1'},
          'content': [
            {'type': 'text', 'text': 'boom'},
            {'type': 'text', 'text': 'line2'},
          ],
        },
        'error': {
          'name': 'ToolOutcomeUnknownError',
          'code': 'TOOL_OUTCOME_UNKNOWN',
        },
      });
      expect(r.callId, 'c1');
      expect(r.isError, isTrue);
      expect(r.resultText, 'boom\nline2');
      expect(r.errorCode, 'TOOL_OUTCOME_UNKNOWN');
    });

    test('无 source.callId 时回退 toolCallId；无 error 帧为 null', () {
      final r = ToolCallOutcome.from({
        'sessionId': 's1',
        'message': {
          'role': 'tool',
          'toolCallId': 't9',
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
        },
      });
      expect(r.callId, 't9');
      expect(r.isError, isFalse);
      expect(r.errorCode, isNull);
    });
  });

  group('StreamingToolBuffer', () {
    test('delta 增量累积：首包带 id/name，续包只带 index 续同一行', () {
      final b = StreamingToolBuffer()
        ..handleDelta(_delta(callId: 'c1', name: 'tools.bash', delta: '{"comm'))
        ..handleDelta(_delta(delta: 'and": "ls"}'));
      final infos = b.infos;
      expect(infos, hasLength(1));
      expect(infos.single.callId, 'c1');
      expect(infos.single.name, 'tools.bash');
      expect(infos.single.rawArguments, '{"command": "ls"}');
      expect(infos.single.preparing, isTrue);
      expect(infos.single.failed, isFalse);
    });

    test('首包缺 callId 按 index 占位，callId 到达后迁移（不产生重复行）', () {
      final b = StreamingToolBuffer()
        ..handleDelta(_delta(index: 2, name: 'tools.read', delta: '{"path"'))
        ..handleDelta(_delta(index: 2, delta: ': "a"}'))
        ..handleDelta(_delta(index: 2, callId: 'c2', name: 'tools.read'));
      final infos = b.infos;
      expect(infos, hasLength(1));
      expect(infos.single.callId, 'c2');
      expect(infos.single.rawArguments, '{"path": "a"}');
    });

    test('tool-call-end：arguments 定稿覆盖累积增量', () {
      final b = StreamingToolBuffer()
        ..handleDelta(_delta(callId: 'c1', name: 'tools.write', delta: '{"fi'))
        ..handleEnd(
          MessageDelta.from({
            'sessionId': 's1',
            'kind': 'tool-call-end',
            'index': 0,
            'callId': 'c1',
            'name': 'tools.write',
            'arguments': '{"file_path": "/tmp/x", "content": "hi"}',
          }),
        );
      expect(
        b.infos.single.rawArguments,
        '{"file_path": "/tmp/x", "content": "hi"}',
      );
      expect(b.infos.single.preparing, isFalse);
    });

    test('chat.tool.call 覆盖 preparing（running，非 preparing）', () {
      final b = StreamingToolBuffer()
        ..handleDelta(
          _delta(callId: 'c1', name: 'tools.bash', delta: '{"command": "ls"}'),
        )
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'tools.bash',
            'arguments': '{"command": "ls -l"}',
          }),
        );
      expect(b.infos.single.preparing, isFalse);
      expect(b.infos.single.rawArguments, '{"command": "ls -l"}');
    });

    test('tool.result：isError → failed；interrupted → 已停止不算失败', () {
      final b = StreamingToolBuffer()
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'tools.bash',
          }),
        )
        ..handleResult(
          ToolCallOutcome.from({
            'sessionId': 's1',
            'message': {
              'role': 'tool',
              'toolCallId': 'c1',
              'isError': true,
              'content': [
                {'type': 'text', 'text': 'ls: boom\n[exit code: 2]'},
              ],
            },
          }),
        );
      expect(b.infos.single.failed, isTrue);
      expect(b.infos.single.resultText, 'ls: boom\n[exit code: 2]');

      final b2 = StreamingToolBuffer()
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'tools.bash',
          }),
        )
        ..handleResult(
          ToolCallOutcome.from({
            'sessionId': 's1',
            'message': {
              'role': 'tool',
              'toolCallId': 'c1',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
            'error': {'code': 'interrupted'},
          }),
        );
      expect(b2.infos.single.failed, isFalse);
      expect(b2.infos.single.errorCode, 'interrupted');
    });

    test('tool.result：ASK_CANCELLED 不算失败；未知 code 失败；空结果正文回 null', () {
      final b = StreamingToolBuffer()
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'ask_user_question',
          }),
        )
        ..handleResult(
          ToolCallOutcome.from({
            'sessionId': 's1',
            'message': {
              'role': 'tool',
              'toolCallId': 'c1',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
            'error': {'code': 'ASK_CANCELLED'},
          }),
        );
      expect(b.infos.single.failed, isFalse);
      expect(b.infos.single.errorCode, 'ASK_CANCELLED');
      expect(b.infos.single.resultText, isNull);

      final b2 = StreamingToolBuffer()
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c2',
            'name': 'tools.bash',
          }),
        )
        ..handleResult(
          ToolCallOutcome.from({
            'sessionId': 's1',
            'message': {
              'role': 'tool',
              'toolCallId': 'c2',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
            'error': {'code': 'TOOL_NOT_STARTED'},
          }),
        );
      expect(b2.infos.single.failed, isTrue);
    });

    test('重复 tool/call 同 callId 去重覆盖；缺 name 兜底「工具调用」', () {
      final b = StreamingToolBuffer()
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'tools.read',
          }),
        )
        ..handleCall(
          ToolCallStarted.from({
            'sessionId': 's1',
            'callId': 'c1',
            'name': 'tools.read',
          }),
        )
        // 无 callId 的结构化帧无法对应行：忽略。
        ..handleCall(
          ToolCallStarted.from({'sessionId': 's1', 'callId': '', 'name': ''}),
        );
      final infos = b.infos;
      expect(infos, hasLength(1));
      expect(infos.single.name, 'tools.read');

      final b2 = StreamingToolBuffer()
        ..handleCall(ToolCallStarted.from({'sessionId': 's1', 'callId': 'c1'}));
      expect(b2.infos.single.name, '工具调用');
    });

    test('processMessage：空缓冲 null；非空为 role=process 的合成组（seq=-2）', () {
      final b = StreamingToolBuffer();
      expect(b.processMessage, isNull);
      b.handleDelta(_delta(callId: 'c1', name: 'tools.bash', delta: '{}'));
      final group = b.processMessage!;
      expect(group.role, 'process');
      expect(group.seq, -2);
      expect(group.toolCalls, hasLength(1));
      b.clear();
      expect(b.isEmpty, isTrue);
      expect(b.processMessage, isNull);
    });
  });
  group('dropPersisted', () {
    test('命中删除、未命中保留、删后 index 映射不再找回', () {
      final b = StreamingToolBuffer()
        ..handleDelta(
          _delta(
            index: 0,
            callId: 'c1',
            name: 'tools.read',
            delta: '{"path": "a"}',
          ),
        )
        ..handleDelta(
          _delta(index: 1, callId: 'c2', name: 'tools.bash', delta: '{"comm'),
        )
        ..handleDelta(_delta(index: 1, delta: 'and": "ls"}'));
      b.dropPersisted({'c1', 'nope'});
      final infos = b.infos;
      expect(infos, hasLength(1));
      expect(infos.single.callId, 'c2');
      // c1 的行与 index 映射一并清除：同 index 续包不会找回旧行（新占位）。
      b.handleDelta(_delta(index: 0, delta: '{"x"}'));
      final after = b.infos;
      expect(after, hasLength(2));
      expect(after[0].callId, 'c2');
      expect(after[1].callId, 'idx0');
    });
  });

  group('MessageCommitted.hasReplyContent', () {
    test('缺省 true（老桥兼容）；显式 false 透传', () {
      const frame = {
        'sessionId': 's1',
        'role': 'assistant',
        'seq': 3,
        'turn': 1,
        'step': 2,
      };
      expect(MessageCommitted.from(frame).hasReplyContent, isTrue);
      expect(
        MessageCommitted.from({...frame, 'hasReplyContent': false})
            .hasReplyContent,
        isFalse,
      );
    });
  });

  group('persisted callId 判定（迟到 tool/call 帧防双份）', () {
    test('dropPersistedToolRows 刷新集合；isPersistedToolCall 判定', () {
      final state = ChatState(GatewayClient(baseUrl: 'http://127.0.0.1:1'));
      addTearDown(state.dispose);
      state
        ..sessionId = 's1'
        ..messages = [
          ChatMessage(
            role: 'process',
            text: '',
            toolCalls: const [
              ToolCallInfo(callId: 'c1', name: 'tools.read', phrases: []),
            ],
          ),
        ];
      expect(state.isPersistedToolCall('c1'), isFalse);
      state.dropPersistedToolRows();
      expect(state.isPersistedToolCall('c1'), isTrue);
      expect(state.isPersistedToolCall('c2'), isFalse);
      expect(state.isPersistedToolCall(''), isFalse);
      // 下一次 reload：messages 变化后集合整体刷新（c1 已不在持久层）。
      state.messages = const [];
      state.dropPersistedToolRows();
      expect(state.isPersistedToolCall('c1'), isFalse);
    });
  });
}
