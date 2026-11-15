/// HITL 动作（问答 / 审批；从 chat_state.dart 拆出，宪法 §7 单文件 ≤500 行）：
/// 提交回答 / 跳过提问 / 审批决定，失败统一落 state.lastError 并 notifyUi。
///
/// 只读写 ChatState 的 public 成员（gateway getter / hitl / lastError /
/// notifyUi），chat_state.dart 里保留同名薄转发，UI 调用点不动。类型
/// PendingQuestion/PendingApproval/QuestionAnswerItem 经 chat_state.dart 的
/// export（hitl_state.dart）与 models.dart 链进来，无需直接 import。
library;

import '../bridge/gateway.dart'; // RequestException
import 'chat_state.dart';

/// 提交一套答案（question-answer 帧）。成功即本地摘卡（hitl 内部处理）。
Future<void> submitChatAnswer(
  ChatState state,
  PendingQuestion question,
  List<QuestionAnswerItem> answers,
) async {
  state.lastError = null;
  try {
    await state.hitl.answerQuestion(state.gateway, question, answers);
  } on RequestException catch (e) {
    state.lastError = '提交回答失败：${e.message}';
  }
  state.notifyUi();
}

/// 放弃一条提问（question-cancel）；continued 态取消不了会提示。
Future<void> skipChatQuestion(ChatState state, PendingQuestion question) async {
  state.lastError = null;
  try {
    await state.hitl.cancelQuestion(state.gateway, question);
  } on RequestException catch (e) {
    state.lastError = '无法跳过该提问：${e.message}';
  }
  state.notifyUi();
}

/// 审批决定（allowed-once / rejected）。成功即本地摘卡。
Future<void> decideChatApproval(
  ChatState state,
  PendingApproval approval,
  bool allow,
) async {
  state.lastError = null;
  try {
    await state.hitl.decideApproval(state.gateway, approval, allow);
  } on RequestException catch (e) {
    state.lastError = '审批操作失败：${e.message}';
  }
  state.notifyUi();
}
