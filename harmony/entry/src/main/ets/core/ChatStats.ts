/**
 * 会话统计的**服务端半边** —— 桥 `session-stats` 帧（bridge ≥ 2.12：
 * sessionStats / tokenUsage / contextPressure 三个容器）。本地那半仍在
 * core/Projections.ts 的 chatStatsOf（不产生网络请求）。
 *
 * 口径（与 app/lib/ui/stats_sheet.dart 对齐）：
 * - 桥把内核字段原样透传，键名与单位不在本仓契约里，所以这里**不翻译键名、
 *   不猜单位**，只把标量叶子拍平成「分组 / 键 / 值」；Map/List/null 一律跳过；
 * - 空分组直接消失，不留空标题；
 * - 老桥没有这一帧（回 UNKNOWN_TYPE）是常态：失败静默，UI 回落本地统计，
 *   不许把「能力缺席」渲染成「出错了」。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import type { ChatStore } from './ChatStore';

/** 一行服务端统计（分组标题 + 原始键 + 格式化后的值）。 */
export class ServerStatRow {
  group: string;
  label: string;
  value: string;

  constructor(group: string, label: string, value: string) {
    this.group = group;
    this.label = label;
    this.value = value;
  }
}

/** 容器键 → 面板分组标题（顺序即渲染顺序）。 */
class StatGroup {
  key: string;
  title: string;

  constructor(key: string, title: string) {
    this.key = key;
    this.title = title;
  }
}

const SERVER_GROUPS: StatGroup[] = [
  new StatGroup('sessionStats', '服务端统计'),
  new StatGroup('tokenUsage', 'Token 用量'),
  new StatGroup('contextPressure', '上下文占用'),
];

/** 标量 → 显示文本；非标量返回 ''（跳过）。 */
function scalarText(v: Object | null): string {
  if (v === null || v === undefined) {
    return '';
  }
  if (typeof v === 'number') {
    return (v as number).toString();
  }
  if (typeof v === 'boolean') {
    return (v as boolean) ? '是' : '否';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  return '';
}

/** 纯函数：`session-stats` 应答 → 扁平行（便于单测）。 */
export function serverStatRows(stats: JsonMap | null): ServerStatRow[] {
  const out: ServerStatRow[] = [];
  if (stats === null) {
    return out;
  }
  for (const g of SERVER_GROUPS) {
    const raw: JsonMap | null = JsonAccess.obj(stats, g.key);
    if (raw === null) {
      continue;
    }
    for (const k of Object.keys(raw)) {
      const text: string = scalarText(JsonAccess.raw(raw, k));
      if (text !== '') {
        out.push(new ServerStatRow(g.title, k, text));
      }
    }
  }
  return out;
}

/**
 * 拉一次服务端统计写回 store（统计面板打开时调）。失败静默置 null ——
 * 「桥没这一帧」与「网络抖了一下」都不该弹错误，本地统计照常显示。
 */
export function loadServerStatsIn(store: ChatStore): void {
  const id: string | null = store.sessionId;
  if (id === null || id === '') {
    return;
  }
  store.api.sessionStats(id).then((data: JsonMap): void => {
    if (store.sessionId !== id) {
      return; // 期间切了会话：丢弃
    }
    store.serverStats = data;
    store.changed();
  }).catch((e: Error): void => {
    if (store.sessionId === id) {
      store.serverStats = null;
      store.changed();
    }
  });
}
