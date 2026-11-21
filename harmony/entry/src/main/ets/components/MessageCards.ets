/**
 * 消息列表里的三种小卡片：命令卡 / 交付文件卡 / 错误条。
 * 2026-11-17 从 MessageList.ets 抽出 —— 本端补流式渲染后该文件超 500 行上限
 * （宪法 §7），三张卡的配色与语义独立，搬出后由 MessageList 直接引用。
 * 配色/圆角 token 与安卓 chat_message_items.dart 同口径。
 */
import { DeliverableFile } from '../core/HistoryPage';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

/** 命令卡（安卓 _CommandCard 口径）：首行 monospace + ✓/✗ 结果。 */
@Component
export struct CommandCard {
  text: string = '';
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Row({ space: 8 }) {
      Text('⌨')
        .fontSize(DsTypography.base.size)
        .fontColor(this.text.includes('\u2717') ? this.c().danger : this.c().chipSelectedFg)
        .margin({ top: 2 })
      Column({ space: 2 }) {
        Text(this.text.split('\n')[0])
          .fontSize(DsTypography.small.size).lineHeight(DsTypography.small.lineHeight)
          .fontFamily('monospace').fontColor(this.c().labelPrimary)
          .width('100%')
        if (this.text.includes('\n')) {
          Text(this.text.split('\n').slice(1).join('\n'))
            .fontSize(DsTypography.small.size).lineHeight(DsTypography.small.lineHeight)
            .fontColor(this.text.includes('\u2717') ? this.c().danger : this.c().labelTertiary).width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .margin({ top: DsSpacing.blockGap })
    .borderRadius(DsSpacing.codeBlockRadius)
    .backgroundColor(this.c().bgLayer1)
    .borderWidth(1)
    .borderColor(this.c().inputBorder)
  }
}

/** 交付文件卡（安卓 _DeliverableStrip 口径）：.md 走站内查看器，其余交系统。 */
@Component
export struct DeliverableCard {
  files: DeliverableFile[] = [];
  /** 点 .md 文件：交给父级打开站内查看器（父级持有 bindContentCover）。 */
  onOpenDoc: ((path: string, title: string) => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** .md / .markdown 判定（安卓 _isMarkdown 口径）。 */
  private isMarkdown(path: string): boolean {
    const lower: string = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  build() {
    Column({ space: 6 }) {
      Repeat<DeliverableFile>(this.files).each((item: RepeatItem<DeliverableFile>) => {
        Row({ space: 8 }) {
          Text(this.isMarkdown(item.item.path) ? '📄' : '📎')
            .fontSize(DsTypography.base.size)
          Column({ space: 2 }) {
            Text(item.item.name.length > 0 ? item.item.name : item.item.path)
              .fontSize(DsTypography.small.size).lineHeight(DsTypography.small.lineHeight)
              .fontColor(this.c().labelPrimary).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (item.item.description !== null) {
              Text(item.item.description as string)
                .fontSize(DsTypography.caption.size).lineHeight(DsTypography.caption.lineHeight)
                .fontColor(this.c().labelTertiary).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10).backgroundColor(this.c().bgLayer1)
        .accessibilityText(item.item.name + '，文件：' + item.item.path)
        .onClick(() => {
          if (this.isMarkdown(item.item.path) && this.onOpenDoc !== null) {
            (this.onOpenDoc as (path: string, title: string) => void)(
              item.item.path, item.item.name.length > 0 ? item.item.name : item.item.path);
          }
        })
      }).key((f: DeliverableFile) => f.path)
    }
    .width('100%')
  }
}

/** 错误条（turn 失败）：红字轻背景。 */
@Component
export struct ErrorBar {
  text: string = '';
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Text(this.text === '' ? '执行失败' : this.text)
      .fontSize(DsTypography.small.size).lineHeight(DsTypography.small.lineHeight)
      .fontColor(this.c().danger)
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.c().borderL1).borderRadius(10)
  }
}
