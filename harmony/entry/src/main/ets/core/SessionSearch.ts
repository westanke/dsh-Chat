/**
 * 会话内容搜索（内核端点 `session/search`，走 `dshrb-v1` 通用调用面）。
 *
 * 对齐安卓 `app/lib/ui/session_search.dart`：
 * - 抽屉里按标题本地过滤只能搜到已拉下来的标题；正文命中必须问内核；
 * - 目录是唯一真相：`args` 的键按 `kernel-endpoints` 的 `wires` 拼，不硬编码；
 * - 结果 `{items:[{sessionId, snippet}], hasMore}`，snippet 是内核已截断的片段；
 * - 降级：没有 `dshrb-v1` / 目录里没这个端点 → 调用方原样退回标题过滤；
 * - 部署侧已知限制：内核会话索引默认 `openAt:"never"`，端点调得通但结果可能为空，
 *   所以「空结果」不能文案上写死「没有匹配」。
 *
 * 纯逻辑，node 直测。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { KernelEndpoint } from './KernelCall';

/** 一条内容命中：会话 id + 摘要片段（片段可能带高亮标记，按纯文本渲染）。 */
export class SessionSearchHit {
  sessionId: string = '';
  snippet: string = '';

  constructor(sessionId: string, snippet: string) {
    this.sessionId = sessionId;
    this.snippet = snippet;
  }
}

/** 片段里的换行/制表/连续空白压成单空格：单行省略号显示，多行只会被截掉。 */
export function tidySnippet(raw: string): string {
  let out: string = '';
  let space: boolean = false;
  for (let i = 0; i < raw.length; i++) {
    const ch: string = raw.charAt(i);
    const isSpace: boolean = ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t';
    if (isSpace) {
      space = true;
      continue;
    }
    if (space && out !== '') {
      out += ' ';
    }
    space = false;
    out += ch;
  }
  return out;
}

/**
 * 解析 `session/search` 的 `value`。宽容到底：形状不认识回空表、不抛错，
 * 搜索失败不该让抽屉整片红。
 */
export function parseSessionSearchHits(value: Object | null, limit: number = 0): SessionSearchHit[] {
  const map: JsonMap | null = JsonAccess.asMap(value);
  if (map === null) {
    return [];
  }
  const items: JsonMap[] = JsonAccess.objArr(map, 'items');
  const out: SessionSearchHit[] = [];
  for (let i = 0; i < items.length; i++) {
    const id: string = JsonAccess.strOr(items[i], 'sessionId', '');
    if (id === '') {
      continue;
    }
    const rawSnippet: string | null = JsonAccess.str(items[i], 'snippet');
    out.push(new SessionSearchHit(id, rawSnippet === null ? '' : tidySnippet(rawSnippet)));
    if (limit > 0 && out.length >= limit) {
      break;
    }
  }
  return out;
}

/** 结果里的 hasMore（原样保留，翻页语义不变）。 */
export function sessionSearchHasMore(value: Object | null): boolean {
  const map: JsonMap | null = JsonAccess.asMap(value);
  return map !== null && JsonAccess.boolOr(map, 'hasMore', false);
}

/**
 * 拼 `session/search` 的 `args`：键名以目录 `wires` 为准。
 * 目录里没有这个端点时退回已知形状 `{request:{query}}`，让调用链拿到明确错误帧。
 */
export function sessionSearchArgs(endpoint: KernelEndpoint | null, query: string): JsonMap {
  const wires: string[] = endpoint === null ? [] : endpoint.wires;
  if (wires.length === 0) {
    return { request: { query: query } };
  }
  for (let i = 0; i < wires.length; i++) {
    if (wires[i] === 'request') {
      return { request: { query: query } };
    }
    if (wires[i] === 'query') {
      return { query: query };
    }
  }
  // 描述符形状不认识：把 query 塞进第一个 wire 键，让桥按自己的判据回明确的参数错误。
  const out: JsonMap = {};
  out[wires[0]] = { query: query };
  return out;
}
