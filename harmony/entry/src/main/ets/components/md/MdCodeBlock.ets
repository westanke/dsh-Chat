/// 代码块组件 —— 官方 App 实测复刻（灰底 + 语言 banner + 复制 + 1px 分隔线）。
/// 高亮走 core/SimpleHighlight（四类着色，Atom One Light 对照色）。
import { highlight, HlSpan } from '../../core/SimpleHighlight';
import { DsColors, DsPalette, DsTypography, DsSpacing } from '../../ui/theme';
import { pasteboard } from '@kit.BasicServicesKit';

@Component
export struct MdCodeBlock {
  lang: string = '';
  code: string = '';
  @StorageProp('dshDark') dark: boolean = false;
  @State copied: boolean = false;
  @State rows: HlSpan[][] = [];

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.rows = highlight(this.code, this.lang);
  }

  /// 语言/内容变化（流式增长）时重算着色。
  reload(code: string, lang: string): void {
    this.code = code;
    this.lang = lang;
    this.rows = highlight(code, lang);
  }

  private copy(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.copied = true;
    }).catch(() => {
      this.copied = false;
    });
  }

  /// Atom One 对照色一律走 DsPalette token（亮/暗两套，iOS/安卓同源）；
  /// 组件内不留颜色字面量（宪法 §7 + 鸿蒙 R003/R008 双套色要求）。
  private spanColor(cls: string): string {
    if (this.dark) {
      if (cls === 'kw') {
        return DsPalette.synDarkKeyword;
      }
      if (cls === 'str') {
        return DsPalette.synDarkString;
      }
      if (cls === 'num') {
        return DsPalette.synDarkNumber;
      }
      if (cls === 'comment') {
        return DsPalette.synDarkComment;
      }
      return DsPalette.synDarkPlain;
    }
    if (cls === 'kw') {
      return DsPalette.synKeyword;
    }
    if (cls === 'str') {
      return DsPalette.synString;
    }
    if (cls === 'num') {
      return DsPalette.synNumber;
    }
    if (cls === 'comment') {
      return DsPalette.synComment;
    }
    return DsPalette.synPlain;
  }

  build() {
    Column() {
      // banner：语言名 + 复制
      Row() {
        Text(this.lang.length > 0 ? this.lang : 'text')
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontColor(this.c().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row() {
          Text(this.copied ? '✓' : '⧉')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
          Text(this.copied ? '已复制' : '复制')
            .fontSize(DsTypography.codeBlockLabel.size)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 4 })
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
        .accessibilityText(this.copied ? '已复制' : '复制代码')
        .onClick(() => this.copy())
      }
      .padding({
        left: DsSpacing.codeBlockPadH,
        right: DsSpacing.codeBlockPadH - 6,
        top: DsSpacing.codeBlockBannerPadV,
        bottom: DsSpacing.codeBlockBannerPadV,
      })
      // 1px 分隔线
      Divider()
        .color(this.c().mdCodeBlockDivider)
        .strokeWidth(1)
      // 代码正文（水平滚动）
      Scroll() {
        Column() {
          Repeat<HlSpan[]>(this.rows)
            .each((entry: RepeatItem<HlSpan[]>) => {
              this.renderLine(entry.item, entry.index)
            })
            .key((entry: HlSpan[], index: number) => index.toString() + '-' + entry.length.toString())
        }
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .padding({
        left: DsSpacing.codeBlockPadH,
        right: DsSpacing.codeBlockPadH,
        top: DsSpacing.codeBlockPadV,
        bottom: DsSpacing.codeBlockPadV,
      })
    }
    .constraintSize({ minWidth: '100%' })
    .backgroundColor(this.c().mdCodeBlockBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .clip(true)
    .margin({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
  }

  @Builder
  renderLine(row: HlSpan[], lineIdx: number) {
    Row() {
      if (row.length === 0) {
        // 空行也要有行高，否则前后空行比可见行矮，代码块纵向节奏不齐。
        Text(' ')
          .fontSize(DsTypography.codeBlock.size)
          .lineHeight(DsTypography.codeBlock.lineHeight)
          .fontFamily(DsTypography.codeFamily)
      } else {
        // 行高只能落在宿主 Text 上（Span 没有 lineHeight 属性）。
        Text() {
          Repeat<HlSpan>(row)
            .each((entry: RepeatItem<HlSpan>) => {
              Span(entry.item.text)
                .fontColor(this.spanColor(entry.item.cls))
                .fontSize(DsTypography.codeBlock.size)
                .fontFamily(DsTypography.codeFamily)
            })
            .key((entry: HlSpan, index: number) => index.toString() + '-' + entry.text.length.toString())
        }
        .lineHeight(DsTypography.codeBlock.lineHeight)
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}
