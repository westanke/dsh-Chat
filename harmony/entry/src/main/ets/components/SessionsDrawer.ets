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
  @Prop version: number = 0;
  onClose: (() => void) | null = null;
  onOpenSettings: (() => void) | null = null;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  /** 工作区分组标题顺序（未分组垫底，同安卓 session_groups.dart）。 */
  private groups(): string[] {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return [];
    }
    const seen: string[] = [];
    for (const s of st.sessions) {
      const title: string = s.workspaceTitle === null || s.workspaceTitle === ''
        ? '未分组' : s.workspaceTitle;
      if (seen.indexOf(title) < 0) {
        seen.push(title);
      }
    }
    return seen;
  }

  private sessionsOf(groupTitle: string): DshSession[] {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return [];
    }
    const out: DshSession[] = [];
    for (const s of st.sessions) {
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
    }
    .width('78%')
    .height('100%')
    .backgroundColor(this.c().bgLayer1)
    .alignItems(HorizontalAlign.Start)
  }

  private hostLabel(): string {
    const st: ChatStore | null = this.store;
    return st === null ? '' : st.connectionLabel;
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
    }

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
    const st: ChatStore | null = this.store;
    return st === null ? '' : (st.sessionId === null ? '' : st.sessionId);
  }
}
