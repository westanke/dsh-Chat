/// Markdown 块级解析（纯逻辑，node 直测）—— 对齐安卓 md_view 口径。
/// 支持：标题 1-6 / 围栏代码 / 引用 / 无序有序列表 / 任务列表 / 表格 / hr /
/// 块级公式 $$..$$ / 段落。流式安全：未闭合结构照常收纳已输入部分。
/// ArkTS 口径：扁平 class + type 分派（禁判别联合），字段全默认值。
import { parseInline, InlineSeg } from './MdInline';
import { splitLatex } from './LatexLite';

export const MD_P = 'p';
export const MD_H = 'h';
export const MD_CODE = 'code';
export const MD_QUOTE = 'quote';
export const MD_UL = 'ul';
export const MD_OL = 'ol';
export const MD_TABLE = 'table';
export const MD_HR = 'hr';
export const MD_LATEX = 'latex';

export class MdListItem {
  text: string = '';
  segs: InlineSeg[] = [];
  checked: number = -1; // -1 非任务项；0 未勾；1 已勾
}

export class MdBlock {
  type: string = MD_P;
  level: number = 0; // 标题级别 1-6
  lang: string = ''; // 代码块语言标签
  text: string = ''; // p/h/quote/latex 的文本
  segs: InlineSeg[] = []; // p/h 的行内片段（quote 文本也走这里）
  items: MdListItem[] = []; // ul/ol
  rows: string[][] = []; // table（首行表头）
  align: string[] = []; // table 列对齐 l/c/r
}

/// 块级解析总入口。
export function parseMarkdown(text: string): MdBlock[] {
  const lines = text.split('\n');
  const out: MdBlock[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim().length === 0) {
      i += 1;
      continue;
    }
    const fence = matchFence(line);
    if (fence !== null) {
      const r = readFence(lines, i, fence.lang);
      out.push(r.block);
      i = r.next;
      continue;
    }
    if (isHr(line)) {
      const b = new MdBlock();
      b.type = MD_HR;
      out.push(b);
      i += 1;
      continue;
    }
    const h = matchHeading(line);
    if (h !== null) {
      const b = new MdBlock();
      b.type = MD_H;
      b.level = h.level;
      b.text = h.text;
      b.segs = parseInline(h.text);
      out.push(b);
      i += 1;
      continue;
    }
    if (isQuote(line)) {
      const r = readQuote(lines, i);
      out.push(r.block);
      i = r.next;
      continue;
    }
    if (isListItem(line)) {
      const r = readList(lines, i, false);
      out.push(r.block);
      i = r.next;
      continue;
    }
    if (isOrderedItem(line)) {
      const r = readList(lines, i, true);
      out.push(r.block);
      i = r.next;
      continue;
    }
    if (isTableStart(lines, i)) {
      const r = readTable(lines, i);
      out.push(r.block);
      i = r.next;
      continue;
    }
    if (isLatexBlockLine(line)) {
      const r = readLatexBlock(lines, i);
      out.push(r.block);
      i = r.next;
      continue;
    }
    const r = readParagraph(lines, i);
    out.push(r.block);
    i = r.next;
  }
  return out;
}

/// $$ 开行进块公式（单行闭合 / 多行块都由 readLatexBlock 收）。
function isLatexBlockLine(line: string): boolean {
  return line.trim().startsWith('$$');
}

class FenceSig {
  lang: string = '';
  marker: string = '```';
}

function matchFence(line: string): FenceSig | null {
  const t = line.trim();
  if (t.startsWith('```')) {
    const s = new FenceSig();
    s.marker = '```';
    s.lang = t.substring(3).trim();
    return s;
  }
  if (t.startsWith('~~~')) {
    const s = new FenceSig();
    s.marker = '~~~';
    s.lang = t.substring(3).trim();
    return s;
  }
  return null;
}

function readFence(lines: string[], at: number, lang: string): { block: MdBlock, next: number } {
  const body: string[] = [];
  let i = at + 1;
  const close = lines[at].trim().substring(0, 3);
  while (i < lines.length) {
    if (lines[i].trim().startsWith(close)) {
      return { block: codeBlock(lang, body.join('\n')), next: i + 1 };
    }
    body.push(lines[i]);
    i += 1;
  }
  // 流式未闭合：已输入部分照常显示
  return { block: codeBlock(lang, body.join('\n')), next: i };
}

function codeBlock(lang: string, code: string): MdBlock {
  const b = new MdBlock();
  b.type = MD_CODE;
  b.lang = lang.trim();
  b.text = code;
  return b;
}

const RE_HEADING: RegExp = /^(#{1,6})\s+(.+)$/;

function matchHeading(line: string): { level: number, text: string } | null {
  const m = RE_HEADING.exec(line);
  if (m === null) {
    return null;
  }
  return { level: m[1].length, text: m[2].trim() };
}

function isHr(line: string): boolean {
  const t = line.trim();
  if (t.length < 3) {
    return false;
  }
  let ok = true;
  for (const ch of ['-', '*', '_']) {
    ok = true;
    let count = 0;
    for (const c of t) {
      if (c === ch) {
        count += 1;
      } else if (c !== ' ') {
        ok = false;
        break;
      }
    }
    if (ok && count >= 3) {
      return true;
    }
  }
  return false;
}

function isQuote(line: string): boolean {
  return line.trimStart().startsWith('>');
}

function readQuote(lines: string[], at: number): { block: MdBlock, next: number } {
  const body: string[] = [];
  let i = at;
  while (i < lines.length && isQuote(lines[i])) {
    body.push(lines[i].trimStart().substring(1).trimStart());
    i += 1;
  }
  const b = new MdBlock();
  b.type = MD_QUOTE;
  b.text = body.join('\n');
  b.segs = parseInline(b.text);
  return { block: b, next: i };
}

const RE_UL: RegExp = /^\s*[-*+]\s+(.*)$/;
const RE_OL: RegExp = /^\s*\d+[.)]\s+(.*)$/;
const RE_TASK: RegExp = /^\[([ xX])\]\s+(.*)$/;

function isListItem(line: string): boolean {
  return RE_UL.test(line) && !isTaskMarkerOnly(line);
}

function isOrderedItem(line: string): boolean {
  return RE_OL.test(line);
}

/// 行首列表符号 + 勾选框（安卓 normalizeTaskLists 口径：圆点不吃任务项）。
function isTaskMarkerOnly(line: string): boolean {
  const m = RE_UL.exec(line);
  if (m === null) {
    return false;
  }
  return RE_TASK.test(m[1]);
}

function readList(lines: string[], at: number, ordered: boolean): { block: MdBlock, next: number } {
  const items: MdListItem[] = [];
  let i = at;
  while (i < lines.length) {
    const line = lines[i];
    const m = ordered ? RE_OL.exec(line) : RE_UL.exec(line);
    if (m === null) {
      break;
    }
    let content = m[1];
    const item = new MdListItem();
    const task = RE_TASK.exec(content);
    if (task !== null) {
      item.checked = task[1] === ' ' ? 0 : 1;
      content = task[2];
    }
    item.text = content.trim();
    item.segs = parseInline(item.text);
    items.push(item);
    i += 1;
  }
  const b = new MdBlock();
  b.type = ordered ? MD_OL : MD_UL;
  b.items = items;
  return { block: b, next: i };
}

/// 分隔行判定：整行拆格后每格形如 :--- / ---: / :---: / ---
function isAlignRow(line: string): boolean {
  const cells = splitTableRow(line);
  if (cells.length === 0) {
    return false;
  }
  for (const c of cells) {
    if (!/^:?-+:?$/.test(c)) {
      return false;
    }
  }
  return true;
}

function isTableStart(lines: string[], at: number): boolean {
  if (at + 1 >= lines.length) {
    return false;
  }
  const head = lines[at];
  return head.indexOf('|') >= 0 && isAlignRow(lines[at + 1]);
}

function readTable(lines: string[], at: number): { block: MdBlock, next: number } {
  const rows: string[][] = [];
  const align: string[] = [];
  let i = at;
  // 表头
  rows.push(splitTableRow(lines[at]));
  // 分隔行 → 对齐
  align.push(...parseAlignRow(splitTableRow(lines[at + 1])));
  i = at + 2;
  while (i < lines.length && lines[i].indexOf('|') >= 0 && lines[i].trim().length > 0) {
    rows.push(splitTableRow(lines[i]));
    i += 1;
  }
  const b = new MdBlock();
  b.type = MD_TABLE;
  b.rows = rows;
  b.align = align;
  return { block: b, next: i };
}

function splitTableRow(line: string): string[] {
  let t = line.trim();
  if (t.startsWith('|')) {
    t = t.substring(1);
  }
  if (t.endsWith('|')) {
    t = t.substring(0, t.length - 1);
  }
  const cells: string[] = [];
  let cur = '';
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (ch === '\\' && i + 1 < t.length && t[i + 1] === '|') {
      cur += '|';
      i += 1;
    } else if (ch === '|') {
      cells.push(cur.trim());
      cur = '';
    } else {
      cur += ch;
    }
  }
  cells.push(cur.trim());
  return cells;
}

function parseAlignRow(cells: string[]): string[] {
  const out: string[] = [];
  for (const c of cells) {
    const l = c.startsWith(':');
    const r = c.endsWith(':');
    if (l && r) {
      out.push('c');
    } else if (r) {
      out.push('r');
    } else {
      out.push('l');
    }
  }
  return out;
}

function readLatexBlock(lines: string[], at: number): { block: MdBlock, next: number } {
  const b = new MdBlock();
  b.type = MD_LATEX;
  const t = lines[at].trim();
  // 单行闭合：$$x^2$$
  if (t.length > 4 && t.endsWith('$$')) {
    b.text = t.substring(2, t.length - 2).trim();
    return { block: b, next: at + 1 };
  }
  // 多行块：读到 $$ 闭合行或 EOF（流式未闭合照常收尾）
  const body: string[] = [];
  const first = t.substring(2);
  if (first.length > 0) {
    body.push(first);
  }
  let i = at + 1;
  while (i < lines.length) {
    const lt = lines[i].trim();
    if (lt === '$$') {
      i += 1;
      break;
    }
    if (lt.endsWith('$$') && lt.length > 2) {
      body.push(lt.substring(0, lt.length - 2));
      i += 1;
      break;
    }
    body.push(lines[i]);
    i += 1;
  }
  b.text = body.join('\n').trim();
  return { block: b, next: i };
}

function readParagraph(lines: string[], at: number): { block: MdBlock, next: number } {
  const body: string[] = [];
  let i = at;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim().length === 0) {
      break;
    }
    if (i > at && (matchFence(line) !== null || isHr(line) || matchHeading(line) !== null ||
      isQuote(line) || isListItem(line) || isOrderedItem(line) ||
      (line.indexOf('|') >= 0 && i + 1 < lines.length && isAlignRow(lines[i + 1])) ||
      isLatexBlockLine(line))) {
      break;
    }
    body.push(line.trim());
    i += 1;
  }
  return { block: paraBlock(body.join('\n')), next: i };
}

/// 段落文本先切公式段（$...$ 优先），非公式段走行内解析。
export function paraBlock(text: string): MdBlock {
  const b = new MdBlock();
  b.type = MD_P;
  b.text = text;
  const segs = splitLatex(text);
  const merged: InlineSeg[] = [];
  for (const seg of segs) {
    if (!seg.latex) {
      for (const s of parseInline(seg.text)) {
        merged.push(s);
      }
    } else {
      // 公式段以 text 存原样源码，渲染层识别 $$ 前缀
      const s = new InlineSeg();
      s.text = (seg.block ? '$$' : '$') + seg.text + (seg.block ? '$$' : '$');
      merged.push(s);
    }
  }
  b.segs = merged;
  return b;
}

/// 引用块行内片段（含公式段）。
export function quoteSegs(text: string): InlineSeg[] {
  const b = paraBlock(text);
  return b.segs;
}
