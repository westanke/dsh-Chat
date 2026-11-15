/**
 * 消息列表 —— 对照安卓 chat_message_items.dart / chat_message_list.dart 的
 * 阶段 2/3 基础版：用户气泡 / 助手平铺 + Markdown 富渲染（MdView）/ 过程组
 * 短语行 / 错误条 / 流式块。
 * 布局 token：docs/design-tokens.md（msgPad 30 / bubbleRadius 16 / user 气泡
 * 最大宽 86.4%）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage } from '../core/HistoryPage';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';

@Component
export struct MessageList {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** ChatStore.changed() 递增的版本号，驱动本组件重渲染。 */
  @Prop version: number = 0;
  private scroller: Scroller = new Scroller();

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 消息气泡最大宽（官方 user 气泡约 86.4% 屏宽）。 */
  private bubbleMaxWidth(): Length {
    return '86.4%';
  }

  build() {
    if (this.store !== null) {
      this.renderList();
    }
  }

  @Builder
  renderList() {
    List({ scroller: this.scroller, space: 14 }) {
      ForEach(this.messages(), (m: ChatMessage, idx: number) => {
        ListItem() {
          if (m.isUser) {
            this.userBubble(m);
          } else if (m.isError) {
            this.errorBar(m);
          } else {
            this.assistantBlock(m);
          }
        }
      }, (m: ChatMessage, idx: number) => `${m.seq}-${idx}-${m.text.length}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.contentPadRight,
      top: 12, bottom: DsSpacing.msgPad })
    .scrollBar(BarState.Off)
    .onAppear(() => {
      this.jumpToBottom(false);
    })
  }

  private messages(): ChatMessage[] {
    const st: ChatStore | null = this.store;
    return st === null ? [] : st.messages;
  }

  /** 用户消息：右对齐气泡（官方浅色 #edf3fe / 深色 c850）。 */
  @Builder
  userBubble(m: ChatMessage) {
    Row() {
      Blank().layoutWeight(1)
      Text(m.text === '' ? ' ' : m.text)
        .fontSize(16)
        .fontColor(this.c().labelPrimary)
        .lineHeight(22)
        .constraintSize({ maxWidth: this.bubbleMaxWidth() })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.c().userBubble)
        .borderRadius(DsSpacing.bubbleRadius)
    }
    .width('100%')
  }

  /** 助手消息：全宽平铺文本 + 前置过程组短语行 + reasoning 灰字。 */
  @Builder
  assistantBlock(m: ChatMessage) {
    Column() {
      if (m.toolCalls.length > 0) {
        Text(m.phraseText)
          .fontSize(13)
          .fontColor(this.c().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ top: 2, bottom: 4 })
      }
      if (m.reasoning !== '') {
        Text(m.reasoning)
          .fontSize(14)
          .fontColor(this.c().labelTertiary)
          .lineHeight(20)
          .width('100%')
          .padding({ bottom: 6 })
      }
      if (m.text === '') {
        Text(' ')
          .fontSize(16)
          .fontColor(this.c().labelPrimary)
          .lineHeight(24)
          .width('100%')
      } else {
        MdView({ text: m.text })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 错误条（turn 失败）：红字轻背景。 */
  @Builder
  errorBar(m: ChatMessage) {
    Text(m.text === '' ? '执行失败' : m.text)
      .fontSize(14)
      .fontColor(this.c().danger)
      .lineHeight(20)
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.c().borderL1)
      .borderRadius(10)
  }

  /** 版本变化后贴底（streaming / 新历史到达时由 ChatView 触发）。 */
  jumpToBottom(animate: boolean): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // 未挂载时忽略。
    }
  }
}
