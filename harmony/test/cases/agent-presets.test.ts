/**
 * AgentPresets 模型测试 —— 宽容解析 + JSON round-trip（宪法 §5/§7 口径）。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { AgentPreset, AGENT_PRESET_TRUST_SYSTEM } from '../../entry/src/main/ets/core/AgentPresets.ts';
import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';

test('fromJson：全字段解析', () => {
  const p: AgentPreset = AgentPreset.fromJson(JsonAccess.asMap(JsonAccess.parse(
    '{"id":"balanced","name":"均衡","description":"默认预设","trust":"user","isDefault":true,"available":false}')));
  assert.equal(p.id, 'balanced');
  assert.equal(p.name, '均衡');
  assert.equal(p.description, '默认预设');
  assert.equal(p.trust, 'user');
  assert.equal(p.isDefault, true);
  assert.equal(p.available, false);
});

test('fromJson：缺键宽容回默认（姊妹仓 0.2.x 无 trust 实证）', () => {
  const p: AgentPreset = AgentPreset.fromJson(JsonAccess.asMap(JsonAccess.parse(
    '{"id":"p1","name":"预设一"}')));
  assert.equal(p.id, 'p1');
  assert.equal(p.name, '预设一');
  assert.equal(p.description, null);
  assert.equal(p.trust, AGENT_PRESET_TRUST_SYSTEM);
  assert.equal(p.isDefault, false);
  assert.equal(p.available, true);
});

test('fromJson：null / 类型不符 → 全默认不抛', () => {
  const p: AgentPreset = AgentPreset.fromJson(null);
  assert.equal(p.id, '');
  assert.equal(p.name, '');
  assert.equal(p.trust, AGENT_PRESET_TRUST_SYSTEM);
});

test('round-trip：fromJson → toJson → fromJson 字段相等（description null 省键）', () => {
  const source: AgentPreset = AgentPreset.fromJson(JsonAccess.asMap(JsonAccess.parse(
    '{"id":"agentic","name":"Agentic","description":"完整工具链","trust":"system","isDefault":true,"available":true}')));
  const back: AgentPreset = AgentPreset.fromJson(source.toJson());
  assert.equal(back.id, source.id);
  assert.equal(back.name, source.name);
  assert.equal(back.description, source.description);
  assert.equal(back.trust, source.trust);
  assert.equal(back.isDefault, source.isDefault);
  assert.equal(back.available, source.available);
  // description=null 时 toJson 不带该键（协议可选字段口径）。
  const bare: AgentPreset = new AgentPreset();
  bare.id = 'x';
  bare.name = 'y';
  assert.equal('description' in bare.toJson(), false);
});

test('listFrom：数组逐项解析', () => {
  const list: AgentPreset[] = AgentPreset.listFrom([
    JsonAccess.parse('{"id":"a","name":"A"}') as Object,
    JsonAccess.parse('{"id":"b","name":"B","trust":"user"}') as Object,
  ]);
  assert.equal(list.length, 2);
  assert.equal(list[1].trust, 'user');
});
