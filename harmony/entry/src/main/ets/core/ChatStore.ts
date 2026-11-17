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
import { DshSession, MessageCommitted, MessageDelta, ToolCallEvent, ToolResultEvent } from './Models';
import { StreamToolState } from './StreamTools';
import {
  bumpStreamToolsIn, clearStreamToolsIn, afterLiveRowsIn,
  syncLiveRowsIntoMessagesIn, reattachLiveRowsIn,
} from './ChatStreamTools';
import { onEventIn } from './ChatEvents';
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
import { ChatWorkSteps, selectAgentPresetIn } from './ChatWorkSteps';
import { AgentPreset } from './AgentPresets';
import { runCommandIn, regenerateAtIn, cancelTurnIn, setPermissionIn } from './ChatActions';
import {
  refreshPendingMarksIn, pendingMarkOfIn, answerQuestionIn, cancelQuestionIn, decideApprovalIn,
} from './ChatHitl';
import { reloadHistoryIn, loadOlderIn } from './ChatHistory';
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
  /** turn.end reason=max-tokens 置位：列表尾提示「回答被截断…」（MessageList 渲染）。 */
  maxTokensNotice: boolean = false;
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
   * 工作步骤展示状态（通用设置四项的会话页面）：过程组展开集合、detail/timing
   * 档位、Agent 预设镜像。设置页写 AppStorage 后由 ChatView @Watch 抄进来；
   * 实现与测试见 ChatWorkSteps.ts（UI 层只渲染与转发）。
   */
  readonly workSteps: ChatWorkSteps = new ChatWorkSteps();
  /**
   * 新建会话的待定工作目录 —— null = 落「手机会话」工作区（默认）；
   * 选中某授权根下目录后，首条消息走 session-create{rootId,cwd}。
   * 会话建好即清空（目录随会话定死，历史会话不受影响）。
   */
  pendingLocation: SessionLocation | null = null;
  /**
   * 工具调用实时流（bridge chat.message.delta kind='tool-call'/'tool-call-end'
   * 与 chat.tool.call/chat.tool.result 四帧的行状态机，StreamTools.ts 纯逻辑）。
   * callId 去重、后到覆盖；reloadHistory 落库后若仍在流式则重新并入（兜底）。
   * 渲染：syncLiveRowsIntoMessages 并入运行中轮过程组（无组追加合成卡 seq=-1，
   * reload 整体替换时天然消失）；组件刷新走 streamToolsVersion → ChatView 写
   * AppStorage('dshStreamToolsVersion') 广播（LazyForEach 同 key 不重建的坑）。
   */
  streamTools: StreamToolState = new StreamToolState();
  streamToolsVersion: number = 0;
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
    this.maxTokensNotice = false;
    this.rawEvents = [];
    this.projections = null;
    this.historyHasMore = false;
    this.loadingOlder = false;
    this.historyPageJustLoaded = false;
    this.streaming = false;
    this.streamText = '';
    this.streamReasoning = '';
    this.lastError = null;
    // 展开集合与 Agent 预设镜像一并清（新会话新账；尾部 changed() 顺带刷 UI）。
    this.workSteps.resetSessionView();
    clearStreamToolsIn(this);
    this.changed();
  }

  /** reloadHistory 落库后重挂 live 行（实现见 ChatStreamTools.ts）。 */
  reattachLiveRows(): void {
    reattachLiveRowsIn(this);
  }

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
    // 收起时机 = 「下次有新消息时」：发送即收起当前展开的工作步骤组
    //（verbose 档永不自动收；completion 时机挂 COMMITTED assistant 分支）。
    this.workSteps.collapseOnSend();
    const userMsg: ChatMessage = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = trimmed === '' ? '[图片]' : trimmed;
    this.messages = [...this.messages, userMsg];
    // busySendMode 由 Composer 传入（设置页写 dshBusySend）。
    if (!this.streaming) {
      this.streamText = '';
      this.streamReasoning = '';
    }
    this.maxTokensNotice = false;
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

  /** 重拉当前会话历史（实现见 ChatHistory.ts）。 */
  reloadHistory(): Promise<void> {
    return reloadHistoryIn(this);
  }

  /** 向上翻页（实现见 ChatHistory.ts）。 */
  loadOlder(): Promise<void> {
    return loadOlderIn(this);
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

  // ---- HITL（实现见 ChatHitl.ts：全连接挂起表；UI 只渲染当前会话条目）----

  /** HITL 挂起表（ChatHitl 派生函数直接读；UI 不直接用）。 */
  readonly hitl: HitlStore = new HitlStore();

  /** REST 探测出的挂起标记缓存（sessionId → 'question' | 'approval'）。 */
  readonly pendingMarks: Map<string, string> = new Map<string, string>();

  /** 当前会话待答的提问（到达序）。 */
  get pendingQuestions(): PendingQuestion[] {
    return this.hitl.sessionQuestions(this.sessionId);
  }

  /** 当前会话待决的审批。 */
  get pendingApprovals(): PendingApproval[] {
    return this.hitl.sessionApprovals(this.sessionId);
  }

  /** 从 REST 刷新「其它会话」的挂起标记（抽屉打开时调，实现见 ChatHitl）。 */
  refreshPendingMarks(): Promise<void> {
    return refreshPendingMarksIn(this);
  }

  /** 会话抽屉用的「待处理标记」（实现见 ChatHitl）。 */
  pendingMarkOf(sessionId: string): string {
    return pendingMarkOfIn(this, sessionId);
  }

  /** 提交一套答案（question-answer 帧），成功即本地摘卡。 */
  answerQuestion(question: PendingQuestion, answers: QuestionAnswerItem[]): Promise<void> {
    return answerQuestionIn(this, question, answers);
  }

  /** 放弃一条提问（question-cancel）。continued 态取消会失败，卡片保留。 */
  cancelQuestion(question: PendingQuestion): Promise<void> {
    return cancelQuestionIn(this, question);
  }

  /** 切换权限档位（permission 帧；NO_SESSION 时调用方先提示）。 */
  setPermission(name: string): Promise<void> {
    return setPermissionIn(this, name);
  }

  /** 审批决定（allowed-once / rejected），成功即本地摘卡。 */
  decideApproval(approval: PendingApproval, allow: boolean): Promise<void> {
    return decideApprovalIn(this, approval, allow);
  }

  private onEvent(event: GatewayEvent): void {
    onEventIn(this, event);
  }

  /** 800ms 防抖重拉（一轮 turn 事件很密，限流）。 */
  scheduleToolRefresh(): void {
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
  isCurrent(sid: string | null): boolean {
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

  /**
   * 选 Agent 预设（代码工作视图第三段；实现见 ChatWorkSteps.selectAgentPresetIn）。
   * 200 返新 presetId；409 → RequestException('AGENT_PRESET_LOCKED') 由 UI 行内提示。
   */
  selectAgentPreset(presetId: string): Promise<string> {
    return selectAgentPresetIn(this, presetId);
  }

  /**
   * 拉 Agent 预设列表（代码工作视图第三段；GET /chat/agent-presets → items）。
   * 回填 workSteps 镜像并 changed()，UI 的 @Prop 快照随之刷新。
   */
  loadAgentPresets(): Promise<void> {
    return this.api.agentPresets().then((presets: AgentPreset[]): void => {
      this.workSteps.setAgentPresets(presets);
      this.changed();
    });
  }

}
