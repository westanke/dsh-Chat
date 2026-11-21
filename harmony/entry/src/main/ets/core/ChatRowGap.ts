/**
 * 会话列表逐行变距（安卓 app/lib/ui/chat_row_gap.dart 口径）。
 *
 * 间距值由 UI 层从 DsSpacing 传入（core 不 import 主题）：
 * 换轮 24、连续用户 8、相邻过程 0、文件卡 12、其余 8。
 */

import { ChatMessage } from './HistoryPage';

/** 行距档位（UI 层用 DsSpacing 构造）。 */
export class RowGapValues {
  newTurn: number = 24;
  sameTurn: number = 8;
  process: number = 0;
  card: number = 12;
}

function isProcessLike(m: ChatMessage): boolean {
  return m.isProcess || m.role === 'command';
}

/** 当前行上方该留多少空；第一行（previous=null）为 0。 */
export function chatRowGapBefore(cur: ChatMessage,
  previous: ChatMessage | null, gaps: RowGapValues): number {
  if (previous === null) {
    return 0;
  }
  if (cur.isUser) {
    return previous.isUser ? gaps.sameTurn : gaps.newTurn;
  }
  if (isProcessLike(cur) && isProcessLike(previous)) {
    return gaps.process;
  }
  if (cur.role === 'files') {
    return gaps.card;
  }
  return gaps.sameTurn;
}
