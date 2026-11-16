/// 思考流块 —— 与 MessageList 拆开（宪法 §7 单文件 ≤500 行）。
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { reasoningPreviewOf } from '../core/ToolPresent';
/**
 * 思考流块 —— 对齐安卓 `app/lib/ui/chat_message_items.dart:232 _ThinkBlock`：
 * 官方「已深度思考」可折叠小字块。流式时默认展开并显示「深度思考中…」（用户口径
 * m03759：有思考时要能看到过程，不能折叠藏起来），历史消息默认折叠。
 * 展开时内容走 MdView(small=true)，与安卓 `DsMarkdownView(small: true)` 同口径。
 *
 * settledReasoningPreview（展示档 policy，core/ToolDetails）：已完成轮收起时
 * 显示 reasoning 首行预览（弱化小字）；concise 档为 false → 不显示预览。
 */
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

  build() {
    Column() {
      Row({ space: 4 }) {
        Text('🧭')
          .fontSize(12)
          .fontColor(this.c().labelSecondary)
        Text(this.expanded ? '收起深度思考' : (this.streaming ? '深度思考中…' : '已深度思考'))
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelSecondary)
        Text(this.expanded ? '⌃' : '⌄')
          .fontSize(14)
          .fontColor(this.c().labelSecondary)
      }
      .padding({ top: 4, bottom: 4 })
      .accessibilityText(this.expanded ? '收起深度思考' : (this.streaming ? '深度思考中' : '展开深度思考'))
      .onClick((): void => {
        this.expanded = !this.expanded;
      })
      if (!this.expanded && !this.streaming && this.showPreview) {
        Text(reasoningPreviewOf(this.text))
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: DsSpacing.thinkHMargin })
      }
      if (this.expanded) {
        Column() {
          MdView({ text: this.text, small: true })
        }
        .width('100%')
        .padding({ left: DsSpacing.thinkHMargin })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: DsSpacing.thinkHMargin })
  }
}

