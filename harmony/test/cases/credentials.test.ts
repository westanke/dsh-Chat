/**
 * 凭证编解码测试 —— 对应安卓 app/lib/bridge/credentials.dart 的数据形状。
 * 平台持久化（ArkTS preferences）属 entry 层，本文件只测纯逻辑。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  CREDENTIALS_STORAGE_KEY,
  DshCredentials,
} from '../../entry/src/main/ets/core/Credentials.ts';

test('存储键名与安卓版一致（跨端同步同一份本地数据）', () => {
  assert.equal(CREDENTIALS_STORAGE_KEY, 'dsh.credentials');
});

test('encode/decode: round-trip 字段相等', () => {
  const c = new DshCredentials('http://127.0.0.1:8080', 'tok-123');
  const decoded = DshCredentials.decode(c.encode());
  assert.ok(decoded !== null);
  assert.equal(decoded.baseUrl, 'http://127.0.0.1:8080');
  assert.equal(decoded.token, 'tok-123');
  assert.equal(decoded.isComplete, true);
});

test('decode: 非法 JSON / 缺字段 / 类型不符回 null（调用方按未配对处理）', () => {
  assert.equal(DshCredentials.decode('{not-json'), null);
  assert.equal(DshCredentials.decode('{}'), null);
  assert.equal(DshCredentials.decode('{"baseUrl":"u"}'), null);
  assert.equal(DshCredentials.decode('{"baseUrl":1,"token":2}'), null);
  assert.equal(DshCredentials.decode('null'), null);
});

test('isComplete: 空 baseUrl 或空 token 视为未配对', () => {
  assert.equal(new DshCredentials('', 't').isComplete, false);
  assert.equal(new DshCredentials('u', '').isComplete, false);
  assert.equal(new DshCredentials('u', 't').isComplete, true);
});
