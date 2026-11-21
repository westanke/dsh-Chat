/**
 * TurnCards 挂载规则测试：只挂在该轮最后一条 assistant、且轮已闭合、且两卡非空。
 * 口径对齐安卓 app/lib/ui/turn_changes.dart + chat_rows.dart 的轮尾行。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { turnCardsOf } from '../../entry/src/main/ets/core/TurnCards.ts';
import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { JsonMap } from '../../entry/src/main/ets/core/JsonAccess.ts';

function mapOf(text: string): JsonMap {
  return JSON.parse(text) as JsonMap;
}

function user(seq: number, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'user';
  m.seq = seq;
  m.text = text;
  return m;
}

function proc(seq: number, calls: ToolCallInfo[]): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'process';
  m.seq = seq;
  m.toolCalls = calls;
  return m;
}

function call(name: string, args: string, meta: JsonMap | null = null): ToolCallInfo {
  return new ToolCallInfo('c-' + name, name, [], null, false, null, null, args, meta);
}

function assistant(seq: number, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'assistant';
  m.seq = seq;
  m.text = text;
  return m;
}

const EDIT_META: JsonMap = mapOf(JSON.stringify({
  diffs: [{ path: '/w/a.ts', oldText: 'a', newText: 'b' }],
}));

test('闭合轮最后一条 assistant：改动卡挂上，anchorSeq=user.seq', () => {
  const msgs: ChatMessage[] = [
    user(1, '改一下'), proc(2, [call('edit', '', EDIT_META)]), assistant(3, '改好了'),
  ];
  const cards = turnCardsOf(msgs, 2, false);
  assert.ok(cards !== null);
  assert.equal(cards!.hasChanges(), true);
  assert.equal(cards!.changes!.anchorSeq, 1);
  assert.equal(cards!.hasArtifacts(), false);
});

test('同轮中间 assistant 不出卡', () => {
  const msgs: ChatMessage[] = [
    user(1, 'x'), proc(2, [call('edit', '', EDIT_META)]), assistant(3, '中间'),
    assistant(4, '最终'),
  ];
  assert.equal(turnCardsOf(msgs, 2, false), null);
  assert.ok(turnCardsOf(msgs, 3, false) !== null);
});

test('轮还在跑（列表尾、isTurnRunning=true）不出卡', () => {
  const msgs: ChatMessage[] = [
    user(1, 'x'), proc(2, [call('edit', '', EDIT_META)]), assistant(3, '写'),
  ];
  assert.equal(turnCardsOf(msgs, 2, true), null);
});

test('生成文件卡：write 新建文件进入 artifacts', () => {
  const meta: JsonMap = mapOf(JSON.stringify({
    path: '/w/out.md', diffs: [{ path: '/w/out.md', oldText: '', newText: '# hi' }],
  }));
  const msgs: ChatMessage[] = [
    user(1, '写个 md'), proc(2, [call('write', '{"file_path":"/w/out.md","content":"# hi"}', meta)]),
    assistant(3, '已生成 [out.md](out.md)'),
  ];
  const cards = turnCardsOf(msgs, 2, false);
  assert.ok(cards !== null);
  assert.equal(cards!.hasArtifacts(), true);
  assert.equal(cards!.artifacts[0].path, '/w/out.md');
});

test('两卡都空的闭合轮返回 null', () => {
  const msgs: ChatMessage[] = [user(1, '聊'), assistant(2, '好')];
  assert.equal(turnCardsOf(msgs, 1, false), null);
});

test('index 越界或非 assistant 返回 null', () => {
  const msgs: ChatMessage[] = [user(1, 'x'), assistant(2, 'y')];
  assert.equal(turnCardsOf(msgs, -1, false), null);
  assert.equal(turnCardsOf(msgs, 9, false), null);
  assert.equal(turnCardsOf(msgs, 0, false), null);
});
