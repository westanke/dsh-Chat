/// HITL 交互状态：DSH 向用户提问（userQuestions）与工具审批的挂起表与动作。
/// 从 chat_state.dart 拆出（宪法 §7 单文件 ≤500 行）。
///
/// 挂起表是**全连接**的（含其它会话）：bridge 连接建立 + 每次 subscribe 都
/// 补推 replay（replayed:true），按 callId/approvalId 去重入表即可；UI 只
/// 渲染当前会话的条目。结算（answered/dismissed/resolved）时摘卡。
library;

import 'package:flutter/foundation.dart';

import '../bridge/gateway.dart';

class HitlState extends ChangeNotifier {
  /// 全连接的挂起提问（含其它会话的），按 callId 键。
  final Map<String, PendingQuestion> pendingQuestions = {};

  /// 全连接的挂起审批，按 approvalId 键。
  final Map<String, PendingApproval> pendingApprovals = {};

  /// 有挂起提问的会话 id 集（抽屉「待回答」角标用）。全连接视角，与电脑端
  /// 会话列表的 status.compact.answer 同口径。
  Set<String> get pendingQuestionSessionIds =>
      pendingQuestions.values.map((q) => q.sessionId).toSet();

  /// 有挂起审批的会话 id 集（抽屉「待审批」角标用）。
  Set<String> get pendingApprovalSessionIds =>
      pendingApprovals.values.map((a) => a.sessionId).toSet();

  /// REST 兜底合流（GET /chat/sessions/{id}/questions，打开会话时拉一次）：
  /// WS replay 只补本桥前台挂起表，内核 continued（限时提问）只有 REST
  /// 看得到。按 callId upsert；已有条目带 rpcId 而新条目没有时保留旧 rpcId
  /// （WS 推送的条目比 REST 镜像多 cancel 用的关联键）。
  void mergeQuestions(List<PendingQuestion> incoming) {
    var changed = false;
    for (final q in incoming) {
      if (q.callId.isEmpty) continue;
      final old = pendingQuestions[q.callId];
      pendingQuestions[q.callId] =
          (old != null && old.rpcId != null && q.rpcId == null)
          ? PendingQuestion(
              callId: q.callId,
              sessionId: q.sessionId,
              questions: q.questions,
              rpcId: old.rpcId,
              state: q.state,
            )
          : q;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// [sessionId] 会话待答的提问（到达序）。
  List<PendingQuestion> sessionQuestions(String? sessionId) => sessionId == null
      ? const []
      : pendingQuestions.values
            .where((q) => q.sessionId == sessionId)
            .toList();

  /// [sessionId] 会话待决的审批。
  List<PendingApproval> sessionApprovals(String? sessionId) => sessionId == null
      ? const []
      : pendingApprovals.values
            .where((a) => a.sessionId == sessionId)
            .toList();

  // ---- 事件入口（chat_state._onEvent 转发）----

  void onQuestionRequested(PendingQuestion question) {
    pendingQuestions[question.callId] = question;
    notifyListeners();
  }

  void onQuestionResolved(String callId) {
    if (pendingQuestions.remove(callId) != null) notifyListeners();
  }

  void onApprovalRequested(PendingApproval approval) {
    pendingApprovals[approval.approvalId] = approval;
    notifyListeners();
  }

  void onApprovalResolved(String approvalId) {
    if (pendingApprovals.remove(approvalId) != null) notifyListeners();
  }

  // ---- 动作（错误通过返回的 RequestException 上抛，由调用方展示）----

  /// 提交一套答案（question-answer 帧）。成功即本地摘卡（bridge 也会推
  /// userQuestions/answered，双保险）。
  Future<void> answerQuestion(
    GatewayClient gateway,
    PendingQuestion question,
    List<QuestionAnswerItem> answers,
  ) async {
    await gateway.answerQuestion(
      sessionId: question.sessionId,
      callId: question.callId,
      answers: answers,
    );
    pendingQuestions.remove(question.callId);
    notifyListeners();
  }

  /// 放弃一条提问（question-cancel）：只对本桥接管的前台提问有效；
  /// continued 态取消会失败，卡片保留。
  Future<void> cancelQuestion(
    GatewayClient gateway,
    PendingQuestion question,
  ) async {
    await gateway.cancelQuestion(
      sessionId: question.sessionId,
      callId: question.callId,
      rpcId: question.rpcId,
    );
    pendingQuestions.remove(question.callId);
    notifyListeners();
  }

  /// 审批决定（allowed-once / rejected）。成功即本地摘卡（bridge 会补推
  /// approval-resolved）。
  Future<void> decideApproval(
    GatewayClient gateway,
    PendingApproval approval,
    bool allow,
  ) async {
    await gateway.decideApproval(
      sessionId: approval.sessionId,
      approvalId: approval.approvalId,
      allow: allow,
    );
    pendingApprovals.remove(approval.approvalId);
    notifyListeners();
  }
}
