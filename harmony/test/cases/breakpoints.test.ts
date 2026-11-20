import test from 'node:test';
import assert from 'node:assert/strict';

import {
  BP_SM, BP_MD, BP_LG, BP_QUERY_MD, BP_QUERY_LG,
  breakpointOf, atLeastMd, isLarge,
  READABLE_BASE_WIDTH, READABLE_SCALE, FLOAT_INSET,
  readableColumnWidth, floatingColumnWidth,
  drawerWidth, drawerFraction,
} from '../../entry/src/main/ets/core/Breakpoints';

test('breakpointOf：大档优先，其次中等，其余紧凑', () => {
  assert.equal(breakpointOf(true, true), BP_LG);
  assert.equal(breakpointOf(true, false), BP_MD);
  assert.equal(breakpointOf(false, true), BP_LG);
  assert.equal(breakpointOf(false, false), BP_SM);
});

test('atLeastMd / isLarge 边界', () => {
  assert.equal(atLeastMd(BP_SM), false);
  assert.equal(atLeastMd(BP_MD), true);
  assert.equal(atLeastMd(BP_LG), true);
  assert.equal(isLarge(BP_SM), false);
  assert.equal(isLarge(BP_MD), false);
  assert.equal(isLarge(BP_LG), true);
});

test('mediaquery 查询串用 vp 阈值，不含 px', () => {
  assert.equal(BP_QUERY_MD, '(width>=600vp)');
  assert.equal(BP_QUERY_LG, '(width>=840vp)');
});

test('readableColumnWidth：≤720 用满，更宽按 0.9 缓增（不再有 720 硬上限）', () => {
  assert.equal(READABLE_BASE_WIDTH, 720);
  assert.equal(READABLE_SCALE, 0.9);
  // 手机：列宽 = 屏宽（与改动前逐字相同）。
  assert.equal(readableColumnWidth(360), 360);
  // 正好在基准宽：用满，不缩。
  assert.equal(readableColumnWidth(720), 720);
  // 比 720 宽一点：0.9 倍仍 > 720，跟屏宽长（旧的 720 上限会卡在这里）。
  assert.equal(readableColumnWidth(861), 774.9);
  assert.equal(readableColumnWidth(1181), 1062.9);
  assert.equal(readableColumnWidth(1600), 1440);
  // 没有第二道上限：屏再宽继续长。
  assert.ok(readableColumnWidth(2000) > readableColumnWidth(1600));
  // 未量到宽（0 / 负数）返回 0，调用方退化成 100%。
  assert.equal(readableColumnWidth(0), 0);
  assert.equal(readableColumnWidth(-10), 0);
});

test('readableColumnWidth：单调不减且永不超过可用宽', () => {
  let previous = 0;
  for (let w = 320; w <= 2400; w += 1) {
    const column = readableColumnWidth(w);
    assert.ok(column >= previous, `列宽在 ${w} 处回缩了`);
    assert.ok(column <= w, `列宽在 ${w} 处超过可用宽`);
    previous = column;
  }
});

test('floatingColumnWidth：没有富余就铺满，宽窗两侧各收 FLOAT_INSET', () => {
  assert.equal(FLOAT_INSET, 14);
  assert.equal(floatingColumnWidth(360), 360);
  assert.equal(floatingColumnWidth(600), 600);
  assert.equal(floatingColumnWidth(720), 720);
  assert.equal(floatingColumnWidth(738), 692);
  assert.equal(floatingColumnWidth(1181), 1034.9);
  assert.equal(floatingColumnWidth(0), 0);
});

test('drawerWidth：随档加宽，手机档等于 360vp 屏的 80%', () => {
  assert.equal(drawerWidth(BP_SM), 288);
  assert.equal(drawerWidth(BP_MD), 352);
  assert.equal(drawerWidth(BP_LG), 400);
  // 档位单调不减：大屏抽屉不能比手机窄。
  assert.ok(drawerWidth(BP_SM) <= drawerWidth(BP_MD));
  assert.ok(drawerWidth(BP_MD) <= drawerWidth(BP_LG));
});

test('drawerFraction：手机推 80%，大屏推得更少', () => {
  assert.equal(drawerFraction(BP_SM), 0.8);
  assert.equal(drawerFraction(BP_MD), 0.4);
  assert.equal(drawerFraction(BP_LG), 0.32);
  assert.ok(drawerFraction(BP_LG) < drawerFraction(BP_MD));
  assert.ok(drawerFraction(BP_MD) < drawerFraction(BP_SM));
});

test('未知档位退化为紧凑档（不抛异常、不返回 NaN）', () => {
  assert.equal(drawerWidth(''), 288);
  assert.equal(drawerFraction('huge'), 0.8);
  assert.equal(atLeastMd(''), false);
});
