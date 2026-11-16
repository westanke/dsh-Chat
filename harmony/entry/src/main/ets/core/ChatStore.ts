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
import { DshSession, MessageCommitted, MessageDelta } from './Models';
import { GatewayClient } from './GatewayClient';
import { GatewayApi } from './GatewayApi';
import {
  GatewayEvent, GatewayEventType, GatewayState, RequestException,
} from './GatewayEvents';
import { ChatMessage, HistoryPage } from './HistoryPage';
import { ensureMobileWorkspace, oldestSeqOf, prepareSessionFor } from './MobileWorkspace';
import { SessionLocation } from './SessionLocation';
import { mergeOlderMessages } from './HistoryPage';
import { sessionTitleOf, deviceLabelOf, connectionLabelOf } from './ChatLabels';
import { PromptPart } from './Content';
import { DsImageRef } from './ImageRef';
import { ImageFetcher } from './ImageFetcher';
import { HitlStore } from './HitlStore';
import { runCommandIn, regenerateAtIn, cancelTurnIn, setPermissionIn } from './ChatActions';
import { ModelSelection, parseSelectModelReply } from './ModelsView';
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from './Questions';
import type { TimerBridge } from './Transport';

const HISTORY_MAX_MESSAGES: number = 200;
const TOOL_REFRESH_DEBOUNCE_MS: number = 800;

export class ChatStore {
  private gateway: GatewayClient;
  /** 网关 API（面板组件直连：models/命令/权限/REST roots/文档）。 */
  api: GatewayApi;
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

  // 切换中的会话 id（createSession 应答未落时收推送用；prepareSessionFor 写）
  pendingSessionId: string | null = null;
  mobileWorkspaceId: string | null = null;
  /**
   * 新建会话的待定工作目录 —— null = 落「手机会话」工作区（默认）；
   * 选中某授权根下目录后，首条消息走 session-create{rootId,cwd}。
   * 会话建好即清空（目录随会话定死，历史会话不受影响）。
   */
  pendingLocation: SessionLocation | null = null;
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

  changed(): void {
    if (this.notify !== null) {
      this.notify();
    }
  }

  get isEmpty(): boolean {
    return !this.streaming && this.messages.length === 0;
  }

  /** 当前会话标题（顶栏居中显示；新对话空串）。 */
  get sessionTitle(): string {
    return sessionTitleOf(this.sessions, this.sessionId);
  }

  /** 服务端设备信息（hello.device；设置页连接区只读展示）。 */
  getServerDevice(): JsonMap | null {
    return this.gateway.getServerDevice();
  }

  get deviceLabel(): string {
    return deviceLabelOf(this.gateway.getServerDevice());
  }

  get connectionState(): GatewayState {
    return this.gateway.getState();
  }

  get connectionLabel(): string {
    return connectionLabelOf(this.gateway.getBaseUrl());
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
    this.resetSessionView();
    this.gateway.subscribe(s.id);
    // REST 兜底拉一次挂起提问（含内核 continued）：WS replay 只补本桥前台挂起表，
    // 内核 continued（限时提问）只有 REST 看得到。fire-and-forget，失败静默
    //（打断换会话的代价大于漏一张兜底卡）。
    this.refreshPendingQuestions(s.id).catch((): void => {});
    return this.reloadHistory();
  }

  /**
   * REST 拉会话挂起提问并合流进挂起表（见 GatewayApi.fetchQuestions）。
   * 合流后必须自己 changed()：HitlStore 是纯数据类，没有通知通道，
   * UI 快照只由 ChatStore.changed() 驱动重抄（安卓靠 hitl.addListener）。
   */
  refreshPendingQuestions(sessionId: string): Promise<void> {
    if (sessionId === '') {
      return Promise.resolve();
    }
    return this.api.fetchQuestions(sessionId).then((list: PendingQuestion[]): void => {
      if (this.hitl.mergeQuestions(list)) {
        this.changed();
      }
    });
  }

  newChat(): void {
    this.sessionId = null;
    this.messages = [];
    this.resetSessionView();
    this.gateway.subscribe(null);
    this.changed();
  }

  /** 清屏公共段（切会话/新建共用）：原始事件/投影/翻页/流式/错误全清。 */
  private resetSessionView(): void {
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
  }

  /** 发送文本（阶段 2 纯文本；带图走阶段 4 PromptPart.image）。 */
  sendWithImage(text: string, image: PromptPart, mode: string = 'queue'): Promise<void> {
    return this.send(text, image);
  }

  send(text: string, imagePart?: PromptPart, mode: string = 'queue'): Promise<void> {
    const trimmed: string = text.trim();
    // 纯图无文字也允许发（图片是完整消息内容）；两者都空才忽略。
    if (trimmed === '' && imagePart === undefined) {
      return Promise.resolve();
    }
    this.lastError = null;
    const userMsg: ChatMessage = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = trimmed === '' ? '[图片]' : trimmed;
    this.messages = [...this.messages, userMsg];
    // busySendMode 由 Composer 传入（设置页写 dshBusySend）。
    if (!this.streaming) {
      this.streamText = '';
      this.streamReasoning = '';
    }
    this.streaming = true;
    this.changed();
    const self: ChatStore = this;
    return prepareSessionFor(this).then((): Promise<string> => {
      const sidArg: string | null = self.sessionId;
      const parts: JsonMap[] = imagePart === undefined ? [] : [imagePart.toMap()];
      return self.api.sendText(sidArg, trimmed, mode, parts);
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

  /** 图片字节拉取（缓存命中不请求；实现见 ImageFetcher）。 */
  private imageFetcher: ImageFetcher = new ImageFetcher();

  /** 取图片字节（缓存命中不请求；见 ImageFetcher）。 */
  fetchImageBytes(ref: DsImageRef): Promise<Uint8Array> {
    return this.imageFetcher.fetch(this.api, this.sessionId, ref);
  }

  /** 执行斜杠命令（实现见 ChatActions.runCommandIn）。 */
  runCommand(line: string): Promise<void> {
    return runCommandIn(this, line);
  }

  /** 重新生成（实现见 ChatActions.regenerateAtIn）。 */
  regenerateAt(index: number): Promise<void> {
    return regenerateAtIn(this, index);
  }

  /** 停止当前回合（实现见 ChatActions.cancelTurnIn）。 */
  cancelTurn(): Promise<void> {
    return cancelTurnIn(this);
  }

  /** 重拉当前会话历史（openSession / 事件防抖 / 停止后都会调）。 */
  reloadHistory(): Promise<void> {
    const id: string | null = this.sessionId;
    if (id === null || id === '') {
      return Promise.resolve();
    }
    const self: ChatStore = this;
    // 本地命令卡（role='command'，seq=-1）不在服务端历史里，会被整体替换冲掉 ——
    // 重灌回列表尾部（安卓 chat_history_actions.dart:36-40 同口径）。
    const localCards: ChatMessage[] = [];
    for (const m of this.messages) {
      if (m.role === 'command' && m.seq < 0) {
        localCards.push(m);
      }
    }
    return this.api.history(id, HISTORY_MAX_MESSAGES, 0).then((page: HistoryPage): void => {
      self.messages = localCards.length === 0 ? page.items : [...page.items, ...localCards];
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
      const merged: [ChatMessage[], JsonMap[], boolean] =
        mergeOlderMessages(self.messages, self.rawEvents, page.items, page.rawEvents);
      self.messages = merged[0];
      self.rawEvents = merged[1];
      if (merged[2]) {
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

  // ---- HITL（全连接挂起表；UI 只渲染当前会话条目）----

  private readonly hitl: HitlStore = new HitlStore();

  /** REST 探测出的挂起标记缓存（sessionId → 'question' | 'approval'）。 */
  private readonly pendingMarks: Map<string, string> = new Map<string, string>();

  /** 当前会话待答的提问（到达序）。 */
  get pendingQuestions(): PendingQuestion[] {
    return this.hitl.sessionQuestions(this.sessionId);
  }

  /** 当前会话待决的审批。 */
  get pendingApprovals(): PendingApproval[] {
    return this.hitl.sessionApprovals(this.sessionId);
  }

  /**
   * 从 REST 刷新「其它会话」的挂起标记（抽屉打开时调）。
   * 实时事件只覆盖当前连接的推送；非当前会话的挂起项可能在本连接建立前
   * 就已存在（bridge 不在 hello 后补推全部会话的 HITL 帧，实测 0 条），
   * 因此只能用 REST `/questions` + `/approvals` 逐会话探测。
   * 结果写进 pendingMarks（sessionId → 'question' | 'approval'）。
   */
  refreshPendingMarks(): Promise<void> {
    const list: DshSession[] = this.sessions;
    if (list.length === 0) {
      return Promise.resolve();
    }
    const jobs: Promise<void>[] = [];
    for (const s of list) {
      jobs.push(this.api.countPendingQuestions(s.id)
        .then((n: number): Promise<void> | void => {
          if (n > 0) {
            this.pendingMarks.set(s.id, 'question');
            return;
          }
          this.pendingMarks.delete(s.id);
          return this.api.countPendingApprovals(s.id).then((m: number): void => {
            if (m > 0) {
              this.pendingMarks.set(s.id, 'approval');
            } else {
              this.pendingMarks.delete(s.id);
            }
          }).catch((): void => {});
        })
        .catch((): void => {}));
    }
    return Promise.all(jobs).then((): void => {
      this.changed();
    });
  }

  /**
   * 会话抽屉用的「待处理标记」：全连接挂起表里属于该会话的条目。
   * bridge 的 sessions 列表只对**挂起审批**下发 pendingInteraction:'approval'，
   * 挂起提问不发（协议缺口），所以标记一律由本客户端挂起表推导，不看 REST 字段。
   * 返回 'question'（待回答）优先于 'approval'（待审批）——提问是阻塞用户输入的那类。
   */
  pendingMarkOf(sessionId: string): string {
    if (sessionId === '') {
      return '';
    }
    // 实时推送优先（本连接亲眼见过的事件最可信）。
    if (this.hitl.sessionQuestions(sessionId).length > 0) {
      return 'question';
    }
    if (this.hitl.sessionApprovals(sessionId).length > 0) {
      return 'approval';
    }
    // 退回 REST 探测缓存（非当前会话的挂起项不推送，只能查）。
    return this.pendingMarks.get(sessionId) ?? '';
  }

  /** 提交一套答案（question-answer 帧），成功即本地摘卡（HitlStore 持 api 动作）。 */
  answerQuestion(question: PendingQuestion, answers: QuestionAnswerItem[]): Promise<void> {
    return this.hitl.answerQuestion(this.api, question, answers).then((): void => {
      this.changed();
    });
  }

  /** 放弃一条提问（question-cancel）。continued 态取消会失败，卡片保留。 */
  cancelQuestion(question: PendingQuestion): Promise<void> {
    return this.hitl.cancelQuestion(this.api, question).then((): void => {
      this.changed();
    });
  }

  /** 切换权限档位（permission 帧；NO_SESSION 时调用方先提示）。 */
  setPermission(name: string): Promise<void> {
    return setPermissionIn(this, name);
  }

  /** 审批决定（allowed-once / rejected），成功即本地摘卡。 */
  decideApproval(approval: PendingApproval, allow: boolean): Promise<void> {
    return this.hitl.decideApproval(this.api, approval, allow).then((): void => {
      this.changed();
    });
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
    if (this.hitl.onEvent(event)) {
      this.changed();
    }
    return;
    // MODELS_UPDATED（模型列表变化）在阶段 4 模型切换接入。
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
  /** 当前会话权限档位 value（projections.values.permissions.currentValue；
   * 投影缺席/没有该条时为 null，UI 显示「权限」并可拉 permission-options）。 */
  get currentPermission(): string | null {
    const values: JsonMap | null = JsonAccess.obj(this.projections, 'values');
    if (values === null) {
      return null;
    }
    const perm: JsonMap | null = JsonAccess.obj(values, 'permissions');
    if (perm === null) {
      return null;
    }
    const v: string = JsonAccess.strOr(perm, 'currentValue', '');
    return v.length === 0 ? null : v;
  }

  /** 调整模型（select-model 帧；应答 data.type=='select-model' 带 selected）。 */
  selectModel(provider: string, model: string, effort: string | null): Promise<ModelSelection | null> {
    return this.api.selectModel(this.sessionId ?? '', provider, model, effort)
      .then((data: JsonMap): ModelSelection | null => {
        return parseSelectModelReply(data);
      });
  }

}
