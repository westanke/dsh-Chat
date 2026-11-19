/**
 * 刷新历史与「加载更早」的合并 —— 对齐 companion PITFALLS「刷新历史把『加载更早』
 * 的成果抹掉」与「过期响应覆盖新上下文」。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { mergeRefreshedHistory } from '../../entry/src/main/ets/core/ChatHistory.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { JsonMap } from '../../entry/src/main/ets/core/JsonAccess.ts';

function msg(seq: number, role: string = 'user'): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = role;
  m.text = 'm';
  m.seq = seq;
  return m;
}

function ev(seq: number): JsonMap {
  return { seq, type: 'user/message' } as JsonMap;
}

test('重拉保留已翻出来的更早历史并前置；hasMore 由调用方延续', () => {
  // 用户已经翻到 1..4，刷新只回最后一页 3..5
  const r: [ChatMessage[], JsonMap[], boolean] = mergeRefreshedHistory(
    [msg(1), msg(2), msg(3), msg(4)],
    [ev(1), ev(2), ev(3), ev(4)],
    [msg(3), msg(4), msg(5)],
    [ev(3), ev(4), ev(5)]);
  assert.deepEqual(r[0].map((m: ChatMessage): number => m.seq), [1, 2, 3, 4, 5]);
  assert.deepEqual(r[1].map((e: JsonMap): Object => e['seq'] as Object), [1, 2, 3, 4, 5]);
  assert.equal(r[2], true);
});

test('没翻过页（旧内容都在新页内）→ 原样用新页', () => {
  const r: [ChatMessage[], JsonMap[], boolean] = mergeRefreshedHistory(
    [msg(9), msg(10)], [ev(9), ev(10)], [msg(9), msg(10)], [ev(9), ev(10)]);
  assert.equal(r[0].length, 2);
  assert.equal(r[2], false);
});

test('命令卡（seq=-1）不当作更早历史重复前置；空新页不炸', () => {
  const card: ChatMessage = msg(-1, 'command');
  const r: [ChatMessage[], JsonMap[], boolean] = mergeRefreshedHistory(
    [msg(1), card], [ev(1)], [msg(5), msg(6)], [ev(5), ev(6)]);
  assert.deepEqual(r[0].map((m: ChatMessage): number => m.seq), [1, 5, 6]);
  assert.equal(r[0].filter((m: ChatMessage): boolean => m.role === 'command').length, 0);

  const empty: [ChatMessage[], JsonMap[], boolean] = mergeRefreshedHistory(
    [msg(1)], [ev(1)], [], []);
  assert.equal(empty[0].length, 0);
  assert.equal(empty[2], false);
});
