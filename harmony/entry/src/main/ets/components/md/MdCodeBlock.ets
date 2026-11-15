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

  private get c(): DsColors {
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

  /// Atom One Light 对照（暗色下统一偏亮，对照安卓 synPlain 语义）。
  private spanColor(cls: string): string {
    if (this.dark) {
      if (cls === 'kw') {
        return '#cc99cd';
      }
      if (cls === 'str') {
        return '#7ec699';
      }
      if (cls === 'num') {
        return '#7ec699';
      }
      if (cls === 'comment') {
        return '#999999';
      }
      return '#d4d4d4';
    }
    if (cls === 'kw') {
      return '#a626a4';
    }
    if (cls === 'str') {
      return '#50a14f';
    }
    if (cls === 'num') {
      return '#4078f2';
    }
    if (cls === 'comment') {
      return '#a0a1a7';
    }
    return DsPalette.synPlain;
  }

  build() {
    Column() {
      // banner：语言名 + 复制
      Row() {
        Text(this.lang.length > 0 ? this.lang : 'text')
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontColor(this.c.labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row() {
          Text(this.copied ? '✓' : '⧉')
            .fontSize(14)
            .fontColor(this.c.labelTertiary)
          Text(this.copied ? '已复制' : '复制')
            .fontSize(DsTypography.codeBlockLabel.size)
            .fontColor(this.c.labelTertiary)
            .margin({ left: 4 })
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
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
        .color(this.c.mdCodeBlockDivider)
        .strokeWidth(1)
      // 代码正文（水平滚动）
      Scroll() {
        Column() {
          ForEach(this.rows, (row: HlSpan[], lineIdx: number) => {
            this.renderLine(row, lineIdx)
          }, (row: HlSpan[], lineIdx: number) => lineIdx + '-' + row.length)
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
    .backgroundColor(this.c.mdCodeBlockBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .clip(true)
    .margin({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
  }

  @Builder
  renderLine(row: HlSpan[], lineIdx: number) {
    Row() {
      if (row.length === 0) {
        Text(' ')
          .fontSize(DsTypography.codeBlock.size)
          .fontFamily(DsTypography.codeFamily)
      } else {
        Text() {
          ForEach(row, (s: HlSpan) => {
            Span(s.text)
              .fontColor(this.spanColor(s.cls))
              .fontSize(DsTypography.codeBlock.size)
              .fontFamily(DsTypography.codeFamily)
          }, (s: HlSpan, idx: number) => lineIdx + '-' + idx + '-' + s.text.length)
        }
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}
