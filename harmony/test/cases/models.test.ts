/**
 * 协议模型测试 —— 对应安卓 app/lib/bridge/models.dart 的 8 个类。
 * 宪法 §7：每个 bridge 帧模型要有 JSON round-trip 单元测试；
 * 另测宽容口径（缺键/类型不符不抛，退默认值）。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';
import {
  DshSession,
  DshWorkspace,
  MessageDelta,
  MessageCommitted,
  DshDirectoryPage,
  SessionWaitResult,
} from '../../entry/src/main/ets/core/Models.ts';

/** 解析一段 JSON 字面量成对象（测试侧便捷）。 */
function obj(text: string): Object {
  return JSON.parse(text) as Object;
}

test('DshSession: 全字段解析 + 多余键忽略', () => {
  const s = DshSession.fromJson(obj(
    '{"id":"s1","rootId":"r1","updatedAt":1700000000,"running":true,' +
    '"blank":false,"title":"标题","workspaceId":"w1","workspaceTitle":"工作区",' +
    '"cwd":"sub","cwdAbsolute":"/tmp/w","extra":"ignored"}',
  ));
  assert.equal(s.id, 's1');
  assert.equal(s.rootId, 'r1');
  assert.equal(s.updatedAt, 1700000000);
  assert.equal(s.running, true);
  assert.equal(s.blank, false);
  assert.equal(s.title, '标题');
  assert.equal(s.workspaceId, 'w1');
  assert.equal(s.workspaceTitle, '工作区');
  assert.equal(s.cwd, 'sub');
  assert.equal(s.cwdAbsolute, '/tmp/w');
  assert.equal(s.displayTitle, '标题');
});

test('DshSession: 宽容——空对象不抛，退默认值', () => {
  const s = DshSession.fromJson(obj('{}'));
  assert.equal(s.id, '');
  assert.equal(s.rootId, '');
  assert.equal(s.updatedAt, 0);
  assert.equal(s.running, false);
  assert.equal(s.blank, false);
  assert.equal(s.title, null);
  assert.equal(s.workspaceId, null);
  assert.equal(s.workspaceTitle, null);
  assert.equal(s.cwd, '');
  assert.equal(s.cwdAbsolute, null);
  // blank 缺省 false → 走「会话 <id>」分支（id 也空）
  assert.equal(s.displayTitle, '会话 ');
});

test('DshSession: 宽容——类型不符退默认值，不抛', () => {
  const s = DshSession.fromJson(obj(
    '{"id":123,"updatedAt":"9","running":"yes","blank":1,"title":[]}',
  ));
  assert.equal(s.id, '');
  assert.equal(s.updatedAt, 0);
  assert.equal(s.running, false);
  assert.equal(s.blank, false);
  assert.equal(s.title, null);
});

test('DshSession: displayTitle 三分支（有标题/新对话/会话 id）', () => {
  const titled = new DshSession(JsonAccess.asMap(obj('{"id":"a","title":"T"}')));
  assert.equal(titled.displayTitle, 'T');
  const blanked = new DshSession(JsonAccess.asMap(obj('{"id":"a","blank":true}')));
  assert.equal(blanked.displayTitle, '新对话');
  const unnamed = new DshSession(JsonAccess.asMap(obj('{"id":"abc"}')));
  assert.equal(unnamed.displayTitle, '会话 abc');
});

test('DshWorkspace: 全字段解析 + 缺键默认', () => {
  const w = DshWorkspace.fromJson(
    obj('{"id":"w1","title":"WS","rootId":"r1","path":"/x"}'),
  );
  assert.equal(w.id, 'w1');
  assert.equal(w.title, 'WS');
  assert.equal(w.rootId, 'r1');
  assert.equal(w.path, '/x');
  const w2 = DshWorkspace.fromJson(obj('{}'));
  assert.equal(w2.id, '');
  assert.equal(w2.title, '');
  assert.equal(w2.rootId, '');
  assert.equal(w2.path, '');
});

test('MessageDelta: 全字段 + 缺键默认（kind 默认 text）', () => {
  const d = MessageDelta.fromJson(obj(
    '{"sessionId":"s1","turn":2,"step":1,"index":3,"kind":"reasoning","text":"hi"}',
  ));
  assert.equal(d.sessionId, 's1');
  assert.equal(d.turn, 2);
  assert.equal(d.step, 1);
  assert.equal(d.index, 3);
  assert.equal(d.kind, 'reasoning');
  assert.equal(d.text, 'hi');
  const d2 = MessageDelta.fromJson(obj('{}'));
  assert.equal(d2.sessionId, '');
  assert.equal(d2.kind, 'text');
  assert.equal(d2.text, '');
});

test('MessageCommitted: 全字段 + role 缺键默认 assistant', () => {
  const c = MessageCommitted.fromJson(obj(
    '{"sessionId":"s1","role":"user","seq":4,"turn":2,"step":1}',
  ));
  assert.equal(c.sessionId, 's1');
  assert.equal(c.role, 'user');
  assert.equal(c.seq, 4);
  assert.equal(c.turn, 2);
  assert.equal(c.step, 1);
  const c2 = MessageCommitted.fromJson(obj('{}'));
  assert.equal(c2.role, 'assistant');
  assert.equal(c2.seq, 0);
});

test('DshDirectoryPage: entries 列表 + nextCursor + 缺键空页', () => {
  const page = DshDirectoryPage.fromJson(obj(
    '{"rootId":"r1","path":"/sub","nextCursor":"cur2","entries":[' +
    '{"name":"a.txt","path":"/sub/a.txt","kind":"file"},' +
    '{"name":"dir","path":"/sub/dir","kind":"directory"}]}',
  ));
  assert.equal(page.rootId, 'r1');
  assert.equal(page.path, '/sub');
  assert.equal(page.nextCursor, 'cur2');
  assert.equal(page.entries.length, 2);
  assert.equal(page.entries[0].name, 'a.txt');
  assert.equal(page.entries[0].path, '/sub/a.txt');
  assert.equal(page.entries[0].kind, 'file');
  assert.equal(page.entries[1].name, 'dir');
  assert.equal(page.entries[1].kind, 'directory');

  const bare = DshDirectoryPage.fromJson(obj('{}'));
  assert.deepEqual(bare.entries, []);
  assert.equal(bare.nextCursor, null);
  assert.equal(bare.rootId, '');
});

test('SessionWaitResult: state/output 宽容保留原始 map + toJson round-trip', () => {
  const raw =
    '{"reason":"input-required","state":{"cursor":7,"active":true},"output":{"records":[]}}';
  const w = SessionWaitResult.fromJson(obj(raw));
  assert.equal(w.reason, 'input-required');
  assert.equal(w.state['cursor'], 7);
  assert.equal(w.state['active'], true);
  assert.deepEqual(w.output['records'], []);
  // round-trip：编码回去与原始一致
  assert.deepEqual(w.toJson(), obj(raw));

  const bare = SessionWaitResult.fromJson(obj('{}'));
  assert.equal(bare.reason, 'idle');
  assert.deepEqual(bare.state, {});
  assert.deepEqual(bare.output, {});
});
