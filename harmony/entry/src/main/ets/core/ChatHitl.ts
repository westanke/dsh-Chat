/**
 * HITL 派生动作 —— 从 ChatStore 拆出的挂起提问/审批动作（宪法 §7 单文件 ≤500 行）。
 *
 * 数据表本身在 core/HitlStore.ts（纯数据 + 合并/消费）；这里放需要
 * 「表 + api + changed() 回调」三样一起用的动作函数，参数统一收 ChatStore
 * （循环引用走 import type，字段全部 public —— 与 core/ChatActions.ts 同范式）。
 *
 * 为什么需要 REST 探测：bridge 的 sessions 列表只对**挂起审批**下发
 * pendingInteraction:'approval'，挂起提问不发（协议缺口），且 hello 后不补推
 * 其它会话的 HITL 帧（实测 0 条）。所以「非当前会话有没有任务」只能 REST 逐会话查。
 */

import { PendingApproval, PendingQuestion, QuestionAnswerItem } from './Questions';
import type { ChatStore } from './ChatStore';

/**
 * 从 REST 刷新「其它会话」的挂起标记（抽屉打开时调）。
 * 结果写进 store.pendingMarks（sessionId → 'question' | 'approval'）。
 * 逐会话两跳：先查提问数，为 0 再查审批数；任何一个请求失败都静默跳过该会话。
 */
export function refreshPendingMarksIn(store: ChatStore): Promise<void> {
  const list = store.sessions;
  if (list.length === 0) {
    return Promise.resolve();
  }
  const jobs: Promise<void>[] = [];
  for (const s of list) {
    jobs.push(store.api.countPendingQuestions(s.id)
      .then((n: number): Promise<void> | void => {
        if (n > 0) {
          store.pendingMarks.set(s.id, 'question');
          return;
        }
        store.pendingMarks.delete(s.id);
        return store.api.countPendingApprovals(s.id).then((m: number): void => {
          if (m > 0) {
            store.pendingMarks.set(s.id, 'approval');
          } else {
            store.pendingMarks.delete(s.id);
          }
        }).catch((): void => {});
      })
      .catch((): void => {}));
  }
  return Promise.all(jobs).then((): void => {
    store.changed();
  });
}

/**
 * 会话抽屉用的「待处理标记」：全连接挂起表里属于该会话的条目。
 * 返回 'question'（待回答）优先于 'approval'（待审批）——提问是阻塞用户输入的那类。
 */
export function pendingMarkOfIn(store: ChatStore, sessionId: string): string {
  if (sessionId === '') {
    return '';
  }
  // 实时推送优先（本连接亲眼见过的事件最可信）。
  if (store.hitl.sessionQuestions(sessionId).length > 0) {
    return 'question';
  }
  if (store.hitl.sessionApprovals(sessionId).length > 0) {
    return 'approval';
  }
  // 退回 REST 探测缓存（非当前会话的挂起项不推送，只能查）。
  return store.pendingMarks.get(sessionId) ?? '';
}

/** 提交一套答案（question-answer 帧），成功即本地摘卡（HitlStore 持 api 动作）。 */
export function answerQuestionIn(store: ChatStore, question: PendingQuestion,
                                 answers: QuestionAnswerItem[]): Promise<void> {
  return store.hitl.answerQuestion(store.api, question, answers).then((): void => {
    store.changed();
  });
}

/** 放弃一条提问（question-cancel）。continued 态取消会失败，卡片保留。 */
export function cancelQuestionIn(store: ChatStore, question: PendingQuestion): Promise<void> {
  return store.hitl.cancelQuestion(store.api, question).then((): void => {
    store.changed();
  });
}

/** 审批决定（allowed-once / rejected），成功即本地摘卡。 */
export function decideApprovalIn(store: ChatStore, approval: PendingApproval,
                                 allow: boolean): Promise<void> {
  return store.hitl.decideApproval(store.api, approval, allow).then((): void => {
    store.changed();
  });
}
