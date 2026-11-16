/**
 * 会话抽屉 —— 对照安卓 sessions_drawer.dart 阶段 2 基础版：
 * 新建对话按钮 + 按工作区分组的会话列表 + 顶部连接主机标识。
 * 搜索 / 重命名 / 删除 / 设置入口 / 推挤动画是阶段 4（PORT-MAP ☐）；
 * 阶段 2 用右滑覆盖 + 点遮罩关闭的简化交互。
 */

import { ChatStore } from '../core/ChatStore';
import { DshSession } from '../core/Models';
import {
  GROUP_KEY_EARLIER, SessionGroup, SessionRow, groupSessionsByTime, visibleRowsOf,
} from '../core/SessionGroups';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct SessionsDrawer {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 同 MessageList：必须 @Watch + @State 快照，否则 ForEach 数据源不重新求值。 */
  @Prop @Watch('syncVersion') version: number = 0;
  /** 会话列表快照（唯一被观察的数据源）。 */
  @State sessionsView: DshSession[] = [];
  @State currentView: string = '';
  /**
   * 「待回答/待审批」标记快照（sessionId → 'question' | 'approval' | ''）。
   * 用 @State 数组而非 Map：ArkUI 只观察 build 期间读到的 @State，Map 内部
   * 变更不触发重渲染（HitlPanel 踩过同样的坑）。每条编码 `id + '\u0001' + mark`。
   */
  @State marksView: string[] = [];
  /**
   * 「更早」分组展开态（默认收起）。用户口径：超过 2 天的会话收起来，
   * 点分组标题展开/收起。@State 保证点一下立刻重渲染。
   */
  @State earlierOpen: boolean = false;
  /** 分组快照（@State 数组：ForEach 只能观察被 build 读到的 @State）。 */
  @State groupsView: SessionGroup[] = [];
  onClose: (() => void) | null = null;
  onOpenSettings: (() => void) | null = null;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  /** version 变化 → 重抄 store 派生数据（@Prop @Watch 回调）。 */
  syncVersion(): void {
    const st: ChatStore | null = this.store;
    this.sessionsView = st === null ? [] : st.sessions;
    this.currentView = st === null || st.sessionId === null ? '' : st.sessionId;
    const next: string[] = [];
    if (st !== null) {
      for (const s of this.sessionsView) {
        const mark: string = st.pendingMarkOf(s.id);
        if (mark.length > 0) {
          next.push(s.id + '\u0001' + mark);
        }
      }
    }
    this.marksView = next;
    this.groupsView = groupSessionsByTime(this.sessionsView, Date.now());
  }

  /** 某会话的挂起标记（'question' / 'approval' / ''）。 */
  private markOf(sessionId: string): string {
    const prefix: string = sessionId + '\u0001';
    for (const item of this.marksView) {
      if (item.startsWith(prefix)) {
        return item.substring(prefix.length);
      }
    }
    return '';
  }

  aboutToAppear(): void {
    this.syncVersion();
    // 抽屉打开即拉一次「其它会话」的挂起项：HITL 帧只推当前连接关心的会话，
    // 非当前会话的挂起提问/审批只能靠 REST 逐会话探测（每次 2 个请求/会话）。
    const st: ChatStore | null = this.store;
    if (st !== null) {
      st.loadSessions().then((): Promise<void> => {
        return st.refreshPendingMarks();
      }).then((): void => {
        // 标记表变了要再抄一次快照，否则 @State marksView 停在打开时的空表。
        this.syncVersion();
      }).catch((): void => {
        // 探测失败不影响列表本身展示（静默）。
      });
    }
  }

  /** 某个时间分组实际要渲染的行（「更早」收起时返回空）。 */
  private rowsOf(g: SessionGroup): SessionRow[] {
    return visibleRowsOf(g, this.earlierOpen);
  }

  private open(s: DshSession): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    st.openSession(s);
    if (this.onClose !== null) {
      this.onClose();
    }
  }

  build() {
    Column() {
      // 顶部：连接主机 + 新建对话
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('DSH Chat')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.c().labelPrimary)
          Text(this.hostLabel())
            .fontSize(12)
            .fontColor(this.c().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+ 新对话')
          .height(40)
          .fontSize(12)
          .backgroundColor(this.c().brand)
          .fontColor(this.c().onBrand)
          .accessibilityText('当前连接：' + this.hostLabel())
          .onClick(() => {
            const st: ChatStore | null = this.store;
            if (st !== null) {
              st.newChat();
            }
            if (this.onClose !== null) {
              this.onClose();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 12 })

      Divider().color(this.c().borderL1).strokeWidth(1)

      List() {
        ForEach(this.groupsView, (g: SessionGroup) => {
          ListItem() {
            Column() {
              // 分组标题：今天 / 昨天 / 更早（更早可点标题展开收起）。
              Row({ space: 6 }) {
                Text(g.title)
                  .fontSize(12)
                  .fontColor(this.c().drawerGroupLabel)
                  .layoutWeight(1)
                if (g.collapsible) {
                  Text(this.earlierOpen ? (g.count().toString() + ' 条 · 收起') : (g.count().toString() + ' 条 · 展开'))
                    .fontSize(10)
                    .fontColor(this.c().labelTertiary)
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 6 })
              .accessibilityText(g.title + '，' + g.count().toString() + (this.earlierOpen ? ' 条，收起' : ' 条，展开'))
              .onClick(() => {
                if (g.collapsible) {
                  this.earlierOpen = !this.earlierOpen;
                }
              })
              // 行内小节：同工作区只在第一行显示一次（sectionLabel 空串就跳过）。
              ForEach(this.rowsOf(g), (r: SessionRow) => {
                if (r.sectionLabel.length > 0) {
                  Text(r.sectionLabel)
                    .fontSize(10)
                    .fontColor(this.c().drawerGroupLabel)
                    .width('100%')
                    .padding({ left: 20, top: 8, bottom: 2 })
                }
                this.sessionRow(r.session)
              }, (r: SessionRow) => r.session.id)
            }
            .width('100%')
          }
        }, (g: SessionGroup) => g.key)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // 底部唯一设置入口（安卓 sessions_drawer 同位置）。
      Divider().color(this.c().borderL1).strokeWidth(1)

      Row({ space: 8 }) {
        Text('⚙️')
          .fontSize(16)
        Text('设置')
          .fontSize(16)
          .fontColor(this.c().labelPrimary)
          .layoutWeight(1)
        Text('›')
          .fontSize(16)
          .fontColor(this.c().labelTertiary)
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 12 })
      .accessibilityText('打开设置')
      .onClick(() => {
        if (this.onClose !== null) {
          this.onClose();
        }
        if (this.onOpenSettings !== null) {
          this.onOpenSettings();
        }
      })
    }
    .width('80%')
    .height('100%')
    .backgroundColor(this.c().bgLayer1)
    .alignItems(HorizontalAlign.Start)
  }

  private hostLabel(): string {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return '';
    }
    return st.connectionLabel;
  }

  /** 会话行：标题 + 运行中圆点；当前会话高亮 chip 背景。 */
  @Builder
  sessionRow(s: DshSession) {
    Row({ space: 8 }) {
      Circle({ width: 7, height: 7 })
        .fill(s.running ? this.c().brand : Color.Transparent)
        .visibility(s.running ? Visibility.Visible : Visibility.None)
      Text(s.displayTitle)
        .fontSize(16)
        .fontColor(this.c().labelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 待处理标记：提问=「待回答」实心橙点，审批=「待审批」品牌色描边。
      // bridge 会话列表只对挂起审批下发 pendingInteraction，提问不发，
      // 所以标记一律由 HitlStore 全连接挂起表推导（ChatStore.pendingMarkOf）。
      if (this.markOf(s.id) === 'question') {
        Text('待回答')
          .fontSize(10)
          .fontColor(this.c().markQuestion)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor(this.c().markQuestionBg)
      } else if (this.markOf(s.id) === 'approval') {
        Text('待审批')
          .fontSize(10)
          .fontColor(this.c().brand)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .border({ width: 1, color: this.c().brand })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 12 })
    .borderRadius(10)
    .backgroundColor(this.current() === s.id
      ? this.c().chipSelectedBg : Color.Transparent)
    .accessibilityText('待审批')
    .onClick(() => {
      this.open(s);
    })
  }

  private current(): string {
    return this.currentView;
  }
}
