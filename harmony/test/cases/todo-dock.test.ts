import test from 'node:test';
import assert from 'node:assert/strict';

import { TodoDockSummary, todoGlyph } from '../../entry/src/main/ets/core/TodoDock.ts';
import { TodoItem } from '../../entry/src/main/ets/core/Projections.ts';

function todo(content: string, status: string): TodoItem {
  const t: TodoItem = new TodoItem();
  t.content = content;
  t.status = status;
  return t;
}

test('TodoDockSummary：空任务不占位', () => {
  assert.equal(TodoDockSummary.of([], true), null);
});

test('TodoDockSummary：全部完成', () => {
  const s: TodoDockSummary = TodoDockSummary.of([todo('a', 'completed'), todo('b', 'completed')], false) as TodoDockSummary;
  assert.equal(s.headline, '全部完成');
  assert.equal(s.done, 2);
  assert.equal(s.fraction, 1);
  assert.equal(s.running, false);
});

test('TodoDockSummary：正在跑时优先 in_progress，否则首个未完成', () => {
  const s: TodoDockSummary = TodoDockSummary.of([todo('a', 'pending'), todo('b', 'in_progress')], true) as TodoDockSummary;
  assert.equal(s.headline, '正在：b');
  assert.equal(s.current?.content, 'b');
  assert.equal(s.fraction, 0);
  const noProgress: TodoDockSummary = TodoDockSummary.of([todo('a', 'pending'), todo('b', 'completed')], true) as TodoDockSummary;
  assert.equal(noProgress.headline, '下一步：a');
});

test('TodoDockSummary：未在跑时即使有 in_progress 也说下一步', () => {
  const s: TodoDockSummary = TodoDockSummary.of([todo('a', 'in_progress')], false) as TodoDockSummary;
  assert.equal(s.headline, '下一步：a');
});

test('todoGlyph：三态字形', () => {
  assert.deepEqual(['completed', 'in_progress', 'pending', 'x'].map(todoGlyph), ['✓', '●', '○', '○']);
});
