/**
 * 会话抽屉 —— 对照安卓 sessions_drawer.dart 阶段 2 基础版：
 * 新建对话按钮 + 按工作区分组的会话列表 + 顶部连接主机标识。
 * 搜索 / 重命名 / 删除 / 设置入口 / 推挤动画是阶段 4（PORT-MAP ☐）；
 * 阶段 2 用右滑覆盖 + 点遮罩关闭的简化交互。
 */

import { ChatStore } from '../core/ChatStore';
import { DshSession } from '../core/Models';
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

  /** 工作区分组标题顺序（未分组垫底，同安卓 session_groups.dart）。 */
  private groups(): string[] {
    const seen: string[] = [];
    for (const s of this.sessionsView) {
      const title: string = s.workspaceTitle === null || s.workspaceTitle === ''
        ? '未分组' : s.workspaceTitle;
      if (seen.indexOf(title) < 0) {
        seen.push(title);
      }
    }
    return seen;
  }

  private sessionsOf(groupTitle: string): DshSession[] {
    const out: DshSession[] = [];
    for (const s of this.sessionsView) {
      const t: string = s.workspaceTitle === null || s.workspaceTitle === ''
        ? '未分组' : s.workspaceTitle;
      if (t === groupTitle) {
        out.push(s);
      }
    }
    return out;
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
          .height(34)
          .fontSize(13)
          .backgroundColor(this.c().brand)
          .fontColor(this.c().onBrand)
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
        ForEach(this.groups(), (g: string) => {
          ListItem() {
            Column() {
              Text(g)
                .fontSize(12)
                .fontColor(this.c().drawerGroupLabel)
                .width('100%')
                .padding({ left: 16, top: 14, bottom: 6 })
              ForEach(this.sessionsOf(g), (s: DshSession) => {
                this.sessionRow(s)
              }, (s: DshSession) => s.id)
            }
            .width('100%')
          }
        }, (g: string) => g)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // 底部唯一设置入口（安卓 sessions_drawer 同位置）。
      Divider().color(this.c().borderL1).strokeWidth(1)

      Row({ space: 8 }) {
        Text('⚙️')
          .fontSize(17)
        Text('设置')
          .fontSize(15)
          .fontColor(this.c().labelPrimary)
          .layoutWeight(1)
        Text('›')
          .fontSize(15)
          .fontColor(this.c().labelTertiary)
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 12 })
      .onClick(() => {
        if (this.onClose !== null) {
          this.onClose();
        }
        if (this.onOpenSettings !== null) {
          this.onOpenSettings();
        }
      })
    }
    .width('78%')
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
        .fontSize(15)
        .fontColor(this.c().labelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 待处理标记：提问=「待回答」实心橙点，审批=「待审批」品牌色描边。
      // bridge 会话列表只对挂起审批下发 pendingInteraction，提问不发，
      // 所以标记一律由 HitlStore 全连接挂起表推导（ChatStore.pendingMarkOf）。
      if (this.markOf(s.id) === 'question') {
        Text('待回答')
          .fontSize(11)
          .fontColor(this.c().markQuestion)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(7)
          .backgroundColor(this.c().markQuestionBg)
      } else if (this.markOf(s.id) === 'approval') {
        Text('待审批')
          .fontSize(11)
          .fontColor(this.c().brand)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(7)
          .border({ width: 1, color: this.c().brand })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 12 })
    .borderRadius(10)
    .backgroundColor(this.current() === s.id
      ? this.c().chipSelectedBg : Color.Transparent)
    .onClick(() => {
      this.open(s);
    })
  }

  private current(): string {
    return this.currentView;
  }
}
