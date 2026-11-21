/**
 * 会话页顶栏（安卓 app/lib/ui/chat_top_bar.dart 口径）：两行结构。
 * 第一行 44：菜单 / 标题 / 新建 / 更多；第二行 20：状态点 + 状态文字，
 * 左缩进对齐标题。状态判定在 core/ChatHeaderStatus.ts（node 直测）。
 */

import { GatewayState } from '../core/GatewayEvents';
import { ChatHeaderStatus, chatHeaderStatus } from '../core/ChatHeaderStatus';
import { DsColors, DsSpacing, DsTypography } from '../ui/theme';
import { floatingColumnWidth } from '../core/Breakpoints';

@Component
export struct ChatTopBar {
  @Prop title: string = '';
  @Prop state: number = GatewayState.IDLE;
  @Prop streaming: boolean = false;
  @Prop waitingApproval: boolean = false;
  @Prop waitingAnswer: boolean = false;
  @Prop hostLabel: string = '';
  onOpenDrawer: (() => void) | null = null;
  onNewChat: (() => void) | null = null;
  onMenu: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshColumnWidthVp') columnWidth: number = 0;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private status(): ChatHeaderStatus {
    return chatHeaderStatus(this.state as GatewayState, this.streaming,
      this.waitingApproval, this.waitingAnswer, this.hostLabel);
  }

  private statusColor(tone: string): string {
    if (tone === 'ok') {
      return this.c().chatStatusOk;
    }
    if (tone === 'error') {
      return this.c().danger;
    }
    if (tone === 'warn') {
      return this.c().chatStatusWarn;
    }
    if (tone === 'busy') {
      return this.c().brand;
    }
    return this.c().labelTertiary;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('☰')
          .fontSize(22)
          .fontColor(this.c().labelPrimary)
          .width(40)
          .height(DsSpacing.topBarHeight)
          .textAlign(TextAlign.Center)
          .accessibilityText('打开会话列表')
          .onClick((): void => {
            if (this.onOpenDrawer !== null) {
              this.onOpenDrawer();
            }
          })
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('＋')
          .fontSize(22)
          .fontColor(this.c().labelPrimary)
          .width(40)
          .height(DsSpacing.topBarHeight)
          .textAlign(TextAlign.Center)
          .accessibilityText('新建对话')
          .onClick((): void => {
            if (this.onNewChat !== null) {
              this.onNewChat();
            }
          })
        Text('⋮')
          .fontSize(20)
          .fontColor(this.c().labelPrimary)
          .width(40)
          .height(DsSpacing.topBarHeight)
          .textAlign(TextAlign.Center)
          .accessibilityText('更多操作')
          .onClick((): void => {
            if (this.onMenu !== null) {
              this.onMenu();
            }
          })
      }
      .width('100%')
      .height(DsSpacing.topBarHeight)

      Row({ space: DsSpacing.chatStatusGap }) {
        Circle({ width: DsSpacing.chatStatusDot, height: DsSpacing.chatStatusDot })
          .fill(this.statusColor(this.status().tone))
        Text(this.status().label)
          .fontSize(DsTypography.caption.size)
          .lineHeight(DsTypography.caption.lineHeight)
          .fontColor(this.c().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(DsSpacing.chatStatusRow)
      .padding({ left: 56, right: 8 })
      .margin({ bottom: 4 })
    }
    .width('100%')
    .constraintSize({ maxWidth: this.columnWidth > 0 ? floatingColumnWidth(this.columnWidth) : '100%' })
    .backgroundColor(this.c().bgBase)
  }
}
