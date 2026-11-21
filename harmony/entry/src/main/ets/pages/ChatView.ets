/**
 * 对话页 —— 对照安卓 chat_page.dart 阶段 2 基础版：
 * 顶栏（菜单/标题/新建）+ 空态问候 + 消息列表 + 输入条 + 会话抽屉（覆盖式）。
 * HITL 问答卡 / 顶栏溢出菜单（统计/轨迹/团队/TODO/模型）/ 推挤式抽屉动画 /
 * 返回键退出确认是阶段 4（PORT-MAP ☐）。
 * 状态驱动：ChatStore.changed() 递增 this.version（@State），build 直读 store。
 */

import { ChatStore } from '../core/ChatStore';
import {
  BP_SM, drawerWidth, drawerFraction, floatingColumnWidth, readableColumnWidth,
  windowClassOf, reflowsOnDrawer, pageInsetFor, windowSidebarWidth
} from '../core/Breakpoints';
import { GatewayState } from '../core/GatewayEvents';
import { DshSession } from '../core/Models';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MessageList } from '../components/MessageList';
import { Composer } from '../components/Composer';
import { TodoDock } from '../components/TodoDock';
import { ChatTopBar } from '../components/ChatTopBar';
import { HitlPanel } from '../components/HitlPanel';
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from '../core/Questions';
import { SessionsDrawer } from '../components/SessionsDrawer';
import { SessionLocationSheet } from '../components/SessionLocationSheet';
import { SessionLocation, locationChipLabel } from '../core/SessionLocation';
import { ModelSheet } from '../components/ModelSheet';
import { StatsSheet, TrajectorySheet } from '../components/ProjectionSheets';
import { TeamSheet, TodoSheet } from '../components/ProjectionTeamSheets';
import { SubagentRow } from '../core/Projections';
import { SubagentHistoryPage } from './SubagentHistoryPage';
import { ChatOverflowMenu } from '../components/ChatOverflowMenu';
import { CodeWorkSheet } from '../components/CodeWorkSheet';

@Component
export struct ChatView {
  store: ChatStore | null = null;
  onExit: (() => void) | null = null;
  onOpenSettings: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点（@StorageProp 由 Index 的 mediaquery 写）：抽屉宽度/推挤比例按档。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  @State version: number = 0;
  /**
   * 空态/标题快照。ArkUI 的 if 分支只按 @State/@Prop 依赖求值：store 是普通成员，
   * 它的 messages 变化不会让 `if (this.isEmpty())` 重新判定，页面会永远停在初始
   * 分支（真机现象：version 已涨到 73、messages=2，界面仍只显示空态问候）。
   * 故把 store 派生值在 notify 里同步到 @State。
   */
  @State emptyView: boolean = true;
  @State titleView: string = '';
  /** HITL 挂起卡快照（直读 store 普通成员不会触发重渲染，同 @Prop 观察铁律）。 */
  @State questionsView: PendingQuestion[] = [];
  @State approvalsView: PendingApproval[] = [];
  @State drawerOpen: boolean = false;
  /**
   * 会话页实测可用宽（vp）：onAreaChange 量到后写 AppStorage，正文列 / 顶栏 / 输入条 /
   * HITL 各自 @StorageProp 读它算列宽（readableColumnWidth）。0 = 还没量到，约束退 100%。
   */
  @StorageProp('dshColumnWidthVp') columnWidth: number = 0;
  /** 新建会话工作目录面板（空态 chip 打开）。 */
  @State locSheet: boolean = false;
  /** store.pendingLocation 的快照（ArkUI 只观察 build 里读到的 @State）。 */
  @State pendingLocView: SessionLocation | null = null;
  @State menuOpen: boolean = false;
  /** 窗口尺寸（vp）：决定 compact/medium/expanded 三档与抽屉是否改为缩窄页面。 */
  @State winW: number = 0;
  @State winH: number = 0;
  @State statsSheet: boolean = false;
  @State trajectorySheet: boolean = false;
  @State teamSheet: boolean = false;
  /** 子会话只读历史（团队面板点行进入；安卓 SubagentHistoryPage 口径）。 */
  @State subagentOpen: boolean = false;
  @State subagentView: SubagentRow = new SubagentRow();
  @State subagentLead: string = '';
  @State todoSheet: boolean = false;
  @State modelSheet: boolean = false;
  /** 代码工作视图（通用设置④开启后出现在溢出菜单）。 */
  @State codeWorkSheet: boolean = false;
  /**
   * 「显示代码工作视图」档（通用设置④，官方 token '1'|'0'；Index 异步装载）。
   * 关闭时溢出菜单不出现该入口。
   */
  @StorageProp('dshCodeWorkView') codeWorkViewProp: string = '0';

  /**
   * 抽屉推挤位移（R007 一多）：手机上推 80%（安卓同口径，抽屉占 80% 屏宽），
   * 大屏抽屉定宽后按「抽屉宽 / 屏宽」换算，避免推挤过头露出空白。
   */
  private drawerShift(): string {
    const fraction: number = drawerFraction(this.bp);
    return (fraction * 100).toFixed(0) + '%';
  }

  /** 宽窗抽屉：缩窄页面（安卓 Padding(left: pageInsetFor) 口径）。 */
  private reflow(): boolean {
    return this.winW > 0 && reflowsOnDrawer(windowClassOf(this.winW, this.winH));
  }

  private pageInset(): number {
    if (!this.reflow() || !this.drawerOpen) {
      return 0;
    }
    return pageInsetFor(this.winW, windowClassOf(this.winW, this.winH));
  }

  private drawerPanelWidth(): number {
    if (this.reflow()) {
      return windowSidebarWidth(windowClassOf(this.winW, this.winH));
    }
    return drawerWidth(this.bp);
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  aboutToAppear(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    st.setNotify((): void => {
      // 贴底时机由 MessageList 的 List scroller 处理，这里只驱动重渲染。
      this.version += 1;
      this.emptyView = st.isEmpty;
      this.syncPendingLoc();
      this.titleView = st.sessionTitle;
      this.questionsView = st.pendingQuestions;
      this.approvalsView = st.pendingApprovals;
      // 工作步骤展开集合版本：ProcessGroup 靠这个 @StorageProp @Watch 回读
      // store.workSteps 的展开状态（LazyForEach 同 key 不重建，@Prop 链路不通）。
      // snapshotExpanded().version 是自增计数，保证 @Watch 只在真变化时触发。
      AppStorage.setOrCreate('dshExpandedVersion', st.workSteps.snapshotExpanded().version);
      // 工具调用实时流版本：ProcessGroup/ToolBlock 靠这个 @StorageProp @Watch
      // 重读就地 mutate 的流式行（同 key 不重建坑，同上广播链路）。
      AppStorage.setOrCreate('dshStreamToolsVersion', st.streamToolsVersion);
      st.consumeHistoryPageJustLoaded();
    });
    // 首帧快照（重连/复用组件时 store 可能已就绪）。
    this.emptyView = st.isEmpty;
    this.titleView = st.sessionTitle;
    this.questionsView = st.pendingQuestions;
    this.approvalsView = st.pendingApprovals;
    st.loadSessions();
  }

  build() {
    Stack() {
      // 推挤式抽屉（官方口径，docs/design-tokens.md §4.2）：抽屉打开时聊天页整体
      // 右移一个抽屉宽度，页面右缘与抽屉右缘齐平停到屏外；浅色无灰幕，深色淡遮罩。
      // 覆盖式会让抽屉右缘漏出输入框一角（真机截图实证），故按官方做推挤。
      Column() {
        this.chatScaffold()
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.pageInset() })
      .translate({ x: this.reflow() ? 0 : (this.drawerOpen ? this.drawerShift() : 0) })
      // 动效取官方档位 200ms（R017 档位 100/150/200/300/350）。
      .animation({ duration: 200, curve: Curve.EaseOut })
      if (this.drawerOpen) {
        // 遮罩（浅色官方无灰幕，深色淡遮罩；点按关闭）。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.c().drawerScrim)
          .accessibilityText('关闭菜单')
          .onClick(() => {
            this.drawerOpen = false;
          })
        SessionsDrawer({
          store: this.store,
          panelWidth: this.drawerPanelWidth(),
          onClose: (): void => {
            this.drawerOpen = false;
          }, onOpenSettings: (): void => {
            if (this.onOpenSettings !== null) {
              this.onOpenSettings();
            }
          }
        })
      }
      // 溢出菜单：Stack 内联 overlay（bindContentCover 与 bindSheet 同挂一个节点
      // 时不生效，2026-11-16 真机实证；遮罩点按关闭，同会话抽屉口径）。
      if (this.menuOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.c().drawerScrim)
          .accessibilityText('关闭菜单')
          .onClick(() => {
            this.menuOpen = false;
          })
        ChatOverflowMenu({
          codeWorkView: this.codeWorkViewProp,
          onClose: (): void => {
            this.menuOpen = false;
          }, onStats: (): void => {
            this.statsSheet = true;
          }, onTrajectory: (): void => {
            this.trajectorySheet = true;
          }, onCodeWork: (): void => {
            const st: ChatStore | null = this.store;
            if (st !== null) {
              st.loadAgentPresets().catch((): void => {
                // 预设列表拉取失败不拦入口：sheet 内空态兜底。
              });
            }
            this.codeWorkSheet = true;
          }, onTeam: (): void => {
            this.teamSheet = true;
          }, onTodo: (): void => {
            this.todoSheet = true;
          }, onModel: (): void => {
            this.modelSheet = true;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
    .alignContent(Alignment.Start)
    .bindContentCover(this.subagentOpen, this.subagentCover(), {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.subagentOpen = false;
      }
    })
  }

  @Builder
  chatScaffold() {
    Column() {
      this.topBar()
      // HITL 挂起面板（提问/审批；无挂起项不占空间；限高屏 50% 可滚动）
      if (!this.emptyView) {
        HitlPanel({
          questions: this.questionsView,
          approvals: this.approvalsView,
          onAnswer: (q: PendingQuestion, answers: QuestionAnswerItem[]): void => {
            if (this.store !== null) {
              this.store.answerQuestion(q, answers).catch((): void => {});
            }
          },
          onDecide: (a: PendingApproval, allow: boolean): void => {
            if (this.store !== null) {
              this.store.decideApproval(a, allow).catch((): void => {});
            }
          },
        })
      }
      if (this.emptyView) {
        this.greeting()
      } else {
        MessageList({
          store: this.store, version: this.version
        })
      }
      TodoDock({ store: this.store, version: this.version })
      Composer({
        store: this.store, version: this.version
      })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldV: Area, newV: Area) => {
      // 抽屉是 translate 推挤、不改本 Column 的宽，所以这里量的就是可用宽。
      // Area.width 静态类型是 Length，typeof 收窄成 vp 数值（ArkTS 不许 number↔string 强转）。
      const raw = newV.width;
      let w = 0;
      if (typeof raw === 'number') { w = raw; } else if (typeof raw === 'string') { w = parseFloat(raw); }
      const rawH = newV.height;
      let h = 0;
      if (typeof rawH === 'number') { h = rawH; } else if (typeof rawH === 'string') { h = parseFloat(rawH); }
      if (w > 0) { this.winW = w; }
      if (h > 0) { this.winH = h; }
      if (w > 0 && Math.abs(w - this.columnWidth) >= 1) { AppStorage.setOrCreate('dshColumnWidthVp', w); }
    })
    .bindSheet(this.sheetOpen(), this.sheetContent(), {
      height: this.sheetHeight(), showClose: true, title: { title: this.sheetTitle() },
      preferType: SheetType.BOTTOM, onDisappear: (): void => {
        this.statsSheet = false;
        this.trajectorySheet = false;
        this.teamSheet = false;
        this.todoSheet = false;
        this.modelSheet = false;
        this.locSheet = false;
        this.codeWorkSheet = false;
      }
    })
  }

  private sheetOpen(): boolean {
    return this.statsSheet || this.trajectorySheet || this.teamSheet || this.todoSheet
      || this.modelSheet || this.locSheet || this.codeWorkSheet;
  }

  private sheetTitle(): string {
    if (this.statsSheet) {
      return '会话统计';
    }
    if (this.trajectorySheet) {
      return '运行轨迹';
    }
    if (this.teamSheet) {
      return '智能团队';
    }
    if (this.todoSheet) {
      return '任务';
    }
    if (this.modelSheet) {
      return '调整模型';
    }
    if (this.locSheet) {
      return '会话工作目录';
    }
    if (this.codeWorkSheet) {
      return '代码工作视图';
    }
    return '';
  }

  private sheetHeight(): SheetSize {
    if (this.modelSheet) {
      return SheetSize.MEDIUM;
    }
    return SheetSize.LARGE;
  }


  /** 子会话历史全屏页（只读，无输入条）。 */
  @Builder
  subagentCover() {
    SubagentHistoryPage({
      store: this.store,
      leadSessionId: this.subagentLead,
      subagent: this.subagentView,
      onBack: (): void => {
        this.subagentOpen = false;
      }
    })
  }

  /** bindSheet 内容（按当前 sheet 分派；骨架已内联在各组件）。 */
  @Builder
  sheetContent() {
    Column() {
    if (this.statsSheet) {
      StatsSheet({ store: this.store, version: this.version })
    } else if (this.trajectorySheet) {
      TrajectorySheet({ store: this.store })
    } else if (this.teamSheet) {
      TeamSheet({
        store: this.store,
        onOpenSubagent: (s: SubagentRow): void => {
          const st: ChatStore | null = this.store;
          this.subagentLead = st === null ? '' : (st.sessionId ?? '');
          this.subagentView = s;
          this.teamSheet = false;
          this.subagentOpen = true;
        }
      })
    } else if (this.todoSheet) {
      TodoSheet({ store: this.store })
    } else if (this.modelSheet) {
      ModelSheet({
        store: this.store, onDone: (): void => {
          this.modelSheet = false;
        }
      })
    } else if (this.locSheet) {
      SessionLocationSheet({
        store: this.store, current: this.pendingLocView,
        onClose: (): void => {
          this.locSheet = false;
          this.syncPendingLoc();
        }
      })
    } else if (this.codeWorkSheet) {
      CodeWorkSheet({ store: this.store })
    }
    }
    .width('100%')
    .constraintSize({ maxWidth: this.winW >= 600 ? readableColumnWidth(this.winW) : '100%' })
  }

  private isEmpty(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.isEmpty;
  }

  private ready(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  /** 顶栏两行（dsh-go 结构），实现见 components/ChatTopBar.ets。 */
  @Builder
  topBar() {
    ChatTopBar({
      title: this.title(),
      state: this.store === null ? GatewayState.IDLE : this.store.connectionState,
      streaming: this.store !== null && this.store.streaming,
      waitingApproval: this.approvalsView.length > 0,
      waitingAnswer: this.questionsView.length > 0,
      hostLabel: this.store === null ? '' : this.store.connectionLabel,
      onOpenDrawer: (): void => {
        this.drawerOpen = true;
      },
      onNewChat: (): void => {
        const st: ChatStore | null = this.store;
        if (st !== null) {
          st.newChat();
        }
      },
      onMenu: (): void => {
        this.menuOpen = true;
      }
    })
  }

  private title(): string {
    return this.titleView;
  }

  /** 空态问候（品牌标 + 问候语；工作目录 chip 阶段 4）。 */
  @Builder
  greeting() {
    Column({ space: 14 }) {
      Text('DSH')
        .fontSize(38)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().brand)
      Text('嗨！今天想聊些什么？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().labelPrimary)
      Text(this.greetingHost())
        .fontSize(12)
        .fontColor(this.c().labelTertiary)
      // 工作目录选择（对照安卓空态「工作目录」chip）：默认手机会话，
      // 发首条消息前可换成授权根下的指定目录；建好后随会话定死。
      Row({ space: 6 }) {
        Text(this.pendingLocView === null ? '📱' : '📁')
          .fontSize(12)
        Text(locationChipLabel(this.pendingLocView))
          .fontSize(12)
          .fontColor(this.c().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('⌄')
          .fontSize(12)
          .fontColor(this.c().labelTertiary)
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.c().bgLayer1)
      .border({ width: 1, color: this.c().inputBorder })
      .constraintSize({ maxWidth: 300 })
      .margin({ top: 4 })
      .accessibilityText('工作目录：' + locationChipLabel(this.pendingLocView))
      .onClick(() => {
        this.syncPendingLoc();
        this.locSheet = true;
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** store.pendingLocation → @State 快照（普通成员变更不触发重渲染）。 */
  private syncPendingLoc(): void {
    const st: ChatStore | null = this.store;
    this.pendingLocView = st === null ? null : st.pendingLocation;
  }

  private greetingHost(): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '';
    }
    const label: string = st.deviceLabel;
    return label === '' ? st.connectionLabel : label;
  }
}
