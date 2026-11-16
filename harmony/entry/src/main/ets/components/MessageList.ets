/**
 * 消息列表 —— 对照安卓 chat_message_items.dart / chat_message_list.dart 的
 * 阶段 2/3 基础版：用户气泡 / 助手平铺 + Markdown 富渲染（MdView）/ 过程组
 * 短语行 / 错误条 / 流式块。
 * 布局 token：docs/design-tokens.md（msgPad 30 / bubbleRadius 16 / user 气泡
 * 最大宽 86.4%）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage, DeliverableFile } from '../core/HistoryPage';
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
  /**
   * ChatStore.changed() 递增的版本号。必须带 @Watch 并在回调里把 store 派生数据
   * 抄进 @State —— ArkUI 只对 build 期间读到的 @State/@Prop 建立依赖，ForEach 的
   * 数据源若直接读普通成员 store.messages，永远不重新求值（真机现象：List 渲染
   * 出来但子项恒为 0，即使 store.messages 已有 2 条）。
   */
  @Prop @Watch('syncVersion') version: number = 0;
  /** store 派生消息快照（唯一被观察的数据源）。 */
  @State msgs: ChatMessage[] = [];
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
          } else if (m.role === 'files') {
            this.fileCard(m);
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
    .bindContentCover(this.docOpen, this.docViewer(), {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.docOpen = false;
      }
    })
  }

  @Builder
  docViewer() {
    MdDocViewer({
      store: this.store, absolutePath: this.docPath, title: this.docTitle,
      onBack: (): void => {
        this.docOpen = false;
      },
    })
  }

  /** 交付文件卡（安卓 _DeliverableStrip 口径）：.md 走站内查看器，其余交系统。 */
  @Builder
  fileCard(m: ChatMessage) {
    Column({ space: 6 }) {
      ForEach(m.files, (f: DeliverableFile) => {
        Row({ space: 8 }) {
          Text(this.isMarkdown(f.path) ? '📄' : '📎')
            .fontSize(15)
          Column({ space: 2 }) {
            Text(f.name.length > 0 ? f.name : f.path)
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (f.description !== null) {
              Text(f.description as string)
                .fontSize(DsTypography.caption.size)
                .fontColor(this.c().labelTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.c().bgLayer1)
        .onClick(() => {
          if (this.isMarkdown(f.path)) {
            this.docPath = f.path;
            this.docTitle = f.name.length > 0 ? f.name : f.path;
            this.docOpen = true;
          }
        })
      }, (f: DeliverableFile) => f.path)
    }
    .width('100%')
  }

  /** version 变化 → 重抄 store 派生数据（@Prop @Watch 回调）+ 跟随贴底。 */
  syncVersion(): void {
    const st: ChatStore | null = this.store;
    this.msgs = st === null ? [] : st.messages;
    // 新消息/流式增量到达后贴底（等一帧让 List 先按新数据布局）。
    setTimeout((): void => {
      this.jumpToBottom(false);
    }, 30);
  }

  aboutToAppear(): void {
    this.syncVersion();
  }

  private messages(): ChatMessage[] {
    return this.msgs;
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
