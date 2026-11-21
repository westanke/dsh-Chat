/**
 * 工具调用模型与措辞表 —— 移植自 app/lib/bridge/tool_call.dart（220 行）。
 *
 * 措辞对齐官方（与 dsh-companion 的 ChatToolPresentation 同源）：内核的
 * `tool/call` 没有结构化 summary 字段（已逐条核实），只能按工具名与参数近似还原；
 * `run_code` 的 arguments 里会内嵌 `tools.bash` 等名字，扫一遍即可得到
 * 「运行了代码，执行了命令」这类组合。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

/** 一次工具调用（`tool/call` + `tool/result` 按 callId 合并后的展示形态）。 */
export class ToolCallInfo {
  // 字段可变：流式阶段（chat.tool.* 事件）会就地升级同一实例，
  // 让持有引用的工具行组件在版本广播后读到最新值（鸿蒙 LazyForEach 同 key 不重建的坑）。
  callId: string = '';
  name: string = '';
  /** 动作短语，如 `['运行了代码', '执行了命令']`（措辞对齐官方）。 */
  phrases: string[] = [];
  /** 参数摘要（description / path / command / query 的首行）。 */
  summary: string | null = null;
  failed: boolean = false;
  durationMs: number | null = null;
  /** 执行结果正文（tool/result 的 text 段拼接；图片段一行占位）。 */
  resultText: string | null = null;
  /** arguments 原串（JSON 字符串），详情展开用。 */
  rawArguments: string | null = null;
  /**
   * `tool/result` 的 `data.meta`（桥原样透传，形状由工具自己定，安卓同口径）：
   * - edit / write：`{path, operation?, diffs:[{path, oldText, newText}]}`
   * - read：`{path, offset, lines:[{number,text}], totalLines}`
   * - bash：`{cwd}`；read_image：`{path}`。
   *
   * 本轮改动卡（TurnChanges）优先读 `diffs` 里的真实新旧全文，拿不到才退回 arguments。
   */
  meta: JsonMap | null = null;
  /**
   * 显式状态（空串=按字段派生）：'preparing'（参数流式生成中，bridge
   * chat.message.delta kind='tool-call'）；'stopped'（error.code='interrupted'，
   * 用户中断）；'cancelled'（error.code='ASK_CANCELLED'，询问已取消）。
   * 'running'/'done'/'failed' 不落此字段——按 resultText/failed 派生。
   */
  status: string = '';

  constructor(callId: string, name: string, phrases: string[],
              summary: string | null, failed: boolean,
              durationMs: number | null, resultText: string | null,
              rawArguments: string | null, meta: JsonMap | null = null) {
    this.callId = callId;
    this.name = name;
    this.phrases = phrases;
    this.summary = summary;
    this.failed = failed;
    this.durationMs = durationMs;
    this.resultText = resultText;
    this.rawArguments = rawArguments;
    this.meta = meta;
  }

  /** 折叠行用的主短语（run_code 取第一个，其余就是唯一那个）。 */
  get phrase(): string {
    return this.phrases.length === 0 ? this.name : this.phrases[0];
  }
}

/** 工具名 → 动作短语（对齐官方措辞，与安卓 toolPhraseByName 同表）。 */
const TOOL_PHRASE_BY_NAME: Map<string, string> = new Map<string, string>([
  ['bash', '执行了命令'],
  ['pwsh', '执行了命令'],
  ['read', '读取了文件'],
  ['read_image', '读取了图片'],
  ['write', '已写入文件'],
  ['edit', '修改了文件'],
  ['grep', '搜索了内容'],
  ['glob', '搜索了文件'],
  ['web_fetch', '已访问网页'],
  ['web_search', '已搜索网页'],
  ['memory', '记录了记忆'],
  ['job_output', '查看了任务输出'],
  ['job_kill', '停止了任务'],
  ['adb_ui', '检查了手机界面'],
  ['working_directory', '切换了工作目录'],
  ['todo_write', '更新了任务清单'],
  ['wait_agent', '等待了子任务'],
  ['update_goal', '更新了目标'],
  ['compress', '压缩了上下文'],
  ['workflow', '编排了子任务'],
  ['send_message', '发送了消息'],
  ['lead', '调度了团队'],
  ['skill', '调用了技能'],
  ['schedule_create', '创建了定时任务'],
  ['schedule_list', '查看了定时任务'],
  ['schedule_delete', '删除了定时任务'],
  ['schedule_update', '修改了定时任务'],
  ['team_task_create', '创建了团队任务'],
  ['team_task_list', '查看了团队任务'],
  ['team_task_get', '查看了任务详情'],
  ['team_task_update', '更新了团队任务'],
  ['subagent', '派出了子任务'],
  ['ask_user_question', '向用户提问'],
]);

/** run_code arguments 内嵌工具名 → 短语（与安卓 innerToolActions 元组表同序）。 */
const INNER_TOOL_ACTIONS: Map<string, string> = new Map<string, string>([
  ['tools.edit', '修改了文件'],
  ['tools.write', '已写入文件'],
  ['tools.read', '读取了文件'],
  ['tools.bash', '执行了命令'],
  ['tools.grep', '搜索了内容'],
  ['tools.glob', '搜索了文件'],
]);

export function toolPhrases(name: string, args: string | null): string[] {
  const raw: string = args === null ? '' : args;
  if (name === 'run_code') {
    const out: string[] = ['运行了代码'];
    INNER_TOOL_ACTIONS.forEach((phrase: string, needle: string): void => {
      if (raw.indexOf(needle) >= 0 && out.indexOf(phrase) < 0) {
        out.push(phrase);
      }
    });
    return out;
  }
  const byName: string | undefined = TOOL_PHRASE_BY_NAME.get(name);
  if (byName !== undefined) {
    return [byName];
  }
  if (name.startsWith('mcp__')) {
    return ['调用了 ' + name.substring(5).split('__').join(' · ')];
  }
  return [name === '' ? '工具' : name];
}

/** 从 arguments JSON 里挑一个最能说明「在干什么」的字段首行。 */
export function toolSummary(args: string | null): string | null {
  if (args === null || args.trim() === '') {
    return null;
  }
  const parsed: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(args));
  if (parsed === null) {
    return null;
  }
  const keys: string[] = ['description', 'path', 'file_path', 'query', 'pattern',
    'url', 'command', 'name', 'package'];
  for (const key of keys) {
    const v: string | null = JsonAccess.str(parsed, key);
    if (v !== null && v.trim() !== '') {
      return v.split('\n')[0];
    }
  }
  return null;
}

/** 从 tool/result 的 content 数组提取正文：text 段拼接，image 段一行占位。 */
export function toolResultText(content: Object | null): string | null {
  if (typeof content === 'string') {
    const s: string = content.trim();
    return s === '' ? null : s;
  }
  if (!Array.isArray(content)) {
    return null;
  }
  const blocks: Object[] = content as Object[];
  let buf: string = '';
  let hasImage: boolean = false;
  for (const b of blocks) {
    const block: JsonMap | null = JsonAccess.asMap(b);
    if (block === null) {
      continue;
    }
    const type: string = JsonAccess.strOr(block, 'type', '');
    if (type === 'image') {
      hasImage = true;
    } else {
      const t: string | null = JsonAccess.str(block, 'text');
      if (t !== null && t.trim() !== '') {
        if (buf !== '') {
          buf += '\n';
        }
        buf += t.trim();
      }
    }
  }
  let out: string = buf.trim();
  if (out === '' && hasImage) {
    out = '[图片]';
  }
  return out === '' ? null : out;
}

/** 解析中的工具调用（result 还没到）。 */
export class RawToolCall {
  callId: string = '';
  name: string = '';
  arguments: string | null = null;
  time: number = 0;
  /** tool/result 的正文，到达时补上。 */
  resultText: string | null = null;
  failed: boolean = false;
  /** tool/result 的 `data.meta`（见 ToolCallInfo.meta），到达时补上。 */
  meta: JsonMap | null = null;

  toInfo(): ToolCallInfo {
    return new ToolCallInfo(this.callId, this.name,
      toolPhrases(this.name, this.arguments), toolSummary(this.arguments),
      this.failed, null, this.resultText, this.arguments, this.meta);
  }
}

/** 从 assistant content 数组里抽出内嵌的 tool-call 块。 */
export function extractToolCalls(content: Object | null): RawToolCall[] {
  const out: RawToolCall[] = [];
  if (!Array.isArray(content)) {
    return out;
  }
  const blocks: Object[] = content as Object[];
  for (const b of blocks) {
    const block: JsonMap | null = JsonAccess.asMap(b);
    if (block === null) {
      continue;
    }
    if (JsonAccess.strOr(block, 'type', '') !== 'tool-call') {
      continue;
    }
    const id: string = JsonAccess.strOr(block, 'id', '');
    if (id === '') {
      continue;
    }
    const raw: RawToolCall = new RawToolCall();
    raw.callId = id;
    raw.name = JsonAccess.strOr(block, 'name', '');
    raw.arguments = JsonAccess.str(block, 'arguments');
    raw.time = 0;
    out.push(raw);
  }
  return out;
}

/**
 * 耗时展示（安卓 process_group.dart `_duration()` 同口径）：
 * <1s 用 ms，<1min 用 s（一位小数），否则 m+s。负值/空值不显示（时钟倒退）。
 */
export function formatDuration(ms: number | null): string | null {
  if (ms === null || ms < 0) {
    return null;
  }
  if (ms < 1000) {
    return ms.toString() + 'ms';
  }
  if (ms < 60000) {
    return (ms / 1000).toFixed(1) + 's';
  }
  const m: number = Math.floor(ms / 60000);
  const sec: number = Math.floor((ms % 60000) / 1000);
  return m.toString() + 'm' + sec.toString() + 's';
}

/**
 * bash 命令原文：name 为 bash / tools.bash 时从 arguments 里取 command 字段，
 * 详情里按 BASH 代码块渲染（安卓 `_bashCommand()` 同口径）。
 */
export function bashCommandOf(name: string, rawArguments: string | null): string | null {
  if (name !== 'bash' && name !== 'tools.bash') {
    return null;
  }
  if (rawArguments === null || rawArguments.trim() === '') {
    return null;
  }
  const parsed: JsonMap | null = JsonAccess.asMap(JsonAccess.parse(rawArguments));
  if (parsed === null) {
    return null;
  }
  const cmd: string | null = JsonAccess.str(parsed, 'command');
  if (cmd === null || cmd.trim() === '') {
    return null;
  }
  return cmd;
}

/**
 * 参数 JSON 美化：逐行 `k: v`（值超 200 字截断）；非对象/解析失败返回原串。
 * 安卓 `_prettyArgs()` 同口径。
 */
export function prettyArguments(rawArguments: string | null): string | null {
  if (rawArguments === null || rawArguments.trim() === '') {
    return null;
  }
  const parsed: Object | null = JsonAccess.parse(rawArguments);
  const map: JsonMap | null = JsonAccess.asMap(parsed);
  if (map === null) {
    return rawArguments;
  }
  const out: string[] = [];
  const keys: string[] = Object.keys(map);
  for (const k of keys) {
    const v: Object = map[k];
    let text: string = typeof v === 'string' ? (v as string) : JSON.stringify(v);
    if (text.length > 200) {
      text = text.substring(0, 200) + '…';
    }
    out.push(k + ': ' + text);
  }
  return out.length === 0 ? null : out.join('\n');
}
