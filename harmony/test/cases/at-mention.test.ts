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

// ---------- @ 历史会话 / 路径拆分（安卓 composer_at_sessions.dart 口径） ----------

import { AtSessionHit, sessionMatches, insertSessionMention, atQueryDir, atLeafQuery, joinAtDir } from '../../entry/src/main/ets/core/AtMention.ts';
import { DshSession } from '../../entry/src/main/ets/core/Models.ts';

function session(id: string, title: string | null): DshSession {
  return new DshSession({ id: id, title: title === null ? '' : title });
}

test('sessionMatches：子串匹配、排除当前会话、空标题、最多 6 条', () => {
  const sessions: DshSession[] = [
    session('s1', '重构输入条'),
    session('cur', '重构输入条（当前）'),
    session('s2', null),
    session('s3', '行情看板'),
    session('s4', '重构登录页'),
    session('s5', '重构 A'),
    session('s6', '重构 B'),
    session('s7', '重构 C'),
    session('s8', '重构 D'),
  ];
  const hits: AtSessionHit[] = sessionMatches(sessions, 'cur', '重构');
  assert.equal(hits.length, 6);
  assert.deepEqual(hits.map((h: AtSessionHit): string => h.id), ['s1', 's4', 's5', 's6', 's7', 's8']);
  // 大小写不敏感（标题里的 ASCII）
  const latin: DshSession[] = [session('x', 'Fix Login Bug')];
  assert.equal(sessionMatches(latin, null, 'login').length, 1);
});

test('insertSessionMention：插入 Markdown 链接、] 换全角、空标题用 id', () => {
  const draft: string = '看看 @重';
  const at = { query: '重', start: 3, end: 5 };
  const out: string = insertSessionMention(draft, at, 's1', '重[构]');
  assert.equal(out, '看看 @[重[构］](dsh-session:s1) ');
  assert.equal(insertSessionMention('@', { query: '', start: 0, end: 1 }, 's2', ''), '@[s2](dsh-session:s2) ');
});

test('atQueryDir / atLeafQuery / joinAtDir：@src/li 下钻不丢目录', () => {
  assert.equal(atQueryDir('src/li'), 'src');
  assert.equal(atLeafQuery('src/li'), 'li');
  assert.equal(atQueryDir('li'), '');
  assert.equal(atLeafQuery('li'), 'li');
  assert.equal(joinAtDir('', 'src'), 'src');
  assert.equal(joinAtDir('app', 'src/'), 'app/src');
  assert.equal(joinAtDir('app/', ''), 'app');
});
