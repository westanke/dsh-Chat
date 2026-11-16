import test from 'node:test';
import assert from 'node:assert/strict';
import { DshSession } from '../../entry/src/main/ets/core/Models';
import {
  SessionLocation, locationLabel, recentLocations, locationSubtitle,
  parentPath, locationChipLabel,
} from '../../entry/src/main/ets/core/SessionLocation';

function session(id: string, rootId: string, cwd: string, abs: string | null = null): DshSession {
  return new DshSession({
    'id': id, 'rootId': rootId, 'cwd': cwd, 'cwdAbsolute': abs, 'updatedAt': 1,
  } as Record<string, Object>);
}

test('locationLabel：空 cwd 显示根目录，否则显示相对路径', () => {
  assert.equal(locationLabel(''), '根目录');
  assert.equal(locationLabel('app/lib'), 'app/lib');
});

test('recentLocations：按 (rootId,cwd) 去重保序，跳过无根会话', () => {
  const list = [
    session('s1', 'r1', 'a', '/w/a'),
    session('s2', 'r1', 'a', '/w/a'),
    session('s3', 'r2', '', '/w2'),
    session('s4', '', '', null),
    session('s5', 'r1', 'b', '/w/b'),
  ];
  const out = recentLocations(list);
  assert.equal(out.length, 3);
  assert.deepEqual(out.map((x: SessionLocation) => x.key), ['r1\u0000a', 'r2\u0000', 'r1\u0000b']);
  assert.equal(out[0].label, 'a');
  assert.equal(out[1].label, '根目录');
});

test('recentLocations：空列表返回空', () => {
  assert.deepEqual(recentLocations([]), []);
});

test('locationSubtitle：优先绝对路径，退回 rootId，空 rootId 给说明', () => {
  const list = [session('s1', 'r1', 'a', '/w/a')];
  assert.equal(locationSubtitle(list, new SessionLocation('r1', 'a', 'a')), '/w/a');
  assert.equal(locationSubtitle(list, new SessionLocation('r9', '', '根目录')), 'r9');
  assert.equal(locationSubtitle(list, new SessionLocation('', '', '根目录')), '首个授权根');
});

test('parentPath：逐级上退，根处原样', () => {
  assert.equal(parentPath('a/b/c'), 'a/b');
  assert.equal(parentPath('a'), '');
  assert.equal(parentPath(''), '');
});

test('locationChipLabel：默认项与已选项文案', () => {
  assert.equal(locationChipLabel(null), '工作目录：手机会话（默认）');
  assert.equal(locationChipLabel(new SessionLocation('r1', 'app', 'app')), '工作目录：app');
});

test('SessionLocation.key：同根同目录键相同，不同目录键不同', () => {
  const a = new SessionLocation('r1', 'x', 'x');
  const b = new SessionLocation('r1', 'x', '别名字');
  const c = new SessionLocation('r1', 'y', 'y');
  assert.equal(a.key, b.key);
  assert.notEqual(a.key, c.key);
});
