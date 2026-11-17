/**
 * 流式块 —— 对照安卓 `chat_message_items.dart` 的 `_StreamingItem`：
 * 思考中先出 ThinkBlock（streaming=true，默认展开），正文增量走 MdView(streaming=true)。
 * 原先鸿蒙端只在 core 里累积 streamText/streamReasoning、**从未渲染**，真机表现为
 * 「安卓有思考内容、鸿蒙什么都没有」（用户 2026-11-17 反馈）。
 *
 * 数据来源：ChatStore.streamText / streamReasoning（ChatEvents 的 delta 累积，
 * committed/turn.end/turn.failed 清空）。父级 MessageList 在 version 变化时把两者
 * 抄进 @State 再传给本组件（ArkUI 只对 build 读到的 @State 建依赖）。
 */
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { ThinkBlock } from './ThinkBlock';

@Component
export struct StreamingBlock {
  /** 流式思考增量（可能为空）。 */
  reasoning: string = '';
  /** 流式正文增量（可能为空）。 */
  text: string = '';
  /** 折叠态是否给思考预览（policyOf(档位).settledReasoningPreview）。 */
  showPreview: boolean = true;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column() {
      if (this.reasoning !== '') {
        ThinkBlock({ text: this.reasoning, streaming: true, showPreview: this.showPreview })
      }
      // 正文可能为空（还在思考阶段）：给一个占位行高，避免气泡从 0 高度跳变。
      if (this.text !== '') {
        MdView({ text: this.text, streaming: true })
      } else if (this.reasoning === '') {
        Row() {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.c().labelTertiary)
          Text('正在思考…')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 6 })
        }
        .height(24)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: DsSpacing.blockGap })
  }
}
