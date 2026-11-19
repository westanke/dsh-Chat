/**
 * 连接活性（core/LinkLiveness.ts）+「半死连接上的帧不发出去」——
 * 对齐 companion PITFALLS「WS 半死：socket 断了但状态还写着已连接」。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { LinkLiveness } from '../../entry/src/main/ets/core/LinkLiveness.ts';
import { LINK_LIVENESS_MS, NO_INBOUND_YET } from '../../entry/src/main/ets/core/Transport.ts';
import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayState, RequestException } from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { FakeTimers, FakeSocket } from '../helpers/fake-ws.ts';

test('LinkLiveness：未收帧不算死；静默超上限才算；重置后回到未知', () => {
  const live: LinkLiveness = new LinkLiveness();
  assert.equal(live.isStale(1_000_000), false); // 还没收到过帧
  live.seen(1000);
  assert.equal(live.isStale(1000 + LINK_LIVENESS_MS), false, '边界内不算死');
  assert.equal(live.isStale(1000 + LINK_LIVENESS_MS + 1), true);
  assert.equal(live.silentFor(2000), 1000);
  live.reset();
  assert.equal(live.isStale(999_999), false);
  assert.equal(live.silentFor(999_999), -1);
  assert.equal(NO_INBOUND_YET, -1, '哨兵不能用 0（真机时钟与假钟语义会撞）');
});

function makeClock(): { now: () => number; advance: (ms: number) => void } {
  let t: number = 0;
  return { now: (): number => t, advance: (ms: number): void => { t += ms; } };
}

test('静默超上限 → 只记录，连接与心跳都不动（判死权在服务端）', async () => {
  // 真机现场：客户端自己判静默超时会误杀活连接，表现为每 ~50s 一次无谓重连、
  // 收尾把主线程拖住 → tap 5s 不响应 → ANR。所以这里断言「什么都不发生」。
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const clock = makeClock();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai',
    now: clock.now };
  const c: GatewayClient = new GatewayClient('http://h/', deps);
  c.setToken('tok-1', 'harmony');
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  assert.equal(c.getState(), GatewayState.READY);

  const opensBefore: number = socket.openCountOf();
  const sentBefore: number = socket.sent.length;
  clock.advance(LINK_LIVENESS_MS + 1000); // 期间无任何入站帧
  timers.advance(25000);                   // 心跳到点
  assert.equal(c.getState(), GatewayState.READY, '活连接不能被误杀');
  assert.equal(socket.openCountOf(), opensBefore, '不该重连');
  const frames: Record<string, unknown>[] =
    socket.sent.slice(sentBefore).map((t: string): Record<string, unknown> =>
      JSON.parse(t) as Record<string, unknown>);
  assert.equal(frames.length, 1);
  assert.equal(frames[0]['type'], 'ping', '心跳照发');
  assert.equal(timers.pendingCount() >= 1, true, '下一拍心跳还要排上');
});

test('静默超上限后发请求 → 照常送出并等到应答（不预先判死）', async () => {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const clock = makeClock();
  const deps: GatewayDeps = { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai',
    now: clock.now };
  const c: GatewayClient = new GatewayClient('http://h/', deps);
  c.setToken('tok-1', 'harmony');
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;

  clock.advance(LINK_LIVENESS_MS + 1);
  const pending: Promise<Record<string, unknown>> = c.request('sessions', null);
  const reqId: string = socket.lastRequestId();
  assert.notEqual(reqId, '', '请求帧必须真的写进 socket');
  socket.serverFrame({ kind: 'sessions', data: { items: [] }, requestId: reqId });
  const res: Record<string, unknown> = await pending;
  assert.equal(c.getState(), GatewayState.READY);
  assert.equal(typeof res, 'object');
});
