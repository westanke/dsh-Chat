/**
 * @ 文件引用面板的纯逻辑 —— 从 Composer.ets 抽出（宪法 §7 单行数 + 让合并逻辑可单测）。
 *
 * 语义（对齐安卓 composer_bar.dart 的 @ 面板）：
 * - 面板列的是「授权根下的条目」，多根时每项名字前缀 `<根 label>/`；
 * - 只列当前目录（`dir`）的直接子项，目录可下钻（由 UI 维护 dir 与历史）；
 * - 输入 `@` 后跟的 query 按**名字前缀**过滤（不区分大小写，安卓同口径）；
 * - 多根并发拉取时某根报错（典型：下钻到只有单根存在的子目录，其余根 404）**不能**
 *   拖垮整张面板，逐根容错；只有「所有根都失败且当前在子目录」才算真失败。
 */

import { GatewayEntry, GatewayRoot } from './Files';
import { GatewayApi } from './GatewayApi';
import { DshSession } from './Models';
import { AtMentionDraft } from './Content';

/** 面板条目（UI 直接消费；kind 保留 file/directory 供图标与下钻判断）。 */
export class AtEntry {
  name: string = '';
  path: string = '';
  kind: string = '';
  isDirectory: boolean = false;

  static fromEntry(e: GatewayEntry, prefix: string): AtEntry {
    const a: AtEntry = new AtEntry();
    a.name = prefix + e.path;
    a.path = e.path;
    a.kind = e.kind;
    a.isDirectory = e.isDirectory;
    return a;
  }
}

/** 合并结果：可见条目 + 成功拉到的根数（判「全失败」用）。 */
export class AtMentionMerge {
  items: AtEntry[] = [];
  okRoots: number = 0;
}

/**
 * 合并多根条目并按 query 前缀过滤。
 * `lists[i]` 与 `labels[i]` 一一对应（labels 为空时不给前缀）。
 */
export function mergeAtEntries(lists: GatewayEntry[][], labels: string[],
                               query: string, inSubDir: boolean): AtMentionMerge {
  const out: AtMentionMerge = new AtMentionMerge();
  const q: string = query.toLowerCase();
  for (let i = 0; i < lists.length; i++) {
    const label: string = labels.length > i && labels[i].length > 0 ? labels[i] + '/' : '';
    const list: GatewayEntry[] = lists[i];
    // 根层（dir 为空）拿到空列表也算「这个根可访问」；子目录层空列表可能是 404 兜底，不计。
    if (list.length > 0 || !inSubDir) {
      out.okRoots = out.okRoots + 1;
    }
    for (const e of list) {
      const a: AtEntry = AtEntry.fromEntry(e, label);
      if (q.length === 0 || a.name.toLowerCase().indexOf(q) === 0) {
        out.items.push(a);
      }
    }
  }
  return out;
}

/** dir 为空（根层）时不算「在子目录里」——决定全失败判定。 */
export function inSubDirectory(dir: string): boolean {
  return dir.trim().length > 0;
}

/**
 * 逐根拉取当前目录条目并合并（store/api 参数纯函数，「选择项目中的内容」与
 * @ 补全共用）：某个根 404 不拖垮整张面板，全部失败才 okRoots===0。
 * 多根时才给 `label/` 前缀，单根直接列原名（安卓同口径）。
 */
export function loadMergedAtEntries(api: GatewayApi, roots: GatewayRoot[],
                                    dir: string, query: string): Promise<AtMentionMerge> {
  const jobs: Promise<GatewayEntry[]>[] = [];
  for (let i = 0; i < roots.length; i++) {
    jobs.push(api.listEntriesRest(roots[i].id, dir)
      .catch((e: Error): GatewayEntry[] => new Array<GatewayEntry>()));
  }
  return Promise.all(jobs).then((lists: GatewayEntry[][]): AtMentionMerge => {
    const labels: string[] = [];
    for (let i = 0; i < roots.length; i++) {
      labels.push(roots.length > 1 ? roots[i].label : '');
    }
    return mergeAtEntries(lists, labels, query, inSubDirectory(dir));
  });
}


// ---------- @ 历史会话（安卓 composer_at_sessions.dart 口径） ----------

/** 面板里的「对话」条目。 */
export class AtSessionHit {
  id: string = '';
  title: string = '';

  constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
  }
}

/**
 * 标题子串匹配（不区分大小写），排除当前会话、空标题，最多 max 条。
 * 设计口径：@ 面板先列「对话」再列文件；文件名过滤用前缀，会话用子串。
 */
export function sessionMatches(sessions: DshSession[], currentId: string | null,
                               query: string, max: number = 6): AtSessionHit[] {
  const out: AtSessionHit[] = [];
  const q: string = query.trim().toLowerCase();
  for (const s of sessions) {
    if (out.length >= max) {
      break;
    }
    if (currentId !== null && s.id === currentId) {
      continue;
    }
    const title: string = (s.title ?? '').trim();
    if (title === '') {
      continue;
    }
    if (q.length > 0 && title.toLowerCase().indexOf(q) < 0) {
      continue;
    }
    out.push(new AtSessionHit(s.id, title));
  }
  return out;
}

/**
 * 把 `@部分` 换成 `@[标题](dsh-session:<id>) `；标题里的 `]` 换全角］
 * （否则 Markdown 链接会提前闭合）。标题空时用 id 当文字。
 */
export function insertSessionMention(draft: string, at: AtMentionDraft,
                                     id: string, title: string): string {
  const label: string = (title.trim() === '' ? id : title.trim()).replace(/\]/g, '］');
  const mention: string = '@[' + label + '](dsh-session:' + id + ') ';
  return draft.substring(0, at.start) + mention + draft.substring(at.end);
}

/** `@src/li` → 目录部分 `src`（无 `/` 返回空串）。 */
export function atQueryDir(query: string): string {
  const i: number = query.lastIndexOf('/');
  return i < 0 ? '' : query.substring(0, i);
}

/** `@src/li` → 叶子过滤词 `li`（无 `/` 返回整串）。 */
export function atLeafQuery(query: string): string {
  const i: number = query.lastIndexOf('/');
  return i < 0 ? query : query.substring(i + 1);
}

/** 拼当前浏览目录与 @ 里的目录段（`src/` + `li` 两段都可能为空）。 */
export function joinAtDir(baseDir: string, queryDir: string): string {
  const base: string = baseDir.replace(/\/+$/, '');
  const sub: string = queryDir.replace(/^\/+/, '').replace(/\/+$/, '');
  if (sub === '') {
    return base;
  }
  return base === '' ? sub : base + '/' + sub;
}
