/**
 * 提问/审批挂起项与应答帧 —— 对照 app/lib/bridge/questions.dart（132 行）。
 *
 * 协议形状（bridge 仓 openapi.yaml:1180-1216）：
 * questions: {id, question, header?, detail?, multiSelect?, options?: [{label, description?}]}
 * 挂起超时 10 分钟（服务端）；答题帧 question-answer、取消 question-cancel、
 * 审批应答 approval-response（应答 kind=question-response/approval-response）。
 *
 * 宽容口径：fromJson 缺键/类型不符一律默认值，绝不抛异常（姊妹仓同款规矩）。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';

/** 单个选项。description 可空（'' 表示未携带）。 */
export class UserQuestionOption {
  label: string = '';
  description: string = '';

  static fromJson(j: JsonMap | null): UserQuestionOption {
    const o: UserQuestionOption = new UserQuestionOption();
    o.label = JsonAccess.strOr(j, 'label', '');
    o.description = JsonAccess.strOr(j, 'description', '');
    return o;
  }

  static listFrom(map: JsonMap | null, key: string): UserQuestionOption[] {
    const out: UserQuestionOption[] = [];
    const arr: Object[] = JsonAccess.arr(map, key);
    for (let i = 0; i < arr.length; i++) {
      const item: JsonMap | null = JsonAccess.asMap(arr[i]);
      if (item !== null) {
        out.push(UserQuestionOption.fromJson(item));
      }
    }
    return out;
  }
}

/** 一道待回答的问题。 */
export class UserQuestion {
  id: string = '';
  question: string = '';
  header: string = '';
  detail: string = '';
  multiSelect: boolean = false;
  options: UserQuestionOption[] = [];

  static fromJson(j: JsonMap | null): UserQuestion {
    const q: UserQuestion = new UserQuestion();
    q.id = JsonAccess.strOr(j, 'id', '');
    q.question = JsonAccess.strOr(j, 'question', '');
    q.header = JsonAccess.strOr(j, 'header', '');
    q.detail = JsonAccess.strOr(j, 'detail', '');
    q.multiSelect = JsonAccess.boolOr(j, 'multiSelect', false);
    q.options = UserQuestionOption.listFrom(j, 'options');
    return q;
  }

  static listFrom(map: JsonMap | null, key: string): UserQuestion[] {
    const out: UserQuestion[] = [];
    const arr: Object[] = JsonAccess.arr(map, key);
    for (let i = 0; i < arr.length; i++) {
      const item: JsonMap | null = JsonAccess.asMap(arr[i]);
      if (item !== null) {
        out.push(UserQuestion.fromJson(item));
      }
    }
    return out;
  }
}

/** 一组挂起中的提问（userQuestions/requested 事件的 payload）。 */
export class PendingQuestion {
  callId: string = '';
  sessionId: string = '';
  questions: UserQuestion[] = [];
  /** question-cancel 优先用它（服务端携带时才有）。 */
  rpcId: string = '';
  /** 'open' | 'continued'。 */
  state: string = 'open';

  static fromJson(sessionId: string, payload: JsonMap | null): PendingQuestion {
    const q: PendingQuestion = new PendingQuestion();
    q.callId = JsonAccess.strOr(payload, 'callId', '');
    q.sessionId = sessionId;
    q.questions = UserQuestion.listFrom(payload, 'questions');
    q.rpcId = JsonAccess.strOr(payload, 'rpcId', '');
    q.state = JsonAccess.strOr(payload, 'state', 'open');
    return q;
  }
}

/** 一次工具审批请求（approval.requested 事件的 payload）。 */
export class PendingApproval {
  approvalId: string = '';
  sessionId: string = '';
  /** 默认 '工具'（Android 口径 toolName ?? '工具'）。 */
  toolName: string = '工具';
  /** 'standard' | 'full-access'。 */
  risk: string = 'standard';
  reason: string = '';

  static fromJson(sessionId: string, payload: JsonMap | null): PendingApproval {
    const a: PendingApproval = new PendingApproval();
    a.approvalId = JsonAccess.strOr(payload, 'approvalId', '');
    a.sessionId = sessionId;
    a.toolName = JsonAccess.strOr(payload, 'toolName', '工具');
    a.risk = JsonAccess.strOr(payload, 'risk', 'standard');
    a.reason = JsonAccess.strOr(payload, 'reason', '');
    return a;
  }
}

/** 单题应答（question-answer 帧的 answers 数组元素）。 */
export class QuestionAnswerItem {
  id: string = '';
  selected: string[] = [];
  /** 自定义补充；非空才上送（Android 口径 null 键省略）。 */
  custom: string = '';

  constructor(id: string, selected: string[], custom: string) {
    this.id = id;
    this.selected = selected;
    this.custom = custom;
  }

  toMap(): JsonMap {
    const b: WireBuilder = new WireBuilder();
    b.put('id', this.id);
    const arr: Object[] = [];
    for (let i = 0; i < this.selected.length; i++) {
      arr.push(this.selected[i]);
    }
    b.put('selected', arr);
    b.putNonBlank('custom', this.custom);
    return b.buildMap();
  }
}
