/// HITL 交互状态 —— 对齐安卓 hitl_state.dart（从 chat_state.dart 拆出的挂起表）。
/// 挂起表是**全连接**的（含其它会话）：bridge 连接建立 + 每次 subscribe 都补推
/// replay，按 callId/approvalId 去重入表即可；UI 只渲染当前会话的条目。
/// 结算（answered/dismissed/resolved）时摘卡。动作（answer/cancel/decide）在
/// ChatStore（有 notify），本类只管挂起表状态。
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from './Questions';
import type { GatewayApi } from './GatewayApi';
import { GatewayEvent, GatewayEventType } from './GatewayEvents';

export class HitlStore {
  /** 全连接的挂起提问（含其它会话的），按 callId 键。 */
  readonly pendingQuestions: Map<string, PendingQuestion> = new Map<string, PendingQuestion>();

  /** 全连接的挂起审批，按 approvalId 键。 */
  readonly pendingApprovals: Map<string, PendingApproval> = new Map<string, PendingApproval>();

  /** [sessionId] 会话待答的提问（到达序）。 */
  sessionQuestions(sessionId: string | null): PendingQuestion[] {
    const out: PendingQuestion[] = [];
    if (sessionId === null) {
      return out;
    }
    this.pendingQuestions.forEach((q: PendingQuestion): void => {
      if (q.sessionId === sessionId) {
        out.push(q);
      }
    });
    return out;
  }

  /** [sessionId] 会话待决的审批。 */
  sessionApprovals(sessionId: string | null): PendingApproval[] {
    const out: PendingApproval[] = [];
    if (sessionId === null) {
      return out;
    }
    this.pendingApprovals.forEach((a: PendingApproval): void => {
      if (a.sessionId === sessionId) {
        out.push(a);
      }
    });
    return out;
  }

  // ---- 事件入口（ChatStore.onEvent 转发；返回 true 表示表有变化）----

  onQuestionRequested(question: PendingQuestion): boolean {
    this.pendingQuestions.set(question.callId, question);
    return true;
  }

  onQuestionResolved(callId: string): boolean {
    return this.pendingQuestions.delete(callId);
  }

  onApprovalRequested(approval: PendingApproval): boolean {
    this.pendingApprovals.set(approval.approvalId, approval);
    return true;
  }

  onApprovalResolved(approvalId: string): boolean {
    return this.pendingApprovals.delete(approvalId);
  }

  /** 提交成功后的本地摘卡（bridge 也会推 userQuestions/answered，双保险）。 */
  removeQuestion(callId: string): void {
    this.pendingQuestions.delete(callId);
  }

  /** 审批成功后的本地摘卡（bridge 会补推 approval-resolved）。 */
  removeApproval(approvalId: string): void {
    this.pendingApprovals.delete(approvalId);
  }

  /** 提交一套答案（question-answer 帧），成功即本地摘卡。 */
  answerQuestion(api: GatewayApi, question: PendingQuestion, answers: QuestionAnswerItem[]): Promise<void> {
    return api.answerQuestion(question.sessionId, question.callId, answers)
      .then((): void => {
        this.removeQuestion(question.callId);
      });
  }

  /** 放弃一条提问（question-cancel）。continued 态取消会失败，卡片保留。 */
  cancelQuestion(api: GatewayApi, question: PendingQuestion): Promise<void> {
    return api.cancelQuestion(question.sessionId, question.callId, question.rpcId)
      .then((): void => {
        this.removeQuestion(question.callId);
      });
  }

  /** 审批决定（allowed-once / rejected），成功即本地摘卡。 */
  decideApproval(api: GatewayApi, approval: PendingApproval, allow: boolean): Promise<void> {
    return api.decideApproval(approval.sessionId, approval.approvalId, allow)
      .then((): void => {
        this.removeApproval(approval.approvalId);
      });
  }

  /**
   * 事件分派入口：处理 QUESTION/APPROVAL 四类，其它事件不消费。
   * 返回 true = 挂起表变化（调用方 changed()）。
   */
  onEvent(event: GatewayEvent): boolean {
    if (event.type === GatewayEventType.QUESTION_REQUESTED) {
      if (event.question !== null) {
        return this.onQuestionRequested(event.question);
      }
      return false;
    }
    if (event.type === GatewayEventType.QUESTION_RESOLVED) {
      return this.onQuestionResolved(event.callId);
    }
    if (event.type === GatewayEventType.APPROVAL_REQUESTED) {
      if (event.approval !== null) {
        return this.onApprovalRequested(event.approval);
      }
      return false;
    }
    if (event.type === GatewayEventType.APPROVAL_RESOLVED) {
      return this.onApprovalResolved(event.approvalId);
    }
    return false;
  }
}
