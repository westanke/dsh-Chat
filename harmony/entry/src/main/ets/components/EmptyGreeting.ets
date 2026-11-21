/**
 * 会话空态问候（品牌标 + 问候语 + 工作目录 chip）。
 *
 * 从 `pages/ChatView.ets` 抽成独立组件：一是该页面已超单文件行数纪律，
 * 二是这块是纯展示（状态全由父层交进来），拆开后页面只留一行调用。
 *
 * 工作目录 chip 对照安卓空态「工作目录」：默认手机会话，发首条消息前可换成
 * 授权根下的指定目录；会话建好后随会话定死（改目录要开新会话）。
 */

import { DsColors, DsSpacing } from '../ui/theme';
import { SessionLocation, locationChipLabel } from '../core/SessionLocation';

@Component
export struct EmptyGreeting {
  /** 设计 token（父层 `this.c()` 交进来，子组件不自己取主题）。 */
  @Prop colors: DsColors;
  /** 问候语下面那行小字（设备名或连接态，父层算好）。 */
  @Prop host: string;
  /** 当前待建会话的工作目录（null = 手机会话）。 */
  @Prop pendingLoc: SessionLocation | null;
  /** 点 chip：父层刷新快照并打开目录选择层。 */
  onPickLoc: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      Image($r('app.media.brand_mark'))
        .width(DsSpacing.brandMarkWidth)
        .height(DsSpacing.brandMarkHeight)
        .fillColor(this.colors.brandMark)
        .objectFit(ImageFit.Contain)
        .margin({ bottom: DsSpacing.brandMarkGap - 12 })
        .accessibilityText('DSH 标记')
      Text('嗨！今天想聊些什么？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.labelPrimary)
      Text(this.host)
        .fontSize(12)
        .fontColor(this.colors.labelTertiary)
      Row({ space: 6 }) {
        Text(this.pendingLoc === null ? '📱' : '📁')
          .fontSize(12)
        Text(locationChipLabel(this.pendingLoc))
          .fontSize(12)
          .fontColor(this.colors.labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('⌄')
          .fontSize(12)
          .fontColor(this.colors.labelTertiary)
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.colors.bgLayer1)
      .border({ width: 1, color: this.colors.inputBorder })
      .constraintSize({ maxWidth: 300 })
      .margin({ top: 4 })
      .accessibilityText('工作目录：' + locationChipLabel(this.pendingLoc))
      .onClick(() => {
        this.onPickLoc();
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
