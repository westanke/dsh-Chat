/**
 * HitlStore 挂起表测试 —— 对照安卓 hitl_state.dart（2026-11-16 待回答一致性配套）。
 *
 * 覆盖：REST 兜底合流 mergeQuestions（按 callId upsert、保留 WS 侧 rpcId、
 * 空 callId 跳过）、角标用的 pending*SessionIds 派生、事件摘卡。
 * 纯内存类，不需要 FakeSocket。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';
import { HitlStore } from '../../entry/src/main/ets/core/HitlStore.ts';
import { PendingQuestion, PendingApproval } from '../../entry/src/main/ets/core/Questions.ts';
import { GatewayEvent, GatewayEventType } from '../../entry/src/main/ets/core/GatewayEvents.ts';

function m(text: string): Record<string, Object> {
  const parsed: Object | null = JsonAccess.parse(text);
  assert.notEqual(parsed, null);
  return parsed as Record<string, Object>;
}

/** 造一条挂起提问（REST 镜像或 WS 事件同形）。 */
function q(sessionId: string, callId: string, rpcId: string = ''): PendingQuestion {
  return PendingQuestion.fromJson(sessionId, m(JSON.stringify({
    callId, rpcId, questions: [{ id: 'q1', question: '用哪个？' }],
  })));
}

test('mergeQuestions：按 callId upsert，重复合流不产生重复条目', () => {
  const s: HitlStore = new HitlStore();
  assert.equal(s.mergeQuestions([q('s1', 'c1'), q('s1', 'c2')]), true);
  assert.equal(s.sessionQuestions('s1').length, 2);
  // 同一批再来一次：条数不变（Map 覆盖同键）。
  s.mergeQuestions([q('s1', 'c1'), q('s1', 'c2')]);
  assert.equal(s.sessionQuestions('s1').length, 2);
});

test('mergeQuestions：空 callId 跳过，返回 false 表示表未变', () => {
  const s: HitlStore = new HitlStore();
  assert.equal(s.mergeQuestions([]), false);
  const empty: PendingQuestion = PendingQuestion.fromJson('s1', m('{"questions":[]}'));
  assert.equal(empty.callId, '');
  assert.equal(s.mergeQuestions([empty]), false);
  assert.equal(s.sessionQuestions('s1').length, 0);
});

test('mergeQuestions：已有 rpcId 不被 REST 空 rpcId 覆盖（WS 条目多带 cancel 关联键）', () => {
  const s: HitlStore = new HitlStore();
  // WS 推送先到，带 rpcId。
  s.onQuestionRequested(q('s1', 'c1', 'rpc-9'));
  assert.equal(s.sessionQuestions('s1')[0].rpcId, 'rpc-9');
  // REST 镜像后到，rpcId 为空 → 保留旧的。
  s.mergeQuestions([q('s1', 'c1')]);
  assert.equal(s.sessionQuestions('s1').length, 1);
  assert.equal(s.sessionQuestions('s1')[0].rpcId, 'rpc-9');
});

test('mergeQuestions：旧条目无 rpcId 而新条目带上时要采纳新值', () => {
  const s: HitlStore = new HitlStore();
  s.mergeQuestions([q('s1', 'c1')]);
  assert.equal(s.sessionQuestions('s1')[0].rpcId, '');
  s.mergeQuestions([q('s1', 'c1', 'rpc-late')]);
  assert.equal(s.sessionQuestions('s1')[0].rpcId, 'rpc-late');
});

test('mergeQuestions：跨会话合流互不干扰，sessionQuestions 按会话过滤', () => {
  const s: HitlStore = new HitlStore();
  s.mergeQuestions([q('s1', 'c1'), q('s2', 'c2')]);
  assert.equal(s.sessionQuestions('s1').length, 1);
  assert.equal(s.sessionQuestions('s2').length, 1);
  assert.equal(s.sessionQuestions('s1')[0].callId, 'c1');
  assert.equal(s.sessionQuestions(null).length, 0);
  assert.equal(s.sessionQuestions('').length, 0);
});

test('pendingQuestionSessionIds：去重列出有挂起提问的会话（抽屉角标用）', () => {
  const s: HitlStore = new HitlStore();
  assert.equal(s.pendingQuestionSessionIds().length, 0);
  s.mergeQuestions([q('s1', 'c1'), q('s1', 'c2'), q('s3', 'c3')]);
  const ids: string[] = s.pendingQuestionSessionIds();
  assert.equal(ids.length, 2);
  assert.ok(ids.indexOf('s1') >= 0);
  assert.ok(ids.indexOf('s3') >= 0);
});

test('pendingApprovalSessionIds：审批侧独立派生（同会话两表各算各的）', () => {
  const s: HitlStore = new HitlStore();
  assert.equal(s.pendingApprovalSessionIds().length, 0);
  const a1: PendingApproval = PendingApproval.fromJson('s2', m('{"approvalId":"a1","toolName":"write"}'));
  const a2: PendingApproval = PendingApproval.fromJson('s2', m('{"approvalId":"a2"}'));
  s.onApprovalRequested(a1);
  s.onApprovalRequested(a2);
  assert.equal(s.pendingApprovalSessionIds().length, 1);
  assert.equal(s.pendingApprovalSessionIds()[0], 's2');
  // 提问侧为空：两表互不影响。
  assert.equal(s.pendingQuestionSessionIds().length, 0);
});

test('结算摘卡后 pending*SessionIds 立即收缩', () => {
  const s: HitlStore = new HitlStore();
  s.mergeQuestions([q('s1', 'c1'), q('s2', 'c2')]);
  s.onQuestionResolved('c1');
  assert.equal(s.pendingQuestionSessionIds().length, 1);
  assert.equal(s.pendingQuestionSessionIds()[0], 's2');
  s.removeQuestion('c2');
  assert.equal(s.pendingQuestionSessionIds().length, 0);
});

test('onEvent：QUESTION/APPROVAL 四类消费且返 true，其它事件不消费', () => {
  const s: HitlStore = new HitlStore();
  assert.equal(s.onEvent(ev(GatewayEventType.SESSION_EVENT, 'chat.session/event')), false);
  assert.equal(s.onEvent(GatewayEvent.questionRequested(q('s1', 'c1'))), true);
  assert.equal(s.sessionQuestions('s1').length, 1);
  assert.equal(s.onEvent(GatewayEvent.questionResolved('s1', 'c1')), true);
  assert.equal(s.sessionQuestions('s1').length, 0);
  const a: PendingApproval = PendingApproval.fromJson('s2', m('{"approvalId":"a1"}'));
  assert.equal(s.onEvent(GatewayEvent.approvalRequested(a)), true);
  assert.equal(s.sessionApprovals('s2').length, 1);
  assert.equal(s.onEvent(GatewayEvent.approvalResolved('s2', 'a1')), true);
  assert.equal(s.sessionApprovals('s2').length, 0);
  // requested 但载荷缺失：不消费（不返 true）。
  const bare: GatewayEvent = new GatewayEvent();
  bare.type = GatewayEventType.QUESTION_REQUESTED;
  assert.equal(s.onEvent(bare), false);
});

/** 手动组一个事件（GatewayEvent 无通用构造函数，逐字段赋值）。 */
function ev(type: string, message: string): GatewayEvent {
  const e: GatewayEvent = new GatewayEvent();
  e.type = type;
  e.message = message;
  return e;
}
