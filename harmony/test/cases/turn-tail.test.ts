/**
 * core/TurnTail.ts —— 轮尾行纯逻辑（官方 TurnProcessNodeView 口径）：
 * 闭合轮判定 / 失败判定 / 时长（过程组起止，1s 下限）/ hasContent / 组 keys /
 * durationPartsOf（formatRunDuration 逐字）/ turnTailLabel。
 */

import { test } from 'node:test';
import assert from 'node:assert';

import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage';
import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall';
import { durationPartsOf, turnTailLabel, turnTailLead, turnTailOf, DurationPart, TurnTailInfo } from '../../entry/src/main/ets/core/TurnTail';

function toolCall(callId: string): ToolCallInfo {
  return new ToolCallInfo(callId, 'bash', [], null, false, null, null, null);
}

function user(seq: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'user';
  m.seq = seq;
  m.text = 'hi';
  return m;
}

function assistant(seq: number, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'assistant';
  m.seq = seq;
  m.text = text;
  return m;
}

function process(seq: number, callId: string, start: number | null,
  end: number | null): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'process';
  m.seq = seq;
  m.toolCalls = [toolCall(callId)];
  m.startedAt = start;
  m.finishedAt = end;
  return m;
}

function error(seq: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'error';
  m.seq = seq;
  m.text = '失败';
  return m;
}

// ---- turnTailOf -----------------------------------------------------------

test('turnTailOf：非 assistant/流式中/列表尾运行中 → null', () => {
  const messages: ChatMessage[] = [user(1), assistant(2, 'a'), user(3)];
  assert.equal(turnTailOf(messages, 0, false), null);
  const streaming: ChatMessage = assistant(2, 'a');
  streaming.streaming = true;
  assert.equal(turnTailOf([user(1), streaming], 1, true), null);
  // 列表尾 assistant 且轮运行中 → null。
  const tail: ChatMessage[] = [user(1), assistant(2, 'a')];
  assert.equal(turnTailOf(tail, 1, true), null);
});

test('turnTailOf：闭合轮给 hasContent/durationMs（1s 下限）+ 组 keys', () => {
  const messages: ChatMessage[] = [
    user(1),
    process(2, 'c1', 1000, 2600),
    process(3, 'c2', 500, 2000),
    assistant(4, 'done'),
    user(5),
  ];
  const info: TurnTailInfo | null = turnTailOf(messages, 3, false);
  assert.ok(info !== null);
  assert.equal(info.closed, true);
  assert.equal(info.failed, false);
  assert.equal(info.hasContent, true);
  // min(start)=500 → max(end)=2600，span=2100（> 1000 不触下限）。
  assert.equal(info.durationMs, 2100);
  assert.deepEqual(info.groupKeys, ['c1', 'c2']);
});

test('turnTailOf：缺一端/同毫秒 → durationMs null 只给已完成；无过程 → hasContent false', () => {
  const messages: ChatMessage[] = [user(1), process(2, 'c1', 1000, null), assistant(3, 'a'), user(4)];
  const info: TurnTailInfo | null = turnTailOf(messages, 2, false);
  assert.ok(info !== null);
  assert.equal(info.durationMs, null);
  // span<=0 不算（时钟倒退/同毫秒）。
  const same: ChatMessage[] = [user(1), process(2, 'c1', 1000, 1000), assistant(3, 'a'), user(4)];
  assert.equal((turnTailOf(same, 2, false) as TurnTailInfo).durationMs, null);
  const bare: ChatMessage[] = [user(1), assistant(2, 'only text'), user(3)];
  const bareInfo: TurnTailInfo | null = turnTailOf(bare, 1, false);
  assert.ok(bareInfo !== null);
  assert.equal(bareInfo.hasContent, false);
  assert.deepEqual(bareInfo.groupKeys, []);
});

test('turnTailOf：轮内 error 消息 → failed（处理失败）', () => {
  // 轮尾锚点是 assistant（turnTailOf 以 assistant 定轮）；error 在轮范围内即 failed。
  const messages: ChatMessage[] = [user(1), process(2, 'c1', 0, 5000), error(3), assistant(4, ''), user(5)];
  const info: TurnTailInfo | null = turnTailOf(messages, 3, false);
  assert.ok(info !== null);
  assert.equal(info.failed, true);
});

test('turnTailOf：列表尾轮空闲时视为闭合（本轮已结束）', () => {
  const messages: ChatMessage[] = [user(1), process(2, 'c1', 0, 3000), assistant(3, 'a')];
  const info: TurnTailInfo | null = turnTailOf(messages, 2, false);
  assert.ok(info !== null);
  assert.equal(info.closed, true);
  assert.equal(info.durationMs, 3000);
});

// ---- durationPartsOf（官方 formatRunDuration 逐字）------------------------

test('durationPartsOf：h>0→小时、total>=60→分、恒有秒；数字/单位分离', () => {
  assert.deepEqual(durationPartsOf(5000).map((p: DurationPart) => p.text), ['5', '秒']);
  assert.deepEqual(durationPartsOf(65000).map((p: DurationPart) => p.text), ['1', '分', '5', '秒']);
  assert.deepEqual(durationPartsOf(3723000).map((p: DurationPart) => p.text),
    ['1', '小时', '2', '分', '3', '秒']);
  const parts: DurationPart[] = durationPartsOf(65000);
  assert.equal(parts[0].numeric, true);
  assert.equal(parts[1].numeric, false);
  // floor：不足 1 秒按 0 秒（elapsed 下限在 turnTailOf 层做）。
  assert.deepEqual(durationPartsOf(999).map((p: DurationPart) => p.text), ['0', '秒']);
  // 整小时也带 0 分 0 秒（官方 total>=60 即给分段）。
  assert.deepEqual(durationPartsOf(3600000).map((p: DurationPart) => p.text), ['1', '小时', '0', '分', '0', '秒']);
});

// ---- turnTailLabel ---------------------------------------------------------

test('turnTailLabel：失败/无时长/带时长三态', () => {
  const failed: TurnTailInfo = new TurnTailInfo();
  failed.failed = true;
  assert.equal(turnTailLabel(failed, null), '处理失败');
  // failed 优先于时长。
  assert.equal(turnTailLabel(failed, durationPartsOf(5000)), '处理失败');
  const plain: TurnTailInfo = new TurnTailInfo();
  assert.equal(turnTailLabel(plain, null), '已完成');
  const timed: TurnTailInfo = new TurnTailInfo();
  assert.equal(turnTailLabel(timed, durationPartsOf(5000)), '已完成，用时 5秒');
  assert.equal(turnTailLabel(timed, durationPartsOf(3723000)), '已完成，用时 1小时2分3秒');
});

// ---- turnTailLead（行首前缀，时长片段按代码字体另渲染） ---------------------

test('turnTailLead：前缀不含时长文本，避免与时长片段重复', () => {
  const failed: TurnTailInfo = new TurnTailInfo();
  failed.failed = true;
  assert.equal(turnTailLead(failed, true), '处理失败');
  const plain: TurnTailInfo = new TurnTailInfo();
  assert.equal(turnTailLead(plain, false), '已完成');
  const timed: TurnTailInfo = new TurnTailInfo();
  assert.equal(turnTailLead(timed, true), '已完成，用时 ');
  // 前缀 + 片段拼起来必须等于整行文案（真机曾把时长渲染两遍）。
  const joined: string = turnTailLead(timed, true) + durationPartsOf(5000).map((p: DurationPart) => p.text).join('');
  assert.equal(joined, turnTailLabel(timed, durationPartsOf(5000)));
});
