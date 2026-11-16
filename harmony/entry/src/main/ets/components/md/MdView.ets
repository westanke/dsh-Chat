/// Markdown 渲染主组件 —— 块级循环 + 行内混排（对齐安卓 md_view.dart 口径）。
/// 解析在 core/MdParser.ts；代码块/表格/公式分别自绘（官方实测像素）。
/// 首版偏差（PORT-MAP 已记）：流式光标不闪烁；图片块不渲染只留占位。
import { parseMarkdown, MdBlock, MdListItem } from '../../core/MdParser';
import { InlineSeg } from '../../core/MdInline';
import { LatexNode, parseLatex } from '../../core/LatexLite';
import { DsColors, DsTypography, DsSpacing } from '../../ui/theme';
import { common, Want } from '@kit.AbilityKit';
import { MdCodeBlock } from './MdCodeBlock';
import { MdTable } from './MdTable';
import { MdLatexView } from './MdLatex';

@Component
export struct MdView {
  text: string = '';
  streaming: boolean = false;
  small: boolean = false;
  @StorageProp('dshDark') dark: boolean = false;
  @State blocks: MdBlock[] = [];

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.blocks = parseMarkdown(this.text);
  }

  /// 流式增量：文本变长则整体重解析（块数通常 < 50，开销可接受）。
  reload(text: string): void {
    this.text = text;
    this.blocks = parseMarkdown(text);
  }

  private headFont(level: number): Font {
    if (level === 1) {
      return DsTypography.h1;
    }
    if (level === 2) {
      return DsTypography.h2;
    }
    if (level === 3) {
      return DsTypography.h3;
    }
    return DsTypography.h4;
  }

  private segFont(): Font {
    return this.small ? DsTypography.small : DsTypography.base;
  }

  build() {
    Column() {
      Repeat<MdBlock>(this.blocks)
        .each((entry: RepeatItem<MdBlock>) => {
          this.renderBlock(entry.item, entry.index)
        })
        .key((entry: MdBlock, index: number) => index.toString() + '-' + entry.type + '-' + entry.text.length.toString())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  renderBlock(b: MdBlock, idx: number) {
    if (b.type === 'h') {
      Text() {
        Repeat<InlineSeg>(b.segs)
          .each((entry: RepeatItem<InlineSeg>) => {
            this.inlineSpan(entry.item)
          })
          .key((entry: InlineSeg, index: number) => index.toString() + '-' + entry.text.length.toString())
      }
      .fontSize(this.headFont(b.level).size)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.c().labelPrimary)
      .width('100%')
      .margin({ top: b.level <= 3 ? DsSpacing.blockGap : DsSpacing.blockGap / 2, bottom: 8 })
    } else if (b.type === 'p' || b.type === 'quote') {
      if (b.type === 'quote') {
        Row() {
          Column()
            .width(DsSpacing.quoteBarWidth)
            .height('100%')
            .backgroundColor(this.c().quoteBar)
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            this.inlineFlow(b.segs, idx)
          }
          .padding({ left: DsSpacing.quotePadLeft - DsSpacing.quoteBarWidth })
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .margin({ top: DsSpacing.blockGap })
      } else {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          this.inlineFlow(b.segs, idx)
        }
        .width('100%')
        .margin({ top: idx === 0 ? 0 : 2 })
      }
    } else if (b.type === 'code') {
      MdCodeBlock({ lang: b.lang, code: b.text })
    } else if (b.type === 'table') {
      MdTable({ rows: b.rows, aligns: b.align })
    } else if (b.type === 'latex') {
      MdLatexView({ node: parseLatex(b.text), inline: false })
    } else if (b.type === 'ul' || b.type === 'ol') {
      Column() {
        Repeat<MdListItem>(b.items)
          .each((entry: RepeatItem<MdListItem>) => {
            this.renderListItem(b.type, entry.item, idx, entry.index)
          })
          .key((entry: MdListItem, index: number) => index.toString() + '-' + entry.text.length.toString())
      }
      .width('100%')
      .margin({ top: 4, bottom: 4 })
    } else if (b.type === 'hr') {
      Divider()
        .color(this.c().borderL2)
        .strokeWidth(1)
        .margin({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    }
  }

  @Builder
  renderListItem(kind: string, item: MdListItem, blockIdx: number, itemIdx: number) {
    Row() {
      if (item.checked >= 0) {
        // 任务项：勾选框（官方「☑ 已完成」观感，无圆点）
        Text(item.checked === 1 ? '☑' : '☐')
          .fontSize(18)
          .fontColor(item.checked === 1 ? this.c().brand : this.c().listMarker)
          .margin({ right: 6, top: 2 })
      } else if (kind === 'ul') {
        Text('•')
          .fontSize(this.segFont().size)
          .fontColor(this.c().listMarker)
          .margin({ right: 8 })
      } else {
        Text((itemIdx + 1) + '.')
          .fontSize(this.segFont().size)
          .fontColor(this.c().listMarker)
          .margin({ right: 6 })
      }
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.inlineFlow(item.segs, blockIdx)
      }
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /// 行内片段流：连续非 latex 片段合成一个 Text（Span 混排样式），
  /// latex 片段（$ 包裹）单独 MdLatexView。
  @Builder
  inlineFlow(segs: InlineSeg[], blockIdx: number) {
    Repeat<InlineSeg>(segs)
      .each((entry: RepeatItem<InlineSeg>) => {
        this.inlineSegView(entry.item, blockIdx)
      })
      .key((entry: InlineSeg, index: number) => index.toString() + '-' + entry.text.length.toString())
  }

  /** 单个行内片段（latex / 链接 / 普通 Span 混排）。抽 @Builder 让 Repeat 帧只剩一行调用。 */
  @Builder
  inlineSegView(s: InlineSeg, blockIdx: number) {
      if (s.text.startsWith('$') && s.text.lastIndexOf('$') > 0) {
        MdLatexView({ node: this.latexNodeOf(s.text), inline: true })
      } else if (s.link.length > 0) {
        Text(s.text)
          .fontSize(this.segFont().size)
          .fontColor(this.c().link)
          .decoration({ type: TextDecorationType.None })
          .accessibilityText('打开链接：' + s.link)
          .onClick(() => openExternal(s.link))
          .margin({ right: 2 })
      } else {
        Text() {
          Span(s.text)
            .fontSize(this.segFont().size)
            .fontColor(this.c().labelPrimary)
            .fontWeight(s.bold ? FontWeight.Bold : this.segFont().weight)
            .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration({
              type: s.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: this.c().labelPrimary,
            })
            .fontFamily(s.code ? DsTypography.codeFamily : undefined)
            .backgroundColor(s.code ? this.c().mdInlineCodeBg : Color.Transparent)
        }
        .margin({ right: s.code ? 4 : 0 })
      }
  }

  @Builder
  inlineSpan(s: InlineSeg) {
    Span(s.text)
      .fontColor(this.c().labelPrimary)
  }

  private latexNodeOf(wrapped: string): LatexNode {
    let body = wrapped;
    if (body.startsWith('$$')) {
      body = body.substring(2);
      if (body.endsWith('$$')) {
        body = body.substring(0, body.length - 2);
      }
    } else if (body.startsWith('$')) {
      body = body.substring(1);
      if (body.endsWith('$')) {
        body = body.substring(0, body.length - 1);
      }
    }
    return parseLatex(body.trim());
  }
}

/// 外接浏览器打开链接；失败静默（安卓同口径）。
function openExternal(url: string): void {
  try {
    const ctx = getContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
    };
    ctx.startAbility(want).catch(() => {
      // 无浏览器处理：忽略
    });
  } catch (_) {
    // 忽略
  }
}
