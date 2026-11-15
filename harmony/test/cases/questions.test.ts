/**
 * Questions 层测试 —— 对照安卓 questions.dart 语义：宽容解析 + null 键省略。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import { JsonAccess } from '../../entry/src/main/ets/core/JsonAccess.ts';
import { UserQuestion, UserQuestionOption, PendingQuestion, PendingApproval,
  QuestionAnswerItem } from '../../entry/src/main/ets/core/Questions.ts';

function m(text: string): Record<string, Object> {
  const parsed: Object | null = JsonAccess.parse(text);
  assert.notEqual(parsed, null);
  return parsed as Record<string, Object>;
}

test('UserQuestion: 全字段解析', () => {
  const q: UserQuestion = UserQuestion.fromJson(m(
    '{"id":"q1","question":"用哪个？","header":"选择","detail":"二选一","multiSelect":true,'
    + '"options":[{"label":"A"},{"label":"B","description":"更快"}]}'));
  assert.equal(q.id, 'q1');
  assert.equal(q.question, '用哪个？');
  assert.equal(q.header, '选择');
  assert.equal(q.detail, '二选一');
  assert.equal(q.multiSelect, true);
  assert.equal(q.options.length, 2);
  assert.equal(q.options[1].description, '更快');
});

test('UserQuestion: 缺字段全默认，multiSelect 只认 true', () => {
  const q: UserQuestion = UserQuestion.fromJson(m('{"id":"q1"}'));
  assert.equal(q.question, '');
  assert.equal(q.multiSelect, false);
  assert.equal(q.options.length, 0);
  const q2: UserQuestion = UserQuestion.fromJson(m('{"multiSelect":"yes"}'));
  assert.equal(q2.multiSelect, false); // 类型不符回默认
  const q3: UserQuestion = UserQuestion.fromJson(m('{"multiSelect":1}'));
  assert.equal(q3.multiSelect, false);
});

test('UserQuestionOption.listFrom: 非 JSON 对象项过滤', () => {
  const q: UserQuestion = UserQuestion.fromJson(m(
    '{"options":[{"label":"A"},"str",42,{"label":"B"}]}'));
  assert.equal(q.options.length, 2);
  assert.equal(q.options[0].label, 'A');
  assert.equal(q.options[1].label, 'B');
});

test('PendingQuestion: sessionId 注入 + rpcId/state 默认', () => {
  const payload: Record<string, Object> = m('{"callId":"c1","rpcId":"r9","state":"continued",'
    + '"questions":[{"id":"q1","question":"Q"}]}');
  const pq: PendingQuestion = PendingQuestion.fromJson('s1', payload);
  assert.equal(pq.callId, 'c1');
  assert.equal(pq.sessionId, 's1');
  assert.equal(pq.rpcId, 'r9');
  assert.equal(pq.state, 'continued');
  assert.equal(pq.questions.length, 1);

  const pq2: PendingQuestion = PendingQuestion.fromJson('s1', m('{}'));
  assert.equal(pq2.callId, '');
  assert.equal(pq2.rpcId, '');
  assert.equal(pq2.state, 'open');
  assert.equal(pq2.questions.length, 0);
});

test('PendingApproval: toolName/risk 缺省口径', () => {
  const a: PendingApproval = PendingApproval.fromJson('s1', m('{"approvalId":"a1"}'));
  assert.equal(a.approvalId, 'a1');
  assert.equal(a.toolName, '工具');
  assert.equal(a.risk, 'standard');
  assert.equal(a.reason, '');

  const a2: PendingApproval = PendingApproval.fromJson('s1', m(
    '{"approvalId":"a2","toolName":"bash","risk":"full-access","reason":"写文件"}'));
  assert.equal(a2.toolName, 'bash');
  assert.equal(a2.risk, 'full-access');
  assert.equal(a2.reason, '写文件');
});

test('QuestionAnswerItem.toMap: custom 非空才上送', () => {
  const plain: QuestionAnswerItem = new QuestionAnswerItem('q1', ['A'], '');
  const plainMap: Record<string, Object> = plain.toMap();
  assert.equal(plainMap['id'], 'q1');
  assert.deepEqual(plainMap['selected'], ['A']);
  assert.equal('custom' in plainMap, false);

  const withCustom: QuestionAnswerItem = new QuestionAnswerItem('q1', ['A'], '备注');
  const customMap: Record<string, Object> = withCustom.toMap();
  assert.equal(customMap['custom'], '备注');
});

test('QuestionAnswerItem.toMap: JSON 往返', () => {
  const item: QuestionAnswerItem = new QuestionAnswerItem('q2', ['B', 'C'], '补充说明');
  const roundTrip: Object | null = JsonAccess.parse(JSON.stringify(item.toMap()));
  assert.notEqual(roundTrip, null);
  const map: Record<string, Object> = roundTrip as Record<string, Object>;
  assert.equal(map['id'], 'q2');
  assert.deepEqual(map['selected'], ['B', 'C']);
  assert.equal(map['custom'], '补充说明');
});
