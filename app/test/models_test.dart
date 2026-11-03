// 协议模型 JSON round-trip 测试（宪法 §7：构造 → toJson → fromJson → 字段相等）。
import 'package:dshchat/bridge/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PromptPart.text round-trip', () {
    final p = PromptPart.text('你好 bridge');
    final json = p.toJson();
    expect(json, {'type': 'text', 'text': '你好 bridge'});
    // 模型只出 toJson（客户端不收 PromptPart）；重建走同构构造验证一致。
    final rebuilt = PromptPart.text(json['text'] as String);
    expect(rebuilt.toJson(), json);
  });

  test('MessageDelta.from 提取流式增量', () {
    final d = MessageDelta.from({
      'sessionId': 's1',
      'turn': 2,
      'step': 0,
      'index': 5,
      'kind': 'text',
      'text': 'Hello',
    });
    expect(d.sessionId, 's1');
    expect(d.turn, 2);
    expect(d.index, 5);
    expect(d.kind, 'text');
    expect(d.text, 'Hello');
  });

  test('MessageDelta.from 缺字段容错', () {
    final d = MessageDelta.from({});
    expect(d.sessionId, '');
    expect(d.index, 0);
    expect(d.kind, 'text');
    expect(d.text, '');
  });

  test('MessageCommitted.from round-trip', () {
    final c = MessageCommitted.from({
      'sessionId': 's1',
      'role': 'assistant',
      'seq': 9,
      'turn': 3,
      'step': 0,
    });
    expect(c.role, 'assistant');
    expect(c.seq, 9);
    expect(c.turn, 3);
  });

  test('HistoryPage.fromEvents 装配 user+assistant', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'user/message',
          'seq': 1,
          'data': {'content': 'hi'},
        },
      },
      {
        'event': {
          'type': 'assistant/message',
          'seq': 2,
          'data': {
            'content': [
              {'type': 'reasoning', 'text': 'thinking...'},
              {'type': 'text', 'text': '# Title'},
            ],
          },
        },
      },
      {
        'event': {
          'type': 'tool/message',
          'seq': 3,
          'data': {},
        },
      },
    ]);
    expect(page.items.length, 2);
    expect(page.items[0].role, 'user');
    expect(page.items[0].text, 'hi');
    expect(page.items[1].role, 'assistant');
    expect(page.items[1].reasoning, 'thinking...');
    expect(page.items[1].text, '# Title');
  });

  test('HistoryPage.fromEvents 过滤 source.kind != user 的注入上下文', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'user/message',
          'seq': 9,
          'data': {
            'content': [{'type': 'text', 'text': 'real question'}],
            'source': {'kind': 'user'},
          },
        },
      },
      {
        'event': {
          'type': 'user/message',
          'seq': 10,
          'data': {
            'content': [{'type': 'text', 'text': 'Current runtime context...'}],
            'source': {'kind': 'runtime-context', 'form': 'snapshot'},
          },
        },
      },
      {
        'event': {
          'type': 'user/message',
          'seq': 11,
          'data': {
            'content': [{'type': 'text', 'text': '<available_skills>...'}],
            'source': {'kind': 'skill-catalog', 'form': 'catalog'},
          },
        },
      },
      {
        'event': {
          'type': 'user/message',
          'seq': 12,
          'data': {
            'content': [{'type': 'text', 'text': 'Time sampled...'}],
            'source': {'kind': 'time-context', 'form': 'snapshot'},
          },
        },
      },
    ]);
    expect(page.items.length, 1);
    expect(page.items[0].text, 'real question');
  });

  test('HistoryPage.fromEvents assistant message.content 包装（内核实测形状）', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'assistant/message',
          'seq': 9,
          'data': {
            'turn': 1,
            'step': 1,
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'reasoning', 'text': 'think wrapped'},
                {'type': 'text', 'text': '## wrapped body'},
              ],
            },
          },
        },
      },
    ]);
    expect(page.items.length, 1);
    expect(page.items[0].role, 'assistant');
    expect(page.items[0].reasoning, 'think wrapped');
    expect(page.items[0].text, '## wrapped body');
  });

  test('DshSession.displayTitle 兜底', () {
    final blank = DshSession.fromJson({
      'id': 'a1', 'rootId': 'r1', 'cwd': '/x',
      'updatedAt': 0, 'running': false, 'blank': true,
    });
    expect(blank.displayTitle, '新对话');
    final titled = DshSession.fromJson({
      'id': 'a2', 'rootId': 'r1', 'cwd': '/x',
      'updatedAt': 0, 'running': false, 'blank': false, 'title': 'Demo',
    });
    expect(titled.displayTitle, 'Demo');
  });

  test('ContentParts.from 字符串与数组双形态', () {
    expect(ContentParts.from('plain').text, 'plain');
    final arr = ContentParts.from([
      {'type': 'text', 'text': 'a'},
      {'type': 'text', 'text': 'b'},
    ]);
    expect(arr.text, 'a\nb');
  });

  test('toolPhrases 按工具名给官方措辞', () {
    expect(toolPhrases('edit', null), ['修改了文件']);
    expect(toolPhrases('write', null), ['已写入文件']);
    expect(toolPhrases('read', null), ['读取了文件']);
    expect(toolPhrases('bash', null), ['执行了命令']);
    expect(toolPhrases('grep', null), ['搜索了内容']);
    expect(toolPhrases('glob', null), ['搜索了文件']);
    expect(toolPhrases('web_search', null), ['已搜索网页']);
    expect(toolPhrases('mcp__chart__render', null), ['调用了 chart · render']);
    expect(toolPhrases('some_new_tool', null), ['some_new_tool']);
  });

  test('toolPhrases run_code 扫参数组合出多短语', () {
    final phrases = toolPhrases(
      'run_code',
      '{"code":"await tools.bash(...); await tools.edit(...);"}',
    );
    expect(phrases.first, '运行了代码');
    expect(phrases, contains('执行了命令'));
    expect(phrases, contains('修改了文件'));
    // 去重：同一个 needle 出现两次也只加一遍。
    final dup = toolPhrases('run_code', 'tools.bash tools.bash');
    expect(dup.where((p) => p == '执行了命令').length, 1);
  });

  test('toolSummary 取首个有意义字段的首行', () {
    expect(toolSummary('{"file_path":"/a/b.dart","content":"x"}'), '/a/b.dart');
    expect(toolSummary('{"description":"跑测试\\n第二行"}'), '跑测试');
    expect(toolSummary('{"command":"ls -la"}'), 'ls -la');
    expect(toolSummary('not json'), isNull);
    expect(toolSummary(null), isNull);
  });

  test('过程组：空正文的 assistant 消息不劈碎工具调用', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'user/message', 'seq': 1, 'time': 1000,
          'data': {'content': 'go', 'source': {'kind': 'user'}},
        },
      },
      // 三条只含 reasoning + tool-call、没有正文的 assistant 消息。
      for (var i = 0; i < 3; i++)
        {
          'event': {
            'type': 'assistant/message', 'seq': 2 + i, 'time': 2000 + i,
            'data': {
              'message': {
                'content': [
                  {'type': 'reasoning', 'text': 'thinking'},
                  {
                    'type': 'tool-call', 'id': 'c$i', 'name': 'bash',
                    'arguments': '{"command":"ls"}',
                  },
                ],
              },
            },
          },
        },
      {
        'event': {
          'type': 'assistant/message', 'seq': 9, 'time': 3000,
          'data': {
            'message': {
              'content': [{'type': 'text', 'text': 'done'}],
            },
          },
        },
      },
    ]);
    // user + 一个过程组 + assistant 正文 = 3 项（而不是 5 项）。
    expect(page.items.length, 3);
    expect(page.items[0].role, 'user');
    expect(page.items[1].isProcess, isTrue);
    expect(page.items[1].toolCalls.length, 3);
    expect(page.items[1].phraseText, '执行了命令');
    expect(page.items[2].role, 'assistant');
    expect(page.items[2].text, 'done');
  });

  test('过程组：tool/call + tool/result 按 callId 合并并算耗时', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'tool/call', 'seq': 1, 'time': 1000,
          'data': {'callId': 'c1', 'name': 'write', 'arguments': '{"file_path":"/x.dart"}'},
        },
      },
      {
        'event': {
          'type': 'tool/result', 'seq': 2, 'time': 1500,
          'data': {
            'message': {'toolCallId': 'c1', 'isError': false},
          },
        },
      },
    ]);
    expect(page.items.length, 1);
    final g = page.items.first;
    expect(g.isProcess, isTrue);
    expect(g.toolCalls.single.phrase, '已写入文件');
    expect(g.toolCalls.single.summary, '/x.dart');
    expect(g.toolCalls.single.durationMs, 500);
    expect(g.toolCalls.single.failed, isFalse);
  });

  test('过程组：失败结果标记 failed，phraseText 去重并截断', () {
    final page = HistoryPage.fromEvents([
      for (final (i, name) in ['bash', 'bash', 'edit', 'read', 'grep'].indexed)
        {
          'event': {
            'type': 'tool/call', 'seq': i, 'time': 1000 + i,
            'data': {'callId': 'c$i', 'name': name, 'arguments': '{}'},
          },
        },
      {
        'event': {
          'type': 'tool/result', 'seq': 99, 'time': 2000,
          'data': {
            'message': {'toolCallId': 'c0', 'isError': true},
          },
        },
      },
    ]);
    final g = page.items.single;
    expect(g.toolCalls.length, 5);
    expect(g.toolCalls.first.failed, isTrue);
    // 去重后：执行了命令，修改了文件，读取了文件 … 超过 3 个加「等」。
    expect(g.phraseText, '执行了命令，修改了文件，读取了文件 等');
  });

  test('ChatMessage.durationMs 时钟倒退与缺端返回 null', () {
    expect(ChatMessage(role: 'process', text: '', startedAt: 100, finishedAt: 500).durationMs, 400);
    expect(ChatMessage(role: 'process', text: '', startedAt: 500, finishedAt: 100).durationMs, isNull);
    expect(ChatMessage(role: 'process', text: '', startedAt: 100).durationMs, isNull);
    expect(ChatMessage(role: 'process', text: '', startedAt: 100, finishedAt: 100).durationMs, isNull);
  });

  test('过程组：同一 callId 在内嵌块与独立事件里各出现一次时不重复', () {
    // 内核实测行为：assistant/message 的 content 里有 tool-call 块，
    // 同时还有一条独立的 tool/call 事件（同 callId）—— 必须只算一次。
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'assistant/message', 'seq': 1, 'time': 1000,
          'data': {
            'message': {
              'content': [
                {'type': 'reasoning', 'text': 'think'},
                {
                  'type': 'tool-call', 'id': 'call_a', 'name': 'bash',
                  'arguments': '{"description":"List dir"}',
                },
              ],
            },
          },
        },
      },
      {
        'event': {
          'type': 'tool/call', 'seq': 2, 'time': 1001,
          'data': {'callId': 'call_a', 'name': 'bash', 'arguments': '{"description":"List dir"}'},
        },
      },
      {
        'event': {
          'type': 'tool/result', 'seq': 3, 'time': 1200,
          'data': {
            'message': {'toolCallId': 'call_a', 'isError': false},
          },
        },
      },
    ]);
    final g = page.items.single;
    expect(g.toolCalls.length, 1, reason: '同一次调用只能有一条');
    expect(g.toolCalls.single.callId, 'call_a');
    expect(g.toolCalls.single.phrase, '执行了命令');
    expect(g.toolCalls.single.summary, 'List dir');
    expect(g.toolCalls.single.durationMs, 199);
  });

  test('turn/end error → role=error 消息（限流/额度失败要显示出来）', () {
    final page = HistoryPage.fromEvents([
      {
        'event': {
          'type': 'user/message', 'seq': 1, 'time': 1000,
          'data': {
            'source': {'kind': 'user'},
            'content': [{'type': 'text', 'text': 'hi'}],
          },
        },
      },
      {
        'event': {
          'type': 'turn/end', 'seq': 2, 'time': 1500,
          'data': {
            'turn': 1,
            'reason': {
              'kind': 'error',
              'error': {'message': '模型限流中', 'code': 'QUOTA_EXCEEDED'},
            },
          },
        },
      },
    ]);
    expect(page.items.length, 2);
    expect(page.items[0].role, 'user');
    expect(page.items[1].role, 'error');
    expect(page.items[1].isError, isTrue);
    expect(page.items[1].text, '模型限流中');
  });
}
