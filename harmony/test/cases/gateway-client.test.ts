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

test('connect 组帧：wsUrl、Bearer 头、子协议含 dshrb-v1 协商位', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  assert.equal(socket.lastUrl, 'ws://192.168.1.10:8765/ws/mobile');
  assert.equal(socket.lastHeaders.get('Authorization'), 'Bearer tok-1');
  assert.equal(socket.lastProtocol, 'dsh-mobile-v1,dshrb-v1');
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

test('READY 掉线退避 1s；重连中掉线继续接力退避 2s（不终止）', async () => {
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

  // 重连中（未 READY）又掉线 —— 真机实证这里是原实现永久 CLOSED 的地方：
  // 必须留在重连链里，按下一档 2s 继续排（安卓 _onDone 无条件退避同口径）。
  socket.serverDown('flap');
  assert.equal(c.getState(), GatewayState.CONNECTING);
  assert.equal(timers.nextDelay(), 2000);
  assert.equal(timers.pendingCount(), 1);
  await new Promise<void>((r: () => void): void => setImmediate(r)); // 放 catch 微任务跑
  assert.equal(c.getState(), GatewayState.CONNECTING, '失败拒绝不许把重连链收掉');
  assert.equal(timers.pendingCount(), 1);

  // 接力中途连上 → hello 把 index 归零 → 再掉线仍 1s 起步
  timers.advance(2000);
  assert.equal(socket.openCountOf(), 3);
  socket.serverOpen();
  socket.serverHello();
  await new Promise<void>((r: () => void): void => setImmediate(r));
  assert.equal(c.getState(), GatewayState.READY);
  socket.serverDown('drop2');
  assert.equal(timers.nextDelay(), 1000);
});

test('同一次掉线的重复 onDown（error 紧跟 close）只排一次退避', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  // 真机实证：@ohos webSocket 一次掉线先发 error 再发 close，两个回调都上报 onDown。
  socket.serverDown('error');
  socket.serverDown('close');
  assert.equal(c.getState(), GatewayState.CONNECTING);
  assert.equal(timers.pendingCount(), 1, '一次掉线只许排一个重连 timer');
  assert.equal(timers.nextDelay(), 1000, '第一档必须是 1s，不许被第二次回调顶成 2s');
});

test('重连连续失败仍按 1→2→4→8→16→30→30 退避，永不终止', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  const expected: number[] = [1000, 2000, 4000, 8000, 16000, 30000, 30000];
  socket.serverDown('drop');
  for (let i: number = 0; i < expected.length; i += 1) {
    assert.equal(timers.nextDelay(), expected[i], '第 ' + i.toString() + ' 档退避');
    assert.equal(c.getState(), GatewayState.CONNECTING);
    timers.advance(expected[i]);
    // 每次重连都连不上：open 了但服务端立刻断（或根本没 open）
    socket.serverDown('down-' + i.toString());
    await new Promise<void>((r: () => void): void => setImmediate(r));
    assert.notEqual(c.getState(), GatewayState.CLOSED, '第 ' + i.toString() + ' 次失败后不许 CLOSED');
  }
  assert.equal(socket.openCountOf(), 1 + expected.length);
  assert.ok(MAX_BACKOFF_SECONDS === 30);
});

test('重连中 hello 协议不符（致命）→ CLOSED 终止重连链', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('drop');
  timers.advance(1000); // 自动重连：第二次 open
  socket.serverOpen();
  socket.serverHello(2); // 服务端协议版本不符 —— 重试无意义
  await new Promise<void>((r: () => void): void => setImmediate(r));
  assert.equal(c.getState(), GatewayState.CLOSED);
  assert.equal(timers.pendingCount(), 0);
});

test('重连 open 后 hello 超时 → 继续退避接力（不 CLOSED）', async () => {
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
  // hello 超时属于偶发失败（服务端慢/网络抖），继续按下一档退避接力。
  assert.equal(c.getState(), GatewayState.CONNECTING);
  assert.equal(timers.nextDelay(), 2000);
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

// ---------------------------------------------------------------------------
// 协议对齐（2026-11-19）：hello 能力位 + WS close code 语义
// ---------------------------------------------------------------------------

test('hello 带 capabilities/port → 存下来，hasCapability 精确匹配', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello(3, '', ['history-v1', 'mobile-session-stats-v1', 'kernel-call-v1'], 39876);
  await p;
  assert.equal(c.hasCapability('mobile-session-stats-v1'), true);
  assert.equal(c.hasCapability('speech-transcription-v1'), false);
  // 前缀不算命中（能力位是整串匹配，别用 startsWith 近似）
  assert.equal(c.hasCapability('history'), false);
  assert.equal(c.getListenerPort(), 39876);
  assert.equal(c.getCapabilities().length, 3);
});

test('老桥 hello 无 capabilities → 空数组，探测一律 false 不抛', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  assert.equal(c.getCapabilities().length, 0);
  assert.equal(c.hasCapability('history-v1'), false);
  assert.equal(c.getListenerPort(), 0);
});

test('close 4001（设备吊销）→ AUTH_FAILED 且不排重连，并上报 LINK_CLOSED', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const events: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    events.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('Device revoked', 4001);
  assert.equal(c.getState(), GatewayState.AUTH_FAILED);
  // 重连必然被同样打回：不许留下退避链（留下就是无限重连刷屏）
  assert.equal(timers.pendingCount(), 0);
  const link: GatewayEvent = events.filter((e: GatewayEvent): boolean =>
    e.type === GatewayEventType.LINK_CLOSED)[0];
  assert.notEqual(link, undefined);
  assert.equal(link.linkCode, 4001);
  assert.equal(link.linkReason, 'Device revoked');
});

test('close 1009（单帧超限）→ 上报 LINK_CLOSED 但仍按退避重连', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const events: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    events.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('frame too large', 1009);
  assert.equal(c.getState(), GatewayState.CONNECTING);
  assert.equal(timers.nextDelay(), 1000);
  const link: GatewayEvent = events.filter((e: GatewayEvent): boolean =>
    e.type === GatewayEventType.LINK_CLOSED)[0];
  assert.equal(link.linkCode, 1009);
});

test('close 1000（正常关）/ 无 code → 不上报 LINK_CLOSED', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = makeClient(socket, timers);
  const events: GatewayEvent[] = [];
  c.setEventListener((e: GatewayEvent): void => {
    events.push(e);
  });
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  socket.serverDown('bye', 1000);
  socket.serverDown('plain');
  const links: GatewayEvent[] = events.filter((e: GatewayEvent): boolean =>
    e.type === GatewayEventType.LINK_CLOSED);
  assert.equal(links.length, 0);
});
