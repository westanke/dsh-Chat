/**
 * ChatStore 交互动作测试（自 chat-store.test.ts 拆出，职责：工作区与交互动作——
 * 手机工作区预建/带图发送/本地命令卡/HITL 摘卡/权限档/挂起标记与 REST 兜底）。
 * 公共基建见 helpers/chat-ctx.ts；状态容器核心见 chat-store.test.ts。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { ChatMessage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { PromptPart } from '../../entry/src/main/ets/core/Content.ts';
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from '../../entry/src/main/ets/core/Questions.ts';
import { DshSession } from '../../entry/src/main/ets/core/Models.ts';
import { ensureMobileWorkspace } from '../../entry/src/main/ets/core/MobileWorkspace.ts';
import { FakeTimers, FakeSocket, FakeHttp } from '../helpers/fake-ws.ts';
import {
  drain, respond, respondHistory, userItem, makeReady, openSession1, ReadyCtx,
} from '../helpers/chat-ctx.ts';

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

test('runCommand：命中成功分支后本地命令卡不被 reloadHistory 冲掉', async () => {
  const ctx: ReadyCtx = makeReady();
  await openSession1(ctx, []);
  drain();
  const pRun: Promise<void> = ctx.store.runCommand('/compact');
  await drain();
  const reqId: string = ctx.socket.lastRequestId();
  ctx.socket.serverFrame({ kind: 'reply',
    data: { requestId: reqId, result: { kind: 'ok', text: '压缩完成' } } });
  await drain();
  // 成功链里会重拉 history：应答一条用户消息（模拟服务端无命令卡）。
  respondHistory(ctx.socket, [userItem(1, '你好')]);
  await drain();
  await pRun;
  const cards: ChatMessage[] = ctx.store.messages.filter((m: ChatMessage): boolean => m.role === 'command');
  assert.equal(cards.length, 1);
  assert.ok(cards[0].text.includes('✓ 压缩完成'));
  assert.equal(ctx.store.messages.length, 2);
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

test('refreshPendingMarks：REST 探测挂起项 → pendingMarkOf 返 question/approval', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  const pLoad: Promise<void> = ctx.store.loadSessions();
  respond(ctx.socket, { sessions: [
    { id: 's1', updatedAt: 5, running: false, blank: false },
    { id: 's2', updatedAt: 9, running: false, blank: false },
    { id: 's3', updatedAt: 7, running: false, blank: false },
  ] });
  await pLoad;
  // 每个会话先查 questions；s1 有提问（不查 approvals），s2 无提问再查 approvals 命中，
  // s3 两查皆空。FakeHttp 是队列式：按调用顺序准备好应答。
  // 注意顺序：三个 questions 请求在循环里同步发出（s1→s2→s3），approvals 请求
  // 要等 questions 回来才发（s2→s3），所以 approvals 的应答必须排在最后两个。
  ctx.http.push(200, JSON.stringify({ items: [{ callId: 'c1' }] }));   // s1 questions
  ctx.http.push(200, JSON.stringify({ items: [] }));                   // s2 questions
  ctx.http.push(200, JSON.stringify({ items: [] }));                   // s3 questions
  ctx.http.push(200, JSON.stringify({ items: [{ approvalId: 'a1' }] })); // s2 approvals
  ctx.http.push(200, JSON.stringify({ items: [] }));                   // s3 approvals
  const pMarks: Promise<void> = ctx.store.refreshPendingMarks();
  await drain();
  await pMarks;
  assert.equal(ctx.store.pendingMarkOf('s1'), 'question');
  assert.equal(ctx.store.pendingMarkOf('s2'), 'approval');
  assert.equal(ctx.store.pendingMarkOf('s3'), '');
  assert.equal(ctx.store.pendingMarkOf(''), '');
  // 实时挂起表优先：当前会话现场收到提问时立刻标 question（无需 REST 回来）。
  ctx.store.sessionId = 's3';
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.userQuestions/requested', sessionId: 's3',
    data: { type: 'userQuestions/requested', sessionId: 's3', callId: 'c9',
      questions: [{ id: 'q1', question: '吃什么？' }] } } });
  await drain();
  assert.equal(ctx.store.pendingMarkOf('s3'), 'question');
});

test('openSession：REST 兜底拉挂起提问 → 合流进 hitl 表 → 当前会话卡片可渲染', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  const s: DshSession = new DshSession(null);
  s.id = 's1';
  // openSession 先把 fetchQuestions 的 REST 请求发出去，再等历史应答。
  // FakeHttp 队列式：先备好 questions 应答，再注历史。
  ctx.http.push(200, JSON.stringify({ items: [
    { callId: 'c-rest', rpcId: 'rpc-rest', state: 'continued',
      questions: [{ id: 'q1', question: '继续吗？' }] },
    { callId: '', questions: [] },   // 空 callId 必须被丢掉
  ] }));
  const pLoad: Promise<void> = ctx.store.openSession(s);
  respondHistory(ctx.socket, [userItem(1, 'x')]);
  await pLoad;
  await drain();
  const qs: PendingQuestion[] = ctx.store.pendingQuestions;
  assert.equal(qs.length, 1);
  assert.equal(qs[0].callId, 'c-rest');
  assert.equal(qs[0].rpcId, 'rpc-rest');
  assert.equal(qs[0].state, 'continued');
  assert.equal(qs[0].sessionId, 's1');
  assert.equal(qs[0].questions.length, 1);
  assert.equal(qs[0].questions[0].question, '继续吗？');
});

test('openSession：REST 兜底失败静默（不写 lastError、不打断换会话）', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  const s: DshSession = new DshSession(null);
  s.id = 's1';
  ctx.http.push(403, JSON.stringify({ error: { code: 'FORBIDDEN', message: 'no scope' } }));
  let notified: number = 0;
  ctx.store.setNotify((): void => { notified += 1; });
  const pLoad: Promise<void> = ctx.store.openSession(s);
  respondHistory(ctx.socket, [userItem(1, 'x')]);
  await pLoad;
  await drain();
  assert.equal(ctx.store.lastError, null);
  assert.equal(ctx.store.messages.length, 1);
  // 失败不触发额外通知洪水：openSession 自身的通知即可覆盖。
  assert.ok(notified >= 1);
});

test('refreshPendingQuestions：不带 rpcId 时保留 WS 侧已有 rpcId', async () => {
  const ctx: ReadyCtx = makeReady();
  await ctx.p;
  await openSession1(ctx, []);
  // WS 先推一条带 rpcId 的。
  ctx.socket.serverFrame({ kind: 'event', data: {
    type: 'chat.userQuestions/requested', sessionId: 's1',
    data: { type: 'userQuestions/requested', sessionId: 's1', callId: 'c1',
      rpcId: 'rpc-ws', questions: [{ id: 'q1', question: '?' }] } } });
  await drain();
  assert.equal(ctx.store.pendingQuestions.length, 1);
  assert.equal(ctx.store.pendingQuestions[0].rpcId, 'rpc-ws');
  // REST 镜像同一条但不带 rpcId → 保留旧值。
  ctx.http.push(200, JSON.stringify({ items: [
    { callId: 'c1', questions: [{ id: 'q1', question: '?' }] },
  ] }));
  await ctx.store.refreshPendingQuestions('s1');
  assert.equal(ctx.store.pendingQuestions.length, 1);
  assert.equal(ctx.store.pendingQuestions[0].rpcId, 'rpc-ws');
  // 空 sessionId 直接短路，不发请求。
  const before: number = ctx.http.requests.length;
  await ctx.store.refreshPendingQuestions('');
  assert.equal(ctx.http.requests.length, before);
});
