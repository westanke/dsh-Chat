/**
 * core/StreamTools.ts —— bridge 工具调用实时事件 → 流式工具行状态机（node 直测）。
 * 帧形状依据 dsh-remote-bridge tests/chat-adapter.spec.ts（fdb85da）。
 */

import { test } from 'node:test';
import assert from 'node:assert';

import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall';
import { MessageCommitted, MessageDelta } from '../../entry/src/main/ets/core/Models';
import {
  TOOL_STATUS_PREPARING, TOOL_STATUS_STOPPED, TOOL_STATUS_CANCELLED,
  exitBadgeOf, ExitBadge, statusFromErrorCode, rankOf, mergeLiveRow,
  StreamToolState,
} from '../../entry/src/main/ets/core/StreamTools';

// MessageDelta 全字段 readonly、ctor 吃 JsonMap——测试构造走字面量（缺键 strOr 默认 ''）。
function delta(fields: Record<string, Object>): MessageDelta {
  const base: Record<string, Object> = { sessionId: 's1', kind: 'tool-call' };
  const keys: string[] = Object.keys(fields);
  for (let i = 0; i < keys.length; i++) {
    base[keys[i]] = fields[keys[i]];
  }
  return new MessageDelta(base as Record<string, Object>);
}

function rowOf(st: StreamToolState, callId: string): ToolCallInfo | null {
  return st.findRow(callId);
}

// ---- exitBadgeOf ---------------------------------------------------------

test('exitBadgeOf：exit 0 成功 / 非 0 失败 / null 不算失败', () => {
  const ok: ExitBadge | null = exitBadgeOf('done\n[exit code: 0]');
  assert.ok(ok !== null);
  assert.equal((ok as ExitBadge).kind, 'exit');
  assert.equal((ok as ExitBadge).value, '0');
  assert.equal((ok as ExitBadge).failed, false);
  const bad: ExitBadge | null = exitBadgeOf('boom\n[exit code: 2]');
  assert.ok(bad !== null);
  assert.equal((bad as ExitBadge).failed, true);
  const none: ExitBadge | null = exitBadgeOf('clean output');
  assert.ok(none === null);
  const exitNull: ExitBadge | null = exitBadgeOf('x\n[exit code: null]');
  assert.ok(exitNull !== null);
  assert.equal((exitNull as ExitBadge).value, 'null');
  assert.equal((exitNull as ExitBadge).failed, false);
});

test('exitBadgeOf：killed by signal 恒 failed；负数 exit code 失败', () => {
  const sig: ExitBadge | null = exitBadgeOf('terminated\n[killed by signal: SIGKILL]');
  assert.ok(sig !== null);
  assert.equal((sig as ExitBadge).kind, 'signal');
  assert.equal((sig as ExitBadge).value, 'SIGKILL');
  assert.equal((sig as ExitBadge).failed, true);
  const neg: ExitBadge | null = exitBadgeOf('x\n[exit code: -1]');
  assert.ok(neg !== null);
  assert.equal((neg as ExitBadge).value, '-1');
  assert.equal((neg as ExitBadge).failed, true);
  const notTail: ExitBadge | null = exitBadgeOf('[exit code: 2]\nmore text');
  assert.ok(notTail === null);
});

// ---- statusFromErrorCode / rankOf ----------------------------------------

test('statusFromErrorCode：interrupted→stopped / ASK_CANCELLED→cancelled / 未知→failed / 空→空', () => {
  assert.equal(statusFromErrorCode('interrupted'), TOOL_STATUS_STOPPED);
  assert.equal(statusFromErrorCode('ASK_CANCELLED'), TOOL_STATUS_CANCELLED);
  assert.equal(statusFromErrorCode('TOOL_OUTCOME_UNKNOWN'), 'failed');
  assert.equal(statusFromErrorCode('TOOL_NOT_STARTED'), 'failed');
  assert.equal(statusFromErrorCode('some_future_code'), 'failed');
  assert.equal(statusFromErrorCode(''), '');
});

test('rankOf：终态 4 > 有结果 3 > running 2 > preparing 1', () => {
  const preparing: ToolCallInfo = new ToolCallInfo('a', 'read', [], null, false, null, null, null);
  preparing.status = TOOL_STATUS_PREPARING;
  assert.equal(rankOf(preparing), 1);
  const running: ToolCallInfo = new ToolCallInfo('b', 'bash', [], null, false, null, null, '{}');
  assert.equal(rankOf(running), 2);
  const done: ToolCallInfo = new ToolCallInfo('c', 'bash', [], null, false, null, 'ok', '{}');
  assert.equal(rankOf(done), 3);
  const failed: ToolCallInfo = new ToolCallInfo('d', 'bash', [], null, true, null, 'err', '{}');
  assert.equal(rankOf(failed), 4);
  const stopped: ToolCallInfo = new ToolCallInfo('e', 'bash', [], null, false, null, null, '{}');
  stopped.status = TOOL_STATUS_STOPPED;
  assert.equal(rankOf(stopped), 4);
});

// ---- delta / end / call / result -----------------------------------------

test('applyDelta：建 preparing 行，argumentsDelta 增量拼接', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 0, callId: 'c1', name: 'bash', argumentsDelta: '{"comm' }));
  assert.equal(st.rows.length, 1);
  const first: ToolCallInfo | null = rowOf(st, 'c1');
  assert.ok(first !== null);
  assert.equal((first as ToolCallInfo).name, 'bash');
  assert.equal((first as ToolCallInfo).rawArguments, '{"comm');
  assert.equal((first as ToolCallInfo).status, TOOL_STATUS_PREPARING);
  st.applyDelta(delta({ index: 0, callId: 'c1', argumentsDelta: 'and": "ls"}' }));
  assert.equal((first as ToolCallInfo).rawArguments, '{"command": "ls"}');
});

test('applyDelta：缺 name 先「工具调用」占位；真实 callId 首现收编占位行（idx 键消失）', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 3, callId: '', argumentsDelta: '{"path":' }));
  const anonymous: ToolCallInfo | null = rowOf(st, 'idx3');
  assert.ok(anonymous !== null);
  assert.equal((anonymous as ToolCallInfo).name, '工具调用');
  assert.equal((anonymous as ToolCallInfo).status, TOOL_STATUS_PREPARING);
  // 真实 callId 首现：占位行改键迁移（同一个对象继续累计），旧 idx3 键消失。
  st.applyDelta(delta({ index: 3, callId: 'real-id', name: 'read', argumentsDelta: '"a"}' }));
  assert.equal(st.rows.length, 1);
  assert.ok(rowOf(st, 'idx3') === null);
  const named: ToolCallInfo | null = rowOf(st, 'real-id');
  assert.ok(named !== null);
  assert.equal((named as ToolCallInfo).name, 'read');
  assert.equal((named as ToolCallInfo).rawArguments, '{"path":"a"}');
});

test('applyDelta：迁移后续包只带 index 仍命中同一行（不新增行、不丢增量）', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 3, callId: '', argumentsDelta: '{"path":' }));
  st.applyDelta(delta({ index: 3, callId: 'real-id', name: 'read', argumentsDelta: '"a"}' }));
  // 续包无 callId：经 index→callId 映射找回已迁移行。
  st.applyDelta(delta({ index: 3, callId: '', argumentsDelta: ', "tail": 1}' }));
  assert.equal(st.rows.length, 1);
  const row: ToolCallInfo | null = rowOf(st, 'real-id');
  assert.ok(row !== null);
  // 增量按帧顺序拼接（语义正确性由服务端定稿 arguments 兜底，这里只验拼接）。
  assert.equal((row as ToolCallInfo).rawArguments, '{"path":"a"}, "tail": 1}');
});

test('applyEnd：arguments 定稿覆盖；行不存在直接建行', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 0, callId: 'c1', name: 'bash', argumentsDelta: '{"co' }));
  st.applyEnd(delta({ index: 0, callId: 'c1', name: 'bash', arguments: '{"command": "ls"}' }));
  const r: ToolCallInfo | null = rowOf(st, 'c1');
  assert.ok(r !== null);
  assert.equal((r as ToolCallInfo).rawArguments, '{"command": "ls"}');
  const fresh: StreamToolState = new StreamToolState();
  fresh.applyEnd(delta({ index: 1, callId: 'c2', name: 'grep', arguments: '{"pattern": "x"}' }));
  const f: ToolCallInfo | null = rowOf(fresh, 'c2');
  assert.ok(f !== null);
  assert.equal((f as ToolCallInfo).name, 'grep');
  assert.equal((f as ToolCallInfo).status, TOOL_STATUS_PREPARING);
});

test('applyCall：running 覆盖（清 preparing 标记）；缺 callId 忽略', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 0, callId: 'c1', name: 'bash', argumentsDelta: '{"co' }));
  st.applyCall('c1', 'bash', '{"command": "ls -l"}');
  const r: ToolCallInfo | null = rowOf(st, 'c1');
  assert.ok(r !== null);
  assert.equal((r as ToolCallInfo).status, '');
  assert.equal((r as ToolCallInfo).rawArguments, '{"command": "ls -l"}');
  const none: StreamToolState = new StreamToolState();
  none.applyCall('', 'bash', '{}');
  assert.equal(none.rows.length, 0);
});

test('applyResult：done/failed/stopped/cancelled 四路 + 行不存在也建行', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyResult('c1', false, 'hello', '');
  const done: ToolCallInfo | null = rowOf(st, 'c1');
  assert.ok(done !== null);
  assert.equal((done as ToolCallInfo).resultText, 'hello');
  assert.equal((done as ToolCallInfo).failed, false);
  st.applyResult('c1', true, '[exit code: 2] boom', 'TOOL_OUTCOME_UNKNOWN');
  assert.equal((done as ToolCallInfo).failed, true);
  const stopped: StreamToolState = new StreamToolState();
  stopped.applyResult('c2', true, '', 'interrupted');
  const s: ToolCallInfo | null = rowOf(stopped, 'c2');
  assert.ok(s !== null);
  assert.equal((s as ToolCallInfo).status, TOOL_STATUS_STOPPED);
  assert.equal((s as ToolCallInfo).failed, false);
  const cancelled: StreamToolState = new StreamToolState();
  cancelled.applyResult('c3', true, '', 'ASK_CANCELLED');
  const c: ToolCallInfo | null = rowOf(cancelled, 'c3');
  assert.ok(c !== null);
  assert.equal((c as ToolCallInfo).status, TOOL_STATUS_CANCELLED);
  assert.equal((c as ToolCallInfo).failed, false);
});

// ---- mergeLiveRow --------------------------------------------------------

test('mergeLiveRow：live 等级低于持久不降级，完整数据就地覆盖', () => {
  const target: ToolCallInfo = new ToolCallInfo('c1', 'bash', [], null, false, null, '[exit code: 0] ok', '{"command": "ls"}');
  const stalePreparing: ToolCallInfo = new ToolCallInfo('c1', 'bash', [], null, false, null, null, '{"co');
  stalePreparing.status = TOOL_STATUS_PREPARING;
  assert.equal(mergeLiveRow(target, stalePreparing), false);
  assert.equal(target.resultText, '[exit code: 0] ok');
  const newer: ToolCallInfo = new ToolCallInfo('c1', 'bash', [], null, true, null, 'boom', '{}');
  assert.equal(mergeLiveRow(target, newer), true);
  assert.equal(target.failed, true);
  assert.equal(target.resultText, 'boom');
});

// ---- dropPersisted（reload 后已被持久过程组覆盖的行移出缓冲）--------------

test('dropPersisted：callId 命中删除，未命中保留', () => {
  const st: StreamToolState = new StreamToolState();
  st.applyDelta(delta({ index: 0, callId: 'a1', name: 'read', argumentsDelta: '{"p":"a"}' }));
  st.applyDelta(delta({ index: 1, callId: 'a2', name: 'bash', argumentsDelta: '{"c":"ls"}' }));
  assert.equal(st.rows.length, 2);
  st.dropPersisted(new Set<string>(['a1', 'zzz']));
  assert.equal(st.rows.length, 1);
  assert.ok(rowOf(st, 'a1') === null);
  assert.ok(rowOf(st, 'a2') !== null);
});

test('dropPersisted：删后同 index 续包不再复用已删 callId（映射同步失效）', () => {
  const st: StreamToolState = new StreamToolState();
  // 首包占位行 idx0 → 真实 callId 迁移并记 index→callId 映射。
  st.applyDelta(delta({ index: 0, argumentsDelta: '{"p":"a"}' }));
  st.applyDelta(delta({ index: 0, callId: 'c1', name: 'read', argumentsDelta: '' }));
  assert.ok(rowOf(st, 'c1') !== null);
  st.dropPersisted(new Set<string>(['c1']));
  assert.ok(rowOf(st, 'c1') === null);
  // 同 index 只带 argumentsDelta 的续包：映射已失效 → 重建 idx0 占位行，不再命中 c1。
  st.applyDelta(delta({ index: 0, argumentsDelta: ', "tail": 1}' }));
  assert.equal(st.rows.length, 1);
  assert.ok(rowOf(st, 'c1') === null);
  assert.ok(rowOf(st, 'idx0') !== null);
  const row: ToolCallInfo = rowOf(st, 'idx0') as ToolCallInfo;
  assert.equal(row.callId, 'idx0');
});

test('MessageCommitted：hasReplyContent 缺省 true（老桥兼容）/ false 透传', () => {
  const legacy: MessageCommitted = MessageCommitted.fromJson(
    { sessionId: 's1', role: 'assistant', seq: 1, turn: 1, step: 0 } as Record<string, Object>);
  assert.equal(legacy.hasReplyContent, true);
  const settled: MessageCommitted = MessageCommitted.fromJson(
    { sessionId: 's1', role: 'assistant', hasReplyContent: false } as Record<string, Object>);
  assert.equal(settled.hasReplyContent, false);
});
