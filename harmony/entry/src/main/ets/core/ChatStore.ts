/**
 * 会话状态容器 —— 对照 app/lib/ui/chat_state.dart + chat_history_actions.dart +
 * mobile_workspace.dart 移植（core 纯逻辑，node 直测）。
 *
 * 数据流：delta 累积流式 → committed 后重拉 history 保证顺序正确；
 * 实时流只有 eventType（无事件体），工具调用/外部写入靠 800ms 防抖重拉 history。
 * 阶段 2 范围：会话加载/切换/新建/发送/停止 + 历史翻页；HITL、命令卡、
 * 目录选择、消息操作在阶段 4 接入。
 */

import { JsonAccess, JsonMap } from './JsonAccess';
import { DshSession, DshWorkspace, MessageCommitted, MessageDelta } from './Models';
import { GatewayClient } from './GatewayClient';
import { GatewayApi } from './GatewayApi';
import {
  GatewayEvent, GatewayEventType, GatewayState, RequestException,
} from './GatewayEvents';
import { ChatMessage, HistoryPage } from './HistoryPage';
import type { TimerBridge } from './Transport';

const MOBILE_WORKSPACE_DIR: string = '.dsh-mobile';
const MOBILE_WORKSPACE_TITLE: string = '手机会话';
const HISTORY_MAX_MESSAGES: number = 200;
const TOOL_REFRESH_DEBOUNCE_MS: number = 800;

/** 已加载的最小 seq（下一页 beforeSeq）；null = 没有可翻页的消息。 */
export function oldestSeqOf(messages: ChatMessage[]): number | null {
  for (const m of messages) {
    if (m.seq >= 0) {
      return m.seq;
    }
  }
  return null;
}

/**
 * 找到或创建「手机会话」工作区：已知缓存 → title 含「手机」→ 在首个
 * 授权根下建 `.dsh-mobile`（幂等）+ REST 登记 + PATCH 改名。
 * 失败回 null（回落未分组，不阻断发送）。
 */
export function ensureMobileWorkspace(api: GatewayApi,
  cachedId: string | null): Promise<string | null> {
  if (cachedId !== null) {
    return Promise.resolve(cachedId);
  }
  return api.workspaces().then((workspaces: DshWorkspace[]): Promise<string | null> => {
    for (const w of workspaces) {
      if (w.title.indexOf('手机') >= 0) {
        return Promise.resolve(w.id);
      }
    }
    let rootId: string = '';
    for (const w of workspaces) {
      if (w.rootId !== '') {
        rootId = w.rootId;
        break;
      }
    }
    if (rootId === '') {
      return Promise.resolve(null); // 无授权根可见，放弃（不阻断发送）
    }
    return api.createDirectory(rootId, MOBILE_WORKSPACE_DIR)
      .catch((e: Error): void => {
        // 409 = 目录已存在（幂等），其余错误也继续试登记（登记幂等）。
      })
      .then((): Promise<string> => {
        return api.createWorkspaceRest(rootId, MOBILE_WORKSPACE_DIR);
      })
      .then((wsId: string): Promise<string | null> => {
        return api.renameWorkspaceRest(wsId, MOBILE_WORKSPACE_TITLE)
          .catch((e: Error): void => {
            // 名字不重要，继续。
          })
          .then((): Promise<string | null> => {
            return Promise.resolve(wsId);
          });
      })
      .catch((e: Error): Promise<string | null> => {
        return Promise.resolve(null); // 失败回落未分组，不阻断发送
      });
  }).catch((e: Error): Promise<string | null> => {
    return Promise.resolve(null);
  });
}

export class ChatStore {
  private gateway: GatewayClient;
  private api: GatewayApi;
  private timers: TimerBridge;

  sessionId: string | null = null;
  sessions: DshSession[] = [];
  messages: ChatMessage[] = [];
  streamText: string = '';
  streamReasoning: string = '';
  streaming: boolean = false;
  lastError: string | null = null;
  historyHasMore: boolean = false;
  loadingOlder: boolean = false;
  /** 翻页刚 prepend 过更早消息：列表层消费后清零，跳过一次贴底跟随。 */
  historyPageJustLoaded: boolean = false;
  rawEvents: JsonMap[] = [];
  projections: JsonMap | null = null;

  private pendingSessionId: string | null = null;
  private mobileWorkspaceId: string | null = null;
  private refreshScheduled: boolean = false;
  private notify: (() => void) | null = null;

  constructor(gateway: GatewayClient, api: GatewayApi, timers: TimerBridge) {
    this.gateway = gateway;
    this.api = api;
    this.timers = timers;
    const self: ChatStore = this;
    gateway.setEventListener((event: GatewayEvent): void => {
      self.onEvent(event);
    });
    gateway.setStateListener((state: GatewayState): void => {
      self.onGatewayState(state);
    });
  }

  /** UI 刷新钩子（每次状态变化后调用，UI 层置 @State 脏标记）。 */
  setNotify(fn: (() => void) | null): void {
    this.notify = fn;
  }

  private changed(): void {
    if (this.notify !== null) {
      this.notify();
    }
  }

  get isEmpty(): boolean {
    return !this.streaming && this.messages.length === 0;
  }

  /** 当前会话标题（顶栏居中显示；新对话空串）。 */
  get sessionTitle(): string {
    const id: string | null = this.sessionId;
    if (id === null || id === '') {
      return '';
    }
    for (const s of this.sessions) {
      if (s.id === id) {
        return s.displayTitle;
      }
    }
    return '';
  }

  /** 设备名（抽屉底部账号栏；hello.device.name 优先，兜底 'DSH Bridge'）。 */
  get deviceLabel(): string {
    const device: JsonMap | null = this.gateway.getServerDevice();
    if (device !== null) {
      const name: string = JsonAccess.strOr(device, 'name', '').trim();
      if (name !== '') {
        return name;
      }
    }
    return 'DSH Bridge';
  }

  /** 连接地址（去协议前缀，只留 host[:port]）。 */
  get connectionState(): GatewayState {
    return this.gateway.getState();
  }

  get connectionLabel(): string {
    const raw: string = this.gateway.getBaseUrl();
    const stripped: string = raw.replace(/^https?:\/\//, '').replace(/\/+$/, '');
    return stripped === '' ? raw : stripped;
  }

  // ------------------------------------------------------------------
  // 对外动作
  // ------------------------------------------------------------------

  loadSessions(): Promise<void> {
    return this.api.sessions().then((list: DshSession[]): void => {
      this.sessions = list;
      this.lastError = null;
      this.changed();
    }).catch((e: Error): void => {
      if (e instanceof RequestException) {
        this.lastError = '加载会话失败：' + e.message;
        this.changed();
        return;
      }
      throw e;
    });
  }

  openSession(s: DshSession): Promise<void> {
    this.sessionId = s.id;
    // 切会话先清空原始事件/投影/流式缓冲：防止上一会话内容串台
    //（流式残留会以流式气泡挂在新会话页尾部，安卓 2026-11-15 反馈教训）。
    this.rawEvents = [];
    this.projections = null;
    this.historyHasMore = false;
    this.loadingOlder = false;
    this.historyPageJustLoaded = false;
    this.streaming = false;
    this.streamText = '';
    this.streamReasoning = '';
    this.lastError = null;
    this.changed();
    this.gateway.subscribe(s.id);
    return this.reloadHistory();
  }

  newChat(): void {
    this.sessionId = null;
    this.messages = [];
    this.rawEvents = [];
    this.projections = null;
    this.historyHasMore = false;
    this.loadingOlder = false;
    this.historyPageJustLoaded = false;
    this.streaming = false;
    this.streamText = '';
    this.streamReasoning = '';
    this.lastError = null;
    this.gateway.subscribe(null);
    this.changed();
  }

  /** 发送文本（阶段 2 纯文本；带图走阶段 4 PromptPart.image）。 */
  send(text: string): Promise<void> {
    const trimmed: string = text.trim();
    if (trimmed === '') {
      return Promise.resolve();
    }
    this.lastError = null;
    const userMsg: ChatMessage = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = trimmed;
    this.messages = [...this.messages, userMsg];
    // 繁忙发送模式（阶段 2 固定 queue；steer 偏好随设置页在阶段 4 接入）。
    const mode: string = 'queue';
    if (!this.streaming) {
      this.streamText = '';
      this.streamReasoning = '';
    }
    this.streaming = true;
    this.changed();
    const self: ChatStore = this;
    return this.prepareSession().then((): Promise<string> => {
      const sidArg: string | null = self.sessionId;
      return self.api.sendText(sidArg, trimmed, mode, []);
    }).then((sid: string): void => {
      if (self.sessionId === null && sid !== '') {
        self.sessionId = sid;
        self.pendingSessionId = sid;
      }
      const current: string | null = self.sessionId;
      if (current !== null && current !== '') {
        self.gateway.subscribe(current);
      }
      self.changed();
    }).catch((e: Error): void => {
      self.streaming = false;
      if (e instanceof RequestException) {
        self.lastError = '发送失败：' + e.message;
        self.changed();
        return;
      }
      throw e;
    });
  }

  /** 停止当前回合：session-cancel + 立即收流式 + 重拉历史。 */
  cancelTurn(): Promise<void> {
    const id: string | null = this.sessionId;
    if (!this.streaming || id === null || id === '') {
      return Promise.resolve();
    }
    this.streaming = false;
    this.streamText = '';
    this.streamReasoning = '';
    this.lastError = null;
    this.changed();
    return this.api.cancelTurn(id).then((): Promise<void> => {
      return this.reloadHistory();
    }).catch((e: Error): void => {
      if (e instanceof RequestException) {
        this.lastError = '停止失败：' + e.message;
        this.changed();
        return;
      }
      throw e;
    });
  }

  /** 重拉当前会话历史（openSession / 事件防抖 / 停止后都会调）。 */
  reloadHistory(): Promise<void> {
    const id: string | null = this.sessionId;
    if (id === null || id === '') {
      return Promise.resolve();
    }
    const self: ChatStore = this;
    return this.api.history(id, HISTORY_MAX_MESSAGES, 0).then((page: HistoryPage): void => {
      self.messages = page.items;
      self.rawEvents = page.rawEvents;
      self.historyHasMore = page.hasMore;
      // 翻页/刷新时 projections 可能缺席：保留上一份（同会话），避免面板闪空。
      if (page.projections !== null) {
        self.projections = page.projections;
      }
      self.changed();
    }).catch((e: Error): void => {
      if (e instanceof RequestException) {
        self.lastError = '加载历史失败：' + e.message;
        self.changed();
        return;
      }
      throw e;
    });
  }

  /** 向上翻页：beforeSeq=当前最小 seq，结果 prepend 并按 seq 去重。 */
  loadOlder(): Promise<void> {
    const id: string | null = this.sessionId;
    if (id === null || id === '' || this.loadingOlder || !this.historyHasMore) {
      return Promise.resolve();
    }
    const before: number | null = oldestSeqOf(this.messages);
    if (before === null || before <= 0) {
      return Promise.resolve();
    }
    const self: ChatStore = this;
    this.loadingOlder = true;
    this.changed();
    return this.api.history(id, HISTORY_MAX_MESSAGES, before).then((page: HistoryPage): void => {
      if (self.sessionId !== id) {
        return; // 翻页期间切了会话：丢弃
      }
      const known: Map<number, boolean> = new Map();
      for (const m of self.messages) {
        if (m.seq >= 0) {
          known.set(m.seq, true);
        }
      }
      const fresh: ChatMessage[] = [];
      for (const m of page.items) {
        if (m.seq < 0 || !known.has(m.seq)) {
          fresh.push(m);
        }
      }
      if (fresh.length > 0) {
        self.messages = [...fresh, ...self.messages];
        self.rawEvents = [...page.rawEvents, ...self.rawEvents];
        self.historyPageJustLoaded = true;
      }
      self.historyHasMore = page.hasMore;
      self.changed();
    }).catch((e: Error): void => {
      if (e instanceof RequestException) {
        self.lastError = '加载更早消息失败：' + e.message;
        self.changed();
        return;
      }
      throw e;
    }).finally((): void => {
      self.loadingOlder = false;
      if (self.sessionId === id) {
        self.changed();
      }
    });
  }

  /** 翻页标记消费（列表层读后调用，跳过一次贴底跟随）。 */
  consumeHistoryPageJustLoaded(): boolean {
    if (this.historyPageJustLoaded) {
      this.historyPageJustLoaded = false;
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------------
  // 网关事件
  // ------------------------------------------------------------------

  private onGatewayState(state: GatewayState): void {
    if (state === GatewayState.READY) {
      // 断线重连成功：重拉会话与当前历史（resync 兜底）。
      this.loadSessions();
      this.reloadHistory();
    }
    this.changed();
  }

  private onEvent(event: GatewayEvent): void {
    if (event.type === GatewayEventType.DELTA) {
      const delta: MessageDelta | null = event.delta;
      if (delta === null || !this.isCurrent(delta.sessionId)) {
        return;
      }
      if (delta.kind === 'reasoning') {
        this.streamReasoning += delta.text;
      } else {
        this.streamText += delta.text;
      }
      this.streaming = true;
      this.changed();
      return;
    }
    if (event.type === GatewayEventType.COMMITTED) {
      const committed: MessageCommitted | null = event.committed;
      if (committed === null || !this.isCurrent(committed.sessionId)) {
        return;
      }
      if (committed.role === 'assistant') {
        this.streaming = false;
        this.streamText = '';
        this.streamReasoning = '';
        this.reloadHistory();
      } else {
        // 用户消息落库（本端已乐观上屏；别的端/REST 外部写入靠防抖重拉）。
        this.scheduleToolRefresh();
      }
      return;
    }
    if (event.type === GatewayEventType.TURN_FAILED) {
      if (!this.isCurrent(event.sessionId)) {
        return;
      }
      this.streaming = false;
      this.streamText = '';
      this.streamReasoning = '';
      this.lastError = event.message;
      this.changed();
      return;
    }
    if (event.type === GatewayEventType.RESYNC) {
      this.reloadHistory();
      return;
    }
    if (event.type === GatewayEventType.SESSION_EVENT) {
      if (!this.isCurrent(event.sessionId)) {
        return;
      }
      this.scheduleToolRefresh();
      return;
    }
    // QUESTION_* / APPROVAL_* / MODELS_UPDATED 在阶段 4 HITL 接入。
  }

  /** 800ms 防抖重拉（一轮 turn 事件很密，限流）。 */
  private scheduleToolRefresh(): void {
    if (this.refreshScheduled) {
      return;
    }
    const self: ChatStore = this;
    this.refreshScheduled = true;
    this.timers.schedule(TOOL_REFRESH_DEBOUNCE_MS, (): void => {
      self.refreshScheduled = false;
      self.reloadHistory();
    });
  }

  /** 未选会话（空态）时忽略一切推送（连接即重放的其它会话事件不串台）。 */
  private isCurrent(sid: string | null): boolean {
    const current: string | null = this.sessionId;
    if (current === null || current === '') {
      return false;
    }
    if (sid === null) {
      return false;
    }
    return sid === current || sid === this.pendingSessionId;
  }

  // ------------------------------------------------------------------
  // 手机工作区（mobile_workspace.dart 口径）
  // ------------------------------------------------------------------

  /** 首条消息前准备会话通道：目录选择（阶段 4）走 session-create{rootId,cwd}。 */
  private prepareSession(): Promise<void> {
    if (this.sessionId !== null) {
      return Promise.resolve();
    }
    const self: ChatStore = this;
    return ensureMobileWorkspace(this.api, this.mobileWorkspaceId)
      .then((wsId: string | null): Promise<void> => {
        if (wsId === null) {
          return Promise.resolve(); // 落 message 帧自动建（未分组）
        }
        return self.api.createSessionInWorkspace(wsId).then((sid: string): void => {
          self.mobileWorkspaceId = wsId;
          self.sessionId = sid;
          self.pendingSessionId = sid;
        }).catch((e: Error): void => {
          // 建会话失败不阻断发消息：退回 message 帧自动建（落未分组）。
        });
      });
  }
}
