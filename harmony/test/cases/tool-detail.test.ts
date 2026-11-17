/// 过程组详情辅助函数（formatDuration / bashCommandOf / prettyArguments）。
/// 口径来自安卓 app/lib/ui/process_group.dart 与 lib/bridge/tool_call.dart。
/// 官方 Web 行内摘要（searchSummaryOf/webSummaryOf/read.window/expandRest/ask.*）
/// 断言同在本文件（core/ToolDetails.ts）。
import test from 'node:test';
import assert from 'node:assert/strict';
import { formatDuration, bashCommandOf, prettyArguments, ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall';
import {
  ASK_CLOSED, ASK_PENDING, ASK_WAITING,
  askSummaryOf, expandRestLabelOf, ioInputOf, readWindowLabelOf,
  searchSummaryOf, webSummaryOf,
} from '../../entry/src/main/ets/core/ToolDetails';
import { TOOL_STATUS_CANCELLED, TOOL_STATUS_PREPARING } from '../../entry/src/main/ets/core/StreamTools';

test('formatDuration：<1s 用 ms', () => {
  assert.equal(formatDuration(0), '0ms');
  assert.equal(formatDuration(999), '999ms');
});

test('formatDuration：<1min 用 s（一位小数）', () => {
  assert.equal(formatDuration(1000), '1.0s');
  assert.equal(formatDuration(1234), '1.2s');
  assert.equal(formatDuration(59999), '60.0s');
});

test('formatDuration：>=1min 用 m+s', () => {
  assert.equal(formatDuration(60000), '1m0s');
  assert.equal(formatDuration(125000), '2m5s');
});

test('formatDuration：负值与 null 不显示（时钟倒退）', () => {
  assert.equal(formatDuration(-1), null);
  assert.equal(formatDuration(null), null);
});

test('bashCommandOf：只认 bash / tools.bash，取 command 字段首行原样', () => {
  const args = JSON.stringify({ command: 'ls -la\npwd', description: '列目录' });
  assert.equal(bashCommandOf('bash', args), 'ls -la\npwd');
  assert.equal(bashCommandOf('tools.bash', args), 'ls -la\npwd');
  assert.equal(bashCommandOf('read', args), null);
});

test('bashCommandOf：缺 command / 坏 JSON / 空串都返回 null', () => {
  assert.equal(bashCommandOf('bash', JSON.stringify({ path: 'a' })), null);
  assert.equal(bashCommandOf('bash', 'not json'), null);
  assert.equal(bashCommandOf('bash', null), null);
  assert.equal(bashCommandOf('bash', JSON.stringify({ command: '   ' })), null);
});

test('prettyArguments：逐行 k: v，超 200 字截断', () => {
  const out = prettyArguments(JSON.stringify({ a: 1, b: 'x' }));
  assert.equal(out, 'a: 1\nb: x');
  const long = prettyArguments(JSON.stringify({ s: 'a'.repeat(300) }));
  assert.ok(long !== null && long.length < 260, '超长值应截断');
  assert.ok(long !== null && long.endsWith('…'));
});

test('prettyArguments：空入参 null，坏 JSON 原样返回', () => {
  assert.equal(prettyArguments(null), null);
  assert.equal(prettyArguments('   '), null);
  assert.equal(prettyArguments('not json'), 'not json');
});

test('prettyArguments：空对象返回 null（无内容不显示参数节）', () => {
  assert.equal(prettyArguments('{}'), null);
});

// ---- 官方 Web 行内摘要（core/ToolDetails.ts，task-6） ----------------------

function call(name: string, args: string | null, result: string | null): ToolCallInfo {
  return new ToolCallInfo('c-' + Math.random().toString(36).substring(2, 8), name, [], null,
    false, null, result, args);
}

test('searchSummaryOf：grep → N 处匹配 · F 个文件（file=首个冒号前，去重）', () => {
  const result = 'src/a.ts:10: const x = 1\nsrc/a.ts:22: const y = 2\nlib/b.ts:3: export {}';
  const c = call('grep', JSON.stringify({ pattern: 'x' }), result);
  assert.equal(searchSummaryOf(c), '3 处匹配 · 2 个文件');
});

test('searchSummaryOf：glob → N 个路径', () => {
  const c = call('glob', JSON.stringify({ pattern: '*.ts' }), 'src/a.ts\nsrc/b.ts');
  assert.equal(searchSummaryOf(c), '2 个路径');
});

test('searchSummaryOf：空/空白结果 → 无结果', () => {
  assert.equal(searchSummaryOf(call('grep', '{}', null)), '无结果');
  assert.equal(searchSummaryOf(call('grep', '{}', '   \n')), '无结果');
  // 行没有 file 前缀（无冒号）→ 无结果。
  assert.equal(searchSummaryOf(call('grep', '{}', 'plain line')), '无结果');
});

test('webSummaryOf：结果首行；空 → 未找到结果', () => {
  assert.equal(webSummaryOf(call('web_search', '{}', '标题行\n正文')), '标题行');
  assert.equal(webSummaryOf(call('web_search', '{}', null)), '未找到结果');
  assert.equal(webSummaryOf(call('web_fetch', '{}', '  ')), '未找到结果');
});

test('read.window / diff.expandRest 官方文案', () => {
  assert.equal(readWindowLabelOf(8, 42), '显示 8 / 42 行');
  assert.equal(expandRestLabelOf(9), '… 其余 9 行');
});

test('askSummaryOf 六态：等待回答/已继续/已结束/已取消/N-M 已回答/兜底', () => {
  // running → 等待回答。
  assert.equal(askSummaryOf(call('ask_user_question', '{}', null), true), ASK_WAITING);
  // pending=true 且可答 → 已继续工作，仍可回答；不可答 → 已结束。
  const pending = call('ask_user_question', '{}', JSON.stringify({ pending: true }));
  assert.equal(askSummaryOf(pending, true), ASK_PENDING);
  assert.equal(askSummaryOf(pending, false), ASK_CLOSED);
  // 结果带 answers → N/M 已回答。
  const answered = call('ask_user_question', '{}',
    JSON.stringify({ answers: [{ id: 'q1', selected: ['a1'], custom: '' }, { id: 'q2', selected: [], custom: '' }] }));
  assert.equal(askSummaryOf(answered, false), '1/2 已回答');
  // ASK_CANCELLED 状态字 → 已取消。
  const cancelled = call('ask_user_question', '{}', null);
  cancelled.status = TOOL_STATUS_CANCELLED;
  assert.equal(askSummaryOf(cancelled, true), '已取消');
  // 坏 JSON/空结果 → 原 summary 兜底。
  assert.equal(askSummaryOf(call('ask_user_question', '{}', 'not json'), true), '');
});

test('ioInputOf：run_code 取 args.code；普通工具取全参 JSON', () => {
  assert.equal(ioInputOf(call('run_code', JSON.stringify({ code: '1+1' }), null)), '1+1');
  const input = ioInputOf(call('read', JSON.stringify({ path: 'a.ts' }), null));
  assert.ok(input !== null && input.includes('path'), '普通工具输入为参数 JSON');
});

test('ToolCallInfo preparing 状态透传（ToolBlock 行状态词用）', () => {
  const c = call('read', '{}', null);
  c.status = TOOL_STATUS_PREPARING;
  assert.equal(c.status, TOOL_STATUS_PREPARING);
});
