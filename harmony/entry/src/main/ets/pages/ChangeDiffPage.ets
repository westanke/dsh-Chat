/**
 * 查看改动页（安卓 app/lib/ui/chat_diff_page.dart 口径）。
 *
 * 从改动卡打开：顶栏（返回 / 本轮改动 / 合计 / 复制当前路径）+ 横向文件 chips +
 * 选中文件的每个 hunk（「第 N 次修改」+ 红绿行）。全屏模态由 TurnCards 的
 * bindContentCover 承载，返回走回调（本工程不能用 getRouter().back()，会退应用）。
 */

import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { FileChange, EditHunk } from '../core/TurnChanges';
import { DIFF_LINE_ADD, DIFF_LINE_DEL, DiffLine } from '../core/CodeDiff';
import { DsColors, DsSpacing, DsTypography } from '../ui/theme';

/** Toast 停留时长（系统提示口径，非动效档位）。 */
const TOAST_MS: number = 1500;

@Component
export struct ChangeDiffPage {
  sessionId: string = '';
  @Prop files: FileChange[] = [];
  /** 打开时定位到第几个文件（0 起，父层已 clamp）。 */
  initialIndex: number = 0;
  onBack: (() => void) | null = null;
  @State selected: number = 0;
  @State topInset: number = 0;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.selected = this.initialIndex >= 0 && this.initialIndex < this.files.length ? this.initialIndex : 0;
    // bindContentCover 不含系统安全区（MdDocViewer 同款修法）。
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      const avoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(avoid.topRect.height);
    }).catch((): void => {
      // 拿不到按 0 处理。
    });
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

  private diffFileIndexOf(f: FileChange): number {
    return this.files.indexOf(f);
  }

  private current(): FileChange | null {
    if (this.files.length === 0) {
      return null;
    }
    const i: number = this.selected >= 0 && this.selected < this.files.length ? this.selected : 0;
    return this.files[i];
  }

  private copyText(text: string, toast: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: toast, duration: TOAST_MS });
    }).catch((): void => {
      promptAction.showToast({ message: '复制失败', duration: TOAST_MS });
    });
  }

  /** 顶栏「复制」：复制当前选中文件的绝对路径（安卓 chat_diff_page 同口径）。 */
  private copyCurrentPath(): void {
    const f: FileChange | null = this.current();
    if (f === null) {
      return;
    }
    this.copyText(f.path, '已复制路径');
  }

  @Builder
  diffLine(line: DiffLine) {
    Row() {
      Text(line.type === DIFF_LINE_ADD ? '+ ' : (line.type === DIFF_LINE_DEL ? '- ' : '  '))
        .fontSize(DsTypography.codeBlock.size)
        .lineHeight(DsTypography.codeBlock.lineHeight)
        .fontFamily(DsTypography.codeFamily)
        .fontColor(line.type === DIFF_LINE_ADD ? this.c().diffAddFg
          : (line.type === DIFF_LINE_DEL ? this.c().diffDelFg : this.c().mdCodeBlockText))
      Text(line.text)
        .fontSize(DsTypography.codeBlock.size)
        .lineHeight(DsTypography.codeBlock.lineHeight)
        .fontFamily(DsTypography.codeFamily)
        .fontColor(line.type === DIFF_LINE_ADD ? this.c().diffAddFg
          : (line.type === DIFF_LINE_DEL ? this.c().diffDelFg : this.c().mdCodeBlockText))
        .layoutWeight(1)
        .wordBreak(WordBreak.BREAK_ALL)
    }
  }

  private curPath(): string {
    const f: FileChange | null = this.current();
    return f === null ? '' : f.path;
  }

  private curStat(): string {
    const f: FileChange | null = this.current();
    if (f === null) {
      return '';
    }
    return '+' + f.added.toString() + '  −' + f.removed.toString()
      + '  修改 ' + f.edits().toString() + ' 次';
  }

  private curHunks(): EditHunk[] {
    const f: FileChange | null = this.current();
    return f === null ? [] : f.hunks;
  }

  @Builder
  fileBody() {
    Column() {
      Text(this.curPath())
        .fontSize(DsTypography.codeBlockLabel.size)
        .lineHeight(DsTypography.codeBlockLabel.lineHeight)
        .fontFamily(DsTypography.codeFamily)
        .fontColor(this.c().labelSecondary)
        .width('100%')
        .wordBreak(WordBreak.BREAK_ALL)
      Text(this.curStat())
        .fontSize(DsTypography.small.size)
        .lineHeight(DsTypography.small.lineHeight)
        .fontColor(this.c().labelTertiary)
        .margin({ top: 6 })
      Repeat<EditHunk>(this.curHunks()).each((hunk: RepeatItem<EditHunk>) => {
        Text('第 ' + hunk.item.index.toString() + ' 次修改')
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(DsTypography.smallStrong.weight)
          .fontColor(this.c().labelSecondary)
          .margin({ top: 12, bottom: 6 })
        Column() {
          Repeat<DiffLine>(hunk.item.lines).each((line: RepeatItem<DiffLine>) => {
            this.diffLine(line.item)
          }).key((line: DiffLine, index: number) => index.toString() + '|' + line.type + '|'
            + line.text.length.toString())
        }
        .width('100%')
        .backgroundColor(this.c().mdCodeBlockBg)
        .borderRadius(10)
        .borderWidth(1)
        .borderColor(this.c().borderL1)
        .clip(true)
        .margin({ bottom: 16 })
      }).key((h: EditHunk) => h.index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      // 顶栏：返回 / 标题 + 合计 / 复制。
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(this.c().labelPrimary)
          .width(DsSpacing.cardActionSize)
          .height(DsSpacing.cardActionSize)
          .textAlign(TextAlign.Center)
          .accessibilityText('返回')
          .onClick((): void => {
            if (this.onBack !== null) {
              this.onBack();
            }
          })
        Column() {
          Text('本轮改动')
            .fontSize(DsTypography.h4.size)
            .fontWeight(DsTypography.h4.weight)
            .lineHeight(DsTypography.h4.lineHeight)
            .fontColor(this.c().labelPrimary)
          Text(this.files.length.toString() + ' 个文件  +' + this.added().toString()
            + ' −' + this.removed().toString())
            .fontSize(DsTypography.small.size)
            .lineHeight(DsTypography.small.lineHeight)
            .fontColor(this.c().labelTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 4 })
        Text('复制')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().brand)
          .width(DsSpacing.cardActionSize)
          .height(DsSpacing.cardActionSize)
          .textAlign(TextAlign.Center)
          .accessibilityText('复制文件路径')
          .onClick((): void => {
            this.copyCurrentPath();
          })
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 4, bottom: 10 })

      Scroll() {
        Row({ space: 8 }) {
          Repeat<FileChange>(this.files).each((item: RepeatItem<FileChange>) => {
            Row({ space: 6 }) {
              Text(item.item.name())
                .fontSize(DsTypography.small.size)
                .fontColor(this.files.indexOf(item.item) === this.selected ? this.c().brand
                  : this.c().labelPrimary)
                .maxLines(1)
                .constraintSize({ maxWidth: 160 })
              Text('+' + item.item.added.toString())
                .fontSize(DsTypography.codeBlockLabel.size)
                .fontColor(this.c().diffAddFg)
              Text('−' + item.item.removed.toString())
                .fontSize(DsTypography.codeBlockLabel.size)
                .fontColor(this.c().diffDelFg)
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .height(DsSpacing.chipHeight)
            .accessibilityText('查看 ' + item.item.path)
            .backgroundColor(this.diffFileIndexOf(item.item) === this.selected
              ? this.c().chipSelectedBg : this.c().bgLayer1)
            .borderRadius(18)
            .borderWidth(1)
            .borderColor(this.diffFileIndexOf(item.item) === this.selected
              ? this.c().brand : this.c().borderL2)
            .onClick((): void => {
              this.selected = this.diffFileIndexOf(item.item);
            })
          }).key((f: FileChange) => f.path)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)

      Scroll() {
        Column() {
          if (this.current() !== null) {
            this.fileBody()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c().bgBase)
    .padding({ top: this.topInset, left: 16, right: 16 })
  }
}
