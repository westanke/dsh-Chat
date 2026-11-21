/**
 * 会话列表逐行变距（安卓 chat_row_gap.dart 口径）纯函数测试。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { chatRowGapBefore, RowGapValues } from '../../entry/src/main/ets/core/ChatRowGap.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';

const G: RowGapValues = new RowGapValues();

function msg(role: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = role;
  return m;
}

test('第一行不留空', () => {
  assert.equal(chatRowGapBefore(msg('user'), null, G), 0);
});

test('换轮用户消息 24', () => {
  assert.equal(chatRowGapBefore(msg('user'), msg('assistant'), G), 24);
});

test('连续用户消息 8', () => {
  assert.equal(chatRowGapBefore(msg('user'), msg('user'), G), 8);
});

test('相邻过程行 0', () => {
  assert.equal(chatRowGapBefore(msg('process'), msg('process'), G), 0);
  assert.equal(chatRowGapBefore(msg('process'), msg('command'), G), 0);
  assert.equal(chatRowGapBefore(msg('command'), msg('process'), G), 0);
});

test('文件卡 12', () => {
  assert.equal(chatRowGapBefore(msg('files'), msg('assistant'), G), 12);
});

test('其余 8', () => {
  assert.equal(chatRowGapBefore(msg('assistant'), msg('assistant'), G), 8);
  assert.equal(chatRowGapBefore(msg('error'), msg('assistant'), G), 8);
  assert.equal(chatRowGapBefore(msg('process'), msg('assistant'), G), 8);
});
