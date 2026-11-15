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
import { SessionsDrawer } from '../components/SessionsDrawer';

@Component
export struct ChatView {
  store: ChatStore | null = null;
  onExit: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @State version: number = 0;
  @State drawerOpen: boolean = false;

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
      st.consumeHistoryPageJustLoaded();
    });
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
          }
        })
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
      if (this.isEmpty()) {
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
    }
    .width('100%')
    .height(DsSpacing.topBarHeight)
    .padding({ left: DsSpacing.screenPad - 14, right: DsSpacing.screenPad - 14 })
    .backgroundColor(this.c().bgBase)
  }

  private title(): string {
    const st: ChatStore | null = this.store;
    return st === null ? '' : st.sessionTitle;
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
