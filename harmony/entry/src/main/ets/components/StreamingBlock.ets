/**
 * 流式块 —— 对照安卓 `chat_message_items.dart` 的 `_StreamingItem`：
 * 思考中先出 ThinkBlock（streaming=true，默认展开），正文增量走 MdView(streaming=true)。
 * 原先鸿蒙端只在 core 里累积 streamText/streamReasoning、**从未渲染**，真机表现为
 * 「安卓有思考内容、鸿蒙什么都没有」（用户 2026-11-17 反馈）。
 *
 * 数据来源：ChatStore.streamText / streamReasoning（ChatEvents 的 delta 累积，
 * committed/turn.end/turn.failed 清空）。父级 MessageList 在 version 变化时把两者
 * 抄进 @State 再传给本组件（ArkUI 只对 build 读到的 @State 建依赖）。
 *
 * ⚠️ 三个入参**必须是 @Prop**（2026-11-17 真机「流式思考不显示」的真因之一）：
 * `ChatStore.send()` 在用户按下发送那一刻就 `this.streaming = true` + `this.changed()`
 * （core/ChatStore.ts:250-251），MessageList 的 streamingVisible() 于是在**第一个
 * reasoning delta 到达之前**就把本组件建成空实例（屏幕上先是「正在思考…」）。
 * 普通成员只在创建时赋一次值，之后每个增量都灌不进已建好的实例 —— 块永久停在
 * 占位行，尽管 core 里 streamReasoning 一直在涨。
 * 82f6b66 补了「把本组件挂进列表」这一层，却没改成员声明，所以照样不显示。
 */
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { ThinkBlock } from './ThinkBlock';

@Component
export struct StreamingBlock {
  /** 流式思考增量（可能为空）。 */
  @Prop reasoning: string = '';
  /** 流式正文增量（可能为空）。 */
  @Prop text: string = '';
  /** 折叠态是否给思考预览（policyOf(档位).settledReasoningPreview）。 */
  @Prop showPreview: boolean = true;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column() {
      if (this.reasoning !== '') {
        ThinkBlock({
          text: this.reasoning, streaming: true, showPreview: this.showPreview,
          answerStarted: this.text !== ''
        })
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
        // 占位行高用 padding 撑（不用固定 .height：R009 会判小热区，且断点下更好伸缩）。
        .padding({ top: 4, bottom: 4 })
        .accessibilityGroup(true)
        .accessibilityText('正在思考')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: DsSpacing.blockGap })
  }
}
