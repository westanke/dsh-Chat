/// 思考流块 —— 对齐官方 ReasoningRow（dsh-client-ui-chat ReasoningRow 逐条）：
/// 标题恒「思考」font-weight 400；icon Think（本端 emoji 占位）size 14；折叠态
/// [icon][思考][2×2px 分隔点][摘要][chevron]；摘要 = running?最近完成段落首行:
/// 首行（去 **），13px 单行 ellipsis；流式 Shimmer 官方无对应能力 → 降级静态
/// labelSecondary（口径汇报）。preview = !expanded && summary!=='' && (streaming
/// || settledReasoningPreview)；hidden（<signature> 未闭合）整块不渲染。
/// 流式默认展开、结束后自动收起（用户口径 m03759：有思考时要能看到过程）。
/// 展开内容走 MdView(small=true)，与安卓 DsMarkdownView(small:true) 同口径。
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { reasoningHidden, reasoningSummaryOf } from '../core/ReasoningText';

@Component
export struct ThinkBlock {
  text: string = '';
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
          Text('思考')
            .fontSize(DsTypography.small.size)
            .fontWeight(FontWeight.Normal)
            .fontColor(this.c().labelSecondary)
          Text('')
            .fontSize(2)
            .width(2)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.c().labelCaption)
            .margin({ left: 4, right: 8 })
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
        }
        .padding({ top: 4, bottom: 4 })
        .accessibilityText(this.expanded ? '收起思考' : '展开思考')
        .onClick((): void => {
          this.expanded = !this.expanded;
        })
        if (this.expanded) {
          Column() {
            MdView({ text: this.text, small: true })
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
