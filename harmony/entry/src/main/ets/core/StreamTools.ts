/**
 * bridge 工具调用实时事件 → 流式工具行状态机（纯逻辑，node 直测）。
 *
 * 帧语义（dsh-remote-bridge fdb85da / docs/API.md「工具调用的实时事件」）：
 * - chat.message.delta kind='tool-call'：参数流式生成中（preparing），
 *   argumentsDelta 增量拼到 argsRaw；首包可能只有 index 没有 callId。
 * - chat.message.delta kind='tool-call-end'：参数定稿（完整 arguments）。
 * - chat.tool.call：工具开始执行（running），按 callId 去重，后到覆盖。
 * - chat.tool.result：结果；isError → 失败；error.code 是内核失败分类
 *   （interrupted / ASK_CANCELLED / TOOL_OUTCOME_UNKNOWN / TOOL_NOT_STARTED / …），
 *   未知值降级为失败。
 *
 * exit code 徽标是纯客户端解析（非协议字段）：结果文本尾部的
 * `[exit code: N]` / `[killed by signal: X]` 行（官方 parseExitStatus 同款）。
 */

import { ToolCallInfo } from './ToolCall';
import { MessageDelta } from './Models';

/** 显式行状态常量（ToolCallInfo.status；'' 表示按 resultText/failed 派生）。 */
export const TOOL_STATUS_PREPARING: string = 'preparing';
export const TOOL_STATUS_STOPPED: string = 'stopped';
export const TOOL_STATUS_CANCELLED: string = 'cancelled';

/** exit 徽标：kind='exit'（数字或 null）或 'signal'。 */
export class ExitBadge {
  kind: string = 'exit';
  value: string = '';
  /** exit 数值非 0（且非 null）或 signal 时为真；红显还要叠加行失败态。 */
  failed: boolean = false;

  constructor(kind: string, value: string, failed: boolean) {
    this.kind = kind;
    this.value = value;
    this.failed = failed;
  }
}

const EXIT_CODE_RE: RegExp = /\n\[exit code: (-?\d+|null)\]$/;
const KILLED_SIGNAL_RE: RegExp = /\n\[killed by signal: ([^\]\n]+)\]$/;

/**
 * 解析结果文本尾部的 exit/signal 标记。
 *
 * 官方 terminalFailed/terminalExitLabel 口径（dsh-client-ui-tool）：只有
 * 「未成功结束」才出徽标——exit 0 视为成功返回 null（不出徽标）；
 * `[exit code: null]` 是「未正常退出」→ kind 'noExit'（terminal.noExitCode）；
 * 信号恒失败 → kind 'signal'（terminal.signal）；非 0 退出码 → kind 'exit'。
 */
export function exitBadgeOf(resultText: string | null): ExitBadge | null {
  if (resultText === null) {
    return null;
  }
  const signal = KILLED_SIGNAL_RE.exec(resultText);
  if (signal !== null) {
    return new ExitBadge('signal', signal[1], true);
  }
  const exit = EXIT_CODE_RE.exec(resultText);
  if (exit !== null) {
    const value: string = exit[1];
    if (value === 'null') {
      return new ExitBadge('noExit', '', true);
    }
    const numeric: number = parseInt(value, 10);
    if (isNaN(numeric) || numeric === 0) {
      return null;
    }
    return new ExitBadge('exit', value, true);
  }
  return null;
}

/** error.code → 显式状态（'' 表示无 code，按 isError 派生；未知值降级失败）。 */
export function statusFromErrorCode(code: string): string {
  if (code === 'interrupted') {
    return TOOL_STATUS_STOPPED;
  }
  if (code === 'ASK_CANCELLED') {
    return TOOL_STATUS_CANCELLED;
  }
  if (code === '') {
    return '';
  }
  return 'failed';
}

/** 行推进等级（upsert 守卫用）：残缺流式数据不得降级已到的完整数据。 */
export function rankOf(call: ToolCallInfo): number {
  if (call.status === TOOL_STATUS_STOPPED || call.status === TOOL_STATUS_CANCELLED) {
    return 4;
  }
  if (call.failed) {
    return 4;
  }
  if (call.resultText !== null) {
    return 3;
  }
  if (call.status === TOOL_STATUS_PREPARING) {
    return 1;
  }
  return 2;
}

function toolRow(key: string, name: string, rawArguments: string | null,
                 status: string): ToolCallInfo {
  const row: ToolCallInfo = new ToolCallInfo(key, name, [], null, false, null, null, rawArguments);
  row.status = status;
  return row;
}

/**
 * 流式工具行容器：行数组 + index→callId 映射（对齐安卓
 * app/lib/ui/streaming_tools.dart _rowFor 的占位键迁移语义）。
 * - delta 首包可能只有 index 没有 callId：先落 'idx<index>' 占位行；
 * - 真实 callId 首现：占位行就地改键迁移到 callId，映射 index→callId，
 *   旧 'idx<index>' 键消失（不残留重复行）；
 * - 后续只带 index 的续包经映射找回已迁移的行。
 */
export class StreamToolState {
  rows: ToolCallInfo[] = [];
  /** delta.index → 该 index 最终归属的 callId（占位期值为 '' 时按 idx 键找）。 */
  private indexToCallId: Map<number, string> = new Map<number, string>();

  findRow(key: string): ToolCallInfo | null {
    for (let i = 0; i < this.rows.length; i++) {
      if (this.rows[i].callId === key) {
        return this.rows[i];
      }
    }
    return null;
  }

  isEmpty(): boolean {
    return this.rows.length === 0;
  }

  clear(): void {
    this.rows = [];
    this.indexToCallId = new Map<number, string>();
  }

  /** delta 帧定位目标行：真实 callId 直找；只有 index 时走映射 / idx 占位键（含迁移）。 */
  private rowFor(delta: MessageDelta): ToolCallInfo | null {
    if (delta.callId !== '') {
      const known: string | undefined = this.indexToCallId.get(delta.index);
      if (known !== undefined && known !== '' && known !== delta.callId) {
        // index 曾归属另一 callId（异常流）：仍按帧里的 callId 开新行，旧行留在原键。
        return this.findRow(delta.callId);
      }
      // 真实 callId 首现：收编 idx 占位行（改键迁移 + 记映射），不新建。
      const stale: ToolCallInfo | null = this.findRow('idx' + delta.index);
      this.indexToCallId.set(delta.index, delta.callId);
      if (stale !== null) {
        stale.callId = delta.callId;
        return stale;
      }
      return this.findRow(delta.callId);
    }
    const known: string | undefined = this.indexToCallId.get(delta.index);
    if (known !== undefined && known !== '') {
      return this.findRow(known);
    }
    return this.findRow('idx' + delta.index);
  }

  /** delta（kind='tool-call'）→ 建 preparing 行 / 继续拼 argumentsDelta；缺 name 先占位。 */
  applyDelta(delta: MessageDelta): void {
    let row: ToolCallInfo | null = this.rowFor(delta);
    if (row === null) {
      row = toolRow(delta.callId !== '' ? delta.callId : 'idx' + delta.index,
                    delta.name !== '' ? delta.name : '工具调用',
                    delta.argumentsDelta !== '' ? delta.argumentsDelta : null,
                    TOOL_STATUS_PREPARING);
      this.rows.push(row);
      return;
    }
    // 已有行：只补名与参数增量，不推进状态（推进交给 tool/call / result）。
    if (delta.name !== '' && row.name === '工具调用') {
      row.name = delta.name;
    }
    if (delta.argumentsDelta !== '') {
      row.rawArguments = (row.rawArguments ?? '') + delta.argumentsDelta;
    }
  }

  /** delta（kind='tool-call-end'）→ 参数定稿（完整 arguments 覆盖）。 */
  applyEnd(delta: MessageDelta): void {
    const row: ToolCallInfo | null = this.rowFor(delta);
    if (row === null) {
      // 定稿帧先到（delta 没发或被丢）：直接建行，仍待 tool/call 转 running。
      this.rows.push(toolRow(delta.callId !== '' ? delta.callId : 'idx' + delta.index,
                             delta.name !== '' ? delta.name : '工具调用',
                             delta.arguments !== '' ? delta.arguments : null,
                             TOOL_STATUS_PREPARING));
      return;
    }
    if (delta.arguments !== '') {
      row.rawArguments = delta.arguments;
    }
    if (delta.name !== '') {
      row.name = delta.name;
    }
  }

  /** chat.tool.call → running（按 callId 去重，后到覆盖 preparing/running）。 */
  applyCall(callId: string, name: string, args: string): void {
    if (callId === '') {
      return;
    }
    const row: ToolCallInfo | null = this.findRow(callId);
    if (row === null) {
      this.rows.push(toolRow(callId, name !== '' ? name : '工具调用',
                             args !== '' ? args : null, ''));
      return;
    }
    if (name !== '') {
      row.name = name;
    }
    if (args !== '') {
      row.rawArguments = args;
    }
    // running 是隐式状态：清掉 preparing 标记即可。
    row.status = '';
  }

  /**
   * 清掉已被持久过程组覆盖的行（callId 命中即删），并同步清掉指向这些
   * callId 的 index→callId 映射（下轮同 index 从占位行重建）。
   */
  dropPersisted(callIds: Set<string>): void {
    if (this.rows.length === 0 || callIds.size === 0) {
      return;
    }
    const kept: ToolCallInfo[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      if (!callIds.has(this.rows[i].callId)) {
        kept.push(this.rows[i]);
      }
    }
    if (kept.length === this.rows.length) {
      return;
    }
    this.rows = kept;
    const staleIdx: number[] = [];
    this.indexToCallId.forEach((callId: string, idx: number): void => {
      if (callIds.has(callId)) {
        staleIdx.push(idx);
      }
    });
    for (let i = 0; i < staleIdx.length; i++) {
      this.indexToCallId.delete(staleIdx[i]);
    }
  }

  /** chat.tool.result → done / failed / stopped / cancelled。 */
  applyResult(callId: string, isError: boolean, contentText: string,
              errorCode: string): void {
    if (callId === '') {
      return;
    }
    const status: string = statusFromErrorCode(errorCode);
    const failed: boolean = status === '' ? isError
                                            : status !== TOOL_STATUS_STOPPED && status !== TOOL_STATUS_CANCELLED;
    const row: ToolCallInfo | null = this.findRow(callId);
    if (row === null) {
      const fresh: ToolCallInfo = toolRow(callId, '工具调用', null, status);
      fresh.resultText = contentText !== '' ? contentText : null;
      fresh.failed = failed;
      this.rows.push(fresh);
      return;
    }
    row.resultText = contentText !== '' ? contentText : null;
    row.status = status;
    row.failed = failed;
  }
}

/** 流式行并入持久行（就地 mutate，保组件引用）：live 等级 ≥ 持久才覆盖。 */
export function mergeLiveRow(target: ToolCallInfo, live: ToolCallInfo): boolean {
  if (rankOf(live) < rankOf(target)) {
    return false;
  }
  if (live.name !== '') {
    target.name = live.name;
  }
  if (live.rawArguments !== null && live.rawArguments !== '') {
    target.rawArguments = live.rawArguments;
  }
  if (live.resultText !== null) {
    target.resultText = live.resultText;
  }
  target.failed = live.failed;
  target.status = live.status;
  return true;
}
