/**
 * ChatStore 状态容器测试 —— 对照安卓 chat_state.dart /
 * chat_history_actions.dart / mobile_workspace.dart 语义逐条验证。
 * Fake 基建见 helpers/fake-ws.ts。
 *
 * 时序约定：先发起动作（请求同步发出），再注入应答帧（respond 自动读
 * lastRequestId），最后 await 动作 promise——顺序反了应答会扑空。
 */

import test, { after } from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { GatewayState } from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { ChatStore } from '../../entry/src/main/ets/core/ChatStore.ts';
import { oldestSeqOf, ensureMobileWorkspace } from '../../entry/src/main/ets/core/MobileWorkspace.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { PromptPart } from '../../entry/src/main/ets/core/Content.ts';
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from '../../entry/src/main/ets/core/Questions.ts';
import { DshSession } from '../../entry/src/main/ets/core/Models.ts';
import { FakeTimers, FakeSocket, FakeHttp } from '../helpers/fake-ws.ts';

/** 把微任务链跑干净（b18 教训：同步注入帧后 promise 链还没结算）。 */
async function drain(): Promise<void> {
  await new Promise<void>((resolve: (v: void) => void): void => setImmediate(resolve));
}

/** 服务端应答一帧（default 分支按 requestId 结算 data）。 */
function respond(socket: FakeSocket, data: unknown): void {
  socket.serverFrame({ kind: 'reply', data, requestId: socket.lastRequestId() });
}

/** 历史应答（events/hasMore/projections；projections 只在首屏带）。 */
function respondHistory(socket: FakeSocket, items: Object[],
  hasMore: boolean = false): void {
  respond(socket, {
    events: items, hasMore,
    projections: { values: { permissions: { currentValue: 'read-only' } } },
  });
}

function userItem(seq: number, text: string): Object {
  return { type: 'user/message', seq, time: 1700000000000 + seq,
    data: { message: { content: text, source: { kind: 'user' } } } };
}

function assistantItem(seq: number, text: string): Object {
  return { type: 'assistant/message', seq, time: 1700000000000 + seq,
    data: { message: { content: text } } };
}

interface ReadyCtx {
  socket: FakeSocket;
  timers: FakeTimers;
  http: FakeHttp;
  store: ChatStore;
  client: GatewayClient;
  api: GatewayApi;
}

/** 准备好一个 READY 的 GatewayClient + ChatStore。 */
function makeReady(deviceName: string = 'DSH Bridge'): ReadyCtx {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const http: FakeHttp = new FakeHttp();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai' };
  const client: GatewayClient = new GatewayClient('http://192.168.1.10:8765/', deps);
  client.setToken('tok-1', 'harmony');
  const api: GatewayApi = new GatewayApi(client, http);
  const store: ChatStore = new ChatStore(client, api, timers);
  const p: Promise<void> = client.connect();
  socket.serverOpen();
  socket.serverFrame({ kind: 'hello',
    data: { protocol: 3, device: { name: deviceName } } });
  // 连接 promise 一定结算（hello 同步到达）；构造时的 loadSessions 请求挂着无妨。
  p.catch((e: Error): void => {
    throw e;
  });
  createdClients.push(client);
  return { socket, timers, http, store, client, api };
}

/** 文件收口：清掉所有心跳 timer，否则 node:test 报 pending promise。 */
const createdClients: GatewayClient[] = [];
after(() => {
  for (const c of createdClients) {
    c.dispose();
  }
});

/** 打开会话 s1 并注入历史应答（先发起后应答，见文件头时序约定）。 */
async function openSession1(ctx: ReadyCtx, history: Object[],
  hasMore: boolean = false): Promise<void> {
  const s: DshSession = new DshSession(null);
  s.id = 's1';
  const pLoad: Promise<void> = ctx.store.openSession(s);
  respondHistory(ctx.socket, history, hasMore);
  await pLoad;
  await drain();
}

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

test('committed assistant：收流式 + 重拉历史', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, [userItem(1, 'q')]);
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.delta', sessionId: 's1', text: '流式' } });
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.message.committed', sessionId: 's1',
    role: 'assistant', seq: 2, turn: 1, step: 1 } });
  await drain();
  respondHistory(ctx.socket, [userItem(1, 'q'), assistantItem(2, '落库')]);
  await drain();
  assert.equal(ctx.store.streaming, false);
  assert.equal(ctx.store.streamText, '');
  assert.equal(ctx.store.messages.length, 2);
  assert.equal(ctx.store.messages[1].text, '落库');
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

test('ensureMobileWorkspace：命中「手机」工作区直接复用', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const http: FakeHttp = new FakeHttp();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'UTC' };
  const client: GatewayClient = new GatewayClient('http://h/', deps);
  client.setToken('t', 'd');
  const api: GatewayApi = new GatewayApi(client, http);
  const p: Promise<void> = client.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  const pWs: Promise<string | null> = ensureMobileWorkspace(api, null);
  respond(socket, { workspaces: [
    { id: 'ws-a', title: '测试', rootId: 'r1' },
    { id: 'ws-b', title: '手机会话', rootId: 'r2' },
  ] });
  const got: string | null = await pWs;
  assert.equal(got, 'ws-b');
});

test('ensureMobileWorkspace：无手机工作区 → 建目录+登记+改名', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const http: FakeHttp = new FakeHttp();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'UTC' };
  const client: GatewayClient = new GatewayClient('http://h/', deps);
  client.setToken('t', 'd');
  const api: GatewayApi = new GatewayApi(client, http);
  const p: Promise<void> = client.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  const pWs: Promise<string | null> = ensureMobileWorkspace(api, null);
  respond(socket, { workspaces: [
    { id: 'ws-a', title: '测试', rootId: 'r1' },
  ] });
  // FakeHttp 同步出队：REST 登记请求发出前必须先备好应答。
  http.push(200, JSON.stringify({ workspace: { workspaceId: 'ws-new' } }));
  await drain();
  respond(socket, {}); // directory-create
  const got: string | null = await pWs;
  assert.equal(got, 'ws-new');
  let sawPost: boolean = false;
  for (const r of http.requests) {
    if (r.method === 'POST' && r.url.indexOf('/api/v1/chat/workspaces') >= 0) {
      sawPost = true;
    }
  }
  assert.equal(sawPost, true);
});

test('ensureMobileWorkspace：缓存命中不发起请求', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const http: FakeHttp = new FakeHttp();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'UTC' };
  const client: GatewayClient = new GatewayClient('http://h/', deps);
  client.setToken('t', 'd');
  const api: GatewayApi = new GatewayApi(client, http);
  const got: string | null = await ensureMobileWorkspace(api, 'ws-cached');
  assert.equal(got, 'ws-cached');
  assert.equal(http.requests.length, 0);
});

test('sendWithImage：纯图也允许（text 空 → 上屏 [图片]）+ contentParts 携带 image part', async () => {
  const ctx: ReadyCtx = makeReady();
  await openSession1(ctx, []);
  drain();
  const part: PromptPart = PromptPart.image('image/png', 'aGk=', 'x.png');
  const pSend: Promise<void> = ctx.store.sendWithImage('', part);
  await drain();
  const sent = ctx.socket.lastSent();
  assert.equal(sent['type'], 'message');
  const content: Object[] = (sent['content'] as Object[]);
  assert.equal(content.length, 2);
  const imgPart = (content[1] as Record<string, Object>);
  assert.equal(imgPart['type'], 'image');
  assert.equal(imgPart['mediaType'], 'image/png');
  // 上屏占位
  assert.equal(ctx.store.messages[0].text, '[图片]');
  const pWs = ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(), sessionId: 's1' } });
  await pSend;
  ctx.socket.serverHello(3);
});

test('runCommand：本地命令卡 → executeCommand → ✓/✗ 回填', async () => {
  const ctx: ReadyCtx = makeReady();
  await openSession1(ctx, []);
  drain();
  const pRun: Promise<void> = ctx.store.runCommand('/help');
  await drain();
  // 命令卡上屏（seq=-1，role=command）
  const card: ChatMessage | null = ctx.store.messages.length > 0
    ? ctx.store.messages[ctx.store.messages.length - 1] : null;
  assert.ok(card !== null && card.role === 'command');
  assert.ok((card as ChatMessage).text.startsWith('/help'));
  // executeCommand 回显：错误分支
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(),
      result: { kind: 'error', text: '未知命令' } } });
  await pRun;
  assert.ok((card as ChatMessage).text.includes('✗ 未知命令'));
  // 重新执行：成功分支
  const pRun2: Promise<void> = ctx.store.runCommand('/compact');
  await drain();
  const card2 = ctx.store.messages[ctx.store.messages.length - 1];
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(), result: { kind: 'ok', text: '压缩完成' } } });
  await pRun2;
  assert.ok(card2.text.includes('✓ 压缩完成'));
});

test('HITL：question/approval 挂起 → answer/decide 摘卡', async () => {
  const ctx: ReadyCtx = makeReady();
  await openSession1(ctx, []);
  drain();
  // 事件：提问挂起
  ctx.socket.serverFrame({ kind: 'event',
    data: { type: 'userQuestions/requested', sessionId: 's1',
      callId: 'q1', questions: [{ id: 'a', question: '选择环境' }] } });
  await drain();
  assert.equal(ctx.store.pendingQuestions.length, 1);
  // 事件：审批挂起
  ctx.socket.serverFrame({ kind: 'event',
    data: { type: 'approval.requested', sessionId: 's1',
      approvalId: 'ap1', toolName: 'bash', risk: 'standard' } });
  await drain();
  assert.equal(ctx.store.pendingApprovals.length, 1);
  // answer
  const q: PendingQuestion = ctx.store.pendingQuestions[0];
  const pAns: Promise<void> = ctx.store.answerQuestion(q,
    [new QuestionAnswerItem('a', ['本地'], '')]);
  await drain();
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(), accepted: true } });
  await pAns;
  assert.equal(ctx.store.pendingQuestions.length, 0);
  // decide allow
  const ap: PendingApproval = ctx.store.pendingApprovals[0];
  const pDec: Promise<void> = ctx.store.decideApproval(ap, true);
  await drain();
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(), accepted: true } });
  await pDec;
  assert.equal(ctx.store.pendingApprovals.length, 0);
});

test('setPermission：当前有会话才发 permission 帧', async () => {
  const ctx: ReadyCtx = makeReady();
  await openSession1(ctx, []);
  drain();
  const pSet: Promise<void> = ctx.store.setPermission('workspace-write');
  await drain();
  const sent = ctx.socket.lastSent();
  assert.equal(sent['type'], 'permission');
  assert.equal(sent['name'], 'workspace-write');
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: ctx.socket.lastRequestId(), result: { kind: 'ok' } } });
  // 切换成功后会让 store 重拉 history（投影 values.permissions 才更新）。
  await drain();
  respondHistory(ctx.socket, []);
  await pSet;
  // 无会话：拒绝 NO_SESSION
  ctx.store.sessionId = null;
  await assert.rejects(ctx.store.setPermission('read-only'),
    (e: Error): boolean => (e as Error).message.includes('当前没有会话'));
});
