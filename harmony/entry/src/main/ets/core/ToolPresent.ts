/**
 * 工具调用呈现纯逻辑（上半：活动归类/词表/过程组标题/工具行摘要）——
 * 官方 Web 会话页（dsh-client-ui-chat / dsh-client-ui-tool）的 node 直测口径，
 * 与 app/ Flutter 端同构（Lead 逆向核实 2026-11-17）。
 * 官方 bundle 依据：dsh-client-ui-chat/lib/client.js processTitle 区（完成组 2 类
 * joinTwo=「{first}并{second}」，second 与 first 都以「已」开头时 second 去「已」；
 * ≥3 类「，」连接，总类数>3 末尾追加「等」，无工具「已完成分析」）；工具行组件在
 * dsh-client-ui-tool/lib/client.js（图标官方是 SVG，本端 emoji 占位）。
 * 详情分派/询问状态机/展示档位 policy 在 core/ToolDetails.ts（本文件超 500 行拆分）。
 * 数据不可得不做（汇报口径）：preparing 独立态（以 running 且 rawArguments==null
 * 近似）、exit code badge、stopped 态、结构化 detail 字段表、~ 路径缩写、轮级状态行。
 */

import { ToolCallInfo } from './ToolCall';
import { JsonAccess, JsonMap } from './JsonAccess';
import { TOOL_STATUS_PREPARING, TOOL_STATUS_STOPPED, TOOL_STATUS_CANCELLED } from './StreamTools';
// ---- 活动归类（官方 activityKind） --------------------------------------

export const AK_THINKING: string = 'thinking';
export const AK_READ: string = 'read';
export const AK_READ_IMAGE: string = 'readImage';
export const AK_SEARCH: string = 'search';
export const AK_WRITE: string = 'write';
export const AK_EDIT: string = 'edit';
export const AK_COMMANDS: string = 'commands';
export const AK_CODE: string = 'code';
export const AK_WEB_SEARCH: string = 'webSearch';
export const AK_WEB_FETCH: string = 'webFetch';
export const AK_SUBAGENTS: string = 'subagents';
export const AK_QUESTIONS: string = 'questions';
export const AK_PLAN: string = 'plan';
export const AK_TOOLS: string = 'tools';

/** 官方 activityKind：剥 tools. 前缀后按精确名/前缀/后缀归类；空名 → thinking。 */
export function activityKind(name: string): string {
  let n: string = name;
  if (n.startsWith('tools.')) {
    n = n.substring('tools.'.length);
  }
  if (n === '') {
    return AK_THINKING;
  }
  if (n === 'read') {
    return AK_READ;
  }
  if (n === 'read_image') {
    return AK_READ_IMAGE;
  }
  if (n === 'grep' || n === 'glob' || n.endsWith('_inspect')) {
    return AK_SEARCH;
  }
  if (n === 'write') {
    return AK_WRITE;
  }
  if (n === 'edit' || n === 'apply_patch') {
    return AK_EDIT;
  }
  if (n === 'bash' || n === 'pwsh' || n === 'exec_command' || n === 'write_stdin' ||
    n.startsWith('terminal_')) {
    return AK_COMMANDS;
  }
  if (n === 'run_code') {
    return AK_CODE;
  }
  if (n === 'web_search') {
    return AK_WEB_SEARCH;
  }
  if (n === 'web_fetch') {
    return AK_WEB_FETCH;
  }
  if (n === 'subagent' || n.startsWith('subagent_')) {
    return AK_SUBAGENTS;
  }
  if (n === 'ask_user_question') {
    return AK_QUESTIONS;
  }
  if (n === 'todo_write') {
    return AK_PLAN;
  }
  return AK_TOOLS;
}

/** 扁平 key/value 对建 Map（ArkTS 禁动态键对象字面量）。 */
function mapOf(pairs: string[]): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    out.set(pairs[i], pairs[i + 1]);
  }
  return out;
}
// ---- 词表（zh 措辞逐字对齐官方） ----------------------------------------

/** 进行中组标题词表（无 running 工具 → thinking）。 */
export const RUNNING_LABELS: Map<string, string> = mapOf([
  AK_THINKING, '正在分析请求',
  AK_READ, '正在读取文件',
  AK_READ_IMAGE, '正在读取图片',
  AK_WRITE, '正在写入文件',
  AK_SEARCH, '正在搜索代码',
  AK_EDIT, '正在编辑文件',
  AK_COMMANDS, '正在运行命令',
  AK_CODE, '正在运行代码',
  AK_WEB_SEARCH, '正在搜索网页',
  AK_WEB_FETCH, '正在访问网页',
  AK_SUBAGENTS, '正在协调子智能体',
  AK_PLAN, '正在更新计划',
  AK_QUESTIONS, '等待你的操作',
  AK_TOOLS, '正在调用工具',
]);

/** preparing 近似词表（running 且 rawArguments==null）。官方 prepare.<activity>：
 * thinking → prepare.tools「准备调用工具」，其余各 activity 自有词。 */
export const PREPARING_LABELS: Map<string, string> = mapOf([
  AK_THINKING, '准备调用工具',
  AK_READ, '准备读取文件',
  AK_READ_IMAGE, '准备读取图片',
  AK_WRITE, '准备写入文件',
  AK_SEARCH, '准备搜索代码',
  AK_EDIT, '准备编辑文件',
  AK_COMMANDS, '准备运行命令',
  AK_CODE, '准备运行代码',
  AK_WEB_SEARCH, '准备搜索网页',
  AK_WEB_FETCH, '准备访问网页',
  AK_SUBAGENTS, '准备协调子智能体',
  AK_PLAN, '准备更新计划',
  AK_QUESTIONS, '准备提问',
  AK_TOOLS, '准备调用工具',
]);

/** 完成组 done 词表（注意 edit=「修改了」、plan=「更新了」，非「已」开头）。 */
export const DONE_LABELS: Map<string, string> = mapOf([
  AK_THINKING, '已完成分析',
  AK_READ, '已读取文件',
  AK_READ_IMAGE, '已读取图片',
  AK_WRITE, '已写入文件',
  AK_SEARCH, '已搜索代码',
  AK_EDIT, '修改了文件',
  AK_COMMANDS, '执行了命令',
  AK_CODE, '运行了代码',
  AK_WEB_SEARCH, '已搜索网页',
  AK_WEB_FETCH, '已访问网页',
  AK_SUBAGENTS, '已协调子智能体',
  AK_PLAN, '更新了计划',
  AK_QUESTIONS, '向用户提出了问题',
  AK_TOOLS, '已调用工具',
]);

/** kind → 行首图标（官方是 SVG，本端用 emoji 占位）。 */
export const KIND_ICONS: Map<string, string> = mapOf([
  AK_THINKING, '💭',
  AK_READ, '📄',
  AK_READ_IMAGE, '🖼️',
  AK_SEARCH, '🔍',
  AK_WRITE, '📝',
  AK_EDIT, '✏️',
  AK_COMMANDS, '⌨️',
  AK_CODE, '🧩',
  AK_WEB_SEARCH, '🌐',
  AK_WEB_FETCH, '🌐',
  AK_SUBAGENTS, '🤖',
  AK_QUESTIONS, '❓',
  AK_PLAN, '☑️',
  AK_TOOLS, '🔧',
]);

export function kindIcon(kind: string): string {
  const icon: string | undefined = KIND_ICONS.get(kind);
  return icon === undefined ? '🔧' : icon;
}

/**
 * 过程组闭合态图标（官方 counts[0].kind 口径）：各 kind 计数降序，并列按
 * 首现取第一；空组 → thinking（「已完成分析」图标）。
 */
export function topKindOf(calls: ToolCallInfo[]): string {
  const counts: Map<string, number> = new Map<string, number>();
  const order: string[] = [];
  for (let i = 0; i < calls.length; i++) {
    const kind: string = activityKind(calls[i].name);
    if (!counts.has(kind)) {
      order.push(kind);
    }
    counts.set(kind, (counts.get(kind) ?? 0) + 1);
  }
  let best: string | null = null;
  let bestCount: number = -1;
  for (let i = 0; i < order.length; i++) {
    const c: number = counts.get(order[i]) ?? 0;
    if (c > bestCount) {
      bestCount = c;
      best = order[i];
    }
  }
  return best === null ? AK_THINKING : best;
}
// ---- 文本工具 -----------------------------------------------------------

/** 首个非空行（trim 后）；全空返回 ''。 */
export function firstLineOf(text: string): string {
  const lines: string[] = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const t: string = lines[i].trim();
    if (t.length > 0) {
      return t;
    }
  }
  return '';
}

/** runningDetail 截断：>160 字符截断加省略号。 */
export function truncateDetail(text: string): string {
  if (text.length > 160) {
    return text.substring(0, 160) + '…';
  }
  return text;
}

/** 去 markdown 加粗星号。 */
export function stripStars(text: string): string {
  return text.split('**').join('');
}

/** reasoning 尾段：最后一个非空行（去 **）。 */
export function reasoningTailOf(reasoning: string): string {
  const lines: string[] = reasoning.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    const t: string = stripStars(lines[i]).trim();
    if (t.length > 0) {
      return t;
    }
  }
  return '';
}
// ---- 运行态判定 ---------------------------------------------------------

/** 调用是否运行中：无结果且未失败、也没有显式终态（stopped/cancelled）。 */
export function isCallRunning(call: ToolCallInfo): boolean {
  return call.resultText === null && !call.failed
    && call.status !== TOOL_STATUS_STOPPED && call.status !== TOOL_STATUS_CANCELLED;
}

/**
 * preparing = bridge chat.message.delta kind='tool-call' 的流式行
 * （ToolCallInfo.status 显式标记；真数据驱动，弃 rawArguments==null 近似）。
 */
export function isCallPreparing(call: ToolCallInfo): boolean {
  return call.status === TOOL_STATUS_PREPARING;
}

/** 组内是否有运行中调用（组级「进行中」渲染判定）。 */
export function hasRunningCall(calls: ToolCallInfo[]): boolean {
  for (let i = 0; i < calls.length; i++) {
    if (isCallRunning(calls[i])) {
      return true;
    }
  }
  return false;
}
// ---- 进行中组 detail ----------------------------------------------------

/** 官方 LIVE_TOOL_DETAIL_KEYS（按序首个命中键）。 */
export const LIVE_TOOL_DETAIL_KEYS: string[] = [
  'title', 'description', 'objective', 'task', 'task_name', 'name', 'question',
  'questions', 'prompt', 'message', 'command', 'cmd', 'queries', 'query',
  'pattern', 'url', 'uri', 'file_path', 'path', 'target', 'action', 'status',
];

function argsObjectOf(rawArguments: string | null): Object | null {
  if (rawArguments === null) {
    return null;
  }
  const trimmed: string = rawArguments.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return JsonAccess.parse(trimmed);
}

/** 参数 JSON → 键值对象（宽容；非对象返回 null）。 */
function argsRecordOf(rawArguments: string | null): JsonMap | null {
  return JsonAccess.asMap(argsObjectOf(rawArguments));
}

/** running 工具的 detail 文本：首个命中键的文本首行（截 160；queries 取首项）。 */
export function liveDetailOf(call: ToolCallInfo): string {
  const record: JsonMap | null = argsRecordOf(call.rawArguments);
  if (record === null) {
    return '';
  }
  for (let i = 0; i < LIVE_TOOL_DETAIL_KEYS.length; i++) {
    const key: string = LIVE_TOOL_DETAIL_KEYS[i];
    const value: Object | null = JsonAccess.raw(record, key);
    if (value === null) {
      continue;
    }
    if (Array.isArray(value)) {
      const items: Object[] = value as Object[];
      if (items.length > 0 && typeof items[0] === 'string') {
        const t: string = firstLineOf(items[0] as string);
        if (t.length > 0) {
          return truncateDetail(t);
        }
      }
      continue;
    }
    if (typeof value === 'string') {
      const t: string = firstLineOf(value as string);
      if (t.length > 0) {
        return truncateDetail(t);
      }
    }
  }
  return '';
}

/**
 * 进行中组 detail：最新 running 工具的 detail；无 running 工具取组内最后一条
 * reasoning 最后非空段（去 **）。detail 空则由调用方不加后缀。
 */
export function runningDetailOf(calls: ToolCallInfo[], reasoning: string): string {
  for (let i = calls.length - 1; i >= 0; i--) {
    if (isCallRunning(calls[i])) {
      return liveDetailOf(calls[i]);
    }
  }
  return reasoningTailOf(reasoning);
}
// ---- 过程组标题 ----------------------------------------------------------

export class GroupTitleOptions {
  liveProcessDetail: boolean = false;
  reasoning: string = '';
}

/** 过程组标题：进行中→「正在…/准备…」词表（最新 running 工具 kind，无 running→thinking），liveProcessDetail 时附加「 · detail」；完成→done 词组合。 */
export function processGroupTitle(calls: ToolCallInfo[], inProgress: boolean,
  opts: GroupTitleOptions): string {
  if (inProgress) {
    let runningIdx: number = -1;
    for (let i = calls.length - 1; i >= 0; i--) {
      if (isCallRunning(calls[i])) {
        runningIdx = i;
        break;
      }
    }
    const kind: string = runningIdx >= 0 ? activityKind(calls[runningIdx].name) : AK_THINKING;
    let label: string | undefined = RUNNING_LABELS.get(kind);
    if (label === undefined) {
      label = '正在调用工具';
    }
    if (runningIdx >= 0 && isCallPreparing(calls[runningIdx])) {
      const preparing: string | undefined = PREPARING_LABELS.get(kind);
      if (preparing !== undefined) {
        label = preparing;
      }
    }
    if (opts.liveProcessDetail) {
      const detail: string = runningDetailOf(calls, opts.reasoning);
      if (detail.length > 0) {
        return label + ' · ' + detail;
      }
    }
    return label;
  }
  return doneGroupTitle(calls);
}

/** 单 kind 的 done 词（未知 kind 兜底 tools 词）。 */
export function doneWordOf(kind: string): string {
  const word: string | undefined = DONE_LABELS.get(kind);
  return word === undefined ? (DONE_LABELS.get(AK_TOOLS) ?? '已调用工具') : word;
}

/** 完成组 done 词组合（官方 joinTwo 口径）：1 类直接；2 类「{first}并{second}」（second 与 first 都以「已」开头时 second 去「已」）；≥3 类「，」连接；总类数>3 末尾「等」；无工具「已完成分析」。 */
export function combineDoneWords(words: string[], totalKinds: number): string {
  if (words.length === 0) {
    return doneWordOf(AK_THINKING);
  }
  if (words.length === 1) {
    return words[0];
  }
  if (words.length === 2) {
    let second: string = words[1];
    if (second.startsWith('已') && words[0].startsWith('已')) {
      second = second.substring(1);
    }
    return words[0] + '并' + second;
  }
  const joined: string = words.join('，');
  return totalKinds > 3 ? joined + '等' : joined;
}

/** 完成组标题：counts 按 kind 聚合，count 降序（并列按首次出现）取前 3 类。 */
export function doneGroupTitle(calls: ToolCallInfo[]): string {
  const counts: Map<string, number> = new Map<string, number>();
  const order: string[] = [];
  for (let i = 0; i < calls.length; i++) {
    const kind: string = activityKind(calls[i].name);
    const current: number | undefined = counts.get(kind);
    if (current === undefined) {
      counts.set(kind, 1);
      order.push(kind);
    } else {
      counts.set(kind, current + 1);
    }
  }
  if (order.length === 0) {
    return doneWordOf(AK_THINKING);
  }
  const sorted: string[] = order.slice();
  sorted.sort((a: string, b: string): number => (counts.get(b) ?? 0) - (counts.get(a) ?? 0));
  const words: string[] = [];
  for (let i = 0; i < sorted.length && i < 3; i++) {
    words.push(doneWordOf(sorted[i]));
  }
  return combineDoneWords(words, sorted.length);
}
// ---- 工具行摘要（SUMMARY_KEYS） -----------------------------------------

/** kind → 摘要键（按序首个命中；search 的 queries 数组 join(', ')）。 */
export const SUMMARY_KEYS_BY_KIND: Map<string, string[]> = new Map<string, string[]>([
  [AK_COMMANDS, ['description', 'command']],
  [AK_READ, ['path', 'file_path', 'url']],
  [AK_SEARCH, ['query', 'pattern', 'url']],
  [AK_WRITE, ['path', 'file_path']],
  [AK_EDIT, ['path', 'file_path']],
  [AK_CODE, ['description']],
]);

function summaryValueText(value: Object | null): string {
  if (value === null) {
    return '';
  }
  if (Array.isArray(value)) {
    const items: Object[] = value as Object[];
    const parts: string[] = [];
    for (let i = 0; i < items.length; i++) {
      if (typeof items[i] === 'string') {
        const line: string = firstLineOf(items[i] as string);
        if (line.length > 0) {
          parts.push(line);
        }
      }
    }
    return parts.join(', ');
  }
  if (typeof value === 'string') {
    return firstLineOf(value);
  }
  return '';
}

/** 工具行 summary：kind 键表 → 首个字符串值首行 → argsRaw 首行。 */
export function toolSummaryOf(call: ToolCallInfo): string {
  const record: JsonMap | null = argsRecordOf(call.rawArguments);
  if (record !== null) {
    const keys: string[] | undefined = SUMMARY_KEYS_BY_KIND.get(activityKind(call.name));
    if (keys !== undefined) {
      for (let i = 0; i < keys.length; i++) {
        const text: string = summaryValueText(JsonAccess.raw(record, keys[i]));
        if (text.length > 0) {
          return text;
        }
      }
    }
    // 兜底：首个字符串值首行（Record 键序 = 插入序）。
    const objKeys: string[] = Object.keys(record);
    for (let i = 0; i < objKeys.length; i++) {
      const value: Object | null = JsonAccess.raw(record, objKeys[i]);
      if (value !== null && typeof value === 'string') {
        const text: string = firstLineOf(value);
        if (text.length > 0) {
          return text;
        }
      }
    }
  }
  const raw: string | null = call.rawArguments;
  if (raw !== null && raw.trim().length > 0) {
    return firstLineOf(raw);
  }
  return '';
}
