/// 过程组详情辅助函数（formatDuration / bashCommandOf / prettyArguments）。
/// 口径来自安卓 app/lib/ui/process_group.dart 与 lib/bridge/tool_call.dart。
import test from 'node:test';
import assert from 'node:assert/strict';
import { formatDuration, bashCommandOf, prettyArguments } from '../../entry/src/main/ets/core/ToolCall';

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
