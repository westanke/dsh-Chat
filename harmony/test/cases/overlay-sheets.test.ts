/**
 * core/OverlaySheets 的纯逻辑单测（node:test，无鸿蒙 SDK 依赖）。
 *
 * 覆盖：七个浮层的开关判定、标题映射、优先级与「都没开」的空串口径。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sheetOpenOf, sheetTitleOf } from '../../entry/src/main/ets/core/OverlaySheets';
import type { SheetFlags } from '../../entry/src/main/ets/core/OverlaySheets';

function flags(over: Partial<SheetFlags> = {}): SheetFlags {
  return {
    stats: false,
    trajectory: false,
    team: false,
    todo: false,
    model: false,
    loc: false,
    codeWork: false,
    ...over,
  };
}

test('都没开：sheetOpenOf=false、标题空串', () => {
  assert.equal(sheetOpenOf(flags()), false);
  assert.equal(sheetTitleOf(flags()), '');
});

test('七个浮层各自都能判定为开、标题对得上', () => {
  const cases: Array<[keyof SheetFlags, string]> = [
    ['stats', '会话统计'],
    ['trajectory', '运行轨迹'],
    ['team', '智能团队'],
    ['todo', '任务'],
    ['model', '调整模型'],
    ['loc', '会话工作目录'],
    ['codeWork', '代码工作视图'],
  ];
  for (const [key, title] of cases) {
    const f = flags({ [key]: true } as Partial<SheetFlags>);
    assert.equal(sheetOpenOf(f), true, `${key} 应判定为开着`);
    assert.equal(sheetTitleOf(f), title, `${key} 的标题`);
  }
});

test('同时开多个：按声明顺序取第一个命中的标题', () => {
  // stats 在 trajectory 之前 → 取「会话统计」。
  assert.equal(sheetTitleOf(flags({ stats: true, trajectory: true })), '会话统计');
  // team 在 todo 之前。
  assert.equal(sheetTitleOf(flags({ team: true, todo: true })), '智能团队');
  // model 在 loc 之前。
  assert.equal(sheetTitleOf(flags({ model: true, loc: true })), '调整模型');
  // 兜底那个（codeWork）只有在前面都没开时才轮到。
  assert.equal(sheetTitleOf(flags({ codeWork: true, loc: true })), '会话工作目录');
});

test('只在某个浮层关着时，标题不会串到下一个', () => {
  assert.equal(sheetTitleOf(flags({ codeWork: true })), '代码工作视图');
  assert.equal(sheetOpenOf(flags({ codeWork: true })), true);
});
