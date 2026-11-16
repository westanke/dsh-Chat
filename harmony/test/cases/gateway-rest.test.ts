/**
 * GatewayApi REST 端点测试 —— FakeHttp 回放，验证 URL 拼装/头/错误映射。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { RequestException } from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { FakeTimers, FakeSocket, FakeHttp } from '../helpers/fake-ws.ts';

async function makeApi(http: FakeHttp | null): Promise<GatewayApi> {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = new GatewayClient('http://192.168.1.10:8765',
    { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai' } as never);
  c.setToken('tok-9', 'harmony');
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  return new GatewayApi(c, http);
}

test('pairViaRest: POST /api/v1/pairings/exchange，body 带 code/deviceName', async () => {
  const http: FakeHttp = new FakeHttp();
  http.push(200, '{"token":"t1","device":{"id":"d1"}}');
  const api: GatewayApi = await makeApi(http);
  const resp: Record<string, Object> = await api.pairViaRest(' 123456 ', ' HarmonyOS 手机 ') as Record<string, Object>;
  const req = http.requests[0];
  assert.equal(req.method, 'POST');
  assert.equal(req.url, 'http://192.168.1.10:8765/api/v1/pairings/exchange');
  assert.equal(req.headers.get('content-type'), 'application/json');
  assert.equal(req.headers.get('authorization'), 'Bearer tok-9');
  const body: Record<string, unknown> = JSON.parse(req.body as string) as Record<string, unknown>;
  assert.equal(body['code'], ' 123456 ');
  assert.equal(body['deviceName'], ' HarmonyOS 手机 ');
  assert.equal(resp['token'], 't1');
});

test('REST 非 2xx → HTTP_<code> reject', async () => {
  const http: FakeHttp = new FakeHttp();
  http.push(404, 'not found');
  const api: GatewayApi = await makeApi(http);
  await assert.rejects(api.pairViaRest('x', 'y'), (e: Error): boolean =>
    (e as RequestException).code === 'HTTP_404');
});

test('REST 应答非 JSON 对象 → BAD_REPLY', async () => {
  const http: FakeHttp = new FakeHttp();
  http.push(200, '[1,2,3]');
  const api: GatewayApi = await makeApi(http);
  await assert.rejects(api.pairViaRest('x', 'y'), (e: Error): boolean =>
    (e as RequestException).code === 'BAD_REPLY');
});

test('REST 空 body → 空对象', async () => {
  const http: FakeHttp = new FakeHttp();
  http.push(201, '');
  const api: GatewayApi = await makeApi(http);
  const resp: Record<string, Object> = await api.pairViaRest('x', 'y') as Record<string, Object>;
  assert.deepEqual(resp, {});
});

test('fetchAttachment: sha256 冒号 percent-encode + sessionId 必带', async () => {
  const http: FakeHttp = new FakeHttp();
  http.pushBytes(200, new Uint8Array([1, 2, 3, 4]));
  const api: GatewayApi = await makeApi(http);
  const data: Uint8Array = await api.fetchAttachment('sha256:abc123', 's/1?x');
  assert.equal(data.length, 4);
  const req = http.requests[0];
  assert.equal(req.method, 'GET');
  assert.equal(req.url,
    'http://192.168.1.10:8765/api/v1/attachments/sha256%3Aabc123?sessionId=s%2F1%3Fx');
  assert.equal(data.length, 4);
});

test('fetchAttachment 非 200 → HTTP_<code>', async () => {
  const http: FakeHttp = new FakeHttp();
  http.push(400, '');
  const api: GatewayApi = await makeApi(http);
  await assert.rejects(api.fetchAttachment('sha256:abc', 's1'), (e: Error): boolean =>
    (e as RequestException).code === 'HTTP_400');
});

test('fetchImageHandoff: name encode', async () => {
  const http: FakeHttp = new FakeHttp();
  const api: GatewayApi = await makeApi(http);
  http.pushBytes(200, new Uint8Array([9, 8, 7, 6]));
  const data: Uint8Array = await api.fetchImageHandoff('abc.png?raw=1', 's1');
  assert.equal(data.length, 4);
  // sessionId 必带（bridge 校验 name + sessionId 同时存在，缺则 400 BODY_INVALID）。
  assert.equal(http.requests[0].url,
    'http://192.168.1.10:8765/api/v1/image-handoff?name=abc.png%3Fraw%3D1&sessionId=s1');
  assert.ok(data instanceof Uint8Array);
  assert.equal(data.length, 4);
});

test('http 未注入 → NO_TRANSPORT（不发请求）', async () => {
  const api: GatewayApi = await makeApi(null);
  await assert.rejects(api.pairViaRest('x', 'y'), (e: Error): boolean =>
    (e as RequestException).code === 'NO_TRANSPORT');
  await assert.rejects(api.fetchAttachment('a', 'b'), (e: Error): boolean =>
    (e as RequestException).code === 'NO_TRANSPORT');
  await assert.rejects(api.fetchImageHandoff('a', 'b'), (e: Error): boolean =>
    (e as RequestException).code === 'NO_TRANSPORT');
});
