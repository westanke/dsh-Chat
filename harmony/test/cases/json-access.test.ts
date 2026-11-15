/**
 * JsonAccess 宽容守卫测试 —— 姊妹仓口径的核心保障：
 * 缺键 / 显式 null / 类型不符 → 默认值或 null，绝不抛异常。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  JsonAccess,
} from '../../entry/src/main/ets/core/JsonAccess.ts';

test('parse: 合法 JSON 进对象，非法回 null', () => {
  const ok = JsonAccess.parse('{"a":1}');
  assert.ok(ok !== null);
  const bad = JsonAccess.parse('{not-json');
  assert.equal(bad, null);
});

test('asMap: 非对象（数字/字符串/数组/null）全部收敛为 null', () => {
  assert.equal(JsonAccess.asMap(null), null);
  assert.equal(JsonAccess.asMap(undefined), null);
  assert.equal(JsonAccess.asMap(1 as Object), null);
  assert.equal(JsonAccess.asMap('x' as Object), null);
  assert.ok(JsonAccess.asMap({ a: 1 } as Object) !== null);
});

test('raw: 缺键/null/undefined 一律回 null', () => {
  const m = JsonAccess.asMap({ a: null, b: 1 } as Object);
  assert.ok(m !== null);
  assert.equal(JsonAccess.raw(m, 'a'), null);
  assert.equal(JsonAccess.raw(m, 'missing'), null);
  assert.equal(JsonAccess.raw(m, 'b'), 1);
  assert.equal(JsonAccess.raw(null, 'b'), null);
});

test('str/num/bool: 类型不符回 null，不抛', () => {
  const m = JsonAccess.asMap({
    s: 'x', n: 3, b: true, sBad: 1, nBad: '1', bBad: 'yes',
  } as Object);
  assert.ok(m !== null);
  assert.equal(JsonAccess.str(m, 's'), 'x');
  assert.equal(JsonAccess.str(m, 'sBad'), null);
  assert.equal(JsonAccess.str(m, 'missing'), null);
  assert.equal(JsonAccess.num(m, 'n'), 3);
  assert.equal(JsonAccess.num(m, 'nBad'), null);
  assert.equal(JsonAccess.bool(m, 'b'), true);
  assert.equal(JsonAccess.bool(m, 'bBad'), null);
});

test('arr/obj/numArr/strArr: 形状不符退空数组/null，混合数组过滤', () => {
  const m = JsonAccess.asMap({
    arr: [1, 'a', 2],
    strs: ['x', 3, 'y'],
    obj: { k: 'v' },
    objBad: 'no',
  } as Object);
  assert.ok(m !== null);
  assert.deepEqual(JsonAccess.numArr(m, 'arr'), [1, 2]);
  assert.deepEqual(JsonAccess.strArr(m, 'strs'), ['x', 'y']);
  assert.deepEqual(JsonAccess.arr(m, 'missing'), []);
  const o = JsonAccess.obj(m, 'obj');
  assert.ok(o !== null);
  assert.equal(JsonAccess.strOr(o, 'k', ''), 'v');
  assert.equal(JsonAccess.obj(m, 'objBad'), null);
});

test('strOr/numOr/boolOr: 缺键给默认值，命中给真值', () => {
  const m = JsonAccess.asMap({ s: 'v', n: 7, b: false } as Object);
  assert.ok(m !== null);
  assert.equal(JsonAccess.strOr(m, 's', 'd'), 'v');
  assert.equal(JsonAccess.strOr(m, 'missing', 'd'), 'd');
  assert.equal(JsonAccess.numOr(m, 'n', 0), 7);
  assert.equal(JsonAccess.numOr(m, 'missing', 9), 9);
  assert.equal(JsonAccess.boolOr(m, 'b', true), false);
  assert.equal(JsonAccess.boolOr(m, 'missing', true), true);
});
