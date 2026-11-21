/**
 * TurnChanges 本轮改动 / 本轮生成文件测试。
 * 数据依据安卓 app/lib/ui/turn_changes.dart 与桥 tool/result.meta 实测。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  turnChangesOf, turnArtifactsOf, artifactKindOf, artifactKindLabel,
  bareToolName, fileNameOf, dirNameOf, markdownRefs, resolveRef,
  ARTIFACT_IMAGE, ARTIFACT_TEXT,
} from '../../entry/src/main/ets/core/TurnChanges.ts';
import { DIFF_LINE_ADD, DIFF_LINE_CTX, DIFF_LINE_DEL, diffLinesOf } from '../../entry/src/main/ets/core/CodeDiff.ts';
import { RawToolCall, ToolCallInfo } from '../../entry/src/main/ets/core/ToolCall.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { JsonMap } from '../../entry/src/main/ets/core/JsonAccess.ts';

function mapOf(text: string): JsonMap {
  return JSON.parse(text) as JsonMap;
}

function call(name: string, args: string, meta: JsonMap | null = null, failed = false): ToolCallInfo {
  return new ToolCallInfo('call-1', name, [], null, failed, null, null, args, meta);
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

function assistant(seq: number, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'assistant';
  m.seq = seq;
  m.text = text;
  return m;
}

test('meta.diffs：一个文件 +2 −1，edits=1', () => {
  const meta: JsonMap = mapOf(JSON.stringify({
    path: '/w/a.ts',
    diffs: [{ path: '/w/a.ts', oldText: 'a\nb', newText: 'a\nB\nc' }],
  }));
  const changes = turnChangesOf([user(1, 'x'), proc(2, [call('edit', '', meta)])], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.anchorSeq, 1);
  assert.equal(changes.files.length, 1);
  const f = changes.files[0];
  assert.equal(f.path, '/w/a.ts');
  assert.equal(f.name(), 'a.ts');
  assert.equal(f.directory(), '/w');
  assert.equal(f.edits(), 1);
  assert.equal(f.hunks[0].index, 1);
  assert.equal(changes.added(), 2);
  assert.equal(changes.removed(), 1);
});

test('同一文件两次编辑合并，hunk 序号递增', () => {
  const m1: JsonMap = mapOf(JSON.stringify({ diffs: [{ path: '/w/a.ts', oldText: 'a', newText: 'b' }] }));
  const m2: JsonMap = mapOf(JSON.stringify({ diffs: [{ path: '/w/a.ts', oldText: 'b', newText: 'c' }] }));
  const changes = turnChangesOf([
    user(1, 'x'), proc(2, [call('edit', '', m1), call('edit', '', m2)]),
  ], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.files.length, 1);
  assert.equal(changes.files[0].edits(), 2);
  assert.equal(changes.files[0].hunks[1].index, 2);
});

test('无 meta 退回 arguments 的 edit', () => {
  const changes = turnChangesOf([
    user(1, 'x'),
    proc(2, [call('edit', '{"file_path":"/w/b.ts","old_string":"x","new_string":"y"}')]),
  ], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.files[0].created, false);
  assert.equal(changes.files[0].added, 1);
  assert.equal(changes.files[0].removed, 1);
});

test('write create：created=true，全 add', () => {
  const changes = turnChangesOf([
    user(1, 'x'),
    proc(2, [call('write', '{"file_path":"/w/new.md","content":"a\\nb\\nc"}')]),
  ], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.files[0].created, true);
  assert.equal(changes.files[0].added, 3);
  assert.equal(changes.files[0].removed, 0);
});

test('write update 不算新建，但算改动', () => {
  const meta: JsonMap = mapOf(JSON.stringify({ operation: 'update', diffs: [{ path: '/w/a', oldText: 'a', newText: 'b' }] }));
  const changes = turnChangesOf([user(1, 'x'), proc(2, [call('write', '', meta)])], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.files[0].created, false);
});

test('failed 调用整条跳过', () => {
  assert.equal(turnChangesOf([
    user(1, 'x'),
    proc(2, [call('edit', '{"file_path":"/w/a","old_string":"a","new_string":"b"}', null, true)]),
  ], 0, 2), null);
});

test('非写调用不产改动', () => {
  assert.equal(turnChangesOf([user(1, 'x'), proc(2, [call('read', '{"file_path":"/w/a"}')])], 0, 2), null);
});

test('meta.diffs 空数组回退 arguments', () => {
  const meta: JsonMap = mapOf(JSON.stringify({ diffs: [] }));
  const changes = turnChangesOf([
    user(1, 'x'),
    proc(2, [call('write', '{"file_path":"/w/a","content":"z"}', meta)]),
  ], 0, 2);
  assert.ok(changes !== null);
  assert.equal(changes.files[0].added, 1);
});

test('非法区间返回 null', () => {
  const messages: ChatMessage[] = [user(1, 'x')];
  assert.equal(turnChangesOf(messages, -1, 1), null);
  assert.equal(turnChangesOf(messages, 0, 1), null);
  assert.equal(turnChangesOf(messages, 0, 5), null);
});

test('bareToolName 只去 tools. 前缀', () => {
  assert.equal(bareToolName('tools.edit'), 'edit');
  assert.equal(bareToolName('mcp__x'), 'mcp__x');
});

test('diffLinesOf：改中间一行得到 ctx/del/add/ctx', () => {
  const lines = diffLinesOf('a\nb\nc', 'a\nB\nc');
  assert.deepEqual(lines.map((l) => l.type), [DIFF_LINE_CTX, DIFF_LINE_DEL, DIFF_LINE_ADD, DIFF_LINE_CTX]);
  assert.deepEqual(lines.map((l) => l.text), ['a', 'b', 'B', 'c']);
});

test('diffLinesOf：末尾换行不产空行', () => {
  const lines = diffLinesOf('a\n', 'a\nb\n');
  assert.equal(lines.filter((l) => l.text === '').length, 0);
});

test('diffLinesOf：空串 old 全 add、空串 new 全 del', () => {
  assert.deepEqual(diffLinesOf('', 'a\nb').map((l) => l.type), [DIFF_LINE_ADD, DIFF_LINE_ADD]);
  assert.deepEqual(diffLinesOf('a\nb', '').map((l) => l.type), [DIFF_LINE_DEL, DIFF_LINE_DEL]);
});

test('生成文件：write create + 正文引用去重，cwd 拼相对路径', () => {
  const meta: JsonMap = mapOf(JSON.stringify({ operation: 'create', cwd: '/w/proj' }));
  const messages: ChatMessage[] = [
    user(1, 'x'),
    proc(2, [call('write', '{"file_path":"/w/proj/out.png","content":"x"}', meta)]),
    assistant(3, '看图 ![图](out.png) 和 [文件](/w/proj/out.png)'),
  ];
  const files = turnArtifactsOf(messages, 0, 3);
  assert.equal(files.length, 1);
  assert.equal(files[0].path, '/w/proj/out.png');
  assert.equal(files[0].kind, ARTIFACT_IMAGE);
  assert.equal(files[0].caption(), '图片 · PNG');
});

test('生成文件：无 cwd 时相对路径丢弃、绝对路径保留；http 跳过', () => {
  const messages: ChatMessage[] = [
    user(1, 'x'),
    assistant(2, '![a](rel.png) ![b](/abs/a.png) [c](https://x/y.png) [d](#z)'),
  ];
  const files = turnArtifactsOf(messages, 0, 2);
  assert.deepEqual(files.map((f) => f.path), ['/abs/a.png']);
});

test('生成文件：update 不进列表', () => {
  const meta: JsonMap = mapOf(JSON.stringify({ operation: 'update' }));
  const messages: ChatMessage[] = [
    user(1, 'x'),
    proc(2, [call('write', '{"file_path":"/w/a.md","content":"z"}', meta)]),
  ];
  assert.equal(turnArtifactsOf(messages, 0, 2).length, 0);
});

test('artifactKindOf 全表边界', () => {
  assert.equal(artifactKindOf('a.png'), ARTIFACT_IMAGE);
  assert.equal(artifactKindOf('a.MD'), 'markdown');
  assert.equal(artifactKindOf('Makefile'), 'other');
  assert.equal(artifactKindOf('a.'), 'other');
  assert.equal(artifactKindOf('.hidden'), 'other');
  assert.equal(artifactKindOf('a.ts'), ARTIFACT_TEXT);
  assert.equal(artifactKindLabel(ARTIFACT_IMAGE), '图片');
});

test('name/directory 边界', () => {
  assert.equal(fileNameOf('/a'), 'a');
  assert.equal(dirNameOf('/a'), '');
  assert.equal(dirNameOf('a'), '');
  assert.equal(dirNameOf('/x/y/a'), '/x/y');
});

test('markdownRefs / resolveRef', () => {
  assert.deepEqual(markdownRefs('![a](p.png) [b](q.md)'), ['p.png', 'q.md']);
  assert.equal(resolveRef('p.png', '/w'), '/w/p.png');
  assert.equal(resolveRef('p.png', '/w/'), '/w/p.png');
  assert.equal(resolveRef('p.png', ''), null);
  assert.equal(resolveRef('/abs', ''), '/abs');
});

test('RawToolCall.toInfo 透传 meta', () => {
  const raw: RawToolCall = new RawToolCall();
  raw.callId = 'c1';
  raw.name = 'edit';
  raw.rawArguments = '{"file_path":"/w/a","old_string":"a","new_string":"b"}';
  raw.meta = mapOf('{"path":"/w/a"}');
  const info = raw.toInfo();
  assert.ok(info.meta !== null);
  assert.equal(info.name, 'edit');
});
