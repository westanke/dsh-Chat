/**
 * ChatStore 测试公共基建（自 chat-store.test.ts 拆出）：
 * Fake 连接 + READY 上下文 + 历史应答桩。node:test 每个测试文件独立子进程
 * 加载本模块，顶层 after() 在各自文件的根上下文注册，互不串扰。
 * Fake 基建本体见 helpers/fake-ws.ts。
 *
 * 时序约定：先发起动作（请求同步发出），再注入应答帧（respond 自动读
 * lastRequestId），最后 await 动作 promise——顺序反了应答会扑空。
 */

import { after } from 'node:test';

import { GatewayClient, GatewayDeps } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { ChatStore } from '../../entry/src/main/ets/core/ChatStore.ts';
import { DshSession } from '../../entry/src/main/ets/core/Models.ts';
import { FakeTimers, FakeSocket, FakeHttp } from './fake-ws.ts';

/** 把微任务链跑干净（b18 教训：同步注入帧后 promise 链还没结算）。 */
export async function drain(): Promise<void> {
  await new Promise<void>((resolve: (v: void) => void): void => setImmediate(resolve));
}

/** 服务端应答一帧（default 分支按 requestId 结算 data）。 */
export function respond(socket: FakeSocket, data: unknown): void {
  socket.serverFrame({ kind: 'reply', data, requestId: socket.lastRequestId() });
}

/** 历史应答（events/hasMore/projections；projections 只在首屏带）。 */
export function respondHistory(socket: FakeSocket, items: Object[],
  hasMore: boolean = false): void {
  respond(socket, {
    events: items, hasMore,
    projections: { values: { permissions: { currentValue: 'read-only' } } },
  });
}

export function userItem(seq: number, text: string): Object {
  return { type: 'user/message', seq, time: 1700000000000 + seq,
    data: { message: { content: text, source: { kind: 'user' } } } };
}

export function assistantItem(seq: number, text: string): Object {
  return { type: 'assistant/message', seq, time: 1700000000000 + seq,
    data: { message: { content: text } } };
}

export interface ReadyCtx {
  socket: FakeSocket;
  timers: FakeTimers;
  http: FakeHttp;
  store: ChatStore;
  client: GatewayClient;
  api: GatewayApi;
}

/** 准备好一个 READY 的 GatewayClient + ChatStore。 */
export function makeReady(deviceName: string = 'DSH Bridge'): ReadyCtx {
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
export async function openSession1(ctx: ReadyCtx, history: Object[],
  hasMore: boolean = false): Promise<void> {
  const s: DshSession = new DshSession(null);
  s.id = 's1';
  const pLoad: Promise<void> = ctx.store.openSession(s);
  respondHistory(ctx.socket, history, hasMore);
  await pLoad;
  await drain();
}
