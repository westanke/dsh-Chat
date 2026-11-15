/// Markdown 行内解析（纯逻辑，node 直测）—— 粗体/斜体/删除线/行内代码/链接。
/// ArkTS 口径：扁平 class（禁判别联合），字段全默认值；正则全部必组。
/// 公式段（$...$）由 MdParser 块层先切走，这里不再处理。
export class InlineSeg {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  link: string = ''; // 非空 = 超链接
}

/// 行内解析总入口：递归下降，最早匹配的定界符优先。
export function parseInline(text: string): InlineSeg[] {
  if (text.length === 0) {
    return [];
  }
  const m = findDelimiter(text);
  if (m === null) {
    const s = new InlineSeg();
    s.text = text;
    return [s];
  }
  const out: InlineSeg[] = [];
  if (m.start > 0) {
    const s = new InlineSeg();
    s.text = text.substring(0, m.start);
    out.push(s);
  }
  const tail = text.substring(m.contentEnd + m.closeLen);
  if (m.link.length > 0 && m.text.length > 0) {
    // 链接：整段原样文本 + url，内部不再嵌套解析（首版口径）
    const s = new InlineSeg();
    s.text = m.text;
    s.link = m.link;
    out.push(s);
  } else {
    const inner = text.substring(m.contentStart, m.contentEnd);
    const parts = parseInline(inner);
    for (const p of parts) {
      const q = new InlineSeg();
      q.text = p.text;
      q.bold = p.bold || m.bold;
      q.italic = p.italic || m.italic;
      q.strike = p.strike || m.strike;
      q.code = p.code || m.code;
      q.link = p.link.length > 0 ? p.link : m.link;
      out.push(q);
    }
  }
  const rest = parseInline(tail);
  for (const r of rest) {
    out.push(r);
  }
  return out;
}

class DelimMatch {
  start: number = 0;
  contentStart: number = 0;
  contentEnd: number = 0; // exclusive
  closeLen: number = 0;
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  link: string = '';
  text: string = ''; // 链接情形存原样文本
}

/// 找最早出现的行内定界符；没有回 null。
function findDelimiter(text: string): DelimMatch | null {
  let best: DelimMatch | null = null;
  let bestIdx = -1;
  const cand = tryMatch(text);
  if (cand !== null) {
    best = cand;
    bestIdx = cand.start;
  }
  // 链接与裸 URL：只要比已命中的定界符更早就替换
  const link = matchLink(text);
  if (link !== null && (best === null || link.start < bestIdx)) {
    best = link;
    bestIdx = link.start;
  }
  return best;
}

const RE_CODE: RegExp = /`([^`\n]+)`/;
const RE_BOLD_STAR: RegExp = /\*\*([^*\n]+)\*\*/;
const RE_BOLD_UNDER: RegExp = /__([^_\n]+)__/;
const RE_ITALIC_STAR: RegExp = /\*([^*\n]+)\*/;
const RE_ITALIC_UNDER: RegExp = /_([^_\n]+)_(?![a-zA-Z0-9])/;
const RE_STRIKE: RegExp = /~~([^~\n]+)~~/;
const RE_LINK: RegExp = /\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/;
const RE_BARE_URL: RegExp = /https?:\/\/[^\s<>()[\]{}'"]+/;

function tryMatch(text: string): DelimMatch | null {
  let best: DelimMatch | null = null;
  let bestIdx = -1;
  const push = (re: RegExp, build: (m: RegExpExecArray) => DelimMatch | null): void => {
    re.lastIndex = 0;
    const m = re.exec(text);
    if (m === null) {
      return;
    }
    const d = build(m);
    if (d === null) {
      return;
    }
    if (best === null || m.index < bestIdx) {
      best = d;
      bestIdx = m.index;
    }
  };
  push(RE_CODE, (m) => pick(m, 1, 1, (d) => { d.code = true; }));
  push(RE_BOLD_STAR, (m) => pick(m, 1, 2, (d) => { d.bold = true; }));
  push(RE_BOLD_UNDER, (m) => pick(m, 1, 2, (d) => { d.bold = true; }));
  push(RE_STRIKE, (m) => pick(m, 1, 2, (d) => { d.strike = true; }));
  push(RE_ITALIC_STAR, (m) => pick(m, 1, 1, (d) => { d.italic = true; }));
  push(RE_ITALIC_UNDER, (m) => pick(m, 1, 1, (d) => { d.italic = true; }));
  return best;
}

function pick(m: RegExpExecArray, group: number, closeLen: number,
  decorate: (d: DelimMatch) => void): DelimMatch | null {
  if (m[group] === undefined) {
    return null;
  }
  const d = new DelimMatch();
  d.start = m.index;
  d.contentStart = m.index + m[0].indexOf(m[group]);
  d.contentEnd = d.contentStart + m[group].length;
  d.closeLen = closeLen;
  decorate(d);
  return d;
}

function matchLink(text: string): DelimMatch | null {
  const link = RE_LINK.exec(text);
  const bare = RE_BARE_URL.exec(text);
  let chosen: DelimMatch | null = null;
  let chosenIdx = -1;
  if (link !== null) {
    const d = new DelimMatch();
    d.start = link.index;
    d.contentStart = link.index;
    d.contentEnd = link.index + link[0].length;
    d.closeLen = 0;
    d.link = link[2];
    d.text = link[0]; // [text](url) 原样
    chosen = d;
    chosenIdx = link.index;
  }
  if (bare !== null && (chosen === null || bare.index < chosenIdx)) {
    const d = new DelimMatch();
    d.start = bare.index;
    d.contentStart = bare.index;
    d.contentEnd = bare.index + bare[0].length;
    d.closeLen = 0;
    d.link = bare[0];
    d.text = bare[0];
    chosen = d;
  }
  return chosen;
}
