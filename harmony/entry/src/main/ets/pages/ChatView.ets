/**
 * 对话页 —— 对照安卓 chat_page.dart 阶段 2 基础版：
 * 顶栏（菜单/标题/新建）+ 空态问候 + 消息列表 + 输入条 + 会话抽屉（覆盖式）。
 * HITL 问答卡 / 顶栏溢出菜单（统计/轨迹/团队/TODO/模型）/ 推挤式抽屉动画 /
 * 返回键退出确认是阶段 4（PORT-MAP ☐）。
 * 状态驱动：ChatStore.changed() 递增 this.version（@State），build 直读 store。
 */

import { ChatStore } from '../core/ChatStore';
import { GatewayState } from '../core/GatewayEvents';
import { DshSession } from '../core/Models';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MessageList } from '../components/MessageList';
import { Composer } from '../components/Composer';
import { HitlPanel } from '../components/HitlPanel';
import { PendingQuestion, PendingApproval, QuestionAnswerItem } from '../core/Questions';
import { SessionsDrawer } from '../components/SessionsDrawer';
import { ModelSheet } from '../components/ModelSheet';
import { StatsSheet, TrajectorySheet, TeamSheet, TodoSheet } from '../components/ProjectionSheets';

@Component
export struct ChatView {
  store: ChatStore | null = null;
  onExit: (() => void) | null = null;
  onOpenSettings: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
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
  @State menuOpen: boolean = false;
  @State statsSheet: boolean = false;
  @State trajectorySheet: boolean = false;
  @State teamSheet: boolean = false;
  @State todoSheet: boolean = false;
  @State modelSheet: boolean = false;

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
      this.titleView = st.sessionTitle;
      this.questionsView = st.pendingQuestions;
      this.approvalsView = st.pendingApprovals;
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
      this.chatScaffold()
      if (this.drawerOpen) {
        // 遮罩（浅色官方无灰幕，深色淡遮罩；点按关闭）。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.c().drawerScrim)
          .onClick(() => {
            this.drawerOpen = false;
          })
        SessionsDrawer({
          store: this.store, onClose: (): void => {
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
          .onClick(() => {
            this.menuOpen = false;
          })
        this.overflowMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
    .alignContent(Alignment.Start)
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
      Composer({
        store: this.store, version: this.version
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet(this.sheetOpen(), this.sheetContent(), {
      height: this.sheetHeight(), showClose: true, title: { title: this.sheetTitle() },
      preferType: SheetType.BOTTOM, onDisappear: (): void => {
        this.statsSheet = false;
        this.trajectorySheet = false;
        this.teamSheet = false;
        this.todoSheet = false;
        this.modelSheet = false;
      }
    })
  }

  private sheetOpen(): boolean {
    return this.statsSheet || this.trajectorySheet || this.teamSheet || this.todoSheet
      || this.modelSheet;
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
      return '待办任务';
    }
    if (this.modelSheet) {
      return '调整模型';
    }
    return '';
  }

  private sheetHeight(): SheetSize {
    if (this.modelSheet) {
      return SheetSize.MEDIUM;
    }
    return SheetSize.LARGE;
  }

  /** 溢出菜单（全屏遮层点任意处关闭；对照安卓 PopupMenu 五项）。 */
  @Builder
  overflowMenu() {
    Column() {
      Column({ space: 4 }) {
        this.menuItem('📊', '会话统计', (): void => {
          this.statsSheet = true;
        })
        this.menuItem('🧭', '运行轨迹', (): void => {
          this.trajectorySheet = true;
        })
        this.menuItem('🧠', '智能团队', (): void => {
          this.teamSheet = true;
        })
        this.menuItem('✅', '待办任务', (): void => {
          this.todoSheet = true;
        })
        this.menuItem('🎛️', '调整模型', (): void => {
          this.modelSheet = true;
        })
      }
      .width(190)
      .padding(6)
      .borderRadius(14)
      .backgroundColor(this.c().settingsSurface)
      .shadow({ radius: 18, color: this.c().shadow, offsetX: 0, offsetY: 4 })
      .margin({ right: DsSpacing.screenPad - 14, top: DsSpacing.topBarHeight })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.End)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  menuItem(icon: string, label: string, onTap: () => void) {
    Row({ space: DsSpacing.chipIconGap }) {
      Text(icon)
        .fontSize(15)
      Text(label)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().labelPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderRadius(10)
    .onClick(() => {
      this.menuOpen = false;
      onTap();
    })
  }

  /** bindSheet 内容（按当前 sheet 分派；骨架已内联在各组件）。 */
  @Builder
  sheetContent() {
    if (this.statsSheet) {
      StatsSheet({ store: this.store })
    } else if (this.trajectorySheet) {
      TrajectorySheet({ store: this.store })
    } else if (this.teamSheet) {
      TeamSheet({ store: this.store })
    } else if (this.todoSheet) {
      TodoSheet({ store: this.store })
    } else if (this.modelSheet) {
      ModelSheet({
        store: this.store, onDone: (): void => {
          this.modelSheet = false;
        }
      })
    }
  }

  private isEmpty(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.isEmpty;
  }

  private ready(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  /** 顶栏 44dp：菜单 / 标题 / 连接点 / 新建对话。 */
  @Builder
  topBar() {
    Row({ space: 8 }) {
      Text('☰')
        .fontSize(22)
        .fontColor(this.c().labelPrimary)
        .width(40)
        .height(DsSpacing.topBarHeight)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.drawerOpen = true;
        })
      Text(this.title())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().labelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Circle({ width: 8, height: 8 })
        .fill(this.ready() ? this.c().brand : this.c().labelTertiary)
      Text('＋')
        .fontSize(22)
        .fontColor(this.c().labelPrimary)
        .width(40)
        .height(DsSpacing.topBarHeight)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          const st: ChatStore | null = this.store;
          if (st !== null) {
            st.newChat();
          }
        })
      Text('⋮')
        .fontSize(20)
        .fontColor(this.c().labelPrimary)
        .width(36)
        .height(DsSpacing.topBarHeight)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.menuOpen = true;
        })
    }
    .width('100%')
    .height(DsSpacing.topBarHeight)
    .padding({ left: DsSpacing.screenPad - 14, right: DsSpacing.screenPad - 14 })
    .backgroundColor(this.c().bgBase)
  }

  private title(): string {
    return this.titleView;
  }

  /** 空态问候（品牌标 + 问候语；工作目录 chip 阶段 4）。 */
  @Builder
  greeting() {
    Column({ space: 14 }) {
      Text('DSH')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().brand)
      Text('嗨！今天想聊些什么？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c().labelPrimary)
      Text(this.greetingHost())
        .fontSize(13)
        .fontColor(this.c().labelTertiary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
