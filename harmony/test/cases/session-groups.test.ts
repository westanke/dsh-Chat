/**
 * SessionGroups 测试 —— 会话抽屉「先时间、后工作区、超 2 天折叠」口径。
 * 对应真机反馈 2026-11-16。
 */

import test, { after } from 'node:test';
import assert from 'node:assert/strict';

import { DshSession } from '../../entry/src/main/ets/core/Models.ts';
import {
  COLLAPSE_AFTER_DAYS,
  GROUP_KEY_EARLIER,
  SessionGroup,
  SessionRow,
  dayBucketOf,
  groupSessionsByTime,
  visibleRowsOf,
  workspaceLabelOf,
} from '../../entry/src/main/ets/core/SessionGroups.ts';

/** 2026-11-16 12:00 本地时间（分组基准）。 */
const NOW: number = new Date(2026, 10, 16, 12, 0, 0).getTime();

function ms(daysAgo: number, hour: number): number {
  const d = new Date(2026, 10, 16 - daysAgo, hour, 0, 0);
  return d.getTime();
}

function session(id: string, updatedAt: number, workspaceTitle: string | null): DshSession {
  return DshSession.fromJson({
    id: id,
    rootId: 'root',
    updatedAt: updatedAt,
    title: id,
    workspaceTitle: workspaceTitle,
  });
}

after(() => {
  // 纯函数用例无资源需释放；保留 hook 便于后续扩展。
});

test('dayBucketOf：今天/昨天/更早按本地日历天分桶', () => {
  assert.equal(dayBucketOf(ms(0, 1), NOW), 0, '当天凌晨属今天');
  assert.equal(dayBucketOf(ms(0, 23), NOW), 0, '当天深夜属今天');
  assert.equal(dayBucketOf(ms(1, 23), NOW), 1, '昨天深夜属昨天');
  assert.equal(dayBucketOf(ms(2, 0), NOW), 2, '前天属更早');
  assert.equal(dayBucketOf(ms(30, 9), NOW), 2, '一个月前属更早');
  assert.equal(dayBucketOf(0, NOW), 2, '缺 updatedAt 归更早（无法判断新旧）');
});

test('workspaceLabelOf：空工作区落「未分组」', () => {
  assert.equal(workspaceLabelOf(session('a', NOW, '手机会话')), '手机会话');
  assert.equal(workspaceLabelOf(session('b', NOW, null)), '未分组');
  assert.equal(workspaceLabelOf(session('c', NOW, '')), '未分组');
});

test('groupSessionsByTime：分组顺序固定 今天 → 昨天 → 更早', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('early', ms(5, 9), 'ws-a'),
    session('yday', ms(1, 9), 'ws-a'),
    session('today', ms(0, 9), 'ws-a'),
  ], NOW);
  assert.equal(groups.length, 3);
  assert.equal(groups[0].title, '今天');
  assert.equal(groups[1].title, '昨天');
  assert.equal(groups[2].title, '更早');
  assert.equal(groups[2].key, GROUP_KEY_EARLIER);
  assert.equal(groups[0].collapsible, false);
  assert.equal(groups[2].collapsible, true, '更早默认可折叠');
});

test('groupSessionsByTime：空桶不产出分组', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('t1', ms(0, 9), 'ws-a'),
    session('t2', ms(0, 10), 'ws-a'),
  ], NOW);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].title, '今天');
});

test('groupSessionsByTime：桶内时间倒序（最新在前）', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('old', ms(0, 3), 'ws-a'),
    session('new', ms(0, 11), 'ws-a'),
    session('mid', ms(0, 7), 'ws-a'),
  ], NOW);
  const ids: string[] = groups[0].rows.map((r: SessionRow) => r.session.id);
  assert.deepEqual(ids, ['new', 'mid', 'old']);
});

test('groupSessionsByTime：桶内按工作区聚合，同工作区只显示一次小节标题', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('a1', ms(0, 11), 'ws-a'),
    session('b1', ms(0, 10), 'ws-b'),
    session('a2', ms(0, 9), 'ws-a'),
    session('a3', ms(0, 8), 'ws-a'),
  ], NOW);
  const rows: SessionRow[] = groups[0].rows;
  // 时间倒序先定工作区出现顺序：ws-a（11点）→ ws-b（10点）；
  // a2/a3 虽在 b1 之后，也要并回 ws-a 小节尾部。
  assert.deepEqual(rows.map((r: SessionRow) => r.session.id), ['a1', 'a2', 'a3', 'b1']);
  assert.deepEqual(rows.map((r: SessionRow) => r.sectionLabel), ['ws-a', '', '', 'ws-b']);
});

test('groupSessionsByTime：无工作区会话的小节名是「未分组」', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('n1', ms(0, 11), null),
    session('n2', ms(0, 10), null),
  ], NOW);
  const rows: SessionRow[] = groups[0].rows;
  assert.equal(rows[0].sectionLabel, '未分组');
  assert.equal(rows[1].sectionLabel, '');
});

test('groupSessionsByTime：同一时刻按工作区名升序（二次排序键）', () => {
  const same: number = ms(0, 9);
  const groups: SessionGroup[] = groupSessionsByTime([
    session('z', same, 'ws-z'),
    session('a', same, 'ws-a'),
  ], NOW);
  assert.deepEqual(groups[0].rows.map((r: SessionRow) => r.session.id), ['a', 'z']);
});

test('visibleRowsOf：更早分组收起时返回空行，其它分组不受影响', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('t', ms(0, 9), 'ws-a'),
    session('e', ms(5, 9), 'ws-a'),
  ], NOW);
  const today: SessionGroup = groups[0];
  const earlier: SessionGroup = groups[1];
  assert.equal(visibleRowsOf(today, false).length, 1, '今天永远可见');
  assert.equal(visibleRowsOf(earlier, false).length, 0, '更早收起时 0 行');
  assert.equal(visibleRowsOf(earlier, true).length, 1, '展开后可见');
});

test('SessionGroup.count 与 COLLAPSE_AFTER_DAYS 常量', () => {
  const groups: SessionGroup[] = groupSessionsByTime([
    session('e1', ms(3, 9), 'ws-a'),
    session('e2', ms(9, 9), 'ws-a'),
  ], NOW);
  assert.equal(groups[0].count(), 2);
  assert.equal(COLLAPSE_AFTER_DAYS, 2, '用户口径：超过 2 天才收起');
});
