/**
 * ChatStore 状态容器测试（自 chat-store.test.ts 拆出，职责：状态容器核心——
 * 打开/订阅/历史装配/流式事件/收轮/翻页/取消；对照安卓 chat_state.dart /
 * chat_history_actions.dart 语义逐条验证）。公共基建见 helpers/chat-ctx.ts。
 * 交互动作（工作区/命令/HITL/权限）见 chat-store-actions.test.ts。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { GatewayState } from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { ChatStore } from '../../entry/src/main/ets/core/ChatStore.ts';
import { oldestSeqOf } from '../../entry/src/main/ets/core/MobileWorkspace.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { DshSession } from '../../entry/src/main/ets/core/Models.ts';
import { FakeTimers, FakeSocket, FakeHttp } from '../helpers/fake-ws.ts';
import {
  drain, respond, respondHistory, userItem, assistantItem,
  makeReady, openSession1, ReadyCtx,
} from '../helpers/chat-ctx.ts';

test('oldestSeqOf：取首个 seq>=0；全流式临时消息回 null', () => {
  const a: ChatMessage = new ChatMessage();
  a.seq = -1;
  const b: ChatMessage = new ChatMessage();
  b.seq = 7;
  const c: ChatMessage = new ChatMessage();
  c.seq = 3;
  assert.equal(oldestSeqOf([a, b, c]), 7);
  assert.equal(oldestSeqOf([a]), null);
});

test('loadSessions：填充 sessions 并通知', async () => {
  const ctx: ReadyCtx = makeReady();
  let notified: number = 0;
  ctx.store.setNotify((): void => { notified += 1; });
  const pLoad: Promise<void> = ctx.store.loadSessions();
  respond(ctx.socket, { sessions: [
    { id: 's1', updatedAt: 5, running: false, blank: false },
    { id: 's2', updatedAt: 9, running: true, blank: true, title: '标题' },
  ] });
  await pLoad;
  assert.equal(ctx.store.sessions.length, 2);
  assert.equal(ctx.store.sessions[1].displayTitle, '标题');
  assert.ok(notified >= 1);
});

test('openSession：清空旧会话残留 + subscribe + reloadHistory', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  // 未选会话（空态）：其它会话的推送不串台
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's9', text: 'A 残留' } });
  await drain();
  assert.equal(ctx.store.streamText, '');
  const s: DshSession = new DshSession(null);
  s.id = 's9';
  const pLoad: Promise<void> = ctx.store.openSession(s);
  respondHistory(ctx.socket, [userItem(1, '旧会话消息')]);
  await pLoad;
  assert.equal(ctx.store.messages.length, 1);
  assert.equal(ctx.store.messages[0].text, '旧会话消息');
  assert.notEqual(ctx.store.projections, null);
});

test('newChat：清空一切并 subscribe(null)', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'x')]);
  ctx.store.newChat();
  assert.equal(ctx.store.sessionId, null);
  assert.equal(ctx.store.messages.length, 0);
  assert.equal(ctx.store.projections, null);
  assert.equal(ctx.store.isEmpty, true);
});

test('send：乐观上屏 user 消息，首条走手机工作区预建会话', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  const pSend: Promise<void> = ctx.store.send('  你好  ');
  respond(ctx.socket, { workspaces: [
    { id: 'ws-phone', title: '手机会话', rootId: 'r1' },
  ] });
  await drain();
  respond(ctx.socket, { sessionId: 'sid-9' }); // session-created
  await drain();
  respond(ctx.socket, { type: 'message', sessionId: 'sid-9' }); // message 应答
  await pSend;
  assert.equal(ctx.store.messages.length, 1);
  assert.equal(ctx.store.messages[0].role, 'user');
  assert.equal(ctx.store.messages[0].text, '你好');
  assert.equal(ctx.store.sessionId, 'sid-9');
  assert.equal(ctx.store.streaming, true);
  let sawMessage: boolean = false;
  for (const raw of ctx.socket.sent) {
    const f: Record<string, unknown> = JSON.parse(raw) as Record<string, unknown>;
    if (f['type'] === 'message') {
      sawMessage = true;
      assert.equal(f['clientTimeZone'], 'Asia/Shanghai');
      assert.equal(f['mode'], 'queue');
    }
  }
  assert.equal(sawMessage, true);
});

test('send 失败：streaming 收起 + lastError', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  const pSend: Promise<void> = ctx.store.send('hi');
  respond(ctx.socket, { workspaces: [
    { id: 'ws-phone', title: '手机会话', rootId: 'r1' },
  ] });
  await drain();
  // 预建会话被 error 帧打回（吞掉，退回 message 帧自动建）
  ctx.socket.serverFrame({ kind: 'error', data: {
    code: 'HTTP_500', message: 'boom', requestId: ctx.socket.lastRequestId() } });
  await drain();
  // message 帧也被打回 → send 失败
  ctx.socket.serverFrame({ kind: 'error', data: {
    code: 'HTTP_500', message: 'boom', requestId: ctx.socket.lastRequestId() } });
  await pSend;
  assert.equal(ctx.store.streaming, false);
  assert.notEqual(ctx.store.lastError, null);
});

test('delta 累积：text/reasoning 分开 + 其它会话不串台', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', turn: 1, step: 1, index: 0,
    kind: 'reasoning', text: '思考' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', turn: 1, step: 1, index: 1,
    kind: 'text', text: '答案' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 'other-session', text: '串台' } });
  assert.equal(ctx.store.streamText, '答案');
  assert.equal(ctx.store.streamReasoning, '思考');
  assert.equal(ctx.store.streaming, true);
});

test('committed assistant（带正文）：只清正文缓冲，流式态保留等 turn.end', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', text: '流式' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.committed', sessionId: 's1',
    role: 'assistant', seq: 2, turn: 1, step: 1, hasReplyContent: true } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '落库')]);
  await drain();
  // 中途 commit 语义：streaming 不收、工具行不清；只把正文从流缓冲清掉。
  assert.equal(ctx.store.streaming, true);
  assert.equal(ctx.store.streamText, '');
  assert.equal(ctx.store.messages.length, 2);
  assert.equal(ctx.store.messages[1].text, '落库');
});

test('committed assistant（无正文 hasReplyContent=false）：正文缓冲保留', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', text: '正文缓冲' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.committed', sessionId: 's1',
    role: 'assistant', seq: 2, turn: 1, step: 1, hasReplyContent: false } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '')]);
  await drain();
  assert.equal(ctx.store.streaming, true);
  assert.equal(ctx.store.streamText, '正文缓冲');
});

test('turn.start/turn.end：开轮置位、收轮清流收起 + max-tokens 提示', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.start', sessionId: 's1' } });
  await drain();
  assert.equal(ctx.store.streaming, true);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', text: '答案' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.end', sessionId: 's1', reason: { kind: 'max-tokens' } } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '截断')]);
  await drain();
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.streamText, '');
  assert.equal(ctx.store.maxTokensNotice, true);
  assert.equal(ctx.store.messages.length, 2);
});

test('turn.end aborted：不收起过程组、不置截断提示', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.end', sessionId: 's1', reason: { kind: 'aborted' } } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q')]);
  await drain();
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.maxTokensNotice, false);
});

test('committed user / sessionEvent：800ms 防抖重拉', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  const baseTimers: number = ctx.timers.pendingCount();
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.committed', sessionId: 's1',
    role: 'user', seq: 1, turn: 1, step: 1 } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.session.event', sessionId: 's1', eventType: 'tool/call' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.session.event', sessionId: 's1', eventType: 'tool/result' } });
  // READY 心跳 timer 也在挂起列表里，只比基线多挂一个防抖。
  assert.equal(ctx.timers.pendingCount(), baseTimers + 1);
  ctx.timers.advance(801); // 触发 reloadHistory（请求发出）
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '工具结果')]);
  await drain();
  assert.equal(ctx.store.messages.length, 2);
});

test('turnFailed：收流式 + lastError=message', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.failed', sessionId: 's1', message: '执行失败' } });
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.lastError, '执行失败');
});

test('resync：直接重拉历史', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'connection.resync-required' } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q')]);
  await drain();
  assert.equal(ctx.store.messages.length, 1);
});

test('loadOlder：beforeSeq 翻页 + seq 去重 prepend + justLoaded 标记', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(10, 'q')], true);
  assert.equal(ctx.store.historyHasMore, true);
  const pOlder: Promise<void> = ctx.store.loadOlder();
  respondHistory(ctx.socket, [userItem(9, '更早'), userItem(10, 'q 重叠')], false);
  await pOlder;
  assert.equal(ctx.store.messages.length, 2);
  assert.equal(ctx.store.messages[0].text, '更早');
  assert.equal(ctx.store.historyPageJustLoaded, true);
  assert.equal(ctx.store.consumeHistoryPageJustLoaded(), true);
  assert.equal(ctx.store.consumeHistoryPageJustLoaded(), false);
  assert.equal(ctx.store.historyHasMore, false);
});

test('cancelTurn：收流式 + session-cancel + 重拉', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', text: '跑着' } });
  const pCancel: Promise<void> = ctx.store.cancelTurn();
  respond(ctx.socket, {}); // session-cancel 应答
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '被停')]);
  await pCancel;
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.messages[1].text, '被停');
});

test('READY 状态回调触发 UI 通知', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const http: FakeHttp = new FakeHttp();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'UTC' };
  const client: GatewayClient = new GatewayClient('http://h/', deps);
  client.setToken('t', 'd');
  const api: GatewayApi = new GatewayApi(client, http);
  const store: ChatStore = new ChatStore(client, api, timers);
  let sawReady: boolean = false;
  client.setStateListener((st: GatewayState): void => {
    if (st === GatewayState.READY) {
      sawReady = true;
    }
  });
  const p: Promise<void> = client.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  assert.equal(sawReady, true);
  assert.equal(store.sessions.length, 0); // sessions 请求已发，应答未到
});

/** 取最近一次指定 type 请求帧的 requestId（重连后会连发 sessions/history）。 */
function requestIdOfType(socket: FakeSocket, type: string): string {
  for (let i = socket.sent.length - 1; i >= 0; i--) {
    const f: Record<string, unknown> = JSON.parse(socket.sent[i]) as Record<string, unknown>;
    if (f['type'] === type) {
      return typeof f['requestId'] === 'string' ? f['requestId'] as string : '';
    }
  }
  return '';
}

/** 断线 → 退避 1s → 重连 READY（READY 分支会重发 sessions + history）。 */
function reconnect(ctx: ReadyCtx): void {
  ctx.socket.serverDown('drop');
  ctx.timers.advance(1000);
  ctx.socket.serverOpen();
  ctx.socket.serverHello();
}

test('READY 重连：服务端说会话没在跑 → 本地流式态收口（不卡「正在思考…」）', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  // 流式中断线：delta 已到，TURN_END 帧永远收不到了。
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '思考中' } });
  await drain();
  assert.equal(ctx.store.streaming, true);

  reconnect(ctx);
  await drain();
  // 会话列表回来后核对：服务端 running:false 说明该回合其实已经结束。
  const sessionsReq: string = requestIdOfType(ctx.socket, 'sessions');
  assert.notEqual(sessionsReq, '');
  ctx.socket.serverFrame({ kind: 'reply', requestId: sessionsReq, data: {
    sessions: [{ id: 's1', updatedAt: 5, running: false }] } });
  await drain();
  await drain();

  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.streamReasoning, '');
  assert.equal(ctx.store.streamText, '');
});

test('READY 重连：服务端说会话还在跑 → 本地流式态保留（等后续 delta）', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '思考中' } });
  await drain();

  reconnect(ctx);
  await drain();
  const sessionsReq: string = requestIdOfType(ctx.socket, 'sessions');
  ctx.socket.serverFrame({ kind: 'reply', requestId: sessionsReq, data: {
    sessions: [{ id: 's1', updatedAt: 5, running: true }] } });
  await drain();
  await drain();

  assert.equal(ctx.store.streaming, true);
  assert.equal(ctx.store.streamReasoning, '思考中');
});

test('READY 重连：streaming 已 false 但缓冲有残留 → 一样清干净（轮尾占位不钉死）', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '残留思考' } });
  await drain();
  // 模拟「streaming 已收口、缓冲没清」：旧版 syncStreamingWithServer 的
  // `if (!this.streaming) return;` 会在这里直接早退，残留永远留着。
  ctx.store.streaming = false;

  reconnect(ctx);
  await drain();
  const sessionsReq: string = requestIdOfType(ctx.socket, 'sessions');
  ctx.socket.serverFrame({ kind: 'reply', requestId: sessionsReq, data: {
    sessions: [{ id: 's1', updatedAt: 5, running: false }] } });
  await drain();
  await drain();

  assert.equal(ctx.store.streamReasoning, '');
  assert.equal(ctx.store.streamText, '');
  assert.equal(ctx.store.streaming, false);
});

test('对账判定没在跑之后：迟到增量丢弃，不再把 streaming 抬回 true', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '思考中' } });
  await drain();
  reconnect(ctx);
  await drain();
  const sessionsReq: string = requestIdOfType(ctx.socket, 'sessions');
  ctx.socket.serverFrame({ kind: 'reply', requestId: sessionsReq, data: {
    sessions: [{ id: 's1', updatedAt: 5, running: false }] } });
  await drain();
  await drain();
  assert.equal(ctx.store.streaming, false);

  // 网络上飘着的旧回合增量（TURN_END 已丢，不会再来）——必须丢弃。
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '迟到' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'text', text: '迟到正文' } });
  await drain();
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.streamReasoning, '');
  assert.equal(ctx.store.streamText, '');
});

test('对账判定没在跑之后：新回合 turn.start 撤销结论，增量照常收', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  reconnect(ctx);
  await drain();
  const sessionsReq: string = requestIdOfType(ctx.socket, 'sessions');
  ctx.socket.serverFrame({ kind: 'reply', requestId: sessionsReq, data: {
    sessions: [{ id: 's1', updatedAt: 5, running: false }] } });
  await drain();
  await drain();
  assert.equal(ctx.store.isServerIdle('s1'), true);

  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.turn.start', sessionId: 's1' } });
  await drain();
  assert.equal(ctx.store.isServerIdle('s1'), false);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', kind: 'reasoning', text: '新一轮' } });
  await drain();
  assert.equal(ctx.store.streaming, true);
  assert.equal(ctx.store.streamReasoning, '新一轮');
});

test('deviceLabel/connectionLabel/sessionTitle 取值口径', () => {
  const ctx: ReadyCtx = makeReady('DSH Bridge 手机端');
  assert.equal(ctx.store.deviceLabel, 'DSH Bridge 手机端');
  assert.equal(ctx.store.connectionLabel, '192.168.1.10:8765');
  assert.equal(ctx.store.sessionTitle, '');
  const s: DshSession = new DshSession(null);
  s.id = 's1';
  s.title = '会话甲';
  ctx.store.sessions = [s];
  ctx.store.sessionId = 's1';
  assert.equal(ctx.store.sessionTitle, '会话甲');
});
