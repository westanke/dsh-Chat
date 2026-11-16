/**
 * 工具调用呈现纯逻辑（下半：展开详情分派/询问状态机/展示档位 policy/alwaysOpen）
 * —— 官方 Web 会话页（dsh-client-ui-tool/lib/client.js AskQuestionRow 等）的
 * node 直测口径，与 app/ Flutter 端同构（Lead 逆向核实 2026-11-17）。
 *
 * 活动归类/词表/过程组标题/摘要键在 core/ToolPresent.ts（本文件为其 ≤500 行拆分）。
 * 不做（汇报口径）：ASK_CANCELLED/ASK_ABORTED 态、exit code badge、stopped 态。
 */

import { ChatMessage } from './HistoryPage';
import { ToolCallInfo } from './ToolCall';
import { JsonAccess, JsonMap } from './JsonAccess';
import { WorkStepsDetail } from './WorkSteps';
import { QuestionAnswerItem, UserQuestion } from './Questions';
import { AK_COMMANDS, AK_EDIT, AK_READ, AK_QUESTIONS, AK_WEB_FETCH, AK_WEB_SEARCH,
  AK_WRITE, activityKind, firstLineOf, isCallRunning } from './ToolPresent';

// ---- 展开详情分派 -------------------------------------------------------

export const DETAIL_DIFF_MAX_LINES: number = 9;
export const DETAIL_READ_WINDOW: number = 8;
export const DETAIL_INPUT_MAX_CHARS: number = 200;

/** 详情模式：edit/write→diff；commands→command；read→read；questions→ask；其余 io。 */
export function detailModeOf(call: ToolCallInfo): string {
  const kind: string = activityKind(call.name);
  if (kind === AK_EDIT || kind === AK_WRITE) {
    return 'diff';
  }
  if (kind === AK_COMMANDS) {
    return 'command';
  }
  if (kind === AK_READ) {
    return 'read';
  }
  if (kind === AK_QUESTIONS) {
    return 'ask';
  }
  return 'io';
}

/** read 详情行窗：结果按行切（保留空行，去尾部空行）。 */
export function readLinesOf(resultText: string | null): string[] {
  if (resultText === null) {
    return [];
  }
  const lines: string[] = resultText.split('\n');
  while (lines.length > 0 && lines[lines.length - 1].trim().length === 0) {
    lines.pop();
  }
  return lines;
}

/** io 详情输入：run_code 只显示 args.code 正文；其余 JSON 2 空格美化截 200 字。 */
export function ioInputOf(call: ToolCallInfo): string {
  const raw: string | null = call.rawArguments;
  if (raw === null || raw.trim().length === 0) {
    return '';
  }
  const record: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(raw.trim()));
  if (activityKind(call.name) === 'code') {
    if (record !== null) {
      const code: Object | null = JsonAccess.raw(record, 'code');
      if (typeof code === 'string') {
        return code;
      }
    }
    return raw;
  }
  if (record === null) {
    return firstLineOf(raw);
  }
  const pretty: string = JSON.stringify(record, null, 2);
  if (pretty.length > DETAIL_INPUT_MAX_CHARS) {
    return pretty.substring(0, DETAIL_INPUT_MAX_CHARS) + '…';
  }
  return pretty;
}

/** io 详情输出：结果为空时 webSearch/webFetch → 未找到结果，其余 → 无结果。 */
export function ioOutputOf(call: ToolCallInfo): string {
  if (call.resultText !== null && call.resultText.trim().length > 0) {
    return call.resultText;
  }
  const kind: string = activityKind(call.name);
  if (kind === AK_WEB_SEARCH || kind === AK_WEB_FETCH) {
    return '未找到结果';
  }
  return '无结果';
}

// ---- 询问（ask_user_question）状态机 ------------------------------------

export const ASK_WAITING: string = '等待中';
export const ASK_PENDING: string = '已继续；仍可回答';
export const ASK_CLOSED: string = '已关闭';
export const ASK_NOT_ANSWERED: string = '未回答';

/** 答案是否已答：selected 非空或 custom 非空。 */
export function isAnswered(answer: QuestionAnswerItem): boolean {
  return answer.selected.length > 0 || answer.custom.trim().length > 0;
}

/** ask 结果解析（官方键 id/selected/custom）；无 answers 数组 → null。 */
export function answerEntries(resultText: string | null): QuestionAnswerItem[] | null {
  if (resultText === null) {
    return null;
  }
  const record: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(resultText.trim()));
  if (record === null) {
    return null;
  }
  const rawArr: Object | null = JsonAccess.raw(record, 'answers');
  if (rawArr === null || !Array.isArray(rawArr)) {
    return null;
  }
  const items: Object[] = rawArr as Object[];
  const out: QuestionAnswerItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const entry: JsonMap | null = JsonAccess.asMap(items[i]);
    if (entry === null) {
      continue;
    }
    const id: string = JsonAccess.strOr(entry, 'id', '');
    const selected: string[] = JsonAccess.strArr(entry, 'selected');
    const custom: string = JsonAccess.strOr(entry, 'custom', '');
    out.push(new QuestionAnswerItem(id, selected, custom));
  }
  return out;
}

/**
 * ask 行 summary 状态映射：running → 等待中；pending===true 且 answerable →
 * 已继续；仍可回答；pending 且不可答 → 已关闭；answers 数组 → {n}/{total} 已回答；
 * 解析失败 → 原 summary 兜底。
 */
export function askSummaryOf(call: ToolCallInfo, answerable: boolean): string {
  if (isCallRunning(call)) {
    return ASK_WAITING;
  }
  const raw: string | null = call.resultText;
  if (raw === null || raw.trim().length === 0) {
    return call.summary ?? '';
  }
  const record: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(raw.trim()));
  if (record === null) {
    return call.summary ?? '';
  }
  const pending: boolean | null = JsonAccess.bool(record, 'pending');
  if (pending === true) {
    return answerable ? ASK_PENDING : ASK_CLOSED;
  }
  const answers: QuestionAnswerItem[] | null = answerEntries(raw);
  if (answers !== null) {
    let done: number = 0;
    for (let i = 0; i < answers.length; i++) {
      if (isAnswered(answers[i])) {
        done += 1;
      }
    }
    return done.toString() + '/' + answers.length.toString() + ' 已回答';
  }
  return call.summary ?? '';
}

/**
 * ask 工具参数解析（questions: id/question 必填，重复 id 或缺字段 → 整份 null）。
 * 复用 UserQuestion 宽容解析；工具参数键 multi_select 与协议键 multiSelect 都收。
 */
export function askQuestions(argsRaw: string | null): UserQuestion[] | null {
  if (argsRaw === null || argsRaw.trim().length === 0) {
    return null;
  }
  const record: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(argsRaw.trim()));
  if (record === null) {
    return null;
  }
  const rawArr: Object | null = JsonAccess.raw(record, 'questions');
  if (rawArr === null || !Array.isArray(rawArr)) {
    return null;
  }
  const items: Object[] = rawArr as Object[];
  const out: UserQuestion[] = [];
  const seen: Map<string, boolean> = new Map<string, boolean>();
  for (let i = 0; i < items.length; i++) {
    const entry: JsonMap | null = JsonAccess.asMap(items[i]);
    if (entry === null) {
      return null;
    }
    const id: string = JsonAccess.strOr(entry, 'id', '');
    const question: string = JsonAccess.strOr(entry, 'question', '');
    if (id.length === 0 || question.length === 0) {
      return null;
    }
    if (seen.get(id) === true) {
      return null;
    }
    seen.set(id, true);
    const q: UserQuestion = UserQuestion.fromJson(entry);
    if (!q.multiSelect && JsonAccess.boolOr(entry, 'multi_select', false)) {
      q.multiSelect = true;
    }
    out.push(q);
  }
  return out.length === 0 ? null : out;
}

// ---- 展示档位 → 官方 policy ---------------------------------------------

export const STEP_GROUPING_COLLAPSED: string = 'collapsed';
export const STEP_GROUPING_HISTORY: string = 'history';
export const STEP_GROUPING_NONE: string = 'none';

/** 官方 policy 表四元组（foldCompletedTurns/stepGrouping/liveProcessDetail/preview）。 */
export class WorkStepsPolicy {
  foldCompletedTurns: boolean = true;
  stepGrouping: string = STEP_GROUPING_COLLAPSED;
  liveProcessDetail: boolean = true;
  settledReasoningPreview: boolean = true;
}

export function policyOf(detail: WorkStepsDetail): WorkStepsPolicy {
  const p: WorkStepsPolicy = new WorkStepsPolicy();
  if (detail === 'concise') {
    p.liveProcessDetail = false;
    p.settledReasoningPreview = false;
  } else if (detail === 'detailed') {
    p.stepGrouping = STEP_GROUPING_HISTORY;
  } else if (detail === 'verbose') {
    p.foldCompletedTurns = false;
    p.stepGrouping = STEP_GROUPING_NONE;
    p.liveProcessDetail = false;
  }
  return p;
}

// ---- alwaysOpen（forceExpanded） ----------------------------------------

/**
 * 组恒展开判定（官方 alwaysOpen/forceExpanded）：组后同轮有 user 消息（steer/追问
 * 且轮内无最终回复）→ 恒展开；走到列表尾 → 仅当轮运行中恒展开；遇到最终 assistant
 * 正文或 error 卡 → 轮已结束，不恒展开。
 */
export function isGroupForceOpen(messages: ChatMessage[], groupIndex: number,
  isTurnRunning: boolean): boolean {
  for (let i = groupIndex + 1; i < messages.length; i++) {
    const m: ChatMessage = messages[i];
    if (m.isUser) {
      return true;
    }
    if (m.role === 'assistant' && !m.streaming && m.text.length > 0) {
      return false;
    }
    if (m.isError) {
      return false;
    }
  }
  return isTurnRunning;
}
