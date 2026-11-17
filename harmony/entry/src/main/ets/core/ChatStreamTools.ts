/**
 * 流式工具行 ↔ ChatStore 粘合（自 ChatStore.ts 拆出，对齐 ChatHistory/ChatActions
 * 的「函数收 store」范式；import type 防循环引用）。
 *
 * 职责：live 行版本号（AppStorage 广播）、清流、合成过程卡回收、live 行并入
 * 运行中轮消息列表。行状态机本体在 StreamTools.ts（StreamToolState 容器）。
 */

import type { ChatStore } from './ChatStore';
import { ChatMessage } from './HistoryPage';
import { ToolCallInfo } from './ToolCall';
import { mergeLiveRow } from './StreamTools';

/** 流式工具行版本 +1（经 ChatView 写 AppStorage 广播给工具行/组头刷新）。 */
export function bumpStreamToolsIn(store: ChatStore): void {
  store.streamToolsVersion += 1;
}

/** 清空实时流并去掉合成过程卡（持久过程组保留——reload 会整表刷新）。 */
export function clearStreamToolsIn(store: ChatStore): void {
  if (store.streamTools.isEmpty()) {
    return;
  }
  store.streamTools.clear();
  dropSyntheticGroupsIn(store);
  bumpStreamToolsIn(store);
}

/** 去掉 seq=-1 的合成过程卡（流式期间的占位组，reload 天然消失，这里兜底闪现）。 */
export function dropSyntheticGroupsIn(store: ChatStore): void {
  let hasSynthetic: boolean = false;
  for (let i = 0; i < store.messages.length; i++) {
    const m: ChatMessage = store.messages[i];
    if (m.isProcess && m.seq < 0) {
      hasSynthetic = true;
      break;
    }
  }
  if (!hasSynthetic) {
    return;
  }
  const kept: ChatMessage[] = [];
  for (let i = 0; i < store.messages.length; i++) {
    const m: ChatMessage = store.messages[i];
    if (m.isProcess && m.seq < 0) {
      continue;
    }
    kept.push(m);
  }
  store.messages = kept;
}

/** 只清流式正文/思考缓冲（中途 commit 正文已落库；工具行保留继续跑）。 */
export function clearStreamTextIn(store: ChatStore): void {
  store.streamText = '';
  store.streamReasoning = '';
}

/** reload 后把已被持久 process 组覆盖（同 callId）的 live 行移出缓冲，防重复行。 */
export function dropPersistedRowsIn(store: ChatStore): void {
  if (store.streamTools.isEmpty()) {
    return;
  }
  const callIds: Set<string> = new Set<string>();
  for (let i = 0; i < store.messages.length; i++) {
    const m: ChatMessage = store.messages[i];
    if (m.isProcess) {
      for (let j = 0; j < m.toolCalls.length; j++) {
        callIds.add(m.toolCalls[j].callId);
      }
    }
  }
  store.streamTools.dropPersisted(callIds);
}

/** 每帧工具事件后：确保流式态、把 live 行并入消息列表、广播、通知 UI。 */
export function afterLiveRowsIn(store: ChatStore): void {
  store.streaming = true;
  syncLiveRowsIntoMessagesIn(store);
  bumpStreamToolsIn(store);
  store.changed();
}

/**
 * 把 streamTools 并入运行中轮：轮内最后一张过程组按 callId 命中就地升级
 * （mergeLiveRow 的 rank 守卫防 reload 先到把完整持久行被残缺 live 行降级），
 * 未命中追加；无组则追加合成过程卡（seq=-1）——reload 整体替换时天然消失。
 */
export function syncLiveRowsIntoMessagesIn(store: ChatStore): void {
  if (store.streamTools.isEmpty()) {
    return;
  }
  // 运行中轮起点 = 最后一条 user 消息（无 user 时从 0 起）。
  let turnStart: number = 0;
  for (let i = store.messages.length - 1; i >= 0; i--) {
    if (store.messages[i].isUser) {
      turnStart = i;
      break;
    }
  }
  let groupIdx: number = -1;
  for (let i = turnStart; i < store.messages.length; i++) {
    if (store.messages[i].isProcess) {
      groupIdx = i;
    }
  }
  if (groupIdx < 0) {
    const card: ChatMessage = new ChatMessage();
    card.role = 'process';
    card.seq = -1;
    card.toolCalls = store.streamTools.rows.slice();
    store.messages = [...store.messages, card];
    return;
  }
  const group: ChatMessage = store.messages[groupIdx];
  const rows: ToolCallInfo[] = store.streamTools.rows;
  for (let i = 0; i < rows.length; i++) {
    const liveRow: ToolCallInfo = rows[i];
    let target: ToolCallInfo | null = null;
    for (let j = 0; j < group.toolCalls.length; j++) {
      if (group.toolCalls[j].callId === liveRow.callId) {
        target = group.toolCalls[j];
        break;
      }
    }
    if (target === null) {
      group.toolCalls.push(liveRow);
    } else {
      mergeLiveRow(target, liveRow);
    }
  }
}

/** reloadHistory 落库后重挂 live 行（仍在流式：持久行可能缺 preparing/刚完成的行）。 */
export function reattachLiveRowsIn(store: ChatStore): void {
  if (store.streamTools.isEmpty()) {
    return;
  }
  syncLiveRowsIntoMessagesIn(store);
  // 中途 commit 已把工具行落成持久过程组：同 callId 的 live 行移出缓冲，
  // 防下一帧重建后与持久组双份（合并语义由 syncLiveRows 的 callId 命中保证）。
  dropPersistedRowsIn(store);
  bumpStreamToolsIn(store);
}
