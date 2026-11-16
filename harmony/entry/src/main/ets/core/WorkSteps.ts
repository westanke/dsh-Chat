/**
 * 工作步骤展示偏好与会话可见性 —— 官方「通用设置」四项的会话页纯逻辑。
 *
 * 偏好键（PrefsStore，值一律存官方 token 字符串）：
 * - dsh.workStepsDetail: concise|standard|detailed|verbose（默认 detailed）
 * - dsh.collapseTiming:  completion|next-input（默认 completion）
 * - dsh.foldedReplies:   all|final（默认 all）
 * - dsh.codeWorkView:    '1'|'0'（默认 '0'；纯开关，解析放 SettingsGeneralSection）
 *
 * 解析口径：未知值/空值/类型不符一律回退默认（与 Models.ts 宽容解析同族）；
 * 值的生效路径：UI 层写 AppStorage + PrefsStore，ChatView @Watch 把字符串
 * 解析后抄进 ChatStore（applyWorkStepsPrefsIn），自动收起逻辑只读 store 镜像。
 *
 * 可见性（visibleMessagesOf）：foldedReplies='final' 且轮已完成时，每轮只保留
 * 最后一条「text 非空且不带工具调用」的 assistant 正文，其余 assistant 正文隐藏；
 * files/error/command 卡始终可见；process 组不过滤（展开状态由 UI 层收口在
 * ChatStore.expandedGroups）；运行中轮全部可见；轮内无合格 assistant 消息则整轮不隐藏。
 */

import { ChatMessage } from './HistoryPage';

export type WorkStepsDetail = 'concise' | 'standard' | 'detailed' | 'verbose';
export type CollapseTiming = 'completion' | 'next-input';
export type FoldedReplies = 'all' | 'final';

export const WORK_STEPS_DETAIL_DEFAULT: WorkStepsDetail = 'detailed';
export const COLLAPSE_TIMING_DEFAULT: CollapseTiming = 'completion';
export const FOLDED_REPLIES_DEFAULT: FoldedReplies = 'all';

/** PrefsStore 键（值存官方 token 字符串；AppStorage 键同名，SettingsGeneralSection 写）。 */
export const PREF_WORK_STEPS_DETAIL: string = 'dsh.workStepsDetail';
export const PREF_COLLAPSE_TIMING: string = 'dsh.collapseTiming';
export const PREF_FOLDED_REPLIES: string = 'dsh.foldedReplies';
export const PREF_CODE_WORK_VIEW: string = 'dsh.codeWorkView';

/** 工作步骤展示档位解析：未知回退 detailed。 */
export function parseWorkStepsDetail(raw: string | null): WorkStepsDetail {
  if (raw === 'concise' || raw === 'standard' || raw === 'detailed' || raw === 'verbose') {
    return raw;
  }
  return WORK_STEPS_DETAIL_DEFAULT;
}

/** 收起时机解析：未知回退 completion（回答结束后）。 */
export function parseCollapseTiming(raw: string | null): CollapseTiming {
  if (raw === 'completion' || raw === 'next-input') {
    return raw;
  }
  return COLLAPSE_TIMING_DEFAULT;
}

/** 收起后显示的回复解析：未知回退 all（全部回复）。 */
export function parseFoldedReplies(raw: string | null): FoldedReplies {
  if (raw === 'all' || raw === 'final') {
    return raw;
  }
  return FOLDED_REPLIES_DEFAULT;
}

/**
 * 按轮分组：每条 user 消息起，至下一条 user 前。开头无 user 的历史边界
 * 消息（理论上不该出现，翻页截断兜底）算第 0 轮。
 */
export function turnsOf(messages: ChatMessage[]): ChatMessage[][] {
  const turns: ChatMessage[][] = [];
  let current: ChatMessage[] | null = null;
  for (let i = 0; i < messages.length; i++) {
    const m: ChatMessage = messages[i];
    if (m.isUser) {
      current = [];
      turns.push(current);
      current.push(m);
      continue;
    }
    if (current === null) {
      current = [];
      turns.push(current);
    }
    current.push(m);
  }
  return turns;
}

/** 最后一轮（空历史回空数组）。 */
export function lastTurnOf(messages: ChatMessage[]): ChatMessage[] {
  const turns: ChatMessage[][] = turnsOf(messages);
  if (turns.length === 0) {
    return [];
  }
  return turns[turns.length - 1];
}

/** 该 assistant 正文是否为「final 候选」：有正文且不带工具调用。 */
function isFinalCandidate(m: ChatMessage): boolean {
  return m.role === 'assistant' && m.text !== '' && m.toolCalls.length === 0;
}

/** 轮是否运行中：会话在流式，或轮内有未 committed/流式中的消息（乐观上屏 seq=-1）。 */
function turnRunning(turn: ChatMessage[], isTurnRunning: boolean): boolean {
  if (isTurnRunning) {
    return true;
  }
  for (let i = 0; i < turn.length; i++) {
    const m: ChatMessage = turn[i];
    if (m.streaming || m.seq < 0) {
      return true;
    }
  }
  return false;
}

/**
 * 折叠回复后的可见消息序列。'all' 原样返回（不复制）；'final' 按 visibleMessagesOf
 * 头注释的口径逐轮过滤。user / process / files / error / command 一律保留。
 */
export function visibleMessagesOf(messages: ChatMessage[], foldedReplies: FoldedReplies,
                                  isTurnRunning: boolean): ChatMessage[] {
  if (foldedReplies !== 'final') {
    return messages;
  }
  const turns: ChatMessage[][] = turnsOf(messages);
  const out: ChatMessage[] = [];
  for (let t = 0; t < turns.length; t++) {
    const turn: ChatMessage[] = turns[t];
    if (turnRunning(turn, isTurnRunning)) {
      for (let i = 0; i < turn.length; i++) {
        out.push(turn[i]);
      }
      continue;
    }
    // 最后一条 final 候选（text 非空且不带工具调用的 assistant 正文）。
    let finalIdx: number = -1;
    for (let i = 0; i < turn.length; i++) {
      if (isFinalCandidate(turn[i])) {
        finalIdx = i;
      }
    }
    if (finalIdx < 0) {
      // 无合格 assistant 消息则整轮不隐藏（过程组/文件卡/错误卡照常可见）。
      for (let i = 0; i < turn.length; i++) {
        out.push(turn[i]);
      }
      continue;
    }
    for (let i = 0; i < turn.length; i++) {
      const m: ChatMessage = turn[i];
      if (i === finalIdx || m.isUser || m.isProcess || m.isError
        || m.role === 'files' || m.role === 'command') {
        out.push(m);
      }
      // 其余 assistant 正文隐藏。
    }
  }
  return out;
}

/**
 * 过程组的展开 key（ChatStore.expandedGroups 用）：组内首个 callId；
 * 无 callId（极端：arguments 缺失的历史事件）用 'seq<起始seq>'。
 */
export function processGroupKey(m: ChatMessage): string {
  if (m.toolCalls.length > 0 && m.toolCalls[0].callId !== '') {
    return m.toolCalls[0].callId;
  }
  return 'seq' + m.seq.toString();
}

/** 一轮内全部过程组的展开 key（completion 自动收起用）。 */
export function groupKeysOfTurn(turn: ChatMessage[]): string[] {
  const keys: string[] = [];
  for (let i = 0; i < turn.length; i++) {
    const m: ChatMessage = turn[i];
    if (m.isProcess) {
      keys.push(processGroupKey(m));
    }
  }
  return keys;
}

/** 最后一轮的组 keys（轮 committed 后按 completion 时机收起）。 */
export function lastTurnGroupKeys(messages: ChatMessage[]): string[] {
  return groupKeysOfTurn(lastTurnOf(messages));
}
