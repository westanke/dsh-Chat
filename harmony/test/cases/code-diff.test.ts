/**
 * CodeDiff 代码差异提取测试 —— edit/write 工具调用 → 行模型与聚合。
 * 工具名与参数键名依据 core/ToolCall.ts 措辞表与桥侧 tool/call 事件实测。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fileDiffOfCall, codeDiffsOfTurn, codeDiffsOfLastTurn,
  DIFF_LINE_ADD, DIFF_LINE_DEL, DIFF_KIND_EDIT, DIFF_KIND_WRITE,
} from '../../entry/src/main/ets/core/CodeDiff.ts';
import { ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';

function call(name: string, args: string): ToolCallInfo {
  return new ToolCallInfo('call-' + name, name, [], null, false, null, null, args);
}

function procOf(seq: number, calls: ToolCallInfo[]): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'process';
  m.seq = seq;
  m.toolCalls = calls;
  return m;
}

test('edit：old_string→del 行，new_string→add 行（del 在前）', () => {
  const diff = fileDiffOfCall(call('edit',
    '{"file_path":"a.ts","old_string":"const a = 1;\\nconst b = 2;","new_string":"const a = 3;"}'));
  assert.notEqual(diff, null);
  assert.equal(diff?.path, 'a.ts');
  assert.equal(diff?.kind, DIFF_KIND_EDIT);
  assert.deepEqual(diff?.lines.map((l) => l.type), [DIFF_LINE_DEL, DIFF_LINE_DEL, DIFF_LINE_ADD]);
  assert.deepEqual(diff?.lines.map((l) => l.text), ['const a = 1;', 'const b = 2;', 'const a = 3;']);
});

test('write：content 全部 add 行，空内容不产行', () => {
  const diff = fileDiffOfCall(call('write', '{"file_path":"n.md","content":"# 标题\\n正文"}'));
  assert.notEqual(diff, null);
  assert.equal(diff?.kind, DIFF_KIND_WRITE);
  assert.deepEqual(diff?.lines.map((l) => l.type), [DIFF_LINE_ADD, DIFF_LINE_ADD]);
  assert.deepEqual(diff?.lines.map((l) => l.text), ['# 标题', '正文']);
  const empty = fileDiffOfCall(call('write', '{"file_path":"n.md","content":""}'));
  assert.notEqual(empty, null);
  assert.equal(empty?.lines.length, 0);
});

test('非 edit/write 工具、坏 JSON、缺 file_path → null', () => {
  assert.equal(fileDiffOfCall(call('bash', '{"command":"ls"}')), null);
  assert.equal(fileDiffOfCall(call('read', '{"path":"x"}')), null);
  assert.equal(fileDiffOfCall(call('edit', '不是 JSON')), null);
  assert.equal(fileDiffOfCall(call('edit', '{"old_string":"a","new_string":"b"}')), null);
  assert.equal(fileDiffOfCall(call('edit', '{"file_path":"","old_string":"a"}')), null);
  assert.equal(fileDiffOfCall(call('write', '{"content":"x"}')), null);
});

test('tools.edit / tools.write 内嵌名同样识别', () => {
  assert.equal(fileDiffOfCall(call('tools.edit',
    '{"file_path":"b.ts","old_string":"x","new_string":"y"}'))?.kind, DIFF_KIND_EDIT);
  assert.equal(fileDiffOfCall(call('tools.write', '{"file_path":"b.ts","content":"y"}'))?.kind,
    DIFF_KIND_WRITE);
});

test('codeDiffsOfTurn：同 path 聚合拼接行序，跨文件保首次出现顺序', () => {
  const turn: ChatMessage[] = [
    procOf(1, [
      call('edit', '{"file_path":"a.ts","old_string":"old-a","new_string":"new-a"}'),
      call('write', '{"file_path":"b.ts","content":"b1"}'),
    ]),
    procOf(2, [
      call('edit', '{"file_path":"a.ts","old_string":"old-a2","new_string":"new-a2"}'),
      call('grep', '{"query":"zzz"}'),
    ]),
  ];
  const diffs = codeDiffsOfTurn(turn);
  assert.equal(diffs.length, 2);
  assert.deepEqual(diffs.map((d) => d.path), ['a.ts', 'b.ts']);
  // a.ts 两次 edit 行序拼接；kind 取首次（edit）。
  assert.deepEqual(diffs[0].lines.map((l) => l.text), ['old-a', 'new-a', 'old-a2', 'new-a2']);
  assert.equal(diffs[0].kind, DIFF_KIND_EDIT);
  // grep 不产出；b.ts kind=write。
  assert.equal(diffs[1].kind, DIFF_KIND_WRITE);
});

test('codeDiffsOfLastTurn：只取最后一轮', () => {
  const msgs: ChatMessage[] = [];
  const q1: ChatMessage = new ChatMessage();
  q1.role = 'user';
  q1.text = '第一问';
  msgs.push(q1);
  msgs.push(procOf(1, [call('write', '{"file_path":"old.ts","content":"旧轮"}')]));
  const a1: ChatMessage = new ChatMessage();
  a1.role = 'assistant';
  a1.text = '答一';
  msgs.push(a1);
  // 第二轮从第二条 user 起。
  const q2: ChatMessage = new ChatMessage();
  q2.role = 'user';
  q2.text = '第二问';
  msgs.push(q2);
  msgs.push(procOf(2, [call('write', '{"file_path":"new.ts","content":"新轮"}')]));
  const diffs = codeDiffsOfLastTurn(msgs);
  assert.equal(diffs.length, 1);
  assert.equal(diffs[0].path, 'new.ts');
  assert.equal(codeDiffsOfLastTurn([]).length, 0);
});

// ---------- diffLinesOf（LCS；安卓 code_diff.dart 口径） ----------

import { diffLinesOf, DiffLine, DIFF_LINE_ADD, DIFF_LINE_CTX, DIFF_LINE_DEL } from '../../entry/src/main/ets/core/CodeDiff.ts';

function kinds(lines: DiffLine[]): string[] {
  const out: string[] = [];
  for (const l of lines) {
    out.push(l.type + ':' + l.text);
  }
  return out;
}

test('diffLinesOf：中间改一行 = ctx/del/add/ctx', () => {
  assert.deepEqual(kinds(diffLinesOf('a\nb\nc', 'a\nB\nc')),
    [DIFF_LINE_CTX + ':a', DIFF_LINE_DEL + ':b', DIFF_LINE_ADD + ':B', DIFF_LINE_CTX + ':c']);
});

test('diffLinesOf：末尾换行不产空行，空原文全 add', () => {
  assert.deepEqual(kinds(diffLinesOf('', 'x\ny')), [DIFF_LINE_ADD + ':x', DIFF_LINE_ADD + ':y']);
  assert.deepEqual(kinds(diffLinesOf('a\n', 'a\nb\n')),
    [DIFF_LINE_CTX + ':a', DIFF_LINE_ADD + ':b']);
});

test('diffLinesOf：纯删除与纯新增', () => {
  assert.deepEqual(kinds(diffLinesOf('a\nb', 'a')), [DIFF_LINE_CTX + ':a', DIFF_LINE_DEL + ':b']);
  assert.deepEqual(kinds(diffLinesOf('a', 'a\nb')), [DIFF_LINE_CTX + ':a', DIFF_LINE_ADD + ':b']);
});

test('diffLinesOf：行数超阈值退回裁剪版仍只标改动行', () => {
  const oldLines: string[] = [];
  const newLines: string[] = [];
  for (let i = 0; i < 700; i++) {
    oldLines.push('l' + i);
    newLines.push(i === 350 ? 'changed' : 'l' + i);
  }
  const lines: DiffLine[] = diffLinesOf(oldLines.join('\n'), newLines.join('\n'));
  const dels: number = lines.filter((l: DiffLine): boolean => l.type === DIFF_LINE_DEL).length;
  const adds: number = lines.filter((l: DiffLine): boolean => l.type === DIFF_LINE_ADD).length;
  assert.equal(dels, 1);
  assert.equal(adds, 1);
});
