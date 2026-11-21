// 「直接回答提问」（对照 dsh-go ChatState.singleQuestion / ChatScreen）：
// 单题提问挂着且无图片时，输入条文字作为该题的 custom 答案提交，
// 不再发成新一轮用户消息。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingGateway extends GatewayClient {
  _RecordingGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<(String, Map<String, dynamic>)> requests = [];

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) async {
    requests.add((type, payload));
    if (type == 'question-answer') return <String, dynamic>{'accepted': true};
    throw RequestException('NOT_CONNECTED', 'fake gateway');
  }
}

ChatState _state(_RecordingGateway gw, {String? sid = 'sid-1'}) {
  final state = ChatState(gw);
  state.sessionId = sid;
  return state;
}

PendingQuestion _question({int count = 1}) => PendingQuestion(
  callId: 'call-1',
  sessionId: 'sid-1',
  questions: [
    for (var i = 0; i < count; i++)
      UserQuestion(id: 'q$i', question: '选哪个方案？'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('单题提问挂着时，发送的文字作为自定义答案提交', () async {
    final gw = _RecordingGateway();
    final state = _state(gw);
    state.hitlState.onQuestionRequested(_question());

    await state.send('用第二个方案');

    final answer = gw.requests.singleWhere((r) => r.$1 == 'question-answer');
    expect(answer.$2['callId'], 'call-1');
    final answers = answer.$2['answers'] as List;
    final first = answers.single as Map;
    expect(first['id'], 'q0');
    expect(first['custom'], '用第二个方案');
    expect(first['selected'], isEmpty);
    // 不当成新一轮：不产生用户气泡、不进流式态。
    expect(state.messages, isEmpty);
    expect(state.streaming, isFalse);
    // 本地摘卡（bridge 也会推 answered，双保险）。
    expect(state.hitlState.pendingQuestions, isEmpty);
  });

  test('多题提问不拦截（仍按普通消息发送）', () async {
    final gw = _RecordingGateway();
    final state = _state(gw);
    state.hitlState.onQuestionRequested(_question(count: 2));

    expect(state.singleOpenQuestion, isNull);
    await state.send('普通消息');

    expect(
      gw.requests.any((r) => r.$1 == 'question-answer'),
      isFalse,
    );
    expect(state.messages.single.role, 'user');
    expect(state.messages.single.text, '普通消息');
  });

  test('有待决审批时不抢答', () async {
    final gw = _RecordingGateway();
    final state = _state(gw);
    state.hitlState.onQuestionRequested(_question());
    state.hitlState.onApprovalRequested(
      const PendingApproval(
        sessionId: 'sid-1',
        approvalId: 'ap-1',
        toolName: 'bash',
        risk: 'high',
      ),
    );

    expect(state.singleOpenQuestion, isNull);
  });
}
