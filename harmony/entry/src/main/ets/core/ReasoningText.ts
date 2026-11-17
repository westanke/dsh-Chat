/**
 * 思考行文本纯函数（官方 dsh-client-ui-chat/lib/client.js ReasoningRow +
 * reasoning-text.js 逐字移植）：
 * - reasoningText：<signature> 标记剥离（不完整前缀/未闭合 → 空串）；
 * - firstLine：首行原文（官方不去空白）；
 * - paragraphPreview：running 摘要 = 最近一个「已完成段落」的首行
 *   （段落分隔 = 空白行；候选行 trim 后非空才更新）。
 * 折叠摘要渲染前统一 replaceAll('**','')（官方 summary 口径）。
 * hidden 判定：text !== rawText && text.trim()==='' → 整块不渲染。
 */

/**
 * <signature> 剥离：text[0] !== '<' 原样返回；以 '<signature>' 开头但尚未写完
 * （open.startsWith）或未闭合（无 </signature>）→ 空串；闭合后跳过紧随换行，
 * 返回剩余正文；非 signature 开头原样。
 */
export function reasoningText(text: string): string {
  if (text.length === 0 || text[0] !== '<') {
    return text;
  }
  const opening: string = '<signature>';
  if (opening.startsWith(text)) {
    return '';
  }
  if (!text.startsWith(opening)) {
    return text;
  }
  const end: number = text.indexOf('</signature>', 11);
  if (end === -1) {
    return '';
  }
  let start: number = end + 12;
  while (start < text.length) {
    if (text[start] === '\n') {
      start++;
    } else if (text[start] === '\r' && text[start + 1] === '\n') {
      start += 2;
    } else {
      break;
    }
  }
  return text.slice(start);
}

/** 官方 firstLine：按第一个 \n 切（不 trim）。 */
export function reasoningFirstLine(text: string): string {
  const newline: number = text.indexOf('\n');
  return newline === -1 ? text : text.slice(0, newline);
}

/**
 * 官方 latestCompletedParagraphFirstLine：扫描段落（分隔 = \r?\n[ \t]*\r?\n 空白行
 * 序列），每个段落里第一个换行前的行 trim 后非空则记为候选；返回最后一个候选。
 */
export function reasoningParagraphPreview(text: string): string {
  let summary: string = '';
  let paragraphStart: number = 0;
  const separator: RegExp = /\r?\n(?:[\t ]*\r?\n)+/g;
  while (true) {
    const match: RegExpExecArray | null = separator.exec(text);
    let paragraphEnd: number;
    if (match === null) {
      paragraphEnd = text.length;
    } else {
      const firstNewlineInSep: number = match[0].indexOf('\n');
      paragraphEnd = match.index + firstNewlineInSep;
    }
    const newline: number = text.indexOf('\n', paragraphStart);
    if (newline !== -1 && newline <= paragraphEnd) {
      const candidate: string = text.slice(paragraphStart, newline).trim();
      if (candidate !== '') {
        summary = candidate;
      }
    }
    if (match === null) {
      return summary;
    }
    paragraphStart = match.index + match[0].length;
  }
}

/** 折叠摘要：running 用段落预览、收起用首行，统一去 **。 */
export function reasoningSummaryOf(text: string, running: boolean): string {
  const prepared: string = reasoningText(text);
  const raw: string = running ? reasoningParagraphPreview(prepared) : reasoningFirstLine(prepared);
  return raw.split('**').join('');
}

/** hidden 判定（官方 ReasoningRow）：剥离前后有差异且剥离后为空 → 整块不渲染。 */
export function reasoningHidden(rawText: string): boolean {
  const text: string = reasoningText(rawText);
  return text !== rawText && text.trim() === '';
}
