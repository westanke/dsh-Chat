/**
 * Hosts/ModelsView/Permissions 测试 —— 对齐安卓对应测试口径。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { DshHost, stableId, decodeDsh1, upsertHost, removeHost,
  HOSTS_STORAGE_KEY, parseHosts, encodeHosts }
  from '../../entry/src/main/ets/core/Hosts.ts';
import { SessionModels, ModelSelection, parseSelectModelReply, reasoningEffortLabel }
  from '../../entry/src/main/ets/core/ModelsView.ts';
import { PermissionCatalog, permissionLabelOf }
  from '../../entry/src/main/ets/core/Permissions.ts';
import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';

function map(text: string): Record<string, Object> | null {
  return JsonAccess.asMap(JsonAccess.parse(text));
}

test('stableId: FNV-1a 16 hex，同输入同输出；相似 URL 不同', () => {
  const a: string = stableId('http://192.168.1.10:8765');
  const b: string = stableId('http://192.168.1.11:8765');
  assert.equal(a.length, 16);
  assert.equal(a, stableId('http://192.168.1.10:8765'));
  assert.notEqual(a, b);
  // 已知向量：空串 FNV-1a 64 = cbf29ce484222325
  assert.equal(stableId(''), 'cbf29ce484222325');
  // 多字节 UTF-8（中文 URL 路径）不崩且稳定
  const c: string = stableId('http://192.168.1.5:8765/中文');
  assert.equal(c, stableId('http://192.168.1.5:8765/中文'));
});

test('DshHost: fromJson/toJson 往返，token 空/缺省 null 不上键', () => {
  const h: DshHost = DshHost.fromJson(map(
    '{"id":"a1","displayName":"工作台","baseUrl":"http://1.2.3.4:8765","token":"tk","lastUsedAt":99}')!);
  assert.equal(h.id, 'a1');
  assert.equal(h.token, 'tk');
  const j: Record<string, Object> = h.toMap();
  assert.equal(JsonAccess.strOr(j, 'token', ''), 'tk');
  const noToken: DshHost = DshHost.fromJson(map('{"baseUrl":"x"}'));
  assert.equal(noToken.token, null);
  assert.equal('token' in noToken.toMap(), false);
});

test('decodeDsh1: 标准前缀 + URL-safe 无填充', () => {
  const payload: string = JSON.stringify({
    displayName: '台式机', token: 'tok-1',
    endpoints: [{ baseUrl: 'http://192.168.1.10:8765/api/v1' }],
  });
  const b64: string = Buffer.from(payload, 'utf8').toString('base64url');
  const host: DshHost | null = decodeDsh1('DSH1:' + b64, 1000);
  assert.notEqual(host, null);
  assert.equal((host as DshHost).displayName, '台式机');
  assert.equal((host as DshHost).baseUrl, 'http://192.168.1.10:8765'); // 剥 /api/v1
  assert.equal((host as DshHost).token, 'tok-1');
  assert.equal((host as DshHost).id, stableId('http://192.168.1.10:8765'));
  assert.equal((host as DshHost).lastUsedAt, 1000);
});

test('decodeDsh1: 宽容——大小写/空白/前后噪声/缺填充/外层噪声', () => {
  const payload: string = JSON.stringify({
    displayName: ' n1 ', endpoints: [{ baseUrl: 'http://10.0.0.2:9000' }],
  });
  const b64: string = Buffer.from(payload, 'utf8').toString('base64url')
    .replace(/-/g, '_').replace(/\+/g, '-').replace(/=+$/, '');
  // 前后粘噪声 + 空白 + 小写前缀
  const host: DshHost | null = decodeDsh1('  前缀 "dsh1:' + b64 + '"。尾部  ', 2000);
  assert.notEqual(host, null);
  assert.equal((host as DshHost).baseUrl, 'http://10.0.0.2:9000');
  assert.equal((host as DshHost).displayName, 'n1'); // trim
  assert.equal((host as DshHost).token, null);
  assert.equal((host as DshHost).displayName, 'n1');
});

test('decodeDsh1: 截最外层 {...} 再试；display 默认；失败一律 null', () => {
  const payload: string = JSON.stringify({
    endpoints: [{ baseUrl: 'http://10.0.0.3:80' }],
  });
  const b64: string = Buffer.from('垃圾头' + payload + '尾部', 'utf8').toString('base64url');
  const host: DshHost | null = decodeDsh1('dsh1:' + b64, 3000);
  assert.notEqual(host, null);
  assert.equal((host as DshHost).displayName, '导入的主机');

  assert.equal(decodeDsh1('', 0), null);
  assert.equal(decodeDsh1('dsh1:', 0), null);
  assert.equal(decodeDsh1('dsh1:!!!!', 0), null);
  assert.equal(decodeDsh1('dsh1:ABC', 0), null); // mod==1
  const noUrl: string = Buffer.from(JSON.stringify({ displayName: 'x' }), 'utf8')
    .toString('base64url');
  assert.equal(decodeDsh1('dsh1:' + noUrl, 0), null); // endpoints 缺失
});

test('hosts 列表纯操作: upsert 幂等降序/remove 双键/parse+encode 往返', () => {
  assert.equal(HOSTS_STORAGE_KEY, 'dsh.hosts');
  const h1: DshHost = new DshHost();
  h1.baseUrl = 'http://a'; h1.id = stableId('http://a'); h1.lastUsedAt = 10;
  const h2: DshHost = new DshHost();
  h2.baseUrl = 'http://b'; h2.id = stableId('http://b'); h2.lastUsedAt = 20;
  const h2new: DshHost = new DshHost();
  h2new.baseUrl = 'http://b'; h2new.displayName = '更新'; h2new.lastUsedAt = 30;

  let list: DshHost[] = upsertHost([], h1);
  list = upsertHost(list, h2);
  list = upsertHost(list, h2new); // 同 baseUrl 更新不重复建行
  assert.equal(list.length, 2);
  assert.equal(list[0].baseUrl, 'http://b'); // lastUsedAt 降序
  assert.equal(list[0].displayName, '更新');

  const victim: DshHost = new DshHost();
  victim.baseUrl = 'http://a';
  const removed: DshHost[] = removeHost(list, victim);
  assert.equal(removed.length, 1);
  assert.equal(removeHost(removed, victim).length, 1); // 未命中返回等长列表

  const round: DshHost[] = parseHosts(encodeHosts(list));
  assert.equal(round.length, 2);
  assert.equal(round[0].displayName, '更新');
  assert.deepEqual(parseHosts(''), []);
  assert.deepEqual(parseHosts('not-json'), []);
});

test('SessionModels: 完整形状收敛 + 宽容 + parse 直通', () => {
  const sm: SessionModels = SessionModels.parse(map(`{
    "sessionId":"s1",
    "current":{"provider":"deepseek","model":"v3.2","reasoningEffort":"high"},
    "routable":true,
    "groups":[{"id":"deepseek","name":"DeepSeek","models":[
      {"id":"v3.2","name":"V3.2","description":"主力",
       "reasoning":{"efforts":[{"id":"off","name":"关闭"},{"id":"low","name":"低"}],
                    "defaultEffort":"high"}}]},
      {"id":"openai","name":"OpenAI","models":[]}],
    "failures":[{"provider":"ollama","message":"连接失败"}]}`));
  assert.equal(sm.current.provider, 'deepseek');
  assert.equal(sm.current.reasoningEffort, 'high');
  assert.equal(sm.routable, true);
  assert.equal(sm.groups.length, 2);
  assert.equal(sm.groups[0].models[0].reasoning?.efforts.length, 2);
  assert.equal(sm.groups[0].models[0].reasoning?.defaultEffort, 'high');
  assert.equal(sm.failures[0].message, '连接失败');

  const empty: SessionModels = SessionModels.parse(null);
  assert.equal(empty.routable, false);
  assert.equal(empty.groups.length, 0);
});

test('parseSelectModelReply: type 判别 + selected 缺失 null + toMap 往返', () => {
  const ok: ModelSelection | null = parseSelectModelReply(map(
    '{"type":"select-model","selected":{"provider":"deepseek","model":"v3.2","reasoningEffort":"low"}}'));
  assert.notEqual(ok, null);
  assert.equal((ok as ModelSelection).model, 'v3.2');
  assert.equal(parseSelectModelReply(map('{"type":"other"}')), null);
  assert.equal(parseSelectModelReply(map('{"type":"select-model"}')), null); // 缺 selected
  assert.equal(parseSelectModelReply(null), null);

  const sel: ModelSelection = ModelSelection.fromJson(map('{"provider":"p","model":"m"}'));
  const back: ModelSelection = ModelSelection.fromJson(sel.toMap() as never);
  assert.equal(back.provider, 'p');
  assert.equal(back.model, 'm');
});

test('reasoningEffortLabel: 四档中文 + 未知回退', () => {
  assert.equal(reasoningEffortLabel('off'), '关闭');
  assert.equal(reasoningEffortLabel('low'), '低');
  assert.equal(reasoningEffortLabel('high'), '高');
  assert.equal(reasoningEffortLabel('max'), '最高');
  assert.equal(reasoningEffortLabel('medium'), 'medium');
});

test('PermissionCatalog: 权威清单透传 + label/descriptionLabel/needsConfirm', () => {
  const cat: PermissionCatalog = PermissionCatalog.fromJson(map(`{
    "options":[
      {"value":"read-only","name":"Read Only","description":"server desc"},
      {"value":"workspace-write","name":"Workspace Write"},
      {"value":"danger-full-access","name":"Full Access"},
      {"value":"custom","name":"Custom"}],
    "defaultPreset":"workspace-write"}`));
  assert.equal(cat.options.length, 4);
  assert.equal(cat.defaultPreset, 'workspace-write');
  assert.equal(cat.switchable.length, 3); // custom 派生态过滤

  const ro = cat.options[0];
  assert.equal(ro.label, '仅可查看');
  assert.equal(ro.descriptionLabel, '只能查看会话内容，不能写入'); // 本地标签优先
  assert.equal(ro.needsConfirm, false);
  const full = cat.options[2];
  assert.equal(full.label, '完全权限');
  assert.equal(full.needsConfirm, true);
  const custom = cat.options[3];
  assert.equal(custom.isDerived, true);
  const unknown = PermissionCatalog.fromJson(map(
    '{"options":[{"value":"enterprise-gate","name":"企业网关"}]}')).options[0];
  assert.equal(unknown.label, '企业网关'); // 未知回退服务端 name
  assert.equal(unknown.descriptionLabel, null);
});

test('permissionLabelOf: 未设置/已知/未知', () => {
  assert.equal(permissionLabelOf(null), '权限未设置');
  assert.equal(permissionLabelOf(''), '权限未设置');
  assert.equal(permissionLabelOf('workspace-write'), '工作区读写');
  assert.equal(permissionLabelOf('some-future'), 'some-future');
});
