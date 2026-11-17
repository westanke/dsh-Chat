/**
 * 会话历史装载/翻页 —— 从 ChatStore 拆出（宪法 §7 单文件 ≤500 行）。
 *
 * 两个动作都要「读写 store 的 messages/rawEvents/projections 并触发 changed()」，
 * 参数统一收 ChatStore（循环引用走 import type，字段 public —— 与
 * core/ChatActions.ts、core/ChatHitl.ts 同范式）。
 *
 * 关键口径（对齐 app/lib/ui/chat_history_actions.dart）：
 * - 本地命令卡（role='command'，seq=-1）不在服务端历史里，重拉后要灌回列表尾部；
 * - 翻页 beforeSeq = 当前最小 seq，结果 prepend 并按 seq 去重（HistoryPage.mergeOlderMessages）；
 * - 翻页期间切了会话 → 整批丢弃（sessionId 变了就不写回）。
 */

import type { JsonMap } from './JsonAccess';
import { ChatMessage, HistoryPage, mergeOlderMessages } from './HistoryPage';
import { RequestException } from './GatewayEvents';
import { oldestSeqOf } from './MobileWorkspace';
import type { ChatStore } from './ChatStore';

const HISTORY_MAX_MESSAGES: number = 200;

/** 重拉当前会话历史（openSession / 事件防抖 / 停止后都会调）。 */
export function reloadHistoryIn(store: ChatStore): Promise<void> {
  const id: string | null = store.sessionId;
  if (id === null || id === '') {
    return Promise.resolve();
  }
  // 本地命令卡（role='command'，seq=-1）不在服务端历史里，会被整体替换冲掉 ——
  // 重灌回列表尾部（安卓 chat_history_actions.dart:36-40 同口径）。
  const localCards: ChatMessage[] = [];
  for (const m of store.messages) {
    if (m.role === 'command' && m.seq < 0) {
      localCards.push(m);
    }
  }
  return store.api.history(id, HISTORY_MAX_MESSAGES, 0).then((page: HistoryPage): void => {
    store.messages = localCards.length === 0 ? page.items : [...page.items, ...localCards];
    store.rawEvents = page.rawEvents;
    store.historyHasMore = page.hasMore;
    // 翻页/刷新时 projections 可能缺席：保留上一份（同会话），避免面板闪空。
    if (page.projections !== null) {
      store.projections = page.projections;
    }
    // 仍在流式：重挂工具调用实时行（持久行可能缺 preparing/刚完成的行）。
    if (store.streaming) {
      store.reattachLiveRows();
    }
    store.changed();
  }).catch((e: Error): void => {
    if (e instanceof RequestException) {
      store.lastError = '加载历史失败：' + e.message;
      store.changed();
      return;
    }
    throw e;
  });
}

/** 向上翻页：beforeSeq=当前最小 seq，结果 prepend 并按 seq 去重。 */
export function loadOlderIn(store: ChatStore): Promise<void> {
  const id: string | null = store.sessionId;
  if (id === null || id === '' || store.loadingOlder || !store.historyHasMore) {
    return Promise.resolve();
  }
  const before: number | null = oldestSeqOf(store.messages);
  if (before === null || before <= 0) {
    return Promise.resolve();
  }
  store.loadingOlder = true;
  store.changed();
  return store.api.history(id, HISTORY_MAX_MESSAGES, before).then((page: HistoryPage): void => {
    if (store.sessionId !== id) {
      return; // 翻页期间切了会话：丢弃
    }
    const merged: [ChatMessage[], JsonMap[], boolean] =
      mergeOlderMessages(store.messages, store.rawEvents, page.items, page.rawEvents);
    store.messages = merged[0];
    store.rawEvents = merged[1];
    if (merged[2]) {
      store.historyPageJustLoaded = true;
    }
    store.historyHasMore = page.hasMore;
    store.changed();
  }).catch((e: Error): void => {
    if (e instanceof RequestException) {
      store.lastError = '加载更早消息失败：' + e.message;
      store.changed();
      return;
    }
    throw e;
  }).finally((): void => {
    store.loadingOlder = false;
    if (store.sessionId === id) {
      store.changed();
    }
  });
}
