/**
 * 新建会话工作目录 —— 对照安卓 app/lib/ui/session_location_sheet.dart 的
 * 纯逻辑部分（core，node 直测）。鸿蒙版 2026-11-16 按用户反馈补齐：
 * 「安卓新建会话有默认目录，可选目录」。
 *
 * 语义（两端一致）：
 * - 默认（null）= 落「手机会话」工作区（ensureMobileWorkspace 通道）；
 * - 选了某授权根下的目录 → 首条消息走 session-create{rootId,cwd}，
 *   会话落「未分组」，目录在创建时定死，历史会话不受影响。
 */

import { DshSession } from './Models';

/** 授权根（GET /api/v1/roots 项）。 */
export class LocationRoot {
  readonly id: string;
  readonly label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

/** 新建会话的目标工作目录（rootId 空 = 首个授权根；cwd 是根内相对路径）。 */
export class SessionLocation {
  readonly rootId: string;
  readonly cwd: string;
  readonly label: string;

  constructor(rootId: string, cwd: string, label: string) {
    this.rootId = rootId;
    this.cwd = cwd;
    this.label = label;
  }

  /** 契约串（UI 层 @State 比较/编码用，避免直接比对象引用）。 */
  get key(): string {
    return this.rootId + '\u0000' + this.cwd;
  }
}

/** 目录显示名：'' = 授权根本身；否则显示相对路径。 */
export function locationLabel(cwd: string): string {
  return cwd === '' ? '根目录' : cwd;
}

/**
 * 历史会话的目录候选（(rootId, cwd) 去重、保序）——会话列表已按 updatedAt
 * 倒序，所以最近用过的排前（安卓 recentCandidates 同口径）。
 * 排除「没有任何根信息」的会话（rootId 与 cwd 都空 = 手机工作区会话）。
 */
export function recentLocations(sessions: DshSession[]): SessionLocation[] {
  const out: SessionLocation[] = [];
  const seen: string[] = [];
  for (const s of sessions) {
    if (s.rootId === '') {
      continue;
    }
    const key: string = s.rootId + '\u0000' + s.cwd;
    if (seen.indexOf(key) >= 0) {
      continue;
    }
    seen.push(key);
    out.push(new SessionLocation(s.rootId, s.cwd, locationLabel(s.cwd)));
  }
  return out;
}

/** 候选副标题：优先会话快照的绝对路径（比 uuid 可读），退回 rootId。 */
export function locationSubtitle(sessions: DshSession[], loc: SessionLocation): string {
  for (const s of sessions) {
    if (s.rootId === loc.rootId && s.cwd === loc.cwd) {
      const abs: string | null = s.cwdAbsolute;
      if (abs !== null && abs !== '') {
        return abs;
      }
      break;
    }
  }
  return loc.rootId === '' ? '首个授权根' : loc.rootId;
}

/** 面包屑上退一级（'' 已到根，原样返回）。 */
export function parentPath(path: string): string {
  const idx: number = path.lastIndexOf('/');
  return idx < 0 ? '' : path.substring(0, idx);
}

/** 面板标题上的当前选择描述（默认项与已选项统一口径）。 */
export function locationChipLabel(loc: SessionLocation | null): string {
  if (loc === null) {
    return '工作目录：手机会话（默认）';
  }
  return '工作目录：' + loc.label;
}
