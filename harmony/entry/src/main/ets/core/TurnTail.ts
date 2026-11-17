/**
 * 轮尾行纯逻辑（官方 TurnProcessNodeView 口径）：
 * closed 轮在轮尾给一行「已停止|处理失败|已完成[，用时 X]」，数字部分走代码字体，
 * 仅 canCollapse（有可展开过程且非 alwaysOpen）给 chevron。官方数据源是
 * turn.start/end 事件时间戳与本端 reason.kind；本端消息不带轮级时间戳/原因，口径：
 * - 时长 = 轮内过程组 startedAt 最小值 → finishedAt 最大值（不含最终正文生成时间，
 *   消息无时间戳）；任一端缺失 → 只给「已完成」；
 * - 失败 = 轮内出现 error 消息（turn 失败/被拒）→「处理失败」；
 * - stopped（aborted/interrupted）本端无 per-turn reason 持久化，不单独区分（口径
 *   说明见任务汇报）；official elapsedMs=Math.max(1000,end-start) 的 1s 下限同款。
 */

import { ChatMessage } from './HistoryPage';
import { groupKeysOfTurn } from './WorkSteps';

/** 轮尾行信息（扁平类）。 */
export class TurnTailInfo {
  /** 轮已闭合（下一条 user 已出现且轮不在流式中）。 */
  closed: boolean = false;
  /** 轮内出现 error 消息 →「处理失败」。 */
  failed: boolean = false;
  /** 轮时长（过程组起止口径）；null = 数据不足只给「已完成」。 */
  durationMs: number | null = null;
  /** 轮内有可展开过程（过程组带工具调用）→ chevron 可点。 */
  hasContent: boolean = false;
  /** 轮内过程组 key 集合（展开/收起整轮过程用）。 */
  groupKeys: string[] = [];
}

/**
 * 对 assistant 消息判定其所在轮是否 closed 并取轮尾信息。
 * 非 assistant / 轮仍在流式（m.streaming 或 isTurnRunning 且轮未闭合）/ 轮内没有
 * 任何过程与推理内容 → null（官方 turn.status!=='closed' return null）。
 */
export function turnTailOf(messages: ChatMessage[], index: number,
  isTurnRunning: boolean): TurnTailInfo | null {
  if (index < 0 || index >= messages.length) {
    return null;
  }
  const m: ChatMessage = messages[index];
  if (m.role !== 'assistant' || m.streaming) {
    return null;
  }
  // 轮范围：[上一条 user 之后, 下一条 user 之前]。
  let start: number = 0;
  let end: number = messages.length;
  for (let i = index - 1; i >= 0; i--) {
    if (messages[i].isUser) {
      start = i + 1;
      break;
    }
  }
  for (let i = index + 1; i < messages.length; i++) {
    if (messages[i].isUser) {
      end = i;
      break;
    }
  }
  const closedByNextUser: boolean = end < messages.length;
  if (!closedByNextUser && isTurnRunning) {
    return null; // 列表尾且轮运行中 → 轮未闭合。
  }
  const info: TurnTailInfo = new TurnTailInfo();
  info.closed = true;
  let startedAt: number | null = null;
  let finishedAt: number | null = null;
  const turn: ChatMessage[] = [];
  for (let i = start; i < end; i++) {
    const item: ChatMessage = messages[i];
    turn.push(item);
    if (item.isError) {
      info.failed = true;
    }
    if (item.isProcess && item.toolCalls.length > 0) {
      info.hasContent = true;
      if (item.startedAt !== null && (startedAt === null || (item.startedAt as number) < startedAt)) {
        startedAt = item.startedAt;
      }
      if (item.finishedAt !== null && (finishedAt === null || (item.finishedAt as number) > finishedAt)) {
        finishedAt = item.finishedAt;
      }
    }
  }
  info.groupKeys = groupKeysOfTurn(turn);
  if (startedAt !== null && finishedAt !== null) {
    const span: number = (finishedAt as number) - (startedAt as number);
    if (span > 0) {
      // 官方 elapsedMs 下限 1s（不足 1 秒按 1 秒计）。
      info.durationMs = Math.max(1000, span);
    }
  }
  return info;
}

/** 时长片段（数字/单位，数字走代码字体）。 */
export class DurationPart {
  text: string;
  numeric: boolean;
  constructor(text: string, numeric: boolean) {
    this.text = text;
    this.numeric = numeric;
  }
}

/** 官方 formatRunDuration：floor 秒；h>0→「N小时」；total>=60→「N分」；恒有「N秒」。 */
export function durationPartsOf(ms: number): DurationPart[] {
  const total: number = Math.max(0, Math.floor(ms / 1000));
  const hours: number = Math.floor(total / 3600);
  const minutes: number = Math.floor(total / 60) % 60;
  const seconds: number = total % 60;
  const parts: DurationPart[] = [];
  if (hours > 0) {
    parts.push(new DurationPart(hours.toString(), true));
    parts.push(new DurationPart('小时', false));
  }
  if (total >= 60) {
    parts.push(new DurationPart(minutes.toString(), true));
    parts.push(new DurationPart('分', false));
  }
  parts.push(new DurationPart(seconds.toString(), true));
  parts.push(new DurationPart('秒', false));
  return parts;
}

/**
 * 轮尾行前缀（时长片段要单独按代码字体渲染，故只给前缀）：
 * 处理失败 / 已完成 / 「已完成，用时 」（带尾空格）。
 * hasDuration 由调用方按实际拿到的片段决定 —— 行组件用 `parts.length > 0`，
 * 测试可直接构造；不能只看 info.durationMs，否则 durationMs 有值但片段为空的
 * 边界会得到「已完成」+ 无时长片段的不一致文案。
 */
export function turnTailLead(info: TurnTailInfo, hasDuration: boolean): string {
  if (info.failed) {
    return '处理失败';
  }
  return hasDuration ? '已完成，用时 ' : '已完成';
}

/** 轮尾整行文案（无障碍朗读与测试用）：前缀 + 时长片段拼接。 */
export function turnTailLabel(info: TurnTailInfo, parts: DurationPart[] | null): string {
  if (info.failed || parts === null || parts.length === 0) {
    return turnTailLead(info, false);
  }
  let text: string = turnTailLead(info, true);
  for (let i = 0; i < parts.length; i++) {
    text += parts[i].text;
  }
  return text;
}
