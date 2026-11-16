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

import { GatewayEntry } from './Files';

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
