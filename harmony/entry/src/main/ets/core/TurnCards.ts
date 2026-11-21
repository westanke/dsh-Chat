/**
 * 轮级卡片的装配入口：给一条 assistant 消息，返回它所在**闭合轮**的
 * 改动卡数据与生成文件卡数据；不在闭合轮 / 不是该轮最后一条 assistant / 两卡都空
 * → null（不渲染任何东西，官方同口径：卡片挂在轮尾，不在每条回复后面重复）。
 *
 * 纯逻辑，node 直测。
 */

import { ChatMessage } from './HistoryPage';
import { turnTailOf } from './TurnTail';
import { ArtifactFile, TurnChanges, turnArtifactsOf, turnChangesOf } from './TurnChanges';

/** 一条 assistant 消息对应的两张卡（扁平类，ArkTS 禁判别联合）。 */
export class TurnCards {
  changes: TurnChanges | null = null;
  artifacts: ArtifactFile[] = [];

  hasChanges(): boolean {
    return this.changes !== null && !(this.changes as TurnChanges).isEmpty();
  }

  hasArtifacts(): boolean {
    return this.artifacts.length > 0;
  }

  isEmpty(): boolean {
    return !this.hasChanges() && !this.hasArtifacts();
  }
}

/**
 * `index` 是 messages 里的下标（与 MessageList 的 store.messages 同源）。
 * `isTurnRunning` 与 turnTailOf 同义：列表尾且轮还在跑时不算闭合。
 */
export function turnCardsOf(messages: ChatMessage[], index: number,
  isTurnRunning: boolean): TurnCards | null {
  if (index < 0 || index >= messages.length) {
    return null;
  }
  if (messages[index].role !== 'assistant' || messages[index].streaming) {
    return null;
  }
  // 只挂在该轮最后一条 assistant 上（中间过程组后面的过渡正文不出卡）。
  for (let i = index + 1; i < messages.length; i++) {
    if (messages[i].isUser) {
      break;
    }
    if (messages[i].role === 'assistant') {
      return null;
    }
  }
  // closed 判定复用轮尾行口径（含「列表尾空闲视为闭合」）。
  if (turnTailOf(messages, index, isTurnRunning) === null) {
    return null;
  }
  let start: number = 0;
  for (let i = index - 1; i >= 0; i--) {
    if (messages[i].isUser) {
      start = i;
      break;
    }
  }
  let end: number = messages.length;
  for (let i = index + 1; i < messages.length; i++) {
    if (messages[i].isUser) {
      end = i;
      break;
    }
  }
  const cards: TurnCards = new TurnCards();
  cards.changes = turnChangesOf(messages, start, end);
  cards.artifacts = turnArtifactsOf(messages, start, end);
  if (cards.isEmpty()) {
    return null;
  }
  return cards;
}
