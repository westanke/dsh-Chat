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
import { DsColors, DsMotion, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { reasoningHidden, reasoningSummaryOf, reasoningText } from '../core/ReasoningText';
import { ThinkingRowState, thinkingLiveLines, thinkingRowStateOf } from '../core/ThinkingState';

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
  /** 正文已开始输出（活跃态收成摘要的开关；StreamingBlock 传 text !== ''）。 */
  @Prop answerStarted: boolean = false;
  @StorageProp('dshDark') dark: boolean = false;
  @State expanded: boolean = false;
  /** 活跃态呼吸环相位（1200ms 往返，§4.12 statusPulse 同源）。 */
  @State orbPulse: boolean = false;

  /** 流式结束 → 自动收起。只处理 true→false 这一个方向，用户手动展开后不再被强制折叠。 */
  onStreamingChange(): void {
    if (!this.streaming) {
      if (this.expanded) {
        this.expanded = false;
      }
      this.orbPulse = false;
      return;
    }
    this.startPulse();
  }

  private startPulse(): void {
    if (this.orbPulse) {
      return;
    }
    this.getUIContext().animateTo(
      { duration: DsMotion.pulse, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate },
      (): void => {
        this.orbPulse = true;
      });
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    // 初值按 streaming 定（历史消息折叠、流式展开）；后续 streaming 变化不再改，
    // 由用户点击接管 —— 否则每帧增量都会把用户刚折叠的块重新展开。
    this.expanded = this.streaming;
    if (this.state().active) {
      this.startPulse();
    }
  }

  /** 折叠摘要（官方 summaryText 口径；preview 门在 build 里判）。 */
  private summary(): string {
    return reasoningSummaryOf(this.text, this.streaming);
  }

  /** 整块隐藏（官方 hidden：<signature> 未闭合剥完为空）。 */
  private hidden(): boolean {
    return reasoningHidden(this.text);
  }

  private state(): ThinkingRowState {
    return thinkingRowStateOf(this.text, this.streaming, this.answerStarted);
  }

  private liveLines(): string[] {
    return thinkingLiveLines(this.text);
  }

  build() {
    Column() {
      if (!this.hidden()) {
        if (this.state().active) {
          this.activeRow()
        } else {
          this.summaryRow()
        }
        if (this.expanded) {
          Column() {
            MdView({ text: reasoningText(this.text), small: true })
          }
          .width('100%')
          .padding({ left: DsSpacing.thinkBodyIndent })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: DsSpacing.thinkHMargin })
  }

  /** 活跃态：呼吸环 18 + 「思考中」+ 三行实时窗口（dsh-go ReasoningRow 口径）。 */
  @Builder
  activeRow() {
    Column({ space: 2 }) {
      Row({ space: DsSpacing.thinkLeadGap }) {
        Stack() {
          Circle({ width: DsSpacing.thinkOrbSize, height: DsSpacing.thinkOrbSize })
            .fill(Color.Transparent)
            .stroke(this.c().brand)
            .strokeWidth(1.5)
            .opacity(0.45)
          Circle({ width: DsSpacing.thinkDotSize, height: DsSpacing.thinkDotSize })
            .fill(this.c().brand)
        }
        .width(DsSpacing.thinkOrbSize)
        .height(DsSpacing.thinkOrbSize)
        .opacity(this.orbPulse ? 1 : 0.4)
        Text('思考中')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
        Blank()
        Text(this.expanded ? '⌃' : '⌄')
          .fontSize(14)
          .fontColor(this.c().labelSecondary)
          .accessibilityGroup(true)
      }
      .width('100%')
      .padding({ top: 4, bottom: 2 })
      .accessibilityText(this.expanded ? '收起思考过程' : '展开思考过程')
      .onClick((): void => {
        this.expanded = !this.expanded;
      })
      if (!this.expanded) {
        Column({ space: 2 }) {
          Repeat<string>(this.liveLines()).each((item: RepeatItem<string>) => {
            Text(item.item)
              .fontSize(DsTypography.caption.size)
              .fontColor(this.c().labelTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }).key((line: string) => line.length.toString() + line.substring(0, 8))
        }
        .width('100%')
        .padding({ left: DsSpacing.thinkBodyIndent })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 结束/正文已开始：一行摘要 + chevron。 */
  @Builder
  summaryRow() {
    Row({ space: 4 }) {
      Text('🧭')
        .fontSize(14)
        .fontColor(this.c().labelSecondary)
        .accessibilityGroup(true)
      Text('思考')
        .fontSize(DsTypography.small.size)
        .fontWeight(FontWeight.Normal)
        .fontColor(this.c().labelSecondary)
      Column()
        .width(DsSpacing.thinkDotSize / 3)
        .height(DsSpacing.thinkDotSize / 3)
        .borderRadius(DsSpacing.thinkDotSize / 3)
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
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .accessibilityText(this.expanded ? '收起思考' : '展开思考')
    .onClick((): void => {
      this.expanded = !this.expanded;
    })
  }
}
