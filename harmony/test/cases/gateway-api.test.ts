/**
 * GatewayApi WS 端点测试 —— FakeSocket 全链回放：帧形状、requestId 配对、错误映射。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { GatewayClient } from '../../entry/src/main/ets/core/GatewayClient.ts';
import { GatewayApi } from '../../entry/src/main/ets/core/GatewayApi.ts';
import { RequestException } from '../../entry/src/main/ets/core/GatewayEvents.ts';
import { PromptPart } from '../../entry/src/main/ets/core/Content.ts';
import { QuestionAnswerItem } from '../../entry/src/main/ets/core/Questions.ts';
import { HistoryPage } from '../../entry/src/main/ets/core/HistoryPage.ts';
import { FakeTimers, FakeSocket, FakeHttp } from '../helpers/fake-ws.ts';

async function makeApi(): Promise<[GatewayApi, FakeSocket, FakeTimers]> {
  const socket: FakeSocket = new FakeSocket();
  const timers: FakeTimers = new FakeTimers();
  const c: GatewayClient = new GatewayClient('ws://192.168.1.10:8765',
    { ws: socket, timers, timeZoneId: (): string => 'Asia/Shanghai' } as never);
  c.setToken('tok-1', 'harmony');
  const p: Promise<void> = c.connect();
  socket.serverOpen();
  socket.serverHello();
  await p;
  return [new GatewayApi(c), socket, timers];
}

function codeOf(err: unknown): string {
  return (err as RequestException).code;
}

test('workspaces/sessions: data.list 数组解析', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<Record<string, Object>[]> = api.workspaces();
  socket.serverFrame('{"kind":"workspaces","data":{"requestId":"'
    + socket.lastRequestId() + '","workspaces":[{"id":"w1","title":"工作区一"}]}}');
  const ws: Record<string, Object>[] = await p1;
  assert.equal(ws.length, 1);
  assert.equal(ws[0]['id'], 'w1');
  assert.equal(ws[0]['title'], '工作区一');

  const p2: Promise<Record<string, Object>[]> = api.sessions();
  socket.serverFrame('{"kind":"sessions","data":{"requestId":"'
    + socket.lastRequestId() + '","sessions":[{"id":"s1","blank":true}]}}');
  const ss: Record<string, Object>[] = await p2;
  assert.equal(ss.length, 1);
  assert.equal(ss[0]['blank'], true);
});

test('createSessionInWorkspace / createSessionAt: 帧形状与 sessionId 回读', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<string> = api.createSessionInWorkspace('w1');
  const sent1: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent1['type'], 'session-create');
  assert.equal(sent1['workspaceId'], 'w1');
  socket.serverFrame('{"kind":"session-created","data":{"requestId":"'
    + socket.lastRequestId() + '","sessionId":"s-new"}}');
  assert.equal(await p1, 's-new');

  const p2: Promise<string> = api.createSessionAt('root-1', '/tmp/x');
  const sent2: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent2['rootId'], 'root-1');
  assert.equal(sent2['cwd'], '/tmp/x');
  assert.equal('workspaceId' in sent2, false);
  socket.serverFrame('{"kind":"session-created","data":{"requestId":"'
    + socket.lastRequestId() + '","sessionId":"s-2"}}');
  assert.equal(await p2, 's-2');

  const p3: Promise<string> = api.createSessionAt('', '');
  const sent3: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal('rootId' in sent3, false);
  assert.equal(sent3['cwd'], ''); // 安卓口径：cwd 空串也上送
  socket.serverFrame('{"kind":"session-created","data":{"requestId":"'
    + socket.lastRequestId() + '","sessionId":"s-3"}}');
  assert.equal(await p3, 's-3');
});

test('sendText: content 数组 = text part + 追加 parts，clientTimeZone 随帧', async () => {
  const [api, socket] = await makeApi();
  const parts: PromptPart[] = [PromptPart.image('image/png', 'aGk=', 'hello.png')];
  const p: Promise<string> = api.sendText('s1', '你好', 'queue', parts);
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent['type'], 'message');
  assert.equal(sent['sessionId'], 's1');
  assert.equal(sent['mode'], 'queue');
  assert.equal(sent['clientTimeZone'], 'Asia/Shanghai');
  const content: Object[] = sent['content'] as Object[];
  assert.equal(content.length, 2);
  assert.equal((content[0] as Record<string, Object>)['type'], 'text');
  assert.equal((content[0] as Record<string, Object>)['text'], '你好');
  const img: Record<string, Object> = content[1] as Record<string, Object>;
  assert.equal(img['type'], 'image');
  assert.equal(img['mediaType'], 'image/png');
  assert.equal(img['data'], 'aGk=');
  assert.equal(img['name'], 'hello.png');
  socket.serverFrame('{"kind":"message-accepted","data":{"requestId":"'
    + socket.lastRequestId() + '","sessionId":"s9"}}');
  assert.equal(await p, 's9'); // 回显 sessionId 优先
});

test('sendText: 服务端无 sessionId 回显时用入参兜底', async () => {
  const [api, socket] = await makeApi();
  const p: Promise<string> = api.sendText('s-fallback', 'hi');
  socket.serverFrame('{"kind":"message-accepted","data":{"requestId":"'
    + socket.lastRequestId() + '","x":1}}');
  assert.equal(await p, 's-fallback');
});

test('listDirectory: limit 200 + DshDirectoryPage 解析', async () => {
  const [api, socket] = await makeApi();
  const p: Promise<Record<string, Object>> = api.listDirectory('root-1', '/docs', 'cur-7');
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent['type'], 'file-list');
  assert.equal(sent['limit'], 200);
  assert.equal(sent['cursor'], 'cur-7');
  socket.serverFrame('{"kind":"file-list","data":{"requestId":"'
    + socket.lastRequestId() + '","rootId":"root-1","path":"/docs","entries":['
    + '{"name":"a.md","path":"/docs/a.md","kind":"file"},'
    + '{"name":"sub","path":"/docs/sub","kind":"directory"}],"nextCursor":"c2"}}');
  const page: Record<string, Object> = await p;
  assert.equal(page['nextCursor'], 'c2');
  const entries: Object[] = page['entries'] as Object[];
  assert.equal(entries.length, 2);
});

test('sessionWait: clamp 1..120000，wait 非 Map → BAD_REPLY', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<Record<string, Object>> = api.sessionWait('s1', 999999);
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent['timeoutMs'], 120000);
  socket.serverFrame('{"kind":"session-wait-result","data":{"requestId":"'
    + socket.lastRequestId() + '","wait":{"reason":"idle"}}}');
  const r1: Record<string, Object> = await p1;
  assert.equal(r1['reason'], 'idle');

  const p2: Promise<Record<string, Object>> = api.sessionWait('s1', 0);
  socket.serverFrame('{"kind":"session-wait-result","data":{"requestId":"'
    + socket.lastRequestId() + '","wait":"not-a-map"}}');
  await assert.rejects(p2, (e: Error): boolean => codeOf(e) === 'BAD_REPLY');
});

test('setPermission: result.kind=error → PERMISSION', async () => {
  const [api, socket] = await makeApi();
  const p: Promise<void> = api.setPermission('s1', 'full-access');
  socket.serverFrame('{"kind":"permission-result","data":{"requestId":"'
    + socket.lastRequestId() + '","result":{"kind":"error","text":"nope"}}}');
  await assert.rejects(p, (e: Error): boolean =>
    codeOf(e) === 'PERMISSION' && e.message === 'nope');
});

test('answerQuestion: accepted=false → QUESTION_REJECTED', async () => {
  const [api, socket] = await makeApi();
  const items: QuestionAnswerItem[] = [new QuestionAnswerItem('q1', ['A'], '')];
  const p: Promise<void> = api.answerQuestion('s1', 'c1', items);
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent['type'], 'question-answer');
  assert.equal(sent['callId'], 'c1');
  assert.equal((sent['answers'] as Object[]).length, 1);
  socket.serverFrame('{"kind":"question-result","data":{"requestId":"'
    + socket.lastRequestId() + '","accepted":false,"reason":"会话已结束"}}');
  await assert.rejects(p, (e: Error): boolean =>
    codeOf(e) === 'QUESTION_REJECTED' && e.message === '会话已结束');
});

test('decideApproval: outcome 映射 + APPROVAL_REJECTED', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<void> = api.decideApproval('s1', 'a1', true);
  const sent1: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent1['type'], 'approval-response');
  assert.equal(sent1['outcome'], 'allowed-once');
  socket.serverFrame('{"kind":"approval-result","data":{"requestId":"'
    + socket.lastRequestId() + '","accepted":true}}');
  await p1;

  const p2: Promise<void> = api.decideApproval('s1', 'a1', false);
  const sent2: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent2['outcome'], 'rejected');
  socket.serverFrame('{"kind":"approval-result","data":{"requestId":"'
    + socket.lastRequestId() + '","accepted":false,"reason":"已被处理"}}');
  await assert.rejects(p2, (e: Error): boolean => codeOf(e) === 'APPROVAL_REJECTED');
});

test('cancelQuestion: rpcId 空则不放键', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<void> = api.cancelQuestion('s1', 'c1', '');
  const sent1: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent1['type'], 'question-cancel');
  assert.equal('rpcId' in sent1, false);
  socket.serverFrame('{"kind":"question-cancelled","data":{"requestId":"'
    + socket.lastRequestId() + '","accepted":true}}');
  await p1;

  const p2: Promise<void> = api.cancelQuestion('s1', 'c1', 'r5');
  const sent2: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent2['rpcId'], 'r5');
  socket.serverFrame('{"kind":"question-cancelled","data":{"requestId":"'
    + socket.lastRequestId() + '","accepted":true}}');
  await p2;
});

test('selectModel / executeCommand / listCommands / sessionModels 帧形状', async () => {
  const [api, socket] = await makeApi();

  const p1: Promise<void> = api.selectModel('s1', 'deepseek-chat', 'v3', 'high');
  const sent1: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent1['type'], 'select-model');
  assert.equal(sent1['model'], 'v3');
  assert.equal(sent1['reasoningEffort'], 'high');
  socket.serverFrame('{"kind":"sent","data":{"requestId":"'
    + socket.lastRequestId() + '","type":"select-model"}}');
  await p1;

  const p2: Promise<Record<string, Object>> = api.executeCommand('s1', '/compact keep 3');
  const sent2: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent2['line'], '/compact keep 3');
  socket.serverFrame('{"kind":"command-executed","data":{"requestId":"'
    + socket.lastRequestId() + '","result":{"kind":"ok","text":"done"}}}');
  const r2: Record<string, Object> = await p2; // 安卓口径：直返应答 data 顶层
  const result2: Record<string, Object> = r2['result'] as Record<string, Object>;
  assert.equal(result2['kind'], 'ok');

  const p3: Promise<Record<string, Object>> = api.listCommands('s1');
  socket.serverFrame('{"kind":"commands","data":{"requestId":"'
    + socket.lastRequestId() + '","commands":[{"name":"goal"}]}}');
  const r3: Record<string, Object> = await p3; // 安卓口径：直返 data 顶层
  assert.equal((r3['commands'] as Object[]).length, 1);

  const p4: Promise<Record<string, Object>> = api.sessionModels('s1');
  socket.serverFrame('{"kind":"models","data":{"requestId":"'
    + socket.lastRequestId() + '","current":"v3"}}');
  const r4: Record<string, Object> = await p4;
  assert.equal(r4['current'], 'v3');
});

test('history: history 帧 → HistoryPage 装配（events/hasMore/projections）', async () => {
  const [api, socket] = await makeApi();
  const p: Promise<HistoryPage> = api.history('s1', 50, 1200);
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal(sent['type'], 'history');
  assert.equal(sent['sessionId'], 's1');
  assert.equal(sent['maxMessages'], 50);
  assert.equal(sent['beforeSeq'], 1200);
  socket.serverFrame('{"kind":"history","data":{"requestId":"'
    + socket.lastRequestId() + '","events":['
    + '{"type":"user/message","seq":1,"time":100,"data":{"content":"你好","source":{"kind":"user"}}},'
    + '{"type":"assistant/message","seq":2,"time":110,"data":{"message":{"content":"回复"}}}'
    + '],"hasMore":true,"projections":{"asOfSeq":9,"values":{}}}}');
  const page: HistoryPage = await p;
  assert.equal(page.items.length, 2);
  assert.equal(page.items[0].text, '你好');
  assert.equal(page.hasMore, true);
  assert.notEqual(page.projections, null);
});

test('history: 翻页参数 0 不上帧；subagentHistory 走 REST', async () => {
  const [api, socket] = await makeApi();
  const p1: Promise<HistoryPage> = api.history('s1');
  const sent: Record<string, Object> = socket.lastSent() as Record<string, Object>;
  assert.equal('maxMessages' in sent, false);
  assert.equal('beforeSeq' in sent, false);
  socket.serverFrame('{"kind":"history","data":{"requestId":"'
    + socket.lastRequestId() + '","events":[],"hasMore":false}}');
  const page1: HistoryPage = await p1;
  assert.equal(page1.items.length, 0);
  assert.equal(page1.projections, null);

  const http: FakeHttp = new FakeHttp();
  http.push(200, '{"events":[{"type":"user/message","seq":1,"time":10,'
    + '"data":{"content":"子会话内容"}}],"hasMore":true}');
  const socket2: FakeSocket = new FakeSocket();
  const timers2: FakeTimers = new FakeTimers();
  const c2: GatewayClient = new GatewayClient('http://192.168.1.10:8765',
    { ws: socket2, timers: timers2, timeZoneId: (): string => 'UTC' } as never);
  c2.setToken('tok-2', 'harmony');
  const cp: Promise<void> = c2.connect();
  socket2.serverOpen();
  socket2.serverHello();
  await cp;
  const api2: GatewayApi = new GatewayApi(c2, http);
  const page2: HistoryPage = await api2.subagentHistory('lead-1', 'sub-1', 30);
  assert.equal(http.requests[0].url,
    'http://192.168.1.10:8765/api/v1/chat/sessions/lead-1/subagents/sub-1/messages?maxMessages=30');
  assert.equal(http.requests[0].headers.get('authorization'), 'Bearer tok-2');
  assert.equal(page2.items.length, 1);
  assert.equal(page2.items[0].text, '子会话内容');
  assert.equal(page2.hasMore, true);
});
