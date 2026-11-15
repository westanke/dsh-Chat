/**
 * GatewayClient 状态机测试 —— 对照安卓 gateway.dart 语义逐条验证。
 * Fake 基建见 helpers/fake-ws.ts。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayEvent, GatewayEventType, GatewayState, RequestException }
  from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { MAX_BACKOFF_SECONDS, WS_HELLO_TIMEOUT_MS } from '../../entry/src/main/ets/core/Transport.ts';
import { FakeTimers, FakeSocket } from '../helpers/fake-ws.ts';

function makeDeps(socket: FakeSocket, timers: FakeTimers): GatewayDeps {
  return { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai' };
}

function makeClient(socket: FakeSocket, timers: FakeTimers): GatewayClient {
  const c: GatewayClient = new GatewayClient('http://192.168.1.10:8765/', makeDeps(socket, timers));
  c.setToken('tok-1', 'harmony');
  return c;
}

test('connect 无 token → NO_TOKEN，不发 open', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = new GatewayClient('http://h/', makeDeps(socket, timers));
  await assert.rejects(c.connect(), (e: Error): boolean =>
    (e as RequestException).code === 'NO_TOKEN');
  assert.equal(socket.openCountOf(), 0);
});

test('connect 组帧：wsUrl、Bearer 头、子协议 dsh-mobile-v1', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  assert.equal(socket.lastUrl, 'ws://192.168.1.10:8765/ws/mobile');
  assert.equal(socket.lastHeaders.get('Authorization'), 'Bearer tok-1');
  assert.equal(socket.lastProtocol, 'dsh-mobile-v1');
  socket.serverOpen();
  socket.serverHello();
  await p;
  assert.equal(c.getState(), GatewayState.READY);
  assert.notEqual(c.getServerDevice(), null);
});

test('hello protocol!=3 → PROTOCOL reject 并关闭连接', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello(2);
  await assert.rejects(p, (e: Error): boolean => (e as RequestException).code === 'PROTOCOL');
  assert.equal(socket.closedCount, 1);
});

test('hello 8s 超时 → TIMEOUT reject', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  const promise: Promise<void> = assert.rejects(p, (e: Error): boolean =>
    (e as RequestException).code === 'TIMEOUT');
  timers.advance(8001);
  await promise;
});

test('初连失败（hello 前 onDown）→ CLOSED，不自动重连', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverDown('net err');
  await assert.rejects(p, (e: Error): boolean => (e as RequestException).code === 'CONNECT_FAIL');
  assert.equal(c.getState(), GatewayState.CLOSED);
  assert.equal(timers.pendingCount(), 0);
});

test('READY 后掉线 → 1s 退避重连，hello 后 backoff 归零', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('drop');
  assert.equal(c.getState(), GatewayState.CONNECTING);
  assert.equal(timers.nextDelay(), 1000);
  timers.advance(1000);
  // 第二次 open 排上了
  const p2: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p2;
  assert.equal(c.getState(), GatewayState.READY);
});

test('READY 掉线退避 1s；重连中掉线 CLOSED 终止；hello 成功归零 index', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  // READY 掉线 → 退避 1s 排重连
  socket.serverDown('drop');
  assert.equal(timers.nextDelay(), 1000);
  timers.advance(1000);
  assert.equal(socket.openCountOf(), 2);

  // 重连中（未 READY）再掉线：初连失败口径 → CLOSED，不再排程
  socket.serverDown('flap');
  assert.equal(c.getState(), GatewayState.CLOSED);
  assert.equal(timers.pendingCount(), 0);

  // 手动再连成功 → hello 把 index 归零 → 掉线仍是 1s 起步
  const p2: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p2;
  socket.serverDown('drop2');
  assert.equal(timers.nextDelay(), 1000);
  assert.equal(c.getState(), GatewayState.CONNECTING);
  timers.advance(1000);
  socket.serverDown('flap2'); // 又是重连中掉线
  assert.equal(c.getState(), GatewayState.CLOSED);
});

test('重连 open 后 hello 超时 → 内部 promise reject TIMEOUT，catch 兜 CLOSED', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('drop');
  timers.advance(1000); // 自动重连：第二次 open（attempt=2）
  assert.equal(socket.openCountOf(), 2);
  socket.serverOpen();  // 连上了但服务端不发 hello
  timers.advance(WS_HELLO_TIMEOUT_MS + 1); // hello 超时（reject 在微任务里结算）
  await new Promise<void>((r: () => void): void => setImmediate(r)); // 等 catch 微任务跑完
  assert.equal(c.getState(), GatewayState.CLOSED);
});

test('请求/回显：requestId 配对 resolve；error 帧按 code reject', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  const q: Promise<Record<string, unknown>> = c.request('sessions', null);
  const frame: Record<string, unknown> = socket.lastSent();
  const rid: string = frame['requestId'] as string;
  assert.equal(frame['type'], 'sessions');
  assert.match(rid, /^r\d+-30000$/);
  socket.serverFrame({ kind: 'sessions', data: { sessions: [], requestId: rid } });
  const data: Record<string, unknown> = await q;
  assert.deepEqual(data, { sessions: [], requestId: rid });

  const q2: Promise<Record<string, unknown>> = c.request('models', null);
  const rid2: string = socket.lastSent()['requestId'] as string;
  socket.serverFrame({ kind: 'error', data: { code: 'HTTP_404', message: 'x', requestId: rid2 } });
  await assert.rejects(q2, (e: Error): boolean => (e as RequestException).code === 'HTTP_404');
});

test('请求超时 → TIMEOUT 且 pending 移除（后续回显不炸）', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  const q: Promise<Record<string, unknown>> = c.requestWithTimeout('slow', null, 500);
  const rejected: Promise<unknown> = assert.rejects(q, (e: Error): boolean =>
    (e as RequestException).code === 'TIMEOUT');
  timers.advance(501);
  await rejected;
  // 迟到的回显帧不应影响后续（pending 已清）。
  socket.serverFrame({ kind: 'slow', data: { requestId: 'r1-500' } });
  assert.equal(socket.closedCount, 0);
});

test('未连接发请求 → NOT_CONNECTED', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  await assert.rejects(c.request('sessions', null), (e: Error): boolean =>
    (e as RequestException).code === 'NOT_CONNECTED');
});

test('ping 帧 → 回 pong；心跳 25s 自续发 ping', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverFrame({ kind: 'ping' });
  assert.equal(socket.lastSent()['type'], 'pong');

  socket.sent.length = 0;
  timers.advance(25000);
  assert.equal(socket.lastSent()['type'], 'ping');
  timers.advance(25000);
  assert.equal(socket.sent.length, 2); // 自续
});

test('事件分发：delta/committed/turnFailed/sessionEvent', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const got: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    got.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverFrame({ kind: 'event', data: { type: 'chat.message.delta', sessionId: 's1',
    turn: 1, step: 0, index: 0, kind: 'text', text: 'hi' } });
  socket.serverFrame({ kind: 'event', data: { type: 'chat.message.committed', sessionId: 's1',
    role: 'assistant', seq: 3, turn: 1, step: 0 } });
  socket.serverFrame({ kind: 'event', data: { type: 'chat.turn.failed', sessionId: 's1' } });
  socket.serverFrame({ kind: 'event', data: { type: 'chat.session.event', sessionId: 's1',
    eventType: 'files-changed' } });

  assert.equal(got.length, 4);
  assert.equal(got[0].type, GatewayEventType.DELTA);
  assert.equal(got[0].delta !== null ? got[0].delta!.text : '', 'hi');
  assert.equal(got[1].type, GatewayEventType.COMMITTED);
  assert.equal(got[1].committed !== null ? got[1].committed!.seq : 0, 3);
  assert.equal(got[2].type, GatewayEventType.TURN_FAILED);
  assert.equal(got[2].message, '执行失败'); // 缺 message 用默认文案
  assert.equal(got[3].type, GatewayEventType.SESSION_EVENT);
  assert.equal(got[3].message, 'files-changed');
});

test('事件分发：提问/审批/modelsUpdated/deliverables 转会话事件', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const got: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    got.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverFrame({ kind: 'event', data: { type: 'userQuestions/requested', sessionId: 's1',
    callId: 'c1', questions: [{ id: 'q1', question: '用哪个？',
      options: [{ label: 'A' }, { label: 'B', description: '快' }] }] } });
  socket.serverFrame({ kind: 'event', data: { type: 'userQuestions/answered', sessionId: 's1',
    callId: 'c1' } });
  socket.serverFrame({ kind: 'event', data: { type: 'approval.requested', sessionId: 's1',
    approvalId: 'a1', toolName: 'bash', risk: 'full-access' } });
  socket.serverFrame({ kind: 'event', data: { type: 'approval.resolved', sessionId: 's1',
    approvalId: 'a1' } });
  socket.serverFrame({ kind: 'event', data: { type: 'chat.models.updated', provider: 'k2' } });
  socket.serverFrame({ kind: 'event', data: { type: 'chat.deliverables.presented', sessionId: 's1',
    files: [], seq: 9 } });

  assert.equal(got.length, 6);
  assert.equal(got[0].type, GatewayEventType.QUESTION_REQUESTED);
  assert.equal(got[0].question !== null ? got[0].question!.callId : '', 'c1');
  assert.equal(got[0].question !== null && got[0].question!.questions.length > 0
    ? got[0].question!.questions[0].options[1].description : '', '快');
  assert.equal(got[1].type, GatewayEventType.QUESTION_RESOLVED);
  assert.equal(got[2].type, GatewayEventType.APPROVAL_REQUESTED);
  assert.equal(got[2].approval !== null ? got[2].approval!.risk : '', 'full-access');
  assert.equal(got[3].type, GatewayEventType.APPROVAL_RESOLVED);
  assert.equal(got[4].type, GatewayEventType.MODELS_UPDATED);
  assert.equal(got[4].provider, 'k2');
  assert.equal(got[5].type, GatewayEventType.SESSION_EVENT);
  assert.equal(got[5].message, 'deliverables/presented');
});

test('connection-resync-required → resync 事件（dropped 透传）', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const got: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    got.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  socket.serverFrame({ kind: 'connection-resync-required', data: { dropped: true } });
  assert.equal(got.length, 1);
  assert.equal(got[0].type, GatewayEventType.RESYNC);
  assert.equal(got[0].dropped, true);
});

test('subscribe：发出 subscribe 帧，不登记 pending', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  assert.equal(c.subscribe('s1'), true);
  const frame: Record<string, unknown> = socket.lastSent();
  assert.equal(frame['type'], 'subscribe');
  assert.equal(frame['sessionId'], 's1');
});

test('dispose → CLOSED、连接关闭、在途请求打回 NOT_CONNECTED', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  const q: Promise<Record<string, unknown>> = c.request('sessions', null);
  const rejected: Promise<unknown> = assert.rejects(q, (e: Error): boolean =>
    (e as RequestException).code === 'NOT_CONNECTED');
  c.dispose();
  await rejected;
  assert.equal(c.getState(), GatewayState.CLOSED);
  assert.equal(socket.closedCount, 1);
  // dispose 后掉线不再重连
  timers.advance(60000);
  assert.equal(socket.openCountOf(), 1);
});
