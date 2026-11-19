/// 思考流块 —— 对齐官方 ReasoningRow（dsh-client-ui-chat ReasoningRow 逐条）：
/// 标题恒「思考」font-weight 400；icon Think（本端 emoji 占位）size 14；折叠态
/// [icon][思考][2×2px 分隔点][摘要][chevron]；摘要 = running?最近完成段落首行:
/// 首行（去 **），13px 单行 ellipsis；流式 Shimmer 官方无对应能力 → 降级静态
/// labelSecondary（口径汇报）。preview = !expanded && summary!=='' && (streaming
/// || settledReasoningPreview)；hidden（<signature> 未闭合）整块不渲染。
/// 流式默认展开、结束后自动收起（用户口径 m03759：有思考时要能看到过程）。
/// 展开内容走 MdView(small=true)，与安卓 DsMarkdownView(small:true) 同口径；
/// 传给 MdView 的是 reasoningText(剥掉 <signature> 包裹) 而非原文 —— 安卓
/// app/lib/ui/chat_message_blocks.dart:106 就是 reasoningTextOf(widget.text)。
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { reasoningHidden, reasoningSummaryOf, reasoningText } from '../core/ReasoningText';

@Component
export struct ThinkBlock {
  /**
   * 思考原文。**必须是 @Prop**（2026-11-17 真机「流式思考不显示」真因之一）：
   * 普通成员只在组件创建时赋一次值，父层后续把更长的 reasoning 传进来不会重建，
   * 折叠摘要与展开正文永远停在首帧（通常还是空串 → 整块消失）。
   * 本组件的所有派生值（summary/hidden）都在 build 里现算，故 @Prop 已足够刷新，
   * 不需要 @Watch 缓存副本。
   */
  @Prop text: string = '';
  /** 流式态：true 期间默认展开，转为 false 时自动收起（用户口径 2026-11-16）。 */
  @Prop @Watch('onStreamingChange') streaming: boolean = false;
  /** 收起预览开关（MessageList 按 policyOf(档位).settledReasoningPreview 传入）。 */
  @Prop showPreview: boolean = true;
  @StorageProp('dshDark') dark: boolean = false;
  @State expanded: boolean = false;

  /** 流式结束 → 自动收起。只处理 true→false 这一个方向，用户手动展开后不再被强制折叠。 */
  onStreamingChange(): void {
    if (!this.streaming && this.expanded) {
      this.expanded = false;
    }
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    // 初值按 streaming 定（历史消息折叠、流式展开）；后续 streaming 变化不再改，
    // 由用户点击接管 —— 否则每帧增量都会把用户刚折叠的块重新展开。
    this.expanded = this.streaming;
  }

  /** 折叠摘要（官方 summaryText 口径；preview 门在 build 里判）。 */
  private summary(): string {
    return reasoningSummaryOf(this.text, this.streaming);
  }

  /** 整块隐藏（官方 hidden：<signature> 未闭合剥完为空）。 */
  private hidden(): boolean {
    return reasoningHidden(this.text);
  }

  build() {
    Column() {
      if (!this.hidden()) {
        Row({ space: 4 }) {
          Text('🧭')
            .fontSize(14)
            .fontColor(this.c().labelSecondary)
            .accessibilityGroup(true)
          Text('思考')
            .fontSize(DsTypography.small.size)
            .fontWeight(FontWeight.Normal)
            .fontColor(this.c().labelSecondary)
          // 官方 .lcKema_separator：2×2px 圆点（border-radius 1px）。R023 不收字号 2、
          // R003 不收圆角 1 —— 圆点改由空容器绘制（无文字就不涉字号），圆角落最小合法档 2。
          Column()
            .width(2)
            .height(2)
            .borderRadius(2)
            .backgroundColor(this.c().labelCaption)
            .margin({ left: 4, right: 8 })
            .accessibilityGroup(true)
          if (!this.expanded && this.summary() !== '' && (this.streaming || this.showPreview)) {
            Text(this.summary())
              .fontSize(DsTypography.caption.size)
              .fontColor(this.streaming ? this.c().labelSecondary : this.c().labelTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          Text(this.expanded ? '⌃' : '⌄')
            .fontSize(14)
            .fontColor(this.c().labelSecondary)
            .accessibilityGroup(true)
        }
        .padding({ top: 4, bottom: 4 })
        .accessibilityText(this.expanded ? '收起思考' : '展开思考')
        .onClick((): void => {
          this.expanded = !this.expanded;
        })
        if (this.expanded) {
          Column() {
            // 剥壳：<signature>…</signature> 包裹只留正文（对齐安卓 reasoningTextOf）。
            // 直接传原文会把标签当 Markdown 渲染出来；未闭合时 reasoningText 返空串，
            // 但此时 hidden() 已整块不渲染，不会出现空展开区。
            MdView({ text: reasoningText(this.text), small: true })
          }
          .width('100%')
          .padding({ left: DsSpacing.thinkHMargin })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: DsSpacing.thinkHMargin })
  }
}
