/**
 * WorkSteps 通用设置纯逻辑测试 —— 轮分组 / 可见性过滤 / 展开组 key。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  parseWorkStepsDetail, parseCollapseTiming, parseFoldedReplies,
  turnsOf, lastTurnOf, visibleMessagesOf, processGroupKey, groupKeysOfTurn,
  lastTurnGroupKeys,
} from '../../entry/src/main/ets/core/WorkSteps.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall.ts';

function msg(role: string, text: string, seq: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = role;
  m.text = text;
  m.seq = seq;
  return m;
}

/** 过程组消息：单工具调用（rawArguments 为 JSON 字符串）。 */
function proc(seq: number, callId: string, name: string, rawArguments: string | null): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'process';
  m.seq = seq;
  m.toolCalls = [new ToolCallInfo(callId, name, [], null, false, null, null, rawArguments)];
  return m;
}

function files(seq: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'files';
  m.seq = seq;
  return m;
}

test('偏好解析：合法值原样，未知/空回退默认', () => {
  assert.equal(parseWorkStepsDetail('concise'), 'concise');
  assert.equal(parseWorkStepsDetail('verbose'), 'verbose');
  assert.equal(parseWorkStepsDetail('wat'), 'detailed');
  assert.equal(parseWorkStepsDetail(null), 'detailed');
  assert.equal(parseCollapseTiming('next-input'), 'next-input');
  assert.equal(parseCollapseTiming('nope'), 'completion');
  assert.equal(parseFoldedReplies('final'), 'final');
  assert.equal(parseFoldedReplies(''), 'all');
});

test('turnsOf：每条 user 起轮至下一条 user 前', () => {
  const msgs: ChatMessage[] = [
    msg('user', '第一问', 1),
    proc(2, 'c1', 'bash', null),
    msg('assistant', '第一答', 3),
    msg('user', '第二问', 4),
    msg('assistant', '第二答', 5),
  ];
  const turns: ChatMessage[][] = turnsOf(msgs);
  assert.equal(turns.length, 2);
  assert.equal(turns[0].length, 3);
  assert.equal(turns[1].length, 2);
  assert.equal(lastTurnOf(msgs).length, 2);
  // 空历史 → 空轮。
  assert.equal(turnsOf([]).length, 0);
  assert.deepEqual(lastTurnOf([]), []);
});

test('visibleMessagesOf all 档：原样返回', () => {
  const msgs: ChatMessage[] = [msg('user', 'q', 1), msg('assistant', 'a1', 2), msg('assistant', 'a2', 3)];
  assert.equal(visibleMessagesOf(msgs, 'all', false), msgs);
});

test('final 档：已完成轮只留最后一条合格 assistant 正文', () => {
  const msgs: ChatMessage[] = [
    msg('user', 'q', 1),
    proc(2, 'c1', 'bash', null),
    msg('assistant', '草稿一', 3),
    files(4),
    msg('assistant', '最终回答', 5),
  ];
  const out: ChatMessage[] = visibleMessagesOf(msgs, 'final', false);
  // 保留：user / 过程组 / files / final 正文；隐藏：中间 assistant 草稿。
  assert.equal(out.length, 4);
  assert.equal(out[0].text, 'q');
  assert.equal(out[1].isProcess, true);
  assert.equal(out[2].role, 'files');
  assert.equal(out[3].text, '最终回答');
});

test('final 档：带工具调用的 assistant 正文不算 final 候选', () => {
  const withTools: ChatMessage = msg('assistant', '带工具的正文', 3);
  withTools.toolCalls = [new ToolCallInfo('c9', 'bash', [], null, false, null, null, null)];
  const msgs: ChatMessage[] = [
    msg('user', 'q', 1),
    withTools,
    msg('assistant', '干净正文', 4),
  ];
  const out: ChatMessage[] = visibleMessagesOf(msgs, 'final', false);
  assert.equal(out.length, 2);
  assert.equal(out[0].text, 'q');
  assert.equal(out[1].text, '干净正文');
});

test('final 档：运行中轮全部可见（流式 / 乐观 seq<0 / isTurnRunning）', () => {
  const streamingMsg: ChatMessage = msg('assistant', '流式中', 3);
  streamingMsg.streaming = true;
  const optimistic: ChatMessage = msg('user', '刚发的', -1);
  const msgsA: ChatMessage[] = [msg('user', 'q', 1), streamingMsg];
  assert.equal(visibleMessagesOf(msgsA, 'final', false).length, 2);
  const msgsB: ChatMessage[] = [msg('user', '旧问', 1), msg('assistant', '旧答', 2), optimistic];
  assert.equal(visibleMessagesOf(msgsB, 'final', false).length, 3);
  // isTurnRunning 兜底（会话级 streaming）。
  const msgsC: ChatMessage[] = [msg('user', 'q', 1), msg('assistant', 'a1', 2), msg('assistant', 'a2', 3)];
  assert.equal(visibleMessagesOf(msgsC, 'final', true).length, 3);
});

test('final 档：轮内无合格 assistant 消息则整轮保留', () => {
  const msgs: ChatMessage[] = [
    msg('user', 'q', 1),
    proc(2, 'c1', 'bash', null),
    msg('error', '出错了', 3),
  ];
  assert.equal(visibleMessagesOf(msgs, 'final', false).length, 3);
  // 全空轮（纯错误）也不隐藏。
  const errs: ChatMessage[] = [msg('error', '仅错误', 1)];
  assert.equal(visibleMessagesOf(errs, 'final', false).length, 1);
});

test('processGroupKey：组内首个 callId，无 callId 用 seq 前缀', () => {
  assert.equal(processGroupKey(proc(7, 'call-abc', 'bash', null)), 'call-abc');
  const noId: ChatMessage = new ChatMessage();
  noId.role = 'process';
  noId.seq = 12;
  assert.equal(processGroupKey(noId), 'seq12');
});

test('groupKeysOfTurn / lastTurnGroupKeys：只收过程组', () => {
  const msgs: ChatMessage[] = [
    msg('user', 'q1', 1),
    proc(2, 'c1', 'bash', null),
    msg('assistant', 'a1', 3),
    msg('user', 'q2', 4),
    proc(5, 'c2', 'edit', null),
    proc(6, '', 'glob', null),
  ];
  assert.deepEqual(groupKeysOfTurn(turnsOf(msgs)[0]), ['c1']);
  assert.deepEqual(lastTurnGroupKeys(msgs), ['c2', 'seq6']);
});
