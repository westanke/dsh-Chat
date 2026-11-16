import test from 'node:test';
import assert from 'node:assert/strict';

import {
  BP_SM, BP_MD, BP_LG, BP_QUERY_MD, BP_QUERY_LG,
  breakpointOf, atLeastMd, isLarge,
  contentMaxWidth, drawerWidth, sheetMaxWidth, drawerFraction,
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

test('contentMaxWidth：手机不限宽，中/大屏居中留白', () => {
  assert.equal(contentMaxWidth(BP_SM), 0);
  assert.equal(contentMaxWidth(BP_MD), 720);
  assert.equal(contentMaxWidth(BP_LG), 840);
});

test('drawerWidth：随档加宽，手机档等于 360vp 屏的 80%', () => {
  assert.equal(drawerWidth(BP_SM), 288);
  assert.equal(drawerWidth(BP_MD), 352);
  assert.equal(drawerWidth(BP_LG), 400);
  // 档位单调不减：大屏抽屉不能比手机窄。
  assert.ok(drawerWidth(BP_SM) <= drawerWidth(BP_MD));
  assert.ok(drawerWidth(BP_MD) <= drawerWidth(BP_LG));
});

test('sheetMaxWidth：手机 0（交给系统 sheet），大屏限制行长', () => {
  assert.equal(sheetMaxWidth(BP_SM), 0);
  assert.equal(sheetMaxWidth(BP_MD), 640);
  assert.equal(sheetMaxWidth(BP_LG), 720);
});

test('drawerFraction：手机推 80%，大屏推得更少', () => {
  assert.equal(drawerFraction(BP_SM), 0.8);
  assert.equal(drawerFraction(BP_MD), 0.4);
  assert.equal(drawerFraction(BP_LG), 0.32);
  assert.ok(drawerFraction(BP_LG) < drawerFraction(BP_MD));
  assert.ok(drawerFraction(BP_MD) < drawerFraction(BP_SM));
});

test('未知档位退化为紧凑档（不抛异常、不返回 NaN）', () => {
  assert.equal(contentMaxWidth('xl'), 0);
  assert.equal(drawerWidth(''), 288);
  assert.equal(drawerFraction('huge'), 0.8);
  assert.equal(atLeastMd(''), false);
});
