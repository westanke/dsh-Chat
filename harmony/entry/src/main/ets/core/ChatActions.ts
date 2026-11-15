/**
 * 会话动作集 —— 从 ChatStore 拆出的用户动作（命令卡/重新生成/停止/切权限），
 * 对照 app/lib/ui/chat_state.dart 移植（core 纯逻辑，node 直测）。
 * 统一收 ChatStore 参数（循环引用走 import type，字段全部 public）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { RequestException } from './GatewayEvents';
import { ChatMessage } from './HistoryPage';
import type { ChatStore } from './ChatStore';

/** 执行斜杠命令（command-execute）：以本地「命令卡」注入会话流
 *（seq=-1 不参与去重/排序，重拉历史后保留到下次重建）。 */
export function runCommandIn(store: ChatStore, line: string): Promise<void> {
  const id: string | null = store.sessionId;
  if (id === null || id === '') {
    return Promise.resolve();
  }
  store.lastError = null;
  const card: ChatMessage = new ChatMessage();
  card.role = 'command';
  card.text = line;
  store.messages = [...store.messages, card];
  store.changed();
  return store.api.executeCommand(id, line).then((data: JsonMap): void => {
    const result: JsonMap | null = JsonAccess.obj(data, 'result');
    const kind: string = result === null ? '' : JsonAccess.strOr(result, 'kind', '');
    if (kind === 'error') {
      const text: string = result === null ? '命令执行失败' : JsonAccess.strOr(result, 'text', '命令执行失败');
      card.text = line + '\n\u2717 ' + text;
      store.lastError = text;
      store.changed();
      return;
    }
    const detail: string = result === null ? '' : JsonAccess.strOr(result, 'text', '').trim();
    card.text = detail === '' ? line + '\n\u2713 已执行' : line + '\n\u2713 ' + detail;
    store.changed();
    // 成功的命令大多自带落盘事件；保险起见重拉历史落 UI。
    store.reloadHistory().then((): void => {
      store.changed();
    }).catch((): void => {});
  }).catch((e: Error): void => {
    if (e instanceof RequestException) {
      card.text = line + '\n\u2717 ' + e.message;
      store.lastError = e.message;
      store.changed();
      return;
    }
    throw e;
  });
}

/** 重新生成：重发 index 之前最后一条用户消息正文（安卓 chat_state.regenerateAt）。 */
export async function regenerateAtIn(store: ChatStore, index: number): Promise<void> {
  if (store.streaming) {
    return;
  }
  for (let i = Math.min(index, store.messages.length - 1); i >= 0; i--) {
    const m: ChatMessage = store.messages[i];
    if (m.isUser && m.text.trim().length > 0) {
      await store.send(m.text);
      return;
    }
  }
}

/** 停止当前回合：session-cancel + 立即收流式 + 重拉历史。 */
export function cancelTurnIn(store: ChatStore): Promise<void> {
  const id: string | null = store.sessionId;
  if (!store.streaming || id === null || id === '') {
    return Promise.resolve();
  }
  store.streaming = false;
  store.streamText = '';
  store.streamReasoning = '';
  store.lastError = null;
  store.changed();
  return store.api.cancelTurn(id).then((): Promise<void> => {
    return store.reloadHistory();
  }).catch((e: Error): void => {
    if (e instanceof RequestException) {
      store.lastError = '停止失败：' + e.message;
      store.changed();
      return;
    }
    throw e;
  });
}

/** 切换权限档位：NO_SESSION 拒（安卓 ChatState 同款口径）。 */
export function setPermissionIn(store: ChatStore, name: string): Promise<void> {
  const sid: string | null = store.sessionId;
  if (sid === null || sid === '') {
    return Promise.reject(new RequestException('NO_SESSION', '当前没有会话'));
  }
  return store.api.setPermission(sid, name);
}
