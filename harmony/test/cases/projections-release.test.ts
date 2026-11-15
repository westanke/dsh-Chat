/**
 * Projections/ReleaseCheck 测试 —— 对齐安卓 projections_test / release_check_test 口径。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { TrajectoryNodeKind, TrajectoryTurn, trajectoryOf, todoItems,
  agentTeamProjectionOf, prettyJson, UNKNOWN_TURN }
  from '../../entry/src/main/ets/core/Projections.ts';
import { ReleaseInfo, releaseFromJson, isNewerVersion, RELEASE_REPO }
  from '../../entry/src/main/ets/core/ReleaseCheck.ts';
import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';

function map(text: string): Record<string, Object> | null {
  return JsonAccess.asMap(JsonAccess.parse(text));
}

function ev(type: string, seq: number, time: number, turn: number,
            data: Record<string, unknown> = {}): Record<string, Object> {
  const merged: Record<string, Object> = Object.assign({}, data) as Record<string, Object>;
  merged['turn'] = turn;
  return { type, seq, time, data: merged };
}

test('trajectoryOf: 按 turn 分组、组内按 seq、未知轮垫底、过程细节丢弃', () => {
  const turns: TrajectoryTurn[] = trajectoryOf([
    ev('user/message', 3, 300, 2),
    ev('assistant/message', 1, 100, 1),
    ev('tool/call', 2, 200, 1, { name: 'bash' }),
    ev('tool/result', 5, 500, 1), // 丢弃
    ev('step/start', 6, 600, 1), // 丢弃
    ev('session-log-1', 7, 700, 1), // 丢弃
    ev('agent/inbox/x', 8, 800, 1), // 丢弃
    ev('unknown/event', 9, 900, 99), // other
    ev('user/message', 4, 400, 0), // 无 turn → 垫底
  ]);
  assert.equal(turns.length, 4); // 1 + 2 + 99(other 收录) + 0 垫底在最后
  assert.equal(turns[0].turn, 1);
  assert.equal(turns[0].nodes.length, 2); // assistant + tool/call
  assert.equal(turns[0].nodes[0].seq, 1); // 组内按 seq 升序
  assert.equal(turns[0].nodes[1].kind, TrajectoryNodeKind.TOOL);
  assert.equal(turns[0].nodes[1].label, 'bash');
  assert.equal(turns[0].toolCalls, 1);
  assert.equal(turns[0].durationMillis, 100); // 200-100
  assert.equal(turns[1].turn, 2);
  assert.equal(turns[1].nodes[0].kind, TrajectoryNodeKind.USER);
  assert.equal(turns[1].durationMillis, null); // 单节点
  assert.equal(turns[2].turn, 99);
  assert.equal(turns[2].nodes[0].kind, TrajectoryNodeKind.OTHER);
  assert.equal(turns[2].nodes[0].type, 'unknown/event'); // other 用原始 type 做标签
  assert.equal(turns[3].turn, UNKNOWN_TURN); // 无 turn 事件垫底（排最后）
  assert.equal(turns[3].isUnknown, true);
  assert.equal(turns[3].nodes[0].seq, 4);
});

test('trajectoryOf: 跨度非正 durationMillis null；raw 挂 data', () => {
  const turns: TrajectoryTurn[] = trajectoryOf([
    ev('user/message', 1, 100, 1),
    ev('assistant/message', 2, 50, 1), // time 倒挂 → d<0
  ]);
  assert.equal(turns.length, 1);
  assert.equal(turns[0].durationMillis, null);
  assert.equal((turns[0].nodes[0].raw as Record<string, Object>)['turn'], 1);
  assert.deepEqual(trajectoryOf([]), []);
});

test('todoItems: 只认 content+status，{id,text,status} 变体丢弃', () => {
  const proj: Record<string, Object> | null = map(`{
    "values":{"todos":[
      {"content":" 写文档 ","status":"completed"},
      {"content":"  ","status":"pending"},
      {"id":"t2","text":"旧夹具","status":"pending"},
      {"content":"跑测试"}
    ]}}`);
  const items = todoItems(proj);
  assert.equal(items.length, 1); // 空白 content 与缺 status 丢弃
  assert.equal(items[0].content.trim(), '写文档');
  assert.equal(items[0].isCompleted, true);
  assert.equal(items[0].isInProgress, false);
  assert.deepEqual(todoItems(null), []);
  assert.deepEqual(todoItems(map('{"values":{}}')), []);
  const inprog = todoItems(map('{"values":{"todos":[{"content":"a","status":"in_progress"}]}}'));
  assert.equal(inprog[0].isInProgress, true);
});

test('agentTeamProjectionOf: 全量解析 + 空壳 null + subagentCatalog 兼容 sessionId', () => {
  const proj: Record<string, Object> | null = map(`{
    "asOfSeq": 9,
    "values":{
      "agentTeam":{
        "members":[
          {"id":"lead-1","name":"lead","role":"lead"},
          {"id":"dev-1","role":"teammate","phase":"blocked","error":"编译失败"}],
        "tasks":[
          {"id":"t1","subject":"搭骨架","description":"d1","status":"completed",
           "blockedBy":["t0"],"writeScopes":["harmony/"],"ownerName":"dev-1","ready":true},
          {"id":"t2","subject":"移植","status":"pending","ready":false}],
        "failure":null},
      "subagentCatalog":[
        {"id":"sub-1","mode":"fork","label":"审查","createdAt":123},
        {"sessionId":"sub-old","mode":"fresh","label":"旧"}]}}`);
  const team = agentTeamProjectionOf(proj);
  assert.notEqual(team, null);
  const t = team as NonNullable<typeof team>;
  assert.equal(t.hasTeam, true);
  assert.equal(t.members.length, 2);
  assert.equal(t.members[0].isLead, true);
  assert.equal(t.members[1].name, 'dev-1'); // name 缺省回 id
  assert.equal(t.members[1].phase, 'blocked');
  assert.equal(t.completedTasks, 1);
  assert.equal(t.tasks[0].blockedBy.length, 1);
  assert.equal(t.tasks[1].ready, false);
  assert.equal(t.subagents.length, 2);
  assert.equal(t.subagents[0].id, 'sub-1');
  assert.equal(t.subagents[1].id, 'sub-old'); // 老夹具 sessionId 兜底
  assert.equal(t.subagents[0].createdAt, 123);
  assert.equal(t.failure, null);

  // 空壳
  assert.equal(agentTeamProjectionOf(map('{"values":{}}')), null);
  assert.equal(agentTeamProjectionOf(null), null);
  // failure 单独出现不算空壳
  const f = agentTeamProjectionOf(map(
    '{"values":{"agentTeam":{"failure":"投影生成失败"}}}'));
  assert.equal((f as NonNullable<typeof f>).failure, '投影生成失败');
});

test('prettyJson: null 文案 + 缩进序列化', () => {
  assert.equal(prettyJson(null), '（这条事件没有载荷）');
  const s: string = prettyJson(map('{"a":1}') as never);
  assert.ok(s.includes('"a": 1'));
});

test('ReleaseInfo: versionParts 三段补零 + v 前缀剥离', () => {
  RELEASE_REPO; // 常量存在（= westanke/dsh-Chat）
  const r: ReleaseInfo = new ReleaseInfo();
  r.tag = 'v1.2';
  assert.deepEqual(r.versionParts, [1, 2, 0]);
  r.tag = '1.2.3';
  assert.deepEqual(r.versionParts, [1, 2, 3]);
  r.tag = 'vX.Y.Z';
  assert.deepEqual(r.versionParts, [0, 0, 0]);
});

test('releaseFromJson: 双前缀放行/大小写/坏资产过滤/无 apk null', () => {
  const body: Record<string, Object> | null = map(`{
    "tag_name":"v1.0.3","body":"更新说明",
    "assets":[
      {"name":"README.txt","browser_download_url":"http://x/r"},
      {"name":"other-app-1.0.apk","browser_download_url":"http://x/o"},
      {"name":"dsh-Chat-v1.0.3.apk","browser_download_url":"http://x/a","size":12345}]}
  `);
  const rel: ReleaseInfo | null = releaseFromJson(body);
  assert.notEqual(rel, null);
  assert.equal((rel as ReleaseInfo).apkName, 'dsh-Chat-v1.0.3.apk');
  assert.equal((rel as ReleaseInfo).size, 12345);
  assert.equal((rel as ReleaseInfo).notes, '更新说明');

  const alt: ReleaseInfo | null = releaseFromJson(map(`{
    "tag_name":"v1.0.3",
    "assets":[{"name":"DSHCHAT-2_10-android.apk","browser_download_url":"http://x/b"}]}`));
  assert.equal((alt as ReleaseInfo).apkName, 'DSHCHAT-2_10-android.apk');
  assert.equal((alt as ReleaseInfo).size, null); // 没给 size

  const noUrl: ReleaseInfo | null = releaseFromJson(map(`{
    "tag_name":"v1","assets":[{"name":"dsh-chat-1.apk"}]}`));
  assert.equal(noUrl, null); // url 空
  assert.equal(releaseFromJson(null), null);
  assert.equal(releaseFromJson(map('{"tag_name":""}')), null);
  assert.equal(releaseFromJson(map('{"tag_name":"v1","assets":[]}')), null);
});

test('isNewerVersion: 三段逐位比较', () => {
  assert.equal(isNewerVersion([1, 0, 18], [1, 0, 17]), true);
  assert.equal(isNewerVersion([1, 1, 0], [1, 0, 99]), true);
  assert.equal(isNewerVersion([2, 0, 0], [1, 9, 9]), true);
  assert.equal(isNewerVersion([1, 0, 17], [1, 0, 17]), false);
  assert.equal(isNewerVersion([1, 0, 16], [1, 0, 17]), false);
  assert.equal(isNewerVersion([0, 9, 9], [1, 0, 0]), false);
});
