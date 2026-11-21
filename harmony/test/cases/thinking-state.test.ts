import test from 'node:test';
import assert from 'node:assert/strict';

import {
  thinkingRowStateOf, thinkingTickerText, thinkingLiveLines, THINKING_TICKER_ROWS,
} from '../../entry/src/main/ets/core/ThinkingState.ts';

test('thinkingRowStateOf：活跃态只在流式且正文未开始时成立', () => {
  const raw = '想一下\n再想一下';
  assert.equal(thinkingRowStateOf(raw, true, false).active, true);
  assert.equal(thinkingRowStateOf(raw, true, true).active, false);
  assert.equal(thinkingRowStateOf(raw, false, false).active, false);
  assert.equal(thinkingRowStateOf('', true, false).active, false);
});

test('thinkingRowStateOf：未闭合 signature 整块隐藏', () => {
  const state = thinkingRowStateOf('<signature>只写了一半', true, false);
  assert.equal(state.hidden, true);
  assert.equal(state.summary, '');
  assert.equal(state.ticker, '');
});

test('thinkingTickerText：折叠空行、去行尾空白', () => {
  const raw = '第一行  \n\n\n\n第二行';
  assert.equal(thinkingTickerText(raw), '第一行\n\n第二行');
});

test('thinkingLiveLines：只留最后三行且跳过空行', () => {
  const raw = 'a\nb\n\nc\nd\ne';
  const lines: string[] = thinkingLiveLines(raw);
  assert.deepEqual(lines, ['c', 'd', 'e']);
  assert.equal(lines.length, THINKING_TICKER_ROWS);
  assert.deepEqual(thinkingLiveLines('a\nb'), ['a', 'b']);
});

test('thinkingRowStateOf：正文开始后保留摘要', () => {
  const state = thinkingRowStateOf('第一段\n\n第二段', false, true);
  assert.equal(state.active, false);
  assert.equal(state.summary.length > 0, true);
});
