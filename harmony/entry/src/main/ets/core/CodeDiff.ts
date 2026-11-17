/**
 * 本轮代码差异提取 —— 代码工作视图第二段（会话页）。
 *
 * 口径：从一轮消息的过程组工具调用里提取 edit / write 两类写盘调用
 * （工具名与参数键名依据 core/ToolCall.ts 措辞表与桥侧 tool/call 事件实测：
 * edit 用 file_path/old_string/new_string，write 用 file_path/content；
 * rawArguments 是 JSON 字符串，宽容解析，坏参数跳过该调用不抛）。
 *
 * 行模型：del = old_string 逐行（edit），add = new_string 逐行（edit）或
 * content 逐行（write，全 add）；del 行在前 add 行在后（标准 diff 顺序）；
 * ctx 行类型保留给渲染层（当前提取不产生）。同一文件多次调用按 path 聚合、
 * 行顺序拼接，kind 取首次出现的；文件按首次出现顺序输出。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { ChatMessage } from './HistoryPage';
import { ToolCallInfo } from './ToolCall';
import { turnsOf } from './WorkSteps';

/** diff 行类型：'add' | 'del' | 'ctx'（type 字段分派，扁平类）。 */
export const DIFF_LINE_ADD: string = 'add';
export const DIFF_LINE_DEL: string = 'del';
export const DIFF_LINE_CTX: string = 'ctx';

export class DiffLine {
  type: string = DIFF_LINE_ADD;
  text: string = '';

  constructor(type: string, text: string) {
    this.type = type;
    this.text = text;
  }
}

/** 单文件差异块；kind = 'edit' | 'write'。 */
export class FileDiff {
  path: string = '';
  kind: string = 'edit';
  lines: DiffLine[] = [];
}

export const DIFF_KIND_EDIT: string = 'edit';
export const DIFF_KIND_WRITE: string = 'write';

/** 空串不产行（写空文件 = 无行，与 split('\n') 的 [''] 假行区分）。 */
function splitLines(text: string): string[] {
  if (text === '') {
    return [];
  }
  return text.split('\n');
}

function argumentsOf(call: ToolCallInfo): JsonMap | null {
  if (call.rawArguments === null) {
    return null;
  }
  const raw: string = call.rawArguments.trim();
  if (raw === '') {
    return null;
  }
  return JsonAccess.asMap(JsonAccess.parse(raw));
}

/** 单个工具调用 → 差异块；非 edit/write / 参数坏 / 无 file_path → null。 */
export function fileDiffOfCall(call: ToolCallInfo): FileDiff | null {
  const isEdit: boolean = call.name === 'edit' || call.name === 'tools.edit';
  const isWrite: boolean = call.name === 'write' || call.name === 'tools.write';
  if (!isEdit && !isWrite) {
    return null;
  }
  const args: JsonMap | null = argumentsOf(call);
  if (args === null) {
    return null;
  }
  const path: string = JsonAccess.strOr(args, 'file_path', '');
  if (path === '') {
    return null;
  }
  const diff: FileDiff = new FileDiff();
  diff.path = path;
  diff.kind = isEdit ? DIFF_KIND_EDIT : DIFF_KIND_WRITE;
  if (isEdit) {
    const oldLines: string[] = splitLines(JsonAccess.strOr(args, 'old_string', ''));
    const newLines: string[] = splitLines(JsonAccess.strOr(args, 'new_string', ''));
    for (let i = 0; i < oldLines.length; i++) {
      diff.lines.push(new DiffLine(DIFF_LINE_DEL, oldLines[i]));
    }
    for (let i = 0; i < newLines.length; i++) {
      diff.lines.push(new DiffLine(DIFF_LINE_ADD, newLines[i]));
    }
  } else {
    const contentLines: string[] = splitLines(JsonAccess.strOr(args, 'content', ''));
    for (let i = 0; i < contentLines.length; i++) {
      diff.lines.push(new DiffLine(DIFF_LINE_ADD, contentLines[i]));
    }
  }
  return diff;
}

/** 行内 diff 统计（官方 ToolRow diffStat suffix）：「+N -M」。 */
export function diffStatOf(d: FileDiff): string {
  let add: number = 0;
  let del: number = 0;
  for (let i = 0; i < d.lines.length; i++) {
    if (d.lines[i].type === DIFF_LINE_ADD) {
      add += 1;
    } else if (d.lines[i].type === DIFF_LINE_DEL) {
      del += 1;
    }
  }
  return '+' + add.toString() + ' -' + del.toString();
}

/**
 * 一轮内的代码差异，按 path 聚合（行顺序拼接），保文件首次出现顺序。
 * `turn` 传 turnsOf(messages) 的任意一轮（UI 用 codeDiffsOfLastTurn）。
 */export function codeDiffsOfTurn(turn: ChatMessage[]): FileDiff[] {
  const byPath: Map<string, FileDiff> = new Map<string, FileDiff>();
  const order: string[] = [];
  for (let i = 0; i < turn.length; i++) {
    const m: ChatMessage = turn[i];
    if (!m.isProcess) {
      continue;
    }
    for (let c = 0; c < m.toolCalls.length; c++) {
      const diff: FileDiff | null = fileDiffOfCall(m.toolCalls[c]);
      if (diff === null) {
        continue;
      }
      const seen: FileDiff | null = byPath.get(diff.path) === undefined ? null : byPath.get(diff.path) as FileDiff;
      if (seen === null) {
        byPath.set(diff.path, diff);
        order.push(diff.path);
      } else {
        for (let l = 0; l < diff.lines.length; l++) {
          seen.lines.push(diff.lines[l]);
        }
      }
    }
  }
  const out: FileDiff[] = [];
  for (let i = 0; i < order.length; i++) {
    const d: FileDiff | undefined = byPath.get(order[i]);
    if (d !== undefined) {
      out.push(d);
    }
  }
  return out;
}

/** 当前会话最后一轮的代码差异（代码工作视图「本轮代码差异」入口）。 */
export function codeDiffsOfLastTurn(messages: ChatMessage[]): FileDiff[] {
  const turns: ChatMessage[][] = turnsOf(messages);
  if (turns.length === 0) {
    return [];
  }
  return codeDiffsOfTurn(turns[turns.length - 1]);
}
