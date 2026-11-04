/// HITL 交互模型：DSH 向用户提问（userQuestions）与工具审批（approval）。
///
/// 协议事实来源（dsh-remote-bridge）：
/// - WS 推送 `chat.userQuestions/requested|answered|dismissed`
///   （data={sessionId, callId, rpcId, questions:[...]}，replay 带 replayed:true）；
/// - WS 推送 `chat.approval.requested|resolved`
///   （data={sessionId, approvalId, toolName, risk, reason?}，chat-adapter.ts:1477-1492）；
/// - questions 形状 openapi.yaml:1180-1216：每题
///   {id, question, header?, detail?, multiSelect?, options?:[{label, description?}]}。
/// - 答题帧 `question-answer` / 取消 `question-cancel` / 审批 `approval-response`
///   （ws-protocol.ts:267-281，应答 kind=question-response / approval-response 可 await）。
/// 挂起超时 10 分钟（chat.ts:218,227）；同一 callId/approvalId 客户端按 id 去重。
library;

/// 一道待回答的题（bridge 原样透传，多余字段丢弃）。
class UserQuestion {
  const UserQuestion({
    required this.id,
    required this.question,
    this.header,
    this.detail,
    this.multiSelect = false,
    this.options = const [],
  });

  final String id;
  final String question;
  final String? header;
  final String? detail;
  final bool multiSelect;
  final List<UserQuestionOption> options;

  static UserQuestion from(Map<String, dynamic> j) => UserQuestion(
    id: (j['id'] ?? '') as String,
    question: (j['question'] ?? '') as String,
    header: j['header'] is String ? j['header'] as String : null,
    detail: j['detail'] is String ? j['detail'] as String : null,
    multiSelect: j['multiSelect'] == true,
    options: UserQuestionOption.listFrom(j['options']),
  );
}

class UserQuestionOption {
  const UserQuestionOption({required this.label, this.description});

  final String label;
  final String? description;

  static List<UserQuestionOption> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          UserQuestionOption(
            label: ((item['label'] ?? '') as String),
            description: item['description'] is String
                ? item['description'] as String
                : null,
          ),
    ];
  }
}

/// 一次提问会话（bridge 一次 ask = 1..n 道题，统一 callId）。
/// state：WS 推送没有 state 字段（视为 open）；REST 兜底可能带 'continued'。
class PendingQuestion {
  const PendingQuestion({
    required this.callId,
    required this.sessionId,
    required this.questions,
    this.rpcId,
    this.state = 'open',
  });

  final String callId;
  final String sessionId;
  final String? rpcId; // bridge 挂起表键（question-cancel 优先用它）
  final String state; // open | continued
  final List<UserQuestion> questions;

  static PendingQuestion from(String sessionId, Map<String, dynamic> j) =>
      PendingQuestion(
        callId: (j['callId'] ?? '') as String,
        sessionId: sessionId,
        rpcId: j['rpcId'] is String ? j['rpcId'] as String : null,
        state: j['state'] is String ? j['state'] as String : 'open',
        questions: [
          for (final q in (j['questions'] as List? ?? const []))
            if (q is Map) UserQuestion.from(Map<String, dynamic>.from(q)),
        ],
      );
}

/// 一次待审批的工具调用（chat-adapter.ts:1477-1492 专门分支）。
class PendingApproval {
  const PendingApproval({
    required this.approvalId,
    required this.sessionId,
    required this.toolName,
    this.risk = 'standard',
    this.reason,
  });

  final String approvalId;
  final String sessionId;
  final String toolName;
  final String risk; // standard | full-access
  final String? reason;

  static PendingApproval from(Map<String, dynamic> j) => PendingApproval(
    approvalId: (j['approvalId'] ?? '') as String,
    sessionId: (j['sessionId'] ?? '') as String,
    toolName: (j['toolName'] ?? '工具') as String,
    risk: j['risk'] is String ? j['risk'] as String : 'standard',
    reason: j['reason'] is String ? j['reason'] as String : null,
  );
}

/// 答题载荷（question-answer.answers 项；selected 是选项 label 数组）。
class QuestionAnswerItem {
  const QuestionAnswerItem({required this.id, this.selected = const [], this.custom});

  final String id;
  final List<String> selected;
  final String? custom;

  Map<String, dynamic> toJson() => {
    'id': id,
    'selected': selected,
    'custom': ?custom,
  };
}
