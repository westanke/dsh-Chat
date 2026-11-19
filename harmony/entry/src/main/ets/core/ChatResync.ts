/**
 * 重连对账（自 ChatStore.ts 拆出，对齐 ChatHistory/ChatActions/ChatEvents 的
 * 「函数收 store」范式；import type 防循环引用）。
 *
 * 为什么需要它：bridge 的 /ws/mobile **不补发断线期间的事件**
 * （dsh-remote-bridge src/host/ws-event-bridge.ts 只转发在线事件，无重放），
 * 所以断线时结束的回合，其 TURN_END 永远收不到 —— 本地 streaming 与两个
 * 流式缓冲就永久停在「进行中」，屏上一直挂着「正在思考…」。
 * READY 之后拿会话列表的 running 字段做一次对账，是唯一可靠的收口途径。
 */

import type { ChatStore } from './ChatStore';
import { clearStreamToolsIn } from './ChatStreamTools';

/**
 * 用会话列表的 running 字段订正本地流式态（READY resync 专用）。
 *
 * 服务端说没在跑就无条件收口：streaming、两个缓冲、流式工具行一起清，
 * 再重拉一次历史把真实终态补上。**不能只在 streaming 为 true 时才清** ——
 * TURN_END 丢帧后 streaming 可能已经收口成 false 而缓冲还留着旧文本，
 * 那种残留同样会把轮尾「正在思考…」钉在屏上（2026-11-17 真机）。
 * 收口后记下 serverIdleSession，挡住该回合迟到的增量（见 ChatStore 字段注释）。
 * 反向不处理 —— 本地不在流式而服务端在跑时不凭空造流式气泡，下一个 delta 会自己开。
 */
export function syncStreamingWithServerIn(store: ChatStore): void {
  const current: string | null = store.sessionId;
  if (current === null || current === '') {
    return;
  }
  let running: boolean = false;
  let found: boolean = false;
  for (const s of store.sessions) {
    if (s.id === current) {
      running = s.running;
      found = true;
    }
  }
  if (!found || running) {
    return;
  }
  store.serverIdleSession = current;
  const dirty: boolean = store.streaming || store.streamText !== ''
    || store.streamReasoning !== '' || !store.streamTools.isEmpty();
  if (!dirty) {
    // 本来就是干净的：只留结论挡迟到增量，不必多拉一次历史
    //（onGatewayState 的 READY 分支已经拉过了）。
    return;
  }
  store.streaming = false;
  store.streamText = '';
  store.streamReasoning = '';
  clearStreamToolsIn(store);
  store.changed();
  store.reloadHistory();
}