import test from 'node:test';
import assert from 'node:assert/strict';

import { chatHeaderStatus, ChatHeaderStatus, HEADER_TONE_BUSY, HEADER_TONE_ERROR,
  HEADER_TONE_IDLE, HEADER_TONE_OK, HEADER_TONE_WARN } from '../../entry/src/main/ets/core/ChatHeaderStatus.ts';
import { GatewayState } from '../../entry/src/main/ets/core/GatewayEvents.ts';

test('chatHeaderStatus：优先级 未连接 > 连接中 > 已断开 > 等待审批 > 等待回答 > 生成中 > 主机名', () => {
  const idle: ChatHeaderStatus = chatHeaderStatus(GatewayState.IDLE, true, true, true, 'h');
  assert.deepEqual([idle.tone, idle.label], [HEADER_TONE_IDLE, '未连接']);
  const connecting: ChatHeaderStatus = chatHeaderStatus(GatewayState.CONNECTING, true, true, true, 'h');
  assert.equal(connecting.label, '连接中');
  assert.equal(connecting.tone, HEADER_TONE_BUSY);
  const closed: ChatHeaderStatus = chatHeaderStatus(GatewayState.CLOSED, true, true, true, 'h');
  assert.deepEqual([closed.tone, closed.label], [HEADER_TONE_ERROR, '已断开']);
  const auth: ChatHeaderStatus = chatHeaderStatus(GatewayState.AUTH_FAILED, false, false, false, 'h');
  assert.deepEqual([auth.tone, auth.label], [HEADER_TONE_ERROR, '已断开']);
  const approval: ChatHeaderStatus = chatHeaderStatus(GatewayState.READY, true, true, true, 'h');
  assert.deepEqual([approval.tone, approval.label], [HEADER_TONE_WARN, '等待审批']);
  const answer: ChatHeaderStatus = chatHeaderStatus(GatewayState.READY, true, false, true, 'h');
  assert.deepEqual([answer.tone, answer.label], [HEADER_TONE_WARN, '等待回答']);
  const gen: ChatHeaderStatus = chatHeaderStatus(GatewayState.READY, true, false, false, 'h');
  assert.deepEqual([gen.tone, gen.label], [HEADER_TONE_BUSY, '生成中']);
});

test('chatHeaderStatus：就绪时显示主机名，空主机名回落「已连接」', () => {
  const ok: ChatHeaderStatus = chatHeaderStatus(GatewayState.READY, false, false, false, ' 10.0.0.2:8787 ');
  assert.deepEqual([ok.tone, ok.label], [HEADER_TONE_OK, '10.0.0.2:8787']);
  assert.equal(chatHeaderStatus(GatewayState.READY, false, false, false, '  ').label, '已连接');
});
