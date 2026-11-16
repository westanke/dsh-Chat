/**
 * 会话抽屉分组/排序 —— 真机反馈 2026-11-16：列表**先按时间、再按工作区**排序，
 * 超过 2 天的会话收进可折叠的「更早」分组。
 *
 * 与安卓 `app/lib/ui/session_groups.dart` 的差异（PORT-MAP 已记）：安卓是
 * 「工作区优先、组内再分今天/昨天/更早」；本版按用户要求反过来 —— 时间优先
 * 分桶（今天 / 昨天 / 更早），桶内再按工作区名聚成一节，工作区名相同的连续
 * 会话只显示一次小节标题。
 *
 * 纯逻辑、无 ArkUI 依赖，node:test 直测。
 */

import { DshSession } from './Models';

/** 超过这个天数的会话归「更早」并默认收起（用户口径：超过 2 天）。 */
export const COLLAPSE_AFTER_DAYS: number = 2;

/** 「更早」分组的固定 key（抽屉据此记住展开态）。 */
export const GROUP_KEY_EARLIER: string = 'earlier';

/** 一天毫秒数。 */
const DAY_MS: number = 86400000;

/** 一行会话在抽屉里的渲染信息。 */
export class SessionRow {
  /** 对应会话。 */
  readonly session: DshSession;

  /**
   * 该行上方要显示的「工作区」小节标题；空串 = 与上一行同工作区，不重复显示。
   * 首行总是带标题（可能是「未分组」）。
   */
  readonly sectionLabel: string;

  constructor(session: DshSession, sectionLabel: string) {
    this.session = session;
    this.sectionLabel = sectionLabel;
  }
}

/** 一个时间分组（今天 / 昨天 / 更早）。 */
export class SessionGroup {
  /** 稳定分组键：'today' / 'yesterday' / 'earlier'。 */
  readonly key: string;

  /** 分组标题（今天 / 昨天 / 更早）。 */
  readonly title: string;

  /** 该组内的行（已按 工作区 → 时间 排好序）。 */
  readonly rows: SessionRow[];

  /** 是否属于「超过 2 天」的可折叠分组。 */
  readonly collapsible: boolean;

  constructor(key: string, title: string, rows: SessionRow[], collapsible: boolean) {
    this.key = key;
    this.title = title;
    this.rows = rows;
    this.collapsible = collapsible;
  }

  /** 组内会话数（折叠态标题上显示条数）。 */
  count(): number {
    return this.rows.length;
  }
}

/** 工作区名（空 → 「未分组」）。 */
export function workspaceLabelOf(s: DshSession): string {
  const t: string | null = s.workspaceTitle;
  if (t === null || t === '') {
    return '未分组';
  }
  return t;
}

/**
 * 会话分桶下标：0=今天，1=昨天，2=更早（按本地日历天算，跨月/跨年都对）。
 * nowMs 与 updatedAt 都是 epoch 毫秒。
 */
export function dayBucketOf(updatedAt: number, nowMs: number): number {
  if (updatedAt <= 0) {
    return 2;
  }
  const now: Date = new Date(nowMs);
  const then: Date = new Date(updatedAt);
  // 用「本地日历天」的零点比较，避免 23:59 与会话 00:01 被算成同一天。
  const nowDay: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const thenDay: number = new Date(then.getFullYear(), then.getMonth(), then.getDate()).getTime();
  const diffDays: number = Math.round((nowDay - thenDay) / DAY_MS);
  if (diffDays <= 0) {
    return 0;
  }
  if (diffDays === 1) {
    return 1;
  }
  return 2;
}

/** 会话排序：时间倒序（最新在前），同一时刻按工作区名升序（二次键）。 */
function compareSessions(a: DshSession, b: DshSession): number {
  if (a.updatedAt !== b.updatedAt) {
    return b.updatedAt - a.updatedAt;
  }
  const wa: string = workspaceLabelOf(a);
  const wb: string = workspaceLabelOf(b);
  if (wa === wb) {
    return 0;
  }
  return wa < wb ? -1 : 1;
}

/**
 * 把桶内会话按「工作区」聚成连续小节：工作区按首次出现顺序（即该组内最新会话的
 * 时间顺序）排列，同工作区内保持时间倒序。返回带 sectionLabel 的行。
 */
function rowsOf(bucket: DshSession[]): SessionRow[] {
  const byWs: Map<string, DshSession[]> = new Map<string, DshSession[]>();
  const order: string[] = [];
  for (const s of bucket) {
    const w: string = workspaceLabelOf(s);
    let arr: DshSession[] | undefined = byWs.get(w);
    if (arr === undefined) {
      arr = [];
      byWs.set(w, arr);
      order.push(w);
    }
    arr.push(s);
  }
  const rows: SessionRow[] = [];
  for (const w of order) {
    const arr: DshSession[] = byWs.get(w) as DshSession[];
    for (let i = 0; i < arr.length; i++) {
      rows.push(new SessionRow(arr[i], i === 0 ? w : ''));
    }
  }
  return rows;
}

/**
 * 抽屉分组总入口：先按时间分桶（今天/昨天/更早），桶内按工作区聚合。
 * 空桶不产出；顺序固定 今天 → 昨天 → 更早。
 */
export function groupSessionsByTime(sessions: DshSession[], nowMs: number): SessionGroup[] {
  const buckets: DshSession[][] = [[], [], []];
  for (const s of sessions) {
    buckets[dayBucketOf(s.updatedAt, nowMs)].push(s);
  }
  for (const b of buckets) {
    b.sort(compareSessions);
  }
  const out: SessionGroup[] = [];
  if (buckets[0].length > 0) {
    out.push(new SessionGroup('today', '今天', rowsOf(buckets[0]), false));
  }
  if (buckets[1].length > 0) {
    out.push(new SessionGroup('yesterday', '昨天', rowsOf(buckets[1]), false));
  }
  if (buckets[2].length > 0) {
    // 超过 2 天的全部归这里，默认收起（用户口径）。
    out.push(new SessionGroup(GROUP_KEY_EARLIER, '更早', rowsOf(buckets[2]), true));
  }
  return out;
}

/** 展开/收起后实际要渲染的分组（收起态把「更早」的行换成 0 行）。 */
export function visibleRowsOf(group: SessionGroup, expandedEarlier: boolean): SessionRow[] {
  if (group.collapsible && !expandedEarlier) {
    return [];
  }
  return group.rows;
}
