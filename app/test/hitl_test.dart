// HITL 问答/审批：模型收敛 + 提问卡交互（真机反馈补充：DSH 向用户提问）。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/hitl_state.dart';
import 'package:dshchat/ui/question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PendingQuestion _q({bool multiSelect = false, List<UserQuestionOption>? options}) =>
    PendingQuestion(
      callId: 'call-1',
      sessionId: 's1',
      rpcId: 'rpc-1',
      questions: [
        UserQuestion(
          id: 'q1',
          question: '用哪个方案？',
          header: '方案确认',
          detail: '二选一',
          multiSelect: multiSelect,
          options: options ??
              const [
                UserQuestionOption(label: '方案 A', description: '快'),
                UserQuestionOption(label: '方案 B'),
              ],
        ),
      ],
    );

void main() {
  group('PendingQuestion / PendingApproval 收敛', () {
    test('parses bridge userQuestions/requested payload', () {
      final q = PendingQuestion.from('s1', {
        'callId': 'call-1',
        'rpcId': 'rpc-1',
        'questions': [
          {
            'id': 'q1',
            'question': '用哪个方案？',
            'header': '方案确认',
            'multiSelect': true,
            'options': [
              {'label': '方案 A', 'description': '快'},
              {'label': '方案 B'},
            ],
          },
        ],
      });
      expect(q.callId, 'call-1');
      expect(q.rpcId, 'rpc-1');
      expect(q.state, 'open');
      expect(q.questions.single.multiSelect, isTrue);
      expect(q.questions.single.options.first.label, '方案 A');
      expect(q.questions.single.options.first.description, '快');
    });

    test('parses approval.requested payload with defaults', () {
      final a = PendingApproval.from({
        'sessionId': 's1',
        'approvalId': 'ap-1',
        'toolName': 'bash',
      });
      expect(a.approvalId, 'ap-1');
      expect(a.toolName, 'bash');
      expect(a.risk, 'standard');
      expect(a.reason, isNull);
    });

    test('QuestionAnswerItem.toJson omits empty custom', () {
      expect(
        const QuestionAnswerItem(id: 'q1', selected: ['方案 A']).toJson(),
        {'id': 'q1', 'selected': ['方案 A']},
      );
      expect(
        const QuestionAnswerItem(id: 'q1', custom: '都行').toJson()['custom'],
        '都行',
      );
    });
  });

  group('HitlState 挂起表', () {
    test('requested/dedup/settle lifecycle', () {
      final hitl = HitlState();
      hitl.onQuestionRequested(_q());
      hitl.onQuestionRequested(_q()); // replay 补推同 callId：去重
      expect(hitl.pendingQuestions.length, 1);
      expect(hitl.sessionQuestions('s1').length, 1);
      expect(hitl.sessionQuestions('other'), isEmpty);
      hitl.onQuestionResolved('call-1');
      expect(hitl.pendingQuestions, isEmpty);
    });

    test('approval lifecycle', () {
      final hitl = HitlState();
      hitl.onApprovalRequested(
        PendingApproval.from({
          'sessionId': 's1',
          'approvalId': 'ap-1',
          'toolName': 'bash',
        }),
      );
      expect(hitl.sessionApprovals('s1').length, 1);
      hitl.onApprovalResolved('ap-1');
      expect(hitl.pendingApprovals, isEmpty);
    });
  });

  group('HitlPanel 交互', () {
    testWidgets('question card: pick option + submit', (tester) async {
      var submitted = false;
      final hitl = HitlState()..onQuestionRequested(_q());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlPanel(
              state: hitl,
              colors: DsColors(false),
              onAnswer: (q, answers) {
                submitted = true;
                expect(answers.single.id, 'q1');
                expect(answers.single.selected, ['方案 A']);
                expect(answers.single.custom, isNull);
              },
              onDecide: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('方案确认'), findsOneWidget);
      expect(find.text('用哪个方案？'), findsOneWidget);
      await tester.tap(find.text('方案 A'));
      await tester.pump();
      await tester.tap(find.text('提交'));
      await tester.pump();
      expect(submitted, isTrue);
    });

    testWidgets('approval card: allow once / reject', (tester) async {
      final decisions = <bool>[];
      final hitl = HitlState()
        ..onApprovalRequested(
          PendingApproval.from({
            'sessionId': 's1',
            'approvalId': 'ap-1',
            'toolName': 'bash',
            'reason': '执行 rm -rf 前确认',
          }),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlPanel(
              state: hitl,
              colors: DsColors(false),
              onAnswer: (_, _) {},
              onDecide: (_, allow) => decisions.add(allow),
            ),
          ),
        ),
      );
      expect(find.text('DSH 请求使用 bash'), findsOneWidget);
      expect(find.text('执行 rm -rf 前确认'), findsOneWidget);
      await tester.tap(find.text('允许一次'));
      await tester.pump();
      expect(decisions, [true]);
    });

    testWidgets('single-select clears previous pick', (tester) async {
      List<QuestionAnswerItem>? captured;
      final hitl = HitlState()..onQuestionRequested(_q());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlPanel(
              state: hitl,
              colors: DsColors(false),
              onAnswer: (_, answers) => captured = answers,
              onDecide: (_, _) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('方案 A'));
      await tester.pump();
      await tester.tap(find.text('方案 B'));
      await tester.pump();
      await tester.tap(find.text('提交'));
      await tester.pump();
      expect(captured?.single.selected, ['方案 B']);
    });
  });
}
