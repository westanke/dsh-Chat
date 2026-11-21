/**
 * 输入条上方的任务条（安卓 app/lib/ui/todo_dock.dart，240 行）。
 *
 * 数据来自投影 `values.todos`（core/Projections.todoItems）：全部完成 → 显示
 * 「全部完成」；正在跑且有 in_progress →「正在：<当前>」；否则「下一步：<首个未完成>」。
 * 展开后列出全部任务（最多 168vp 内滚）。纯逻辑，node 直测。
 */

import { TodoItem } from './Projections';

/** 任务条摘要（扁平类；ArkTS 禁判别联合）。 */
export class TodoDockSummary {
  total: number = 0;
  done: number = 0;
  /** 当前关注项（首个 in_progress，否则首个未完成；全完成时 null）。 */
  current: TodoItem | null = null;
  /** 「全部完成」/「正在：…」/「下一步：…」。 */
  headline: string = '';
  /** 是否还有未完成项。 */
  running: boolean = false;
  /** 进度比例 0..1（渲染进度线用）。 */
  fraction: number = 0;

  /** 空任务 → null（不占位，安卓同口径）。 */
  static of(todos: TodoItem[], running: boolean): TodoDockSummary | null {
    if (todos.length === 0) {
      return null;
    }
    const s: TodoDockSummary = new TodoDockSummary();
    s.total = todos.length;
    let done: number = 0;
    let inProgress: TodoItem | null = null;
    let firstOpen: TodoItem | null = null;
    for (let i = 0; i < todos.length; i++) {
      const t: TodoItem = todos[i];
      if (t.status === 'completed') {
        done += 1;
      } else {
        if (firstOpen === null) {
          firstOpen = t;
        }
        if (inProgress === null && t.status === 'in_progress') {
          inProgress = t;
        }
      }
    }
    s.done = done;
    s.fraction = todos.length === 0 ? 0 : done / todos.length;
    if (done === todos.length) {
      s.running = false;
      s.headline = '全部完成';
      return s;
    }
    s.running = running;
    s.current = inProgress !== null ? inProgress : firstOpen;
    if (running && s.current !== null && s.current.isInProgress) {
      s.headline = '正在：' + s.current.content;
    } else {
      s.headline = '下一步：' + (s.current === null ? '继续' : s.current.content);
    }
    return s;
  }
}

/** 行首状态字形（展开列表用）。 */
export function todoGlyph(status: string): string {
  if (status === 'completed') {
    return '✓';
  }
  if (status === 'in_progress') {
    return '●';
  }
  return '○';
}
