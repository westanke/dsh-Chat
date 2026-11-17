/**
 * bridge 协议模型（鸿蒙版）—— 移植自安卓版 app/lib/bridge/models.dart。
 * 形状依据 dsh-remote-bridge v2.10.0：docs/api/openapi.yaml、asyncapi.yaml、
 * docs/project/API.md 与姊妹仓 dsh-companion 的历史事件映射。
 *
 * 解析口径与安卓版的差异（PORT-MAP.md 决策 D1）：
 * 安卓版 `fromJson` 缺键给默认值、类型不符抛异常；这里沿用姊妹仓
 * 「宽容解析」口径——缺键 / 显式 null / 类型不符 → 一律退化默认值，绝不抛
 * （历史教训：协议文档标 required 的字段旧桥可能不下发）。所有字段都有默认值。
 *
 * 历史装配四件套（SessionEvent / DeliverableFile / ChatMessage / HistoryPage）
 * 在 History.ts（对应安卓 history_page.dart），消息内容块在 Content.ts。
 */

import { JsonAccess, JsonMap } from './JsonAccess';

/** ChatSession（openapi §ChatSession）。 */
export class DshSession {
  readonly id: string;
  readonly rootId: string;
  readonly updatedAt: number;
  readonly running: boolean;
  readonly blank: boolean;
  readonly title: string | null;
  readonly workspaceId: string | null;

  /** 所属工作区名（抽屉按它分组），空 = 「未分组」。 */
  readonly workspaceTitle: string | null;

  /** 会话工作目录绝对路径（手机端拼 @绝对路径 用）。 */
  readonly cwdAbsolute: string | null;

  /** 会话工作目录，授权根内相对路径；'' = 会话目录就是授权根本身。 */
  readonly cwd: string;

  /** 当前 Agent 预设 id（openapi §ChatSession.agentPreset；未设置/旧桥为 null）。 */
  readonly agentPreset: string | null;

  constructor(j: JsonMap | null) {
    this.id = JsonAccess.strOr(j, 'id', '');
    this.rootId = JsonAccess.strOr(j, 'rootId', '');
    this.updatedAt = JsonAccess.numOr(j, 'updatedAt', 0);
    this.running = JsonAccess.boolOr(j, 'running', false);
    this.blank = JsonAccess.boolOr(j, 'blank', false);
    this.title = JsonAccess.str(j, 'title');
    this.workspaceId = JsonAccess.str(j, 'workspaceId');
    this.workspaceTitle = JsonAccess.str(j, 'workspaceTitle');
    this.cwdAbsolute = JsonAccess.str(j, 'cwdAbsolute');
    this.cwd = JsonAccess.strOr(j, 'cwd', '');
    this.agentPreset = JsonAccess.str(j, 'agentPreset');
  }

  static fromJson(value: Object | null): DshSession {
    return new DshSession(JsonAccess.asMap(value));
  }

  static listFrom(values: Object[]): DshSession[] {
    const out: DshSession[] = [];
    for (let i = 0; i < values.length; i++) {
      out.push(new DshSession(JsonAccess.asMap(values[i])));
    }
    return out;
  }

  /** 抽屉/页头显示标题：title 非空用 title，否则 blank=新对话 / 会话 <id>。 */
  get displayTitle(): string {
    const t = this.title;
    if (t !== null && t.length > 0) {
      return t;
    }
    return this.blank ? '新对话' : `会话 ${this.id}`;
  }
}

/** ChatWorkspace（openapi §ChatWorkspace）。 */
export class DshWorkspace {
  readonly id: string;
  readonly title: string;
  readonly rootId: string;
  readonly path: string;

  constructor(j: JsonMap | null) {
    this.id = JsonAccess.strOr(j, 'id', '');
    this.title = JsonAccess.strOr(j, 'title', '');
    this.rootId = JsonAccess.strOr(j, 'rootId', '');
    this.path = JsonAccess.strOr(j, 'path', '');
  }

  static fromJson(value: Object | null): DshWorkspace {
    return new DshWorkspace(JsonAccess.asMap(value));
  }

  static listFrom(values: Object[]): DshWorkspace[] {
    const out: DshWorkspace[] = [];
    for (let i = 0; i < values.length; i++) {
      out.push(new DshWorkspace(JsonAccess.asMap(values[i])));
    }
    return out;
  }
}

/** 实时推送 chat.message.delta（asyncapi §ChatMessageDelta）。 */
export class MessageDelta {
  readonly sessionId: string;
  readonly turn: number;
  readonly step: number;
  readonly index: number;
  /** 'text' | 'reasoning' | 'tool-call' | 'tool-call-end'（bridge 宽容透传）。 */
  readonly kind: string;
  readonly text: string;
  /** kind='tool-call'/'tool-call-end'：工具 id（首包可能缺，调用方按 index 兜底）。 */
  readonly callId: string;
  /** kind='tool-call'：工具名（首包可能缺，调用方先用「工具调用」占位）。 */
  readonly name: string;
  /** kind='tool-call'：参数增量（拼到已有 argsRaw 后面）。 */
  readonly argumentsDelta: string;
  /** kind='tool-call-end'：定稿的完整 arguments。 */
  readonly arguments: string;

  constructor(d: JsonMap | null) {
    this.sessionId = JsonAccess.strOr(d, 'sessionId', '');
    this.turn = JsonAccess.numOr(d, 'turn', 0);
    this.step = JsonAccess.numOr(d, 'step', 0);
    this.index = JsonAccess.numOr(d, 'index', 0);
    this.kind = JsonAccess.strOr(d, 'kind', 'text');
    this.text = JsonAccess.strOr(d, 'text', '');
    this.callId = JsonAccess.strOr(d, 'callId', '');
    this.name = JsonAccess.strOr(d, 'name', '');
    this.argumentsDelta = JsonAccess.strOr(d, 'argumentsDelta', '');
    this.arguments = JsonAccess.strOr(d, 'arguments', '');
  }

  static fromJson(value: Object | null): MessageDelta {
    return new MessageDelta(JsonAccess.asMap(value));
  }
}

/** chat.tool.call 帧（工具开始执行；data=内核 event.data + base 字段）。 */
export class ToolCallEvent {
  readonly sessionId: string;
  readonly callId: string;
  readonly name: string;
  readonly arguments: string;

  constructor(d: JsonMap | null) {
    this.sessionId = JsonAccess.strOr(d, 'sessionId', '');
    this.callId = JsonAccess.strOr(d, 'callId', '');
    this.name = JsonAccess.strOr(d, 'name', '');
    this.arguments = JsonAccess.strOr(d, 'arguments', '');
  }

  static fromJson(value: Object | null): ToolCallEvent {
    return new ToolCallEvent(JsonAccess.asMap(value));
  }
}

/** chat.tool.result 帧（message.content[*].text 拼正文；error.code 内核失败分类）。 */
export class ToolResultEvent {
  readonly sessionId: string;
  /** message.toolCallId，缺了退 source.callId。 */
  readonly callId: string;
  readonly isError: boolean;
  readonly contentText: string;
  readonly errorName: string;
  readonly errorCode: string;

  constructor(d: JsonMap | null) {
    this.sessionId = JsonAccess.strOr(d, 'sessionId', '');
    const message: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(d, 'message'));
    let callId: string = '';
    let isError: boolean = false;
    let contentText: string = '';
    if (message !== null) {
      callId = JsonAccess.strOr(message, 'toolCallId', '');
      isError = JsonAccess.boolOr(message, 'isError', false);
      const content: Object[] = JsonAccess.arr(message, 'content');
      const parts: string[] = [];
      for (let i = 0; i < content.length; i++) {
        const block: JsonMap | null = JsonAccess.asMap(content[i]);
        if (block !== null && JsonAccess.strOr(block, 'type', '') === 'text') {
          const text: string = JsonAccess.strOr(block, 'text', '');
          if (text !== '') {
            parts.push(text);
          }
        }
      }
      contentText = parts.join('\n');
      if (callId === '') {
        const src: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(message, 'source'));
        callId = src === null ? '' : JsonAccess.strOr(src, 'callId', '');
      }
    }
    this.callId = callId;
    this.isError = isError;
    this.contentText = contentText;
    const error: JsonMap | null = JsonAccess.asMap(JsonAccess.raw(d, 'error'));
    this.errorName = error === null ? '' : JsonAccess.strOr(error, 'name', '');
    this.errorCode = error === null ? '' : JsonAccess.strOr(error, 'code', '');
  }

  static fromJson(value: Object | null): ToolResultEvent {
    return new ToolResultEvent(JsonAccess.asMap(value));
  }
}

/** 实时推送 chat.message.committed（asyncapi §ChatMessageCommitted）。 */
export class MessageCommitted {
  readonly sessionId: string;
  /** 'user' | 'assistant'。 */
  readonly role: string;
  readonly seq: number;
  readonly turn: number;
  readonly step: number;
  /**
   * 这条 assistant 消息是否带正文（bridge e08b6b5：内核在工具执行前先 settle
   * 一条只含 tool-call 块、无 text 块的 assistant/message，hasReplyContent=false）。
   * user/message 不带该键；老桥不带时按 true 兼容。
   */
  readonly hasReplyContent: boolean;

  constructor(d: JsonMap | null) {
    this.sessionId = JsonAccess.strOr(d, 'sessionId', '');
    this.role = JsonAccess.strOr(d, 'role', 'assistant');
    this.seq = JsonAccess.numOr(d, 'seq', 0);
    this.turn = JsonAccess.numOr(d, 'turn', 0);
    this.step = JsonAccess.numOr(d, 'step', 0);
    this.hasReplyContent = JsonAccess.boolOr(d, 'hasReplyContent', true);
  }

  static fromJson(value: Object | null): MessageCommitted {
    return new MessageCommitted(JsonAccess.asMap(value));
  }
}

/**
 * 新建会话的待定工作目录（2026-11-15 反馈「新建会话可选工作目录」）。
 * 发送首条消息前可选；rootId 空 = 首个授权根（session-create 语义），
 * cwd 是授权根内相对路径（WirePath），'' = 会话目录就是根。
 * label 仅 UI 显示（sheet 候选组装），协议层不解释。
 */
export class SessionLocation {
  readonly rootId: string | null;
  readonly cwd: string;
  readonly label: string;

  constructor(rootId: string | null, cwd: string, label: string) {
    this.rootId = rootId;
    this.cwd = cwd;
    this.label = label;
  }
}

/** file-list 应答条目（ws-files.ts handleFileList；openapi §FileEntry）。
 *  kind ∈ file|directory|symlink|other；目录选择浏览器只消费 directory。 */
export class DshFileEntry {
  readonly name: string;
  readonly path: string;
  readonly kind: string;

  constructor(j: JsonMap | null) {
    this.name = JsonAccess.strOr(j, 'name', '');
    this.path = JsonAccess.strOr(j, 'path', '');
    this.kind = JsonAccess.strOr(j, 'kind', 'file');
  }

  static fromJson(value: Object | null): DshFileEntry {
    return new DshFileEntry(JsonAccess.asMap(value));
  }

  static listFrom(values: Object[]): DshFileEntry[] {
    const out: DshFileEntry[] = [];
    for (let i = 0; i < values.length; i++) {
      out.push(new DshFileEntry(JsonAccess.asMap(values[i])));
    }
    return out;
  }
}

/** file-list 应答页（ws-files.ts 应答 data{rootId,...page}；openapi §DirectoryPage）。 */
export class DshDirectoryPage {
  readonly rootId: string;
  readonly path: string;
  readonly entries: DshFileEntry[];
  readonly nextCursor: string | null;

  constructor(j: JsonMap | null) {
    this.rootId = JsonAccess.strOr(j, 'rootId', '');
    this.path = JsonAccess.strOr(j, 'path', '');
    this.nextCursor = JsonAccess.str(j, 'nextCursor');
    this.entries = DshFileEntry.listFrom(JsonAccess.arr(j, 'entries'));
  }

  static fromJson(value: Object | null): DshDirectoryPage {
    return new DshDirectoryPage(JsonAccess.asMap(value));
  }
}

/**
 * session-waited 应答的 wait 体（DSH 0.2.2 session/wait，桥 API.md:791 /
 * openapi §waitChatSession；issue #1 适配）。REST 与 WS 两通道同构：
 * `{reason, state, output}` —— reason ∈ idle|input-required|timeout；
 * state 为唤醒时会话状态（cursor/active/queue/pendingInput）；
 * output 为等待期间观察到的事件（records/truncated）。
 */
export class SessionWaitResult {
  /** 结束原因：'idle'（静止）|'input-required'（有待输入）|'timeout'。 */
  readonly reason: string;

  /** 唤醒时的会话状态（字段随协议演进，宽容保留原始 map）。 */
  readonly state: JsonMap;

  /** 等待期间观察到的事件（records 事件帧数组，老→新；truncated 窗口截断）。 */
  readonly output: JsonMap;

  constructor(j: JsonMap | null) {
    this.reason = JsonAccess.strOr(j, 'reason', 'idle');
    // ArkTS 口径：不用 `?? {}`（无类型字面量），先声明空表再兜底（姊妹仓同款）。
    const emptyState: JsonMap = {};
    const emptyOutput: JsonMap = {};
    const stateMap: JsonMap | null = JsonAccess.obj(j, 'state');
    const outputMap: JsonMap | null = JsonAccess.obj(j, 'output');
    this.state = stateMap !== null ? stateMap : emptyState;
    this.output = outputMap !== null ? outputMap : emptyOutput;
  }

  static fromJson(value: Object | null): SessionWaitResult {
    return new SessionWaitResult(JsonAccess.asMap(value));
  }

  toJson(): JsonMap {
    return { reason: this.reason, state: this.state, output: this.output };
  }
}
