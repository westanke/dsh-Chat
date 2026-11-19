/**
 * Gateway 事件分派（自 ChatStore.ts 拆出，对齐 ChatHistory/ChatActions 的
 * 「函数收 store」范式；import type 防循环引用）。
 *
 * delta 显式分派：'text'→正文、'reasoning'→思考、'tool-call'/'tool-call-end'
 * → StreamToolState 行状态机；**未知 kind 忽略**（bridge 契约：老客户端不得把
 * 未知帧当正文渲染，否则新协议帧的 JSON 参数会漏进气泡）。
 */

import type { ChatStore } from './ChatStore';
import { MessageCommitted, MessageDelta, ToolCallEvent, ToolResultEvent } from './Models';
import { GatewayEvent, GatewayEventType } from './GatewayEvents';
import {
  afterLiveRowsIn, clearStreamTextIn, clearStreamToolsIn,
} from './ChatStreamTools';

/** GatewayClient 事件入口（ChatStore 构造时经 setEventListener 转进来）。 */
export function onEventIn(store: ChatStore, event: GatewayEvent): void {
  if (event.type === GatewayEventType.DELTA) {
    const delta: MessageDelta | null = event.delta;
    if (delta === null || !store.isCurrent(delta.sessionId)) {
      return;
    }
    // resync 已判定该会话「服务端没在跑」：这一轮的 TURN_END 不会再来了，
    // 迟到的增量若放进来会把 streaming 重新抬成 true 并永久卡住（见 ChatStore.serverIdleSession）。
    if (store.isServerIdle(delta.sessionId)) {
      return;
    }
    // 工具参数流式帧：进 streamTools 行状态机，不进文本/思考累积。
    if (delta.kind === 'tool-call') {
      store.streamTools.applyDelta(delta);
      afterLiveRowsIn(store);
      return;
    }
    if (delta.kind === 'tool-call-end') {
      store.streamTools.applyEnd(delta);
      afterLiveRowsIn(store);
      return;
    }
    if (delta.kind === 'text') {
      store.streamText += delta.text;
    } else if (delta.kind === 'reasoning') {
      store.streamReasoning += delta.text;
    } else {
      // 未知 kind：只抬流式态，不渲染（契约见文件头）。
      store.streaming = true;
      store.changed();
      return;
    }
    store.streaming = true;
    store.changed();
    return;
  }
  if (event.type === GatewayEventType.TOOL_CALL) {
    const call: ToolCallEvent | null = event.toolCall;
    if (call === null || !store.isCurrent(call.sessionId) || store.isServerIdle(call.sessionId)) {
      return;
    }
    store.streamTools.applyCall(call.callId, call.name, call.arguments);
    afterLiveRowsIn(store);
    return;
  }
  if (event.type === GatewayEventType.TOOL_RESULT) {
    const result: ToolResultEvent | null = event.toolResult;
    if (result === null || !store.isCurrent(result.sessionId)
      || store.isServerIdle(result.sessionId)) {
      return;
    }
    store.streamTools.applyResult(result.callId, result.isError,
                                  result.contentText, result.errorCode);
    afterLiveRowsIn(store);
    return;
  }
  if (event.type === GatewayEventType.COMMITTED) {
    const committed: MessageCommitted | null = event.committed;
    if (committed === null || !store.isCurrent(committed.sessionId)) {
      return;
    }
    // 中途 commit 语义（bridge e08b6b5）：assistant committed ≠ 轮结束——
    // 内核会在工具执行前先 settle 一条只含 tool-call 块的 assistant 消息
    // （hasReplyContent=false），此后流式工具行要继续跑，这里不再收流/收起。
    if (committed.role === 'assistant') {
      if (committed.hasReplyContent) {
        // 正文已提交落库：只把已持久化正文从流缓冲清掉（clearStreamTextIn），
        // 流式工具行与 streaming 态保留，等 turn.end 统一收束。
        clearStreamTextIn(store);
      }
      store.reloadHistory();
    } else {
      // 用户消息落库（本端已乐观上屏；别的端/REST 外部写入靠防抖重拉）。
      store.scheduleToolRefresh();
    }
    return;
  }
  if (event.type === GatewayEventType.TURN_START) {
    if (!store.isCurrent(event.sessionId)) {
      return;
    }
    // 新回合真的开始了：撤销 resync 的「没在跑」结论，后续增量照常收。
    store.clearServerIdle();
    store.streaming = true;
    store.maxTokensNotice = false;
    store.changed();
    return;
  }
  if (event.type === GatewayEventType.TURN_END) {
    if (!store.isCurrent(event.sessionId)) {
      return;
    }
    store.streaming = false;
    clearStreamTextIn(store);
    clearStreamToolsIn(store);
    // 收起时机 = 「回答结束后」：正常结束（reason 非 aborted/interrupted/error）
    // 才收起该轮过程组；官方 alwaysOpen 判据见 client.js:4941。
    if (event.turnReasonKind !== 'aborted' && event.turnReasonKind !== 'interrupted'
      && event.turnReasonKind !== 'error') {
      store.workSteps.collapseTurnOnCompletion(store.messages);
    }
    if (event.turnReasonKind === 'max-tokens') {
      store.maxTokensNotice = true;
    }
    store.reloadHistory();
    store.changed();
    return;
  }
  if (event.type === GatewayEventType.TURN_FAILED) {
    if (!store.isCurrent(event.sessionId)) {
      return;
    }
    store.streaming = false;
    store.streamText = '';
    store.streamReasoning = '';
    store.lastError = event.message;
    store.maxTokensNotice = false;
    // 清实时流；防抖重拉一次让持久行带上 stopped/cancelled/failed 终态。
    clearStreamToolsIn(store);
    store.scheduleToolRefresh();
    store.changed();
    return;
  }
  if (event.type === GatewayEventType.LINK_CLOSED) {
    // 语义化掉线（协议对齐）：4001 = 令牌/设备被吊销，只有重新配对能恢复；
    // 1009 = 单帧超过 1 MiB。其余 close 只记诊断不打扰用户（自然重连会好）。
    if (event.linkCode === 4001) {
      store.lastError = '设备已被吊销（close 4001），请重新配对';
    } else if (event.linkCode === 1009) {
      store.lastError = '请求内容超过 1 MiB，连接已重置';
    }
    store.changed();
    return;
  }
  if (event.type === GatewayEventType.RESYNC) {
    store.reloadHistory();
    return;
  }
  if (event.type === GatewayEventType.SESSION_EVENT) {
    if (!store.isCurrent(event.sessionId)) {
      return;
    }
    store.scheduleToolRefresh();
    return;
  }
  if (store.hitl.onEvent(event)) {
    store.changed();
  }
  // MODELS_UPDATED（模型列表变化）在阶段 4 模型切换接入。
}
