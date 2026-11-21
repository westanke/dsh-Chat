import test from 'node:test';
import assert from 'node:assert/strict';

import {
  KernelEndpoint, KernelCallResult, KernelCallRegistry, KernelPending,
  parseKernelEndpoints, KERNEL_SESSION_SEARCH,
} from '../../entry/src/main/ets/core/KernelCall.ts';
import {
  parseSessionSearchHits, sessionSearchArgs, tidySnippet, sessionSearchHasMore,
} from '../../entry/src/main/ets/core/SessionSearch.ts';
import { JsonMap } from '../../entry/src/main/ets/core/JsonAccess.ts';

test('parseKernelEndpoints：顶层 endpoints、忽略无端点名/非字符串 wire', () => {
  const frame: JsonMap = {
    kind: 'kernel-endpoints',
    endpoints: [
      { endpoint: 'session/search', scope: 'chat.read', summary: 's', stream: false, wires: ['request'] },
      { endpoint: '', scope: 'x' },
      { endpoint: 'a/b', wires: ['query', 3 as unknown as Object] },
    ],
  };
  const list: KernelEndpoint[] = parseKernelEndpoints(frame);
  assert.equal(list.length, 2);
  assert.equal(list[0].endpoint, KERNEL_SESSION_SEARCH);
  assert.deepEqual(list[0].wires, ['request']);
  assert.deepEqual(list[1].wires, ['query']);
  assert.equal(parseKernelEndpoints(null).length, 0);
});

test('KernelCallResult：成功/失败/空值', () => {
  const ok: KernelCallResult = KernelCallResult.fromFrame({
    kind: 'kernel-call-result', callId: 'c1', ok: true,
    value: { items: [{ sessionId: 's1', snippet: 'hello' }], hasMore: true },
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.object() !== null, true);
  assert.equal(sessionSearchHasMore(ok.value), true);
  const bad: KernelCallResult = KernelCallResult.fromFrame({
    kind: 'kernel-call-result', callId: 'c2', ok: false,
    error: { code: 'METHOD_NOT_ALLOWED', message: '不允许' },
  });
  assert.equal(bad.message(), '不允许');
  assert.equal(bad.object(), null);
  assert.equal(KernelCallResult.fromFrame(null).ok, false);
});

test('KernelCallRegistry：重复 id、take 只结算一次、failAll', () => {
  const reg: KernelCallRegistry = new KernelCallRegistry();
  const p = new KernelPending((): void => {}, (): void => {}, 1);
  assert.equal(reg.add('a', p), true);
  assert.equal(reg.add('a', p), false);
  assert.equal(reg.length(), 1);
  assert.equal(reg.take('a'), p);
  assert.equal(reg.take('a'), null);
  let failed: string = '';
  reg.add('b', new KernelPending((): void => {}, (e: Error): void => { failed = e.message; }, 2));
  reg.failAll('NOT_CONNECTED');
  assert.equal(failed, 'NOT_CONNECTED');
  assert.equal(reg.length(), 0);
});

test('parseSessionSearchHits：坏形状宽容、snippet 压空白、limit', () => {
  assert.equal(parseSessionSearchHits(null).length, 0);
  const hits = parseSessionSearchHits({
    items: [
      { sessionId: 's1', snippet: '第一行\n\t第二行  ' },
      { sessionId: '', snippet: 'x' },
      { sessionId: 's2', snippet: 3 as unknown as Object },
      { sessionId: 's3' },
    ],
  });
  assert.equal(hits.length, 3);
  assert.equal(hits[0].snippet, '第一行 第二行');
  assert.equal(hits[1].snippet, '');
  assert.equal(parseSessionSearchHits({ items: [{ sessionId: 'a' }, { sessionId: 'b' }] }, 1).length, 1);
});

test('tidySnippet：首尾空白与多空格折叠', () => {
  assert.equal(tidySnippet('  a   b\n'), 'a b');
  assert.equal(tidySnippet(''), '');
});

test('sessionSearchArgs：按 wires 选键，未知形状塞第一个 wire', () => {
  const ep = new KernelEndpoint();
  ep.wires = ['request'];
  assert.deepEqual(sessionSearchArgs(ep, 'q'), { request: { query: 'q' } });
  ep.wires = ['query'];
  assert.deepEqual(sessionSearchArgs(ep, 'q'), { query: 'q' });
  ep.wires = ['payload'];
  assert.deepEqual(sessionSearchArgs(ep, 'q'), { payload: { query: 'q' } });
  ep.wires = [];
  assert.deepEqual(sessionSearchArgs(ep, 'q'), { request: { query: 'q' } });
});
