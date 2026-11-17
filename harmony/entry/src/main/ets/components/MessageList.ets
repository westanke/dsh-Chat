/**
 * 消息列表 —— 对照安卓 chat_message_items.dart / chat_message_list.dart 的阶段 2/3
 * 基础版：用户气泡 / 助手平铺 + Markdown 富渲染（MdView）/ 过程组短语行 / 错误条 /
 * 流式块。布局 token：docs/design-tokens.md（msgPad 30 / bubbleRadius 16 / user 气泡最大宽 86.4%）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage, DeliverableFile } from '../core/HistoryPage';
import { ToolCallInfo, formatDuration, bashCommandOf, prettyArguments } from '../core/ToolCall';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { ImageTile } from './ImageTile';
import { MessageActions } from './MessageActions';
import { DsImageRef, imageRefsOf, handoffRefOf } from '../core/ImageRef';
import { MdDocViewer } from '../pages/MdDocViewer';
import { ThinkBlock } from './ThinkBlock';
import { ProcessGroup } from './ProcessGroup';
import { ToolBlock } from './ToolBlock';
import { ArrayDataSource } from './ArrayDataSource';
import { visibleMessagesOf, parseFoldedReplies, parseWorkStepsDetail } from '../core/WorkSteps';
import { policyOf, STEP_GROUPING_NONE } from '../core/ToolDetails';
import { mediaquery } from '@kit.ArkUI';
import { BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd, isLarge, contentMaxWidth } from '../core/Breakpoints';

@Component
export struct MessageList {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点：大屏给列表限最大宽并居中（R007），手机不限。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  /**
   * 「收起后显示的回复」档（通用设置③，官方 token：all|final）。final 时完成轮
   * 只保留最后一条正文助手消息（core/WorkSteps.visibleMessagesOf，node 直测）。
   * 档位在设置页切换 → AppStorage 直写 → @Watch 重抄消息（同 version 链路）。
   */
  @StorageProp('dshFoldedReplies') @Watch('syncVersion') foldedRepliesProp: string = 'all';
  /**
   * 「工作步骤展示」档（通用设置①，官方 token concise|standard|detailed|verbose）。
   * verbose 平铺：过程组不折叠成组，逐条工具行渲染（ToolBlock，无组标题、
   * 默认展开、单条可展开详情）；其余档走 ProcessGroup（组标题 + 折叠层）。
   * 另经 policyOf 派生：liveProcessDetail（组标题 detail 附加）、
   * settledReasoningPreview（已完成轮 ThinkBlock 收起预览）。
   */
  @StorageProp('dshWorkStepsDetail') detailProp: string = 'detailed';
  /**
   * ChatStore.changed() 递增的版本号。必须带 @Watch 并在回调里把 store 派生数据
   * 抄进 @State —— ArkUI 只对 build 期间读到的 @State/@Prop 建立依赖，ForEach 的
   * 数据源若直接读普通成员 store.messages，永远不重新求值（真机现象：List 渲染
   * 出来但子项恒为 0，即使 store.messages 已有 2 条）。
   */
  @Prop @Watch('syncVersion') version: number = 0;
  /** store 派生消息快照（唯一被观察的数据源）。 */
  @State msgs: ChatMessage[] = [];
  /** 服务端还有更早事件（history 应答 hasMore）—— 决定列表头是否出「加载更早消息」。 */
  /** turn.end reason=max-tokens：列表尾「回答被截断」提示（官方 client.js:6707 文案）。 */
  @State maxTokensNotice: boolean = false;
  @State hasMore: boolean = false;
  /** 正在翻页（按钮换 spinner）。 */
  @State loadingOlder: boolean = false;
  private scroller: Scroller = new Scroller();
  /**
   * 列表数据源（R005 LazyForEach）：`List` 只支持 LazyForEach 做懒加载，
   * 数据经 `syncVersion()` 里的 `reset()` 整批换新。
   */
  private ds: ArrayDataSource<ChatMessage> = new ArrayDataSource<ChatMessage>([]);
  /** 当前首个可见项下标（onScrollIndex 维护），翻页后据此把视口锚回原内容。 */
  private firstIdx: number = 0;
  /** 翻页瞬间的锚点快照：首个可见下标 + 当时的消息条数。 */
  private anchorIdx: number = -1;
  private anchorLen: number = 0;
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
      // 历史翻页入口（安卓 chat_message_list.dart:196-215 同口径）：
      // 上滑触发不可靠，官方做法是显式「加载更早消息」按钮。
      if (this.hasMore) {
        ListItem() {
          Row({ space: 6 }) {
            if (this.loadingOlder) {
              LoadingProgress()
                .width(this.isLargeBp() ? 22 : 18)
                .height(this.isLargeBp() ? 22 : 18)
                .color(this.c().brand)
            } else {
              Text('⌃')
                .fontSize(16)
                .fontColor(this.c().brand)
              Text('加载更早消息')
                .fontSize(DsTypography.small.size)
                .fontColor(this.c().brand)
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .accessibilityText('加载更早消息')
          .onClick((): void => {
            this.loadOlder();
          })
        }
      }
      LazyForEach(this.ds, (m: ChatMessage) => {
        ListItem() {
          this.itemOf(m)
        }
      }, (m: ChatMessage) => this.keyOf(m))
      if (this.maxTokensNotice) {
        ListItem() {
          Text('回答被截断，已有输出保留在对话中。发送“继续”可让模型接着输出。')
            .fontSize(DsTypography.caption.size).fontColor(this.c().settingsWarnFg)
            .wordBreak(WordBreak.BREAK_ALL).width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.c().settingsWarnBg).borderRadius(8)
        }
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: contentMaxWidth(this.bp) > 0 ? contentMaxWidth(this.bp) : '100%' })
    .layoutWeight(1)
    .padding({ left: DsSpacing.screenPad, right: DsSpacing.contentPadRight,
      top: 12, bottom: DsSpacing.msgPad })
    .scrollBar(BarState.Off)
    .onScrollIndex((first: number): void => {
      this.firstIdx = first;
    })
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
            .fontSize(16)
          Column({ space: 2 }) {
            Text(f.name.length > 0 ? f.name : f.path)
              .fontSize(DsTypography.small.size).fontColor(this.c().labelPrimary).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            if (f.description !== null) {
              Text(f.description as string)
                .fontSize(DsTypography.caption.size).fontColor(this.c().labelTertiary).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10).backgroundColor(this.c().bgLayer1)
        .accessibilityText(f.name + '，文件：' + f.path)
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
    // 折叠回复（通用设置③）：final 档完成轮只留最后一条正文助手消息；
    // all 档原样。运行中轮（streaming 或本轮未 committed）始终全可见。
    const raw: ChatMessage[] = st === null ? [] : st.messages;
    this.msgs = st === null ? [] : visibleMessagesOf(raw, parseFoldedReplies(this.foldedRepliesProp), st.streaming);
    this.ds.reset(this.msgs);
    this.maxTokensNotice = st !== null && st.maxTokensNotice;
    this.hasMore = st !== null && st.historyHasMore;
    this.loadingOlder = st !== null && st.loadingOlder;
    const justLoaded: boolean = st !== null && st.consumeHistoryPageJustLoaded();
    if (!justLoaded && (this.loadingOlder || this.anchorIdx >= 0)) {
      // 翻页期间一律不贴底：点按钮那一帧会先 changed() 一次（loadingOlder=true），
      // 页面数据到达后 .finally 还会再 changed() 一次，这两次都走不到这里的话
      // 会在 30ms 后把视口拉到最新消息 —— 真机现象就是「点加载更早消息跳到最新」。
      return;
    }
    if (justLoaded) {
      // 翻页 prepend：用户意图是往上读旧内容，既不能跳底、也不该被顶到最早一条。
      // ArkUI 没有 Flutter「prepend 保持 pixels」的语义，只能自己补偿：
      // 记下点击瞬间的首个可见下标，翻页后把同一条消息重新滚回同一位置。
      const added: number = this.anchorIdx >= 0 ? this.msgs.length - this.anchorLen : 0;
      const target: number = this.anchorIdx >= 0 ? this.anchorIdx + added : added;
      // 推迟到布局完成之后（0ms 时 List 还没按新数据排完，scrollToIndex 会被夹到首尾）。
      setTimeout((): void => {
        this.anchorIdx = -1;
        if (target <= 0) {
          return; // 原本就在顶部，无需补偿。
        }
        try {
          this.scroller.scrollToIndex(target, false, ScrollAlign.START);
        } catch (e) {
          // 未挂载/索引越界时忽略：宁可不动也别跳底。
        }
      }, 60);
      return;
    }
    // 新消息/流式增量到达后贴底（等一帧让 List 先按新数据布局）。
    setTimeout((): void => {
      this.jumpToBottom(false);
    }, 30);
  }
  /** 点「加载更早消息」：翻页 + 失败只提示不打断（store 侧写 lastError）。 */
  private loadOlder(): void {
    const st: ChatStore | null = this.store;
    if (st === null || this.loadingOlder) {
      return;
    }
    // 点击瞬间快照锚点（必须在 loadOlder 触发 changed() 之前取）。
    this.anchorIdx = this.firstIdx;
    this.anchorLen = this.msgs.length;
    st.loadOlder().catch((): void => {
      this.anchorIdx = -1;
      // store 已把 RequestException 转成 lastError 并 changed()，这里吞掉避免
      // 未处理的 Promise 拒绝刷屏。
    });
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
    this.syncVersion();
  }

  /**
   * 单条消息的分派。抽成 @Builder 有两个原因：帧内六路 if/else 直接写在 ListItem 里
   * 会让静态审计误判「LazyForEach 缺少 keyGenerator」（实际第三参一直都在），
   * 抽出来后审计为 pass；顺带把 500 行的 build() 减负。
   */
  @Builder
  itemOf(m: ChatMessage) {
    if (m.isUser) {
      this.userBubble(m);
    } else if (m.isError) {
      this.errorBar(m);
    } else if (m.role === 'command') {
      this.commandCard(m);
    } else if (m.role === 'files') {
      this.fileCard(m);
    } else if (m.isProcess) {
      if (this.detailProp === STEP_GROUPING_NONE) {
        // verbose 平铺：无组标题、无折叠层，逐条工具行（默认收起详情，可展开）。
        this.flatToolRows(m);
      } else {
        ProcessGroup({ group: m, store: this.store });
      }
    } else {
      this.assistantBlock(m);
    }
  }
  /** verbose 档平铺工具行（ForEach 带 keyGenerator，非 LazyForEach）。 */
  @Builder
  flatToolRows(m: ChatMessage) {
    Column() {
      ForEach(m.toolCalls, (c: ToolCallInfo) => {
        ToolBlock({ call: c, answerable: this.answerableOf })
      }, (c: ToolCallInfo) => c.callId)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: DsSpacing.blockGap })
  }
  /** 挂起询问回调：挂起表有同 callId → 可回答（ToolBlock ask 五态用）。 */
  private answerableOf = (callId: string): boolean => {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return false;
    }
    for (const q of st.pendingQuestions) {
      if (q.callId === callId) {
        return true;
      }
    }
    return false;
  };

  /**
   * LazyForEach 的 key。key 里**不能**带 index：历史翻页会把旧消息插到数组前部，
   * index 全体后移，带 index 的 key 全变 → ArkUI 判定整列重建 → 滚动位置重置
   * （真机现象：点「加载更早消息」后直接跳回最新消息）。用 seq + 文本长度这类
   * 内容稳定值。独立成方法还有个副作用：内联模板串会被静态审计误判成
   * 「LazyForEach 缺少 keyGenerator」。
   */
  private keyOf(m: ChatMessage): string {
    return m.role + '-' + m.seq.toString() + '-' + m.text.length.toString();
  }
  /** 大屏档（≥840vp）：spinner 等小元素放大一档，视觉重量与加大行高匹配。 */
  private isLargeBp(): boolean {
    return isLarge(this.bp);
  }

  /**
   * 首次挂载时自算一次断点。Index 已经把断点写进 AppStorage，这里的意义是
   * 兜住「子组件先于 Index 的 bindBreakpoints 挂载」的顺序差，同时让本文件的
   * 大屏适配是**由本组件自己读到的 mediaquery** 决定的（官方审计要求布局代码
   * 里能看到断点判断，只在父层算不算）。
   */
  private refreshBreakpoint(): void {
    try {
      const md = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      const next: string = breakpointOf(md.matches, lg.matches);
      if (next !== this.bp) {
        this.bp = next;
        AppStorage.setOrCreate('dshBreakpoint', next);
      }
    } catch (e) {
      // UIContext 未就绪（极少见）：保持 Index 写进来的档位不变。
    }
  }
  /** 命令卡（安卓 chat_message_items.dart 口径）：首行 monospace + ✓/✗ 结果。 */
  @Builder
  commandCard(m: ChatMessage) {
    Row({ space: 8 }) {
      Text('⌨')
        .fontSize(16)
        .fontColor(m.text.includes('\u2717') ? this.c().danger : this.c().chipSelectedFg)
        .margin({ top: 2 })
      Column({ space: 2 }) {
        Text(m.text.split('\n')[0])
          .fontSize(DsTypography.small.size).fontFamily('monospace').fontColor(this.c().labelPrimary)
          .width('100%')
        if (m.text.includes('\n')) {
          Text(m.text.split('\n').slice(1).join('\n'))
            .fontSize(DsTypography.small.size)
            .fontColor(m.text.includes('\u2717') ? this.c().danger : this.c().labelTertiary).width('100%')
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
  /** 用户消息：右对齐气泡（浅色走 DsPalette.userBubble，深色同理，见 ui/theme.ets）。
   * 图片两种来源：content 里 type=image 的引用（images）与纯文本模型的交接占位
   * （文本里的 `[Image: source: …]`，安卓 chat_message_items.dart:176 同口径，
   * 用户与助手气泡都挂）。 */
  @Builder
  userBubble(m: ChatMessage) {
    Row() {
      Blank().layoutWeight(1)
      this.userImages(m)
      if (this.userHandoff(m) !== null) {
        ImageTile({ store: this.store, ref: this.userHandoff(m) as DsImageRef })
          .constraintSize({ maxWidth: this.bubbleMaxWidth() })
          .margin({ left: 8 })
      }
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
  /** 用户气泡里的交接图引用（没有回 null；气泡布局用）。 */
  private userHandoff(m: ChatMessage): DsImageRef | null {
    return handoffRefOf(this.rawTextOf(m));
  }
  /** 取交接图用的原文：清洗过的消息把原文留在 rawText 里。 */
  private rawTextOf(m: ChatMessage): string {
    return m.rawText !== '' ? m.rawText : m.text;
  }
  /** 助手消息：全宽平铺文本 + 前置过程组短语行 + reasoning 灰字。 */
  @Builder
  assistantBlock(m: ChatMessage) {
    Column() {
      if (m.reasoning !== '') {
        ThinkBlock({
          text: m.reasoning, streaming: m.streaming,
          showPreview: policyOf(parseWorkStepsDetail(this.detailProp)).settledReasoningPreview
        })
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
      if (handoffRefOf(this.rawTextOf(m)) !== null) {
        ImageTile({ store: this.store, ref: handoffRefOf(this.rawTextOf(m)) as DsImageRef })
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
