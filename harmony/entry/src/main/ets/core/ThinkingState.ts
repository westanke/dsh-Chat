/**
 * 思考行新形态（dsh-go ReasoningRow）纯逻辑 —— 对照安卓
 * app/lib/ui/chat_thinking.dart 的 thinkingRowStateOf / thinkingTickerText。
 *
 * 流式且正文还没开始（answerStarted=false）时是「活跃态」：呼吸环 +「思考中」+
 * 三行实时窗口；一旦正文出现就收成一行摘要；轮结束后保留摘要预览。
 */

import { reasoningHidden, reasoningSummaryOf, reasoningText } from './ReasoningText';

/** 实时窗口最多显示的正文行数（与安卓 thinkingTickerRows=3 对齐）。 */
export const THINKING_TICKER_ROWS: number = 3;
/** 实时窗口保留的尾部字符数（长思考只留最后一段，避免每帧重排全文）。 */
export const THINKING_TICKER_TAIL: number = 2000;

export class ThinkingRowState {
  /** 活跃态：流式 + 正文未开始 + 有可见思考文本。 */
  active: boolean = false;
  /** 折叠/结束后的摘要（官方 summaryText 口径）。 */
  summary: string = '';
  /** 实时窗口正文（已剥 signature、折叠空行、留尾部）。 */
  ticker: string = '';
  /** 整块不渲染（<signature> 未闭合剥完为空）。 */
  hidden: boolean = false;

  constructor(active: boolean, summary: string, ticker: string, hidden: boolean) {
    this.active = active;
    this.summary = summary;
    this.ticker = ticker;
    this.hidden = hidden;
  }
}

/**
 * 实时窗口文本：剥 signature 壳 → 去行尾空白 → 折叠连续空行为单空行 →
 * 只留尾部 2000 字符 → 去首部空白。窗口只显示最后几行，前面的内容滚掉。
 */
export function thinkingTickerText(raw: string): string {
  const body: string = reasoningText(raw);
  if (body === '') {
    return '';
  }
  const lines: string[] = body.split('\n');
  const out: string[] = [];
  let blank: boolean = false;
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].replace(/\s+$/, '');
    if (line.trim() === '') {
      if (!blank && out.length > 0) {
        out.push('');
        blank = true;
      }
      continue;
    }
    out.push(line);
    blank = false;
  }
  let text: string = out.join('\n');
  if (text.length > THINKING_TICKER_TAIL) {
    text = text.substring(text.length - THINKING_TICKER_TAIL);
  }
  return text.replace(/^\s+/, '');
}

/** 取实时窗口最后 N 个非空行（UI 逐行渲染；空行不占三行窗口）。 */
export function thinkingLiveLines(raw: string, max: number = THINKING_TICKER_ROWS): string[] {
  const text: string = thinkingTickerText(raw);
  if (text === '') {
    return [];
  }
  const lines: string[] = text.split('\n');
  const kept: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== '') {
      kept.push(lines[i]);
    }
  }
  return kept.length > max ? kept.slice(kept.length - max) : kept;
}

/** 一次算齐 UI 需要的四件事。 */
export function thinkingRowStateOf(text: string, streaming: boolean,
                                   answerStarted: boolean): ThinkingRowState {
  const hidden: boolean = reasoningHidden(text);
  const summary: string = hidden ? '' : reasoningSummaryOf(text, streaming);
  const active: boolean = streaming && !answerStarted && !hidden && text.trim() !== '';
  return new ThinkingRowState(active, summary, active ? thinkingTickerText(text) : '', hidden);
}
