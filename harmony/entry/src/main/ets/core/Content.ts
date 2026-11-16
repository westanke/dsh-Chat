/**
 * 消息 content 的部件模型（鸿蒙版）—— 移植自安卓版 app/lib/bridge/content.dart。
 * 形状依据 dsh-remote-bridge v2.10.0：
 * - 文本/推理块：`{type:'text'|'reasoning', text}`（ChatHistoryMapping 同构）。
 * - 图片块（历史）：`{type:'image', attachment:{attachmentId:'sha256:<hex>'}}`
 *   —— 历史里只存引用不存字节（kernel-services.ts:54-58 注释）；发送时才是
 *   base64 内联的 PromptPart.image。
 * - 纯文本模型的图片交接（bridge attachments.ts handoffImagesForTextOnlyModel）：
 *   图片落工作区 `.dsh-images/<sha256>.<ext>`，消息文本留
 *   `[Image: source: <绝对路径>]` 占位。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { WireBuilder } from './Wire';

/** 历史消息里的图片引用（attachmentId，字节走 REST attachments 接口取）。 */
export class ContentImageRef {
  readonly attachmentId: string; // 形如 'sha256:<hex>'

  constructor(attachmentId: string) {
    this.attachmentId = attachmentId;
  }

  static fromJson(value: Object | null): ContentImageRef {
    const att = JsonAccess.obj(JsonAccess.asMap(value), 'attachment');
    const id = JsonAccess.str(att, 'attachmentId');
    return new ContentImageRef(id === null ? '' : id);
  }

  get isValid(): boolean {
    return this.attachmentId.length > 0;
  }
}

/** ContentParts.from 的产物：text+reasoning 文本与图片引用。 */
export class ContentParts {
  readonly text: string;
  readonly reasoning: string;

  /** content 数组里 type=image 的块（历史形状：attachment 引用，无字节）。 */
  readonly images: ContentImageRef[];

  constructor(text: string, reasoning: string, images: ContentImageRef[]) {
    this.text = text;
    this.reasoning = reasoning;
    this.images = images;
  }

  /**
   * 从 content（primitive / array）提取 text+reasoning 文本与图片引用，
   * 文本规则与 companion ChatHistoryMapping.contentTextParts 一致：
   * text 用 \n 拼接、reasoning 用 \n\n 拼接。
   */
  static from(content: Object | null): ContentParts {
    let text = '';
    let reasoning = '';
    const images: ContentImageRef[] = [];

    if (typeof content === 'string') {
      return new ContentParts(content as string, '', images);
    }
    const arr = Array.isArray(content) ? content as Object[] : [];
    for (let i = 0; i < arr.length; i++) {
      const block = JsonAccess.asMap(arr[i]);
      if (block === null) {
        continue;
      }
      const type = JsonAccess.strOr(block, 'type', '');
      if (type === 'image') {
        const ref = ContentImageRef.fromJson(block);
        if (ref.isValid) {
          images.push(ref);
        }
        continue;
      }
      const t = JsonAccess.str(block, 'text');
      if (t === null || t.length === 0) {
        continue;
      }
      if (type === 'reasoning') {
        reasoning += (reasoning.length === 0 ? '' : '\n\n') + t;
      } else {
        text += (text.length === 0 ? '' : '\n') + t;
      }
    }
    return new ContentParts(text, reasoning, images);
  }
}

/**
 * 图片交接占位符：`[Image: source: <绝对路径>]`，文件名是
 * `<sha256-hex>.<ext>`（bridge files.ts 校验格式 `^[0-9a-f]{64}\.[A-Za-z0-9]+$`）。
 * 从消息文本提取交接文件名（bare name）；没有占位符返回 null。
 * 手机端用这个名字走 REST GET /api/v1/image-handoff 取回字节显示。
 */
const HANDOFF_PATTERN =
  /\[Image: source: [^\]]*?([0-9a-f]{64}\.[A-Za-z0-9]+)\s*\]/;

export function handoffImageNameOf(text: string): string | null {
  const m = HANDOFF_PATTERN.exec(text);
  return m === null ? null : m[1];
}

/**
 * bridge 给「纯文本模型 + 图片」注入的说明段（整行，含 `[Image: source: …]` 那一行）：
 *
 *   🖼️ 图片 1「IMG_1657.png」（当前模型看不到图，已存到 .dsh-images/<hex>.png；
 *   要看图，请用识图工具打开下面那行的路径）
 *   [Image: source: /abs/…/<hex>.png]
 *
 * 这段是**给模型看的提示**，不该出现在用户气泡里（安卓 `chat_message_items.dart`
 * 只在气泡里显示原文 + 交接图，同样不显示这段）。剥离后气泡只剩用户真正打的字，
 * 图片本体由 `handoffRefOf(text)` 从原文本里取引用渲染。
 */
const IMAGE_NOTE_LINE_PREFIX = '🖼';

export function stripBridgeImageNote(text: string): string {
  if (text.indexOf('[Image: source:') < 0 && text.indexOf(IMAGE_NOTE_LINE_PREFIX) < 0) {
    return text;
  }
  // 逐行过滤：bridge 注入的说明是独立行（以 🖼 开头），交接占位是独立行
  // （`[Image: source: …]`）。两者都属于「给模型看的提示」，用户气泡不该显示。
  const lines: string[] = text.split('\n');
  const kept: string[] = [];
  for (const line of lines) {
    const t: string = line.trim();
    if (t.startsWith(IMAGE_NOTE_LINE_PREFIX) || t.startsWith('[Image: source:')) {
      continue;
    }
    kept.push(line);
  }
  return kept.join('\n').trim();
}

// ---- PromptPart（chat-adapter.ts 的发送侧判别联合）----

/**
 * 发送侧消息部件。ArkTS 禁止「对象 interface 联合 type」判别联合
 * （arkts-no-union-types），姊妹仓口径 = **单一扁平类 + type 字段分派**：
 * `toMap()` 按 type 只写该形态字段，编码结果与安卓版完全一致，且避开
 * ArkTS 的继承覆盖语法歧义（姊妹仓 ModelsEvents.ts:28-110 同款，已过真机）。
 */
export class PromptPart {
  static readonly TYPE_TEXT: string = 'text';
  static readonly TYPE_IMAGE: string = 'image';
  static readonly TYPE_FILE: string = 'file';

  type: string = PromptPart.TYPE_TEXT;
  /** text 形态：正文。 */
  text: string = '';
  /** image 形态：白名单 png/jpeg/webp/gif（核对见 ImageMediaType.ts）。 */
  mediaType: string = 'image/png';
  /** image 形态：base64 裸串。 */
  data: string = '';
  /** image 形态：可选文件名；null 时不发送该键（安卓 chat-adapter.ts:26-29）。 */
  name: string | null = null;
  /** file 形态：上传换来的回执 id。 */
  receiptId: string = '';

  static text(text: string): PromptPart {
    const p: PromptPart = new PromptPart();
    p.type = PromptPart.TYPE_TEXT;
    p.text = text;
    return p;
  }

  static image(mediaType: string, data: string, name: string | null = null): PromptPart {
    const p: PromptPart = new PromptPart();
    p.type = PromptPart.TYPE_IMAGE;
    p.mediaType = mediaType;
    p.data = data;
    p.name = name;
    return p;
  }

  static file(receiptId: string): PromptPart {
    const p: PromptPart = new PromptPart();
    p.type = PromptPart.TYPE_FILE;
    p.receiptId = receiptId;
    return p;
  }

  /**
   * 按 type **只写该形态的字段**，绝不夹带其它形态的键（姊妹仓教训：
   * encodeDefaults 曾悄悄丢 mediaType，这里显式保证「形态内字段一律写出」）。
   */
  toMap(): JsonMap {
    if (this.type === PromptPart.TYPE_IMAGE) {
      return new WireBuilder()
        .put('type', PromptPart.TYPE_IMAGE)
        .put('mediaType', this.mediaType)
        .put('data', this.data)
        .putNonBlank('name', this.name)
        .buildMap();
    }
    if (this.type === PromptPart.TYPE_FILE) {
      return new WireBuilder()
        .put('type', PromptPart.TYPE_FILE)
        .put('receiptId', this.receiptId)
        .buildMap();
    }
    return new WireBuilder()
      .put('type', PromptPart.TYPE_TEXT)
      .put('text', this.text)
      .buildMap();
  }

  toJsonString(): string {
    return JSON.stringify(this.toMap());
  }

  /** 便捷取 type（node 断言与 ets 判别共用）。 */
  static encodeArray(parts: PromptPart[]): string {
    const list: JsonMap[] = [];
    for (let i = 0; i < parts.length; i++) {
      list.push(parts[i].toMap());
    }
    return JSON.stringify(list);
  }
}

// ---- 斜杠命令（真机反馈 2026-11-04 第 3 项）----

/** bridge `commands` 帧应答 data.commands 单条。 */
export class SlashCommand {
  /** 裸名，如 'model'（去前导 /）。 */
  readonly name: string;
  readonly description: string;
  /** 需要参数时的提示（对应帧字段 `input`）。 */
  readonly inputHint: string | null;

  /** 内核命令定义 id（桥 v2.11.0 commands 帧新增）。 */
  readonly definitionId: string | null;

  /** 是否内置命令（桥 v2.11.0 commands 帧新增）。 */
  readonly builtin: boolean;

  constructor(j: JsonMap | null) {
    this.name = JsonAccess.strOr(j, 'name', '').replace(/^\//, '');
    this.description = JsonAccess.strOr(j, 'description', '');
    this.inputHint = JsonAccess.str(j, 'input');
    this.definitionId = JsonAccess.str(j, 'definitionId');
    this.builtin = JsonAccess.boolOr(j, 'builtin', false);
  }

  static fromJson(value: Object | null): SlashCommand {
    return new SlashCommand(JsonAccess.asMap(value));
  }

  /** 输入框里从 `/abc` 过滤本命令：前缀匹配。 */
  matchesQuery(q: string): boolean {
    return q.length === 0 ||
      this.name.toLowerCase().indexOf(q.toLowerCase()) === 0;
  }
}

/** 内置命令的 en/zh 别名（桥 v2.11.0 commands 帧 `builtinTokens`，帧级）。
 *  goal→目标、plan→计划、feedback→反馈、compact→压缩、permission→权限、export→导出。 */
export class BuiltinCommandTokens {
  readonly en: string;
  readonly zh: string;

  constructor(j: JsonMap | null) {
    this.en = JsonAccess.strOr(j, 'en', '');
    this.zh = JsonAccess.strOr(j, 'zh', '');
  }

  static fromJson(value: Object | null): BuiltinCommandTokens {
    return new BuiltinCommandTokens(JsonAccess.asMap(value));
  }
}

/** `commands` 帧应答收敛。 */
export class SlashCommandList {
  /** 全命令清单为空的面板占位（拉取失败路径复用：不报错）。 */
  static empty(): SlashCommandList {
    return new SlashCommandList([], new Map<string, BuiltinCommandTokens>());
  }

  readonly commands: SlashCommand[];

  /**
   * 键 = 命令裸名（goal/plan/...）。旧桥无此帧级字段 → 空表，中文过滤退化为仅前缀。
   * ArkTS 口径：动态键值映射用 Map（姊妹仓无 Record<string,类> 先例，不赌）。
   */
  readonly builtinTokens: Map<string, BuiltinCommandTokens>;

  constructor(
    commands: SlashCommand[],
    builtinTokens: Map<string, BuiltinCommandTokens>,
  ) {
    this.commands = commands;
    this.builtinTokens = builtinTokens;
  }

  static fromJson(value: Object | null): SlashCommandList {
    const data = JsonAccess.asMap(value);
    const raw = JsonAccess.arr(data, 'commands');
    const list: SlashCommand[] = [];
    for (let i = 0; i < raw.length; i++) {
      const item = JsonAccess.asMap(raw[i]);
      if (item !== null) {
        list.push(new SlashCommand(item));
      }
    }
    const tokens: Map<string, BuiltinCommandTokens> = new Map();
    const tokensRaw = JsonAccess.obj(data, 'builtinTokens');
    if (tokensRaw !== null) {
      const keys = Object.keys(tokensRaw);
      for (let i = 0; i < keys.length; i++) {
        const entry = JsonAccess.asMap(tokensRaw[keys[i]]);
        if (entry !== null) {
          tokens.set(keys[i], new BuiltinCommandTokens(entry));
        }
      }
    }
    return new SlashCommandList(list, tokens);
  }

  /**
   * 输入片段过滤命令（issue #1 命令面板本地化）：裸名前缀之外，内置命令
   * 再按 zh 别名前缀匹配（敲「目标」能过滤出 /goal）；en 别名同时参与
   * （敲中文输入法残留英文也命中）。空片段回全量（v1.0.11 教训：不截断）。
   */
  matching(q: string): SlashCommand[] {
    const t = q.trim();
    if (t.length === 0) {
      return this.commands.slice();
    }
    const lower = t.toLowerCase();
    const out: SlashCommand[] = [];
    for (let i = 0; i < this.commands.length; i++) {
      const c = this.commands[i];
      const tokens: BuiltinCommandTokens | undefined =
        this.builtinTokens.get(c.name);
      const zhHit = tokens !== undefined && tokens.zh.indexOf(t) === 0;
      const enHit =
        tokens !== undefined &&
        tokens.en.toLowerCase().indexOf(lower) === 0;
      if (c.matchesQuery(t) || zhHit || enHit) {
        out.push(c);
      }
    }
    return out;
  }
}

// ---- 输入框草稿解析 ----

/** parseSlashDraft 的产物：命令名片段 + 已敲的参数部分。 */
export interface SlashDraft {
  nameFragment: string;
  args: string;
}

/**
 * 输入框文本解析：`/` 开头视为斜杠命令草稿。
 * 返回 null = 非命令；匹配 bridge 命令名正则 `/^\/([a-z][a-z0-9_-]*)/`。
 *
 * 拆成两个必组正则而非「可选捕获组」：ArkTS/TS 对可选组取值 `m[3]` 的
 * undefined 比较不安全（TS2367 / arkts-strict-comparison），拆开语义逐条
 * 与安卓单正则等价（`/goal`、`/goal x`、`/goal  x`、`/goal `、`/goal:`）。
 */
const SLASH_DRAFT_PLAIN = /^\/([a-z][a-z0-9_-]*)$/;
const SLASH_DRAFT_WITH_ARGS = /^\/([a-z][a-z0-9_-]*)\s+(.*)$/;

export function parseSlashDraft(text: string): SlashDraft | null {
  if (text.indexOf('/') !== 0) {
    return null;
  }
  const plain = SLASH_DRAFT_PLAIN.exec(text);
  if (plain !== null) {
    return { nameFragment: plain[1], args: '' };
  }
  const withArgs = SLASH_DRAFT_WITH_ARGS.exec(text);
  if (withArgs === null) {
    // 只有 `/` 或非法片段（如 `/中文`）：给全量清单，参数为空。
    return { nameFragment: text.substring(1), args: '' };
  }
  return { nameFragment: withArgs[1], args: withArgs[2] };
}

/** parseAtMentionDraft 的产物：查询片段 + 替换区间（含 @，整段换成补全结果）。 */
export interface AtMentionDraft {
  query: string;
  start: number;
  end: number;
}

/**
 * 输入框 @ 文件引用解析（安卓仓第六轮反馈）：光标前最近的 `@路径片段`。
 * 返回 null = 当前没有 @ 草稿。@ 后到光标之间不允许出现空白（出现即
 * 视为上一个引用已结束）。
 */
export function parseAtMentionDraft(
  text: string,
  cursor: number,
): AtMentionDraft | null {
  if (cursor < 0 || cursor > text.length) {
    return null;
  }
  const head = text.substring(0, cursor);
  const at = head.lastIndexOf('@');
  if (at < 0) {
    return null;
  }
  const fragment = head.substring(at + 1);
  // @ 前若是词字符则多半是邮箱/普通文本，保守不触发，避免误弹面板。
  if (at > 0 && !atBoundary(head, at)) {
    return null;
  }
  if (/\s/.test(fragment)) {
    return null;
  }
  return { query: fragment, start: at, end: cursor };
}

/** @ 触发边界：@ 前必须是行首或空白/常用开括号，避免邮箱误触。 */
function atBoundary(head: string, at: number): boolean {
  const prev = head.charAt(at - 1);
  return prev === ' ' || prev === '\n' || prev === '\t' ||
    '（(【[「'.indexOf(prev) >= 0;
}
