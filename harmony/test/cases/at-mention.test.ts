import test from 'node:test';
import assert from 'node:assert/strict';

import { AtEntry, AtMentionMerge, mergeAtEntries, inSubDirectory } from '../../entry/src/main/ets/core/AtMention.ts';
import { GatewayEntry } from '../../entry/src/main/ets/core/Files.ts';

function entry(path: string, isDirectory: boolean): GatewayEntry {
  const e: GatewayEntry = new GatewayEntry();
  e.name = path;
  e.path = path;
  e.kind = isDirectory ? 'directory' : 'file';
  e.isDirectory = isDirectory;
  return e;
}

test('mergeAtEntries：多根时名字带 label/ 前缀，单根不带', () => {
  const lists: GatewayEntry[][] = [[entry('.ci-logs', true)], [entry('dsh-Chat', true)]];
  const multi: AtMentionMerge = mergeAtEntries(lists, ['workspace', 'handheld'], '', true);
  assert.deepEqual(multi.items.map((a: AtEntry): string => a.name),
    ['workspace/.ci-logs', 'handheld/dsh-Chat']);
  // 单根：只有一条 list，lastLabels 只有一项 → 不带前缀
  const single: AtMentionMerge = mergeAtEntries([[entry('.ci-logs', true)]], [''], '', true);
  assert.deepEqual(single.items.map((a: AtEntry): string => a.name), ['.ci-logs']);
});

test('mergeAtEntries：query 只按名字前缀过滤，大小写不敏感', () => {
  const lists: GatewayEntry[][] = [[entry('.ci-logs', true), entry('dsh-Chat', true), entry('zzz', false)]];
  const out: AtMentionMerge = mergeAtEntries(lists, [''], 'DSH', true);
  assert.equal(out.items.length, 1);
  assert.equal(out.items[0].name, 'dsh-Chat');
  // 中缀不匹配（不是「包含」语义）
  const mid: AtMentionMerge = mergeAtEntries(lists, [''], 'chat', true);
  assert.equal(mid.items.length, 0);
});

test('mergeAtEntries：根层空列表也算可访问（okRoots 计入）', () => {
  const lists: GatewayEntry[][] = [[], [entry('a', true)]];
  const out: AtMentionMerge = mergeAtEntries(lists, ['x', 'y'], '', false);
  assert.equal(out.okRoots, 2);
});

test('mergeAtEntries：子目录层空列表不计 okRoots（404 兜底不误判为可访问）', () => {
  const lists: GatewayEntry[][] = [[], []];
  const out: AtMentionMerge = mergeAtEntries(lists, ['x', 'y'], '', true);
  assert.equal(out.okRoots, 0);
  assert.equal(out.items.length, 0);
});

test('mergeAtEntries：一根本身有内容、另一根 404 → okRoots>0，面板不判失败', () => {
  const lists: GatewayEntry[][] = [[entry('rc3', true)], []];
  const out: AtMentionMerge = mergeAtEntries(lists, ['a', 'b'], '', true);
  assert.equal(out.okRoots, 1);
  assert.deepEqual(out.items.map((a: AtEntry): string => a.name), ['a/rc3']);
});

test('mergeAtEntries：labels 比 lists 短时不越界（前缀取空）', () => {
  const lists: GatewayEntry[][] = [[entry('f', false)]];
  const out: AtMentionMerge = mergeAtEntries(lists, [], '', true);
  assert.equal(out.items[0].name, 'f');
});

test('AtEntry.fromEntry：字段逐一搬运，isDirectory 透传', () => {
  const a: AtEntry = AtEntry.fromEntry(entry('dir/x', true), 'root/');
  assert.equal(a.name, 'root/dir/x');
  assert.equal(a.path, 'dir/x');
  assert.equal(a.kind, 'directory');
  assert.equal(a.isDirectory, true);
});

test('inSubDirectory：空串与纯空白都是根层', () => {
  assert.equal(inSubDirectory(''), false);
  assert.equal(inSubDirectory('   '), false);
  assert.equal(inSubDirectory('workspace'), true);
});
