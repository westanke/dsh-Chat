/**
 * HistoryPage/ToolCall 装配器测试 —— 对齐安卓 models_test.dart 的分组语义
 * + tool_call 措辞表 + 文件卡轮尾挂载 + turn/end 错误卡。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { HistoryPage, SessionEvent, DeliverableFile, ChatMessage }
  from '../../entry/src/main/ets/core/HistoryPage.ts';
import {
  ToolCallInfo, RawToolCall, toolPhrases, toolSummary, toolResultText,
  extractToolCalls,
} from '../../entry/src/main/ets/core/ToolCall.ts';

/** 造一条已剥外包装的事件。 */
function ev(type: string, seq: number, time: number, data: Record<string, unknown>): Record<string, unknown> {
  return { type, seq, time, data };
}

test('SessionEvent/DeliverableFile 宽容解析', () => {
  const e: SessionEvent = SessionEvent.fromJson({
    type: 'user/message', seq: 7, time: 100, data: { content: 'hi' },
  } as Record<string, Object>);
  assert.equal(e.type, 'user/message');
  assert.equal(e.seq, 7);
  assert.equal(e.data['content'], 'hi');

  const bad: SessionEvent = SessionEvent.fromJson(null);
  assert.equal(bad.type, '');

  const f: DeliverableFile = DeliverableFile.fromJson(
    { path: '/a/b/report.md', description: '周报' } as Record<string, Object>);
  assert.equal(f.name, 'report.md');
  assert.equal(f.description, '周报');
});

test('toolPhrases 措辞表：具名/未知名/mcp__/run_code 组合', () => {
  assert.deepEqual(toolPhrases('bash', null), ['执行了命令']);
  assert.deepEqual(toolPhrases('read_image', '{}'), ['读取了图片']);
  assert.deepEqual(toolPhrases('no_such_tool', null), ['no_such_tool']);
  assert.deepEqual(toolPhrases('', null), ['工具']);
  assert.deepEqual(toolPhrases('mcp__github__create_pr', null), ['调用了 github · create_pr']);
  assert.deepEqual(toolPhrases('run_code', '{"code":"import tools.bash; tools.bash()"}'),
    ['运行了代码', '执行了命令']);
  assert.deepEqual(toolPhrases('run_code', '{"code":"tools.grep; tools.bash"}'),
    ['运行了代码', '执行了命令', '搜索了内容']); // 表序：bash 先于 grep（安卓同序）
});

test('toolSummary：九键优先级 + 首行截断 + 坏 JSON', () => {
  assert.equal(toolSummary('{"description":"编辑主入口\\n第二行"}'), '编辑主入口');
  assert.equal(toolSummary('{"path":"/a/b.md"}'), '/a/b.md');
  assert.equal(toolSummary('{"file_path":"x.ts"}'), 'x.ts');
  assert.equal(toolSummary('not-json'), null);
  assert.equal(toolSummary('{"unknown":1}'), null);
  assert.equal(toolSummary(null), null);
  assert.equal(toolSummary('{"query":"  "}'), null);
});

test('toolResultText：字符串/数组 text 拼接/图片占位/全空', () => {
  assert.equal(toolResultText('  ok  '), 'ok');
  assert.equal(toolResultText(''), null);
  const blocks: Record<string, unknown>[] = [
    { type: 'text', text: '第一段' },
    { type: 'image' },
    { type: 'text', text: '第二段' },
  ];
  assert.equal(toolResultText(blocks as unknown as Object[]), '第一段\n第二段');
  assert.equal(toolResultText([{ type: 'image' }] as unknown as Object[]), '[图片]');
  assert.equal(toolResultText(null), null);
  assert.equal(toolResultText(42 as unknown as Object), null);
});

test('extractToolCalls：只取 tool-call 块，id 空跳过', () => {
  const content: Record<string, unknown>[] = [
    { type: 'text', text: '正文' },
    { type: 'tool-call', id: 'c1', name: 'bash', arguments: '{"command":"ls"}' },
    { type: 'tool-call', id: '', name: 'no_id' },
    { type: 'tool-call', id: 'c2', name: 'read' },
  ];
  const calls: RawToolCall[] = extractToolCalls(content as unknown as Object[]);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].callId, 'c1');
  assert.equal(calls[0].name, 'bash');
  assert.equal(extractToolCalls('text only' as unknown as Object[]).length, 0);
});

test('fromEvents：user/assistant 正文 + 注入内容过滤（source.kind）', () => {
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('user/message', 1, 100, { content: '你好', source: { kind: 'user' } }),
    ev('user/message', 2, 101, { content: 'runtime context 注入', source: { kind: 'runtime-context' } }),
    ev('assistant/message', 3, 102, { message: { content: '回复正文' } }),
  ], null, false);
  assert.equal(page.items.length, 2);
  assert.equal(page.items[0].role, 'user');
  assert.equal(page.items[0].text, '你好');
  assert.equal(page.items[1].role, 'assistant');
  assert.equal(page.items[1].text, '回复正文');
  // 归一化事件：REST 外包装剥掉
  assert.equal(page.rawEvents.length, 3);
  assert.equal(page.rawEvents[0]['seq'], 1);
});

test('fromEvents：连续工具调用合并过程组（无正文 assistant 不劈段）', () => {
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('user/message', 1, 100, { content: '干活' }),
    ev('assistant/message', 2, 110, {
      message: { content: [{ type: 'tool-call', id: 'c1', name: 'bash', arguments: '{"command":"ls"}' }] },
    }),
    ev('tool/call', 3, 120, { callId: 'c1', name: 'bash', arguments: '{"command":"ls -la"}' }),
    ev('tool/result', 4, 150, { message: { toolCallId: 'c1', content: [{ type: 'text', text: '输出' }] } }),
    ev('tool/call', 5, 160, { callId: 'c2', name: 'read', arguments: '{"path":"/a.md"}' }),
    ev('tool/result', 6, 180, { message: { toolCallId: 'c2', content: [{ type: 'text', text: '内容' }] } }),
    ev('assistant/message', 7, 200, { message: { content: '干完了' } }),
  ], null, false);
  assert.equal(page.items.length, 3);
  const group: ChatMessage = page.items[1];
  assert.equal(group.role, 'process');
  assert.equal(group.toolCalls.length, 2);
  assert.equal(group.toolCalls[0].phrase, '执行了命令');
  assert.equal(group.toolCalls[0].summary, 'ls -la');
  assert.equal(group.toolCalls[0].durationMs, 30);
  assert.equal(group.toolCalls[0].resultText, '输出');
  assert.equal(group.toolCalls[1].phrase, '读取了文件');
  assert.equal(group.startedAt, 110);
  assert.equal(group.finishedAt, 180);
  assert.equal(group.durationMs, 70);
  assert.equal(group.phraseText, '执行了命令，读取了文件');
  assert.equal(page.items[2].text, '干完了');
});

test('fromEvents：tool/call 就地升级（assistant 内嵌登记 + 独立事件补明细不重复）', () => {
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('assistant/message', 1, 100, {
      message: { content: [{ type: 'tool-call', id: 'c1', name: 'bash', arguments: null }] },
    }),
    ev('tool/call', 2, 110, { callId: 'c1', name: 'bash', arguments: '{"command":"echo hi"}' }),
  ], null, false);
  assert.equal(page.items.length, 1);
  const group: ChatMessage = page.items[0];
  assert.equal(group.toolCalls.length, 1); // 不重复追加
  assert.equal(group.toolCalls[0].summary, 'echo hi'); // 明细已升级
});

test('fromEvents：文件卡挂轮尾（deliverables 在收尾正文前，卡在正文后）', () => {
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('user/message', 1, 100, { content: '写报告' }),
    ev('tool/call', 2, 110, { callId: 'p1', name: 'present', arguments: null }),
    ev('tool/result', 3, 140, { message: { toolCallId: 'p1', content: 'ok' } }),
    ev('deliverables/presented', 4, 150, { files: [{ path: '/x/report.md', description: '报告' }] }),
    ev('assistant/message', 5, 160, { message: { content: '报告写好了' } }),
    ev('turn/end', 6, 170, { reason: { kind: 'success' } }),
  ], null, false);
  assert.equal(page.items.length, 4);
  assert.equal(page.items[0].role, 'user');
  assert.equal(page.items[1].role, 'process');
  assert.equal(page.items[2].role, 'assistant'); // 收尾正文
  assert.equal(page.items[3].role, 'files'); // 卡在轮尾
  assert.equal((page.items[3].files[0] as DeliverableFile).name, 'report.md');
});

test('fromEvents：下一轮 user/message 也收口文件卡；turn/end 失败出错误卡', () => {
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('deliverables/presented', 1, 100, { files: [{ path: '/a.md' }] }),
    ev('user/message', 2, 110, { content: '下一轮' }),
    ev('turn/end', 3, 120, { reason: { kind: 'error', error: { message: '额度耗尽' } } }),
    ev('turn/end', 4, 130, { reason: { kind: 'error', error: { message: '' } } }), // 空 message 不出卡
  ], null, false);
  assert.equal(page.items.length, 3);
  assert.equal(page.items[0].role, 'files'); // 第一轮文件卡（被 user/message 收口）
  assert.equal(page.items[1].role, 'user');
  assert.equal(page.items[2].role, 'error');
  assert.equal(page.items[2].text, '额度耗尽');
});

test('fromEvents：hasMore/projections 透传；纯图 user 上屏；空事件流', () => {
  const proj: Record<string, Object> = { asOfSeq: 9, values: {} };
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('user/message', 1, 100, {
      content: [{ type: 'image', attachment: { attachmentId: 'sha256:abc123' } }],
    }),
  ], proj, true);
  assert.equal(page.items.length, 1); // 纯图无文字也上屏
  assert.equal(page.items[0].images.length, 1);
  assert.equal(page.items[0].images[0].attachmentId, 'sha256:abc123');
  assert.equal(page.hasMore, true);
  assert.equal(page.projections, proj);

  const empty: HistoryPage = HistoryPage.fromEvents([], null, false);
  assert.equal(empty.items.length, 0);
  assert.equal(empty.rawEvents.length, 0);
});

test('截断标记（history-byte-budget-v1）：truncated/bytes/historyFormatVersion 透传', () => {
  // bridge 只在真裁剪时带 truncated 与 bytes；historyFormatVersion 恒在（当前 1）。
  const page: HistoryPage = HistoryPage.fromEvents([
    ev('user/message', 1, 100, { content: 'hi' }),
  ], null, false, true, 2097152, 1);
  assert.equal(page.truncated, true);
  assert.equal(page.bytes, 2097152);
  assert.equal(page.historyFormatVersion, 1);

  // 未裁剪：三个字段缺省（老调用点不传也不炸）
  const plain: HistoryPage = HistoryPage.fromEvents([], null, false);
  assert.equal(plain.truncated, false);
  assert.equal(plain.bytes, 0);
  assert.equal(plain.historyFormatVersion, 0);
});
