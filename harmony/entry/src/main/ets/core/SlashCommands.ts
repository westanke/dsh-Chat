/**
 * 斜杠命令面板数据面 —— 对照安卓 `app/lib/bridge/slash_commands.dart`
 * （2026-11-21 对齐 dsh-go `app/lib/state/commands_state.dart`）。
 *
 * 面板三层来源（dsh-go 同口径）：
 * 1. 客户端功能：/new /model /export /features —— 本地执行，绝不上送服务端
 *    （服务端 executeCommand 只认内核命令，app 命令会 404 COMMAND_NOT_FOUND）；
 * 2. 宿主命令：桥 `commands` 帧，按 definitionId 换上 first-party 中文 face；
 * 3. 会话技能：内核 `skills/list`（`dshrb-v1` kernel-call），一条一个 `/name`。
 *
 * 文案真源：官方 Web `dsh-client-ui-commands` 的 zh 字典 + dsh-go `app_zh.arb`。
 * 纯逻辑（不 import @kit），node 直测。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { SlashCommand, SlashCommandKind } from './Content';

/** 内核技能目录端点（`dsh-api-session-controller` 的 `sessionSkillCatalog`）。 */
export const K_SKILLS_LIST: string = 'skills/list';

/** 技能目录可能比命令慢（要扫 skills 目录），单独给 20s。 */
export const SKILLS_LIST_TIMEOUT_MS: number = 20000;

/** 面板顺序：客户端功能在最上，first-party 按 dsh-go `_order`，其余按名字。 */
export const SLASH_ORDER: string[] = [
  'new', 'model', 'compact', 'permission', 'plan', 'goal', 'feedback',
  'export', 'features',
];

/** 宿主里隐藏的条目：export 用客户端自己的（dsh-go `_hiddenCommands`）。 */
export const HIDDEN_HOST: string[] = ['export'];

/** 一条 first-party 中文 face（名字 + 中文名 + 描述 + 参数占位）。 */
export class SlashFace {
  readonly name: string;
  readonly label: string;
  readonly description: string;
  readonly hint: string | null;

  constructor(name: string, label: string, description: string, hint: string | null) {
    this.name = name;
    this.label = label;
    this.description = description;
    this.hint = hint;
  }
}

/** definitionId → 中文 face（官方 zh 字典原文）。 */
function facesByDefinition(): Map<string, SlashFace> {
  const m: Map<string, SlashFace> = new Map<string, SlashFace>();
  m.set('@deepseek-ai/dsh-command-compact',
    new SlashFace('compact', '压缩', '压缩以上对话内容，腾出上下文', null));
  m.set('@deepseek-ai/dsh-permission-presets',
    new SlashFace('permission', '权限', '切换权限预设（沙箱模式与审批策略）', '<预设名>'));
  m.set('@deepseek-ai/dsh-plan-mode',
    new SlashFace('plan', '计划', '进入或退出计划模式', '[off | 要求]'));
  m.set('@deepseek-ai/dsh-command-goal',
    new SlashFace('goal', '目标', '设置或查看长期任务目标', '[目标 | clear | pause | resume]'));
  m.set('@deepseek-ai/dsh-command-feedback',
    new SlashFace('feedback', '反馈', '发送关于当前对话的反馈', '<内容>'));
  return m;
}

/** 裸名 → 中文 face（旧桥没有 definitionId 时的兜底）。 */
function facesByName(): Map<string, SlashFace> {
  const m: Map<string, SlashFace> = new Map<string, SlashFace>();
  const byDef: Map<string, SlashFace> = facesByDefinition();
  byDef.forEach((face: SlashFace): void => {
    m.set(face.name, face);
  });
  return m;
}

/** 客户端自己的四条功能命令（dsh-go `appSlashCommands` 同文案）。 */
export function appSlashCommands(): SlashCommand[] {
  return [
    SlashCommand.make('new', '新对话', '开始一个新对话', null, SlashCommandKind.App),
    SlashCommand.make('model', '模型', '切换模型与思考深度', null, SlashCommandKind.App),
    SlashCommand.make('export', '导出日志',
      '把这个对话的完整记录打包成 ZIP，分享或存到「下载」', null, SlashCommandKind.App),
    SlashCommand.make('features', '全部功能', '官方网页版每项功能的入口', null, SlashCommandKind.App),
  ];
}

/** 宿主命令中文化：按 definitionId 认领 face，认不到按名兜底，认不出原样返回。 */
export function localizeHostCommand(cmd: SlashCommand): SlashCommand {
  let face: SlashFace | null = null;
  if (cmd.definitionId !== null) {
    face = facesByDefinition().get(cmd.definitionId) ?? null;
  }
  if (face === null) {
    face = facesByName().get(cmd.name) ?? null;
  }
  if (face === null) {
    return cmd;
  }
  // 内核没声明参数就不硬加 hint（否则面板会提示一个不存在的参数位）。
  const hint: string | null = cmd.takesInput()
    ? (face.hint !== null ? face.hint : cmd.inputHint) : null;
  return SlashCommand.make(face.name, face.label, face.description, hint,
    SlashCommandKind.Host, cmd.whenToUse);
}

/** 宿主命令进面板前：(1) 去掉隐藏项 (2) 中文化。 */
export function paletteHostCommands(host: SlashCommand[]): SlashCommand[] {
  const out: SlashCommand[] = [];
  for (let i = 0; i < host.length; i++) {
    const cmd: SlashCommand = host[i];
    if (HIDDEN_HOST.indexOf(cmd.name) >= 0) {
      continue;
    }
    out.push(localizeHostCommand(cmd));
  }
  return out;
}

/** 解析 `skills/list` 的 `value`（`{skills:[…]}` 或裸数组）：坏条目跳过、不抛。 */
export function paletteSkillCommands(value: Object | null): SlashCommand[] {
  const out: SlashCommand[] = [];
  let raw: Object[] = [];
  if (Array.isArray(value)) {
    raw = value as Object[];
  } else {
    raw = JsonAccess.arr(JsonAccess.asMap(value), 'skills');
  }
  for (let i = 0; i < raw.length; i++) {
    const item: JsonMap | null = JsonAccess.asMap(raw[i]);
    const name: string | null = JsonAccess.str(item, 'name');
    if (name === null || name.length === 0) {
      continue;
    }
    const description: string = JsonAccess.strOr(item, 'description', '');
    const whenToUse: string | null = JsonAccess.str(item, 'whenToUse');
    // 技能的中文名就是裸名（技能没有本地化表，dsh-go 同口径）。
    out.push(SlashCommand.make(name, name, description, null,
      SlashCommandKind.Skill, whenToUse));
  }
  return out;
}

/** 三层合并：客户端功能 → 宿主 → 技能；同名先出现者胜，再按 SLASH_ORDER 稳定排序。
 *  `host` 应是已过 `paletteHostCommands` 的清单。 */
export function mergePaletteCommands(host: SlashCommand[], skills: SlashCommand[]): SlashCommand[] {
  const seen: Map<string, boolean> = new Map<string, boolean>();
  const merged: SlashCommand[] = [];
  const app: SlashCommand[] = appSlashCommands();
  const groups: SlashCommand[][] = [app, host, skills];
  for (let g = 0; g < groups.length; g++) {
    const list: SlashCommand[] = groups[g];
    for (let i = 0; i < list.length; i++) {
      const cmd: SlashCommand = list[i];
      if (seen.has(cmd.name)) {
        continue;
      }
      seen.set(cmd.name, true);
      merged.push(cmd);
    }
  }
  return sortPalette(merged);
}

/** 排序：SLASH_ORDER 内的按表，其余按名字（稳定：同键保原序）。 */
export function sortPalette(commands: SlashCommand[]): SlashCommand[] {
  const scored: number[] = [];
  for (let i = 0; i < commands.length; i++) {
    const at: number = SLASH_ORDER.indexOf(commands[i].name);
    scored.push(at >= 0 ? at : SLASH_ORDER.length + i);
  }
  const idx: number[] = [];
  for (let i = 0; i < commands.length; i++) {
    idx.push(i);
  }
  idx.sort((a: number, b: number): number => {
    if (scored[a] !== scored[b]) {
      return scored[a] - scored[b];
    }
    return a - b;
  });
  const out: SlashCommand[] = [];
  for (let i = 0; i < idx.length; i++) {
    out.push(commands[idx[i]]);
  }
  return out;
}

/** 匹配档位：0=裸名前缀 1=中文名前缀 2=包含 3=裸名子序列；-1=不中。 */
function matchRank(cmd: SlashCommand, q: string): number {
  const name: string = cmd.name.toLowerCase();
  const label: string = cmd.displayLabel().toLowerCase();
  if (name.indexOf(q) === 0) {
    return 0;
  }
  if (label !== name && label.indexOf(q) === 0) {
    return 1;
  }
  if (name.indexOf(q) >= 0 || label.indexOf(q) >= 0) {
    return 2;
  }
  // 子序列只对裸名（dsh-go 的 score 同口径；中文名做子序列会拖进一堆无关命令）。
  if (isSubsequence(q, name)) {
    return 3;
  }
  return -1;
}

/** q 的字符是否在 s 中按序出现（`gol` → goal）。 */
function isSubsequence(q: string, s: string): boolean {
  let at: number = 0;
  for (let i = 0; i < s.length && at < q.length; i++) {
    if (s.charAt(i) === q.charAt(at)) {
      at++;
    }
  }
  return at === q.length;
}

/** 按输入片段过滤（同分保序：面板顺序即排序结果）。 */
export function filterPaletteCommands(commands: SlashCommand[], query: string): SlashCommand[] {
  const q: string = query.trim().toLowerCase();
  if (q.length === 0) {
    return commands.slice();
  }
  const buckets: SlashCommand[][] = [[], [], [], []];
  for (let i = 0; i < commands.length; i++) {
    const rank: number = matchRank(commands[i], q);
    if (rank >= 0) {
      buckets[rank].push(commands[i]);
    }
  }
  const out: SlashCommand[] = [];
  for (let b = 0; b < buckets.length; b++) {
    for (let i = 0; i < buckets[b].length; i++) {
      out.push(buckets[b][i]);
    }
  }
  return out;
}

/** 精确解析一个令牌：裸名或中文名全等（`/目标` 也要认）。 */
export function resolvePaletteCommand(commands: SlashCommand[], token: string): SlashCommand | null {
  const t: string = token.trim();
  if (t.length === 0) {
    return null;
  }
  const low: string = t.toLowerCase();
  for (let i = 0; i < commands.length; i++) {
    const cmd: SlashCommand = commands[i];
    if (cmd.name.toLowerCase() === low) {
      return cmd;
    }
    if (cmd.displayLabel().toLowerCase() === low) {
      return cmd;
    }
  }
  return null;
}

/** `skills/list` 的唯一参数（内核要求包一层 `request`）。 */
export function skillsListArgs(sessionId: string): JsonMap {
  const inner: JsonMap = {};
  inner['sessionId'] = sessionId;
  const args: JsonMap = {};
  args['request'] = inner;
  return args;
}

/** 这条命令是不是客户端自己执行的（绝不能发给桥）。 */
export function isAppCommand(cmd: SlashCommand): boolean {
  return cmd.kind === SlashCommandKind.App;
}

// ---------------------------------------------------------------------------
// 输入解析 / 面板三态 / 点选 / 发送分流
//
// 这一段是 dsh-go `slash_palette.dart` + `commands_state.dart` 的逐条移植：
// 面板三态（候选 / 参数提示 / 不显示）、点选「插入或直接执行」、回车分流
// （普通消息 / 吃掉回车 / 执行整行 / 选中第一行）。只搬条目与文案是不够的。
// ---------------------------------------------------------------------------

/** 指令草稿：`/` 后的名字 + 名字之后的全部文本（含分隔空白）。 */
export class SlashDraft {
  readonly token: string;
  /** null = 还在打名字，尚未出现空白。 */
  readonly rest: string | null;

  constructor(token: string, rest: string | null) {
    this.token = token;
    this.rest = rest;
  }

  hasArgs(): boolean {
    return this.rest !== null;
  }
}

/** 把输入框内容解析成指令草稿；`/` 不是首个非空白字符时返回 null。 */
export function parseSlashInput(text: string): SlashDraft | null {
  const left: string = text.replace(/^\s+/, '');
  if (!left.startsWith('/')) {
    return null;
  }
  const m: RegExpMatchArray | null = left.match(/\s/);
  if (m === null) {
    return new SlashDraft(left.substring(1), null);
  }
  const at: number = left.indexOf(m[0]);
  return new SlashDraft(left.substring(1, at), left.substring(at));
}

/** 面板三态。 */
export enum PaletteKind {
  None = 'none',
  Matches = 'matches',
  Hint = 'hint',
}

/** 面板内容：kind 决定渲染哪种；matches 只在候选态有意义。 */
export class PaletteContent {
  readonly kind: PaletteKind;
  readonly matches: SlashCommand[];
  /** 已经打了半个名字（第一行就是回车会选中的那行）。 */
  readonly typed: boolean;
  /** 光标后面还有文本。 */
  readonly hasSuffix: boolean;
  /** 用户敲的片段，空列表时用于「没有匹配的命令 ‹片段›」。 */
  readonly query: string;
  /** 参数提示态的命令；其余态为 null。 */
  readonly command: SlashCommand | null;

  constructor(kind: PaletteKind, matches: SlashCommand[], typed: boolean,
    hasSuffix: boolean, query: string, command: SlashCommand | null) {
    this.kind = kind;
    this.matches = matches;
    this.typed = typed;
    this.hasSuffix = hasSuffix;
    this.query = query;
    this.command = command;
  }
}

export const PALETTE_NONE: PaletteContent = new PaletteContent(PaletteKind.None, [], false, false, '', null);

/** 当前输入该显示哪种面板（与 dsh-go `PaletteContent.of` 同判据）。 */
export function paletteContentOf(commands: SlashCommand[], text: string,
  caret: number): PaletteContent {
  const draft: SlashDraft | null = parseSlashInput(text);
  if (draft === null) {
    return PALETTE_NONE;
  }
  const at: number = Math.max(0, Math.min(caret, text.length));
  const suffix: string = text.substring(at);
  if (!draft.hasArgs()) {
    return new PaletteContent(PaletteKind.Matches,
      filterPaletteCommands(commands, draft.token), draft.token.length > 0,
      suffix.length > 0, draft.token, null);
  }
  const rest: string = draft.rest === null ? '' : draft.rest;
  // 已经有参数 / 光标后有字 / 多行草稿：这是在写内容，不是在挑命令。
  if (rest.trim().length > 0 || suffix.length > 0 || text.indexOf('\n') >= 0) {
    return PALETTE_NONE;
  }
  const command: SlashCommand | null = resolvePaletteCommand(commands, draft.token);
  if (command === null || !command.takesInput()) {
    return PALETTE_NONE;
  }
  return new PaletteContent(PaletteKind.Hint, [], false, false, '', command);
}

/** 补全结果：文本 + 光标位置。 */
export class SlashCompletion {
  readonly text: string;
  readonly caret: number;

  constructor(text: string, caret: number) {
    this.text = text;
    this.caret = caret;
  }
}

/** 点选这一行是「插入到输入框」还是「直接执行」。 */
export function slashPickInsertsText(cmd: SlashCommand, hasSuffix: boolean): boolean {
  return hasSuffix || cmd.kind === SlashCommandKind.Skill ||
    (cmd.kind === SlashCommandKind.Host && cmd.takesInput());
}

/** 点选后的输入框内容与光标位置；null = 这一行应当直接执行。 */
export function slashPickCompletion(commands: SlashCommand[], cmd: SlashCommand,
  text: string, caret: number): SlashCompletion | null {
  const leading: number = text.length - text.replace(/^\s+/, '').length;
  const at: number = Math.max(0, Math.min(caret, text.length));
  const full: SlashDraft | null = parseSlashInput(text);
  const end: number = (full !== null && resolvePaletteCommand(commands, full.token) !== null)
    ? leading + 1 + full.token.length
    : at;
  const suffix: string = text.substring(Math.max(0, Math.min(end, text.length)));
  if (!slashPickInsertsText(cmd, suffix.length > 0)) {
    return null;
  }
  const prefix: string = text.substring(0, leading) + '/' + cmd.name;
  const separator: string = (suffix.length === 0 || /^\s/.test(suffix)) ? '' : ' ';
  const out: string = prefix + separator + suffix;
  return new SlashCompletion(out, Math.max(0, Math.min(prefix.length + 1, out.length)));
}

/** 回车分流的结果。 */
export enum SlashSendKind {
  /** 普通消息。 */
  Message = 'message',
  /** 吃掉这次回车（只敲了一个 `/`）。 */
  Swallow = 'swallow',
  /** 交给宿主执行整行。 */
  Run = 'run',
  /** 选中候选第一行。 */
  Pick = 'pick',
}

export class SlashSend {
  readonly kind: SlashSendKind;
  readonly command: SlashCommand | null;
  readonly line: string;

  constructor(kind: SlashSendKind, command: SlashCommand | null, line: string) {
    this.kind = kind;
    this.command = command;
    this.line = line;
  }
}

/**
 * 面板关闭标记的复位规则（dsh-go `_resetSlashDismissal` 同判据）：
 * 离开斜杠输入、或重新敲成裸 `/`，就清掉关闭标记让面板再弹；否则跟着文本走。
 * 空串表示「没关过」（ArkTS 侧不用 null 状态）。
 */
export function resetSlashDismissalOn(dismissed: string, text: string): string {
  if (dismissed.length === 0) {
    return '';
  }
  const restarted: boolean = text.trim() === '/' && dismissed.trim() !== '/';
  return (parseSlashInput(text) === null || restarted) ? '' : text;
}

/** 回车发送时这一行是什么意思（dsh-go `_slashFor` 的判据）。 */
export function classifySlashSend(commands: SlashCommand[], text: string): SlashSend {
  const draft: SlashDraft | null = parseSlashInput(text);
  if (draft === null) {
    return new SlashSend(SlashSendKind.Message, null, '');
  }
  if (draft.token.length === 0 && !draft.hasArgs()) {
    return new SlashSend(SlashSendKind.Swallow, null, '');
  }
  const exact: SlashCommand | null = resolvePaletteCommand(commands, draft.token);
  if (exact !== null) {
    // 技能整行是消息：宿主从正文里加载技能，客户端不该当命令发（会 404）。
    if (exact.kind === SlashCommandKind.Skill) {
      return new SlashSend(SlashSendKind.Message, null, '');
    }
    const rest: string = draft.rest === null ? '' : draft.rest;
    return new SlashSend(SlashSendKind.Run, exact, '/' + exact.name + rest);
  }
  // 名字不认识但带了参数：多半是路径之类的正文。
  if (draft.hasArgs()) {
    return new SlashSend(SlashSendKind.Message, null, '');
  }
  const matches: SlashCommand[] = filterPaletteCommands(commands, draft.token);
  if (matches.length === 0) {
    return new SlashSend(SlashSendKind.Message, null, '');
  }
  return new SlashSend(SlashSendKind.Pick, matches[0], '');
}
