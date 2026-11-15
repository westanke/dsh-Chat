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
import { ImageTile } from './ImageTile';
import { MessageActions } from './MessageActions';
import { DsImageRef, imageRefsOf, handoffRefOf } from '../core/ImageRef';
import { MdDocViewer } from '../pages/MdDocViewer';

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

  @State docOpen: boolean = false;
  @State docPath: string = '';
  @State docTitle: string = '';

  /** .md / .markdown 判定（安卓 _isMarkdown 口径）。 */
  private isMarkdown(path: string): boolean {
    const lower: string = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
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
          } else if (m.role === 'command') {
            this.commandCard(m);
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

  /** 命令卡（安卓 chat_message_items.dart 口径）：首行 monospace + ✓/✗ 结果。 */
  @Builder
  commandCard(m: ChatMessage) {
    Row({ space: 8 }) {
      Text('⌨')
        .fontSize(15)
        .fontColor(m.text.includes('\u2717') ? this.c().danger : this.c().chipSelectedFg)
        .margin({ top: 2 })
      Column({ space: 2 }) {
        Text(m.text.split('\n')[0])
          .fontSize(DsTypography.small.size)
          .fontFamily('monospace')
          .fontColor(this.c().labelPrimary)
          .width('100%')
        if (m.text.includes('\n')) {
          Text(m.text.split('\n').slice(1).join('\n'))
            .fontSize(DsTypography.small.size)
            .fontColor(m.text.includes('\u2717') ? this.c().danger : this.c().labelTertiary)
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .margin({ top: DsSpacing.blockGap })
    .borderRadius(DsSpacing.codeBlockRadius)
    .backgroundColor(this.c().bgLayer1)
    .borderWidth(1)
    .borderColor(this.c().inputBorder)
  }

  /** 用户消息：右对齐气泡（官方浅色 #edf3fe / 深色 c850）。 */
  @Builder
  userBubble(m: ChatMessage) {
    Row() {
      Blank().layoutWeight(1)
      this.userImages(m)
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

  /** 用户消息图片块（发送即带引用）。 */
  @Builder
  userImages(m: ChatMessage) {
    if (m.images.length > 0) {
      Column() {
        ForEach(imageRefsOf(m.images), (r: DsImageRef) => {
          ImageTile({ store: this.store, ref: r })
            .margin({ top: 4, bottom: 4 })
        }, (r: DsImageRef) => r.cacheKey)
      }
      .constraintSize({ maxWidth: this.bubbleMaxWidth() })
    }
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
      if (handoffRefOf(m.text) !== null) {
        ImageTile({ store: this.store, ref: handoffRefOf(m.text) as DsImageRef })
          .margin({ top: 6 })
      }
      if (!m.streaming && m.text !== '') {
        MessageActions({
          text: m.text, sentAt: m.startedAt,
          onRegenerate: (): void => {
            const st: ChatStore | null = this.store;
            if (st !== null) {
              st.regenerateAt(this.indexOf(m));
            }
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 消息在数组中的下标（regenerateAt 用）。 */
  private indexOf(m: ChatMessage): number {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return 0;
    }
    for (let i = 0; i < st.messages.length; i++) {
      if (st.messages[i] === m) {
        return i;
      }
    }
    return 0;
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
