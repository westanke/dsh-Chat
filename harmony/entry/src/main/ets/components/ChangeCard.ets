/**
 * 本轮改动卡（安卓 app/lib/ui/chat_change_card.dart 口径）。
 *
 * 挂在闭合轮最后一条 assistant 之后：标题「改动了 N 个文件」+ 全轮 +A −R，
 * 最多列 3 个文件（文件名 / 弱化目录 / +N −M），脚注「查看改动」开全屏 diff 页。
 * 数据由 core/TurnCards.ts 提供，卡片本身只渲染与转发点击。
 */

import { FileChange } from '../core/TurnChanges';
import { DsColors, DsSpacing, DsTypography } from '../ui/theme';

@Component
export struct ChangeCard {
  /** 本轮的改动文件（父层整替换才会刷新，见 TurnCards.ets）。 */
  @Prop files: FileChange[] = [];
  onOpen: ((index: number) => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private shown(): FileChange[] {
    const out: FileChange[] = [];
    const max: number = DsSpacing.changeCardMaxFiles;
    for (let i = 0; i < this.files.length && i < max; i++) {
      out.push(this.files[i]);
    }
    return out;
  }

  private added(): number {
    let sum: number = 0;
    for (let i = 0; i < this.files.length; i++) {
      sum += this.files[i].added;
    }
    return sum;
  }

  private removed(): number {
    let sum: number = 0;
    for (let i = 0; i < this.files.length; i++) {
      sum += this.files[i].removed;
    }
    return sum;
  }

  private openAt(index: number): void {
    if (this.onOpen !== null && this.files.length > 0) {
      const clamped: number = index < 0 ? 0 : (index >= this.files.length ? this.files.length - 1 : index);
      this.onOpen(clamped);
    }
  }

  build() {
    Column() {
      // 头：图标 + 标题 + 全轮合计。
      Row() {
        Text('✎')
          .fontSize(DsSpacing.changeCardIcon)
          .fontColor(this.c().labelSecondary)
          .margin({ top: 2 })
        Text('改动了 ' + this.files.length.toString() + ' 个文件')
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(DsTypography.smallStrong.weight)
          .lineHeight(DsTypography.smallStrong.lineHeight)
          .fontColor(this.c().labelPrimary)
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.files.length > 1) {
          Text('+' + this.added().toString())
            .fontSize(DsTypography.smallStrong.size)
            .fontWeight(DsTypography.smallStrong.weight)
            .fontColor(this.c().diffAddFg)
          Text('−' + this.removed().toString())
            .fontSize(DsTypography.smallStrong.size)
            .fontWeight(DsTypography.smallStrong.weight)
            .fontColor(this.c().diffDelFg)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })

      ForEach(this.shown(), (f: FileChange, i: number) => {
        Row() {
          Column() {
            Text(f.name())
              .fontSize(DsTypography.small.size)
              .lineHeight(DsTypography.small.lineHeight)
              .fontColor(this.c().labelPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (f.directory() !== '') {
              Text(f.directory())
                .fontSize(DsTypography.codeBlockLabel.size)
                .lineHeight(DsTypography.codeBlockLabel.lineHeight)
                .fontColor(this.c().labelTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('+' + f.added.toString())
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().diffAddFg)
          Text('−' + f.removed.toString())
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().diffDelFg)
            .margin({ left: 6 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .onClick((): void => {
          this.openAt(i);
        })
      }, (f: FileChange, i: number) => f.path + '|' + i.toString())

      Divider().color(this.c().borderL1).strokeWidth(1).margin({ top: 4 })

      // 脚注：查看改动（整轮）/ 还有 N 个文件。
      Row() {
        Text('查看改动')
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(DsTypography.smallStrong.weight)
          .fontColor(this.c().brand)
          .layoutWeight(1)
        if (this.files.length > DsSpacing.changeCardMaxFiles) {
          Text('还有 ' + (this.files.length - DsSpacing.changeCardMaxFiles).toString() + ' 个文件')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
          Text('›')
            .fontSize(DsSpacing.changeCardIcon)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 10, top: 10, bottom: 10 })
      .onClick((): void => {
        this.openAt(0);
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.c().bgLayer1)
    .borderRadius(DsSpacing.changeCardRadius)
    .borderWidth(1)
    .borderColor(this.c().borderL2)
    .clip(true)
    .margin({ top: DsSpacing.chatGapCard })
  }
}
