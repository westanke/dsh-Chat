/// 公式渲染组件 —— 轻量 LaTeX 树 → ArkUI（纯自绘，不引第三方）。
/// 块级公式居中；行内公式随文本基线。解析在 core/LatexLite.ts，本组件只画。
import { LatexNode } from '../../core/LatexLite';
import { DsColors, DsTypography } from '../../ui/theme';
import { mediaquery } from '@kit.ArkUI';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd } from '../../core/Breakpoints';

@Component
export struct MdLatexView {
  node: LatexNode = new LatexNode();
  inline: boolean = false;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点（R007 一多）：分式横线等固定高度在宽屏放大一档。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;

  /** 窗口断点自读（R007 一多）：分式/根式的固定高度在宽屏放大一档。 */
  private refreshBreakpoint(): void {
    try {
      const md: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      const next: string = breakpointOf(md.matches, lg.matches);
      if (next !== this.bp) {
        this.bp = next;
        AppStorage.setOrCreate('dshBreakpoint', next);
      }
    } catch (e) {
      // 拿不到 mediaquery 时按手机档渲染。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
  }

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Row() {
      this.renderNode(this.node)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(this.inline ? FlexAlign.Start : FlexAlign.Center)
    .width(this.inline ? undefined : '100%')
    .padding(this.inline ? 0 : { top: 6, bottom: 6 })
  }

  @Builder
  renderNode(n: LatexNode) {
    if (n.kind === 'text' || n.kind === 'sym') {
      Text(n.text)
        .fontSize(DsTypography.base.size)
        .fontColor(this.c().labelPrimary)
        .fontFamily(DsTypography.codeFamily)
    } else if (n.kind === 'row') {
      Row() {
        Repeat<LatexNode>(n.children)
          .each((entry: RepeatItem<LatexNode>) => {
            this.renderNode(entry.item)
          })
          .key((entry: LatexNode, index: number) => index.toString() + '-' + entry.kind)
      }
      .alignItems(VerticalAlign.Center)
    } else if (n.kind === 'frac') {
      // 分数：分子 / 横线 / 分母
      Column() {
        Column() {
          this.renderNode(n.num === null ? emptyNode() : n.num)
        }
        .constraintSize({ minHeight: this.atLeastMd() ? 22 : 18 })
        Column()
          .width('100%')
          .height(1)
          .backgroundColor(this.c().labelPrimary)
        Column() {
          this.renderNode(n.den === null ? emptyNode() : n.den)
        }
        .constraintSize({ minHeight: this.atLeastMd() ? 22 : 18 })
      }
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 2, right: 2 })
    } else if (n.kind === 'sqrt') {
      // 根号：√ 符号 + 参数上划线
      Row() {
        Text('√')
          .fontSize(DsTypography.base.size)
          .fontColor(this.c().labelPrimary)
        Column() {
          this.renderNode(n.arg === null ? emptyNode() : n.arg)
        }
        .borderWidth({ top: 1 })
        .borderColor(this.c().labelPrimary)
        .padding({ left: 2, right: 2, top: 2 })
        .alignItems(HorizontalAlign.Center)
      }
      .alignItems(VerticalAlign.Bottom)
    } else if (n.kind === 'sup') {
      Text(this.smallArg(n))
        .fontSize((DsTypography.base.size as number) * 0.7)
        .fontColor(this.c().labelPrimary)
        .fontFamily(DsTypography.codeFamily)
        .offset({ y: -6 })
    } else if (n.kind === 'sub') {
      Text(this.smallArg(n))
        .fontSize((DsTypography.base.size as number) * 0.7)
        .fontColor(this.c().labelPrimary)
        .fontFamily(DsTypography.codeFamily)
        .offset({ y: 6 })
    } else {
      Text(n.text)
        .fontSize(DsTypography.base.size)
        .fontColor(this.c().labelPrimary)
    }
  }

  /// 上/下标参数拍平为单行文本（嵌套结构在 70% 字号下不展开，口径：简单可读）。
  private smallArg(n: LatexNode): string {
    const arg = n.arg;
    if (arg === null) {
      return '';
    }
    if (arg.kind === 'text' || arg.kind === 'sym') {
      return arg.text;
    }
    if (arg.kind === 'row' && arg.children.length > 0) {
      let out = '';
      for (const c of arg.children) {
        if (c.kind === 'text' || c.kind === 'sym') {
          out += c.text;
        } else {
          out += this.glyph(c);
        }
      }
      return out;
    }
    return this.glyph(arg);
  }

  /// 非文本节点的单字符近似（² ³ ⁿ ₁ ᵢ 等 + 兜底原样）。
  private glyph(n: LatexNode): string {
    if (n.kind === 'sup') {
      const t = this.smallArg(n);
      if (t === '2') {
        return '²';
      }
      if (t === '3') {
        return '³';
      }
      if (t.length > 0) {
        return '^' + t;
      }
      return '';
    }
    if (n.kind === 'sub') {
      const t = this.smallArg(n);
      if (t === '1') {
        return '₁';
      }
      if (t === '2') {
        return '₂';
      }
      if (t.length > 0) {
        return '_' + t;
      }
      return '';
    }
    if (n.kind === 'frac') {
      const a = n.num !== null ? this.smallArg(n.num) : '';
      const b = n.den !== null ? this.smallArg(n.den) : '';
      return '(' + a + ')/(' + b + ')';
    }
    if (n.kind === 'sqrt') {
      return '√(' + (n.arg !== null ? this.smallArg(n.arg) : '') + ')';
    }
    return n.text;
  }
}

function emptyNode(): LatexNode {
  const n = new LatexNode();
  n.kind = 'text';
  return n;
}
