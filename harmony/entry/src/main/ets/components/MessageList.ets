/**
 * 消息列表 —— 对照安卓 chat_message_items.dart / chat_message_list.dart 的阶段 2/3
 * 基础版：用户气泡 / 助手平铺 + Markdown 富渲染（MdView）/ 过程组短语行 / 错误条 /
 * 流式块。布局 token：docs/design-tokens.md（msgPad 30 / bubbleRadius 16 / user 气泡最大宽 86.4%）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage } from '../core/HistoryPage';
import { ToolCallInfo, formatDuration, bashCommandOf, prettyArguments } from '../core/ToolCall';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdView } from './md/MdView';
import { ImageTile } from './ImageTile';
import { UserBubble } from './UserBubble';
import { MessageActions } from './MessageActions';
import { DsImageRef, handoffRefOf } from '../core/ImageRef';
import { MdDocViewer } from '../pages/MdDocViewer';
import { ThinkBlock } from './ThinkBlock';
import { ProcessGroup } from './ProcessGroup';
import { TurnProcessRow } from './TurnProcessRow';
import { TurnCards } from './TurnCards';
import { StreamingBlock } from './StreamingBlock';
import { CommandCard, DeliverableCard, ErrorBar } from './MessageCards';
import { ToolBlock } from './ToolBlock';
import { ArrayDataSource } from './ArrayDataSource';
import { visibleMessagesOf, parseFoldedReplies, parseWorkStepsDetail } from '../core/WorkSteps';
import { policyOf, STEP_GROUPING_NONE } from '../core/ToolDetails';
import { mediaquery } from '@kit.ArkUI';
import {
  BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd, isLarge, readableColumnWidth
} from '../core/Breakpoints';

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
  /** 会话页实测可用宽（vp；0 = 未量到，退 100%）：正文列 = readableColumnWidth(它)。 */
  @StorageProp('dshColumnWidthVp') columnWidth: number = 0;
  /** store 派生消息快照（唯一被观察的数据源）。 */
  @State msgs: ChatMessage[] = [];
  /** 服务端还有更早事件（history 应答 hasMore）—— 决定列表头是否出「加载更早消息」。 */
  /** turn.end reason=max-tokens：列表尾「回答被截断」提示（官方 client.js:6707 文案）。 */
  @State maxTokensNotice: boolean = false;
  @State hasMore: boolean = false;
  /** 服务端按字节预算裁掉更早事件（history-byte-budget-v1）：列表头提示；
   *  与「加载更早消息」并存（hasMore=还能翻，truncated=翻到底也不是会话开头）。 */
  @State truncated: boolean = false;
  /** 正在翻页（按钮换 spinner）。 */
  @State loadingOlder: boolean = false;
  /** 流式正文/思考快照（core 里累积，syncVersion 抄写；本端原先完全没渲染，2026-11-17 补）。 */
  @State streamTextView: string = '';
  @State streamReasoningView: string = '';
  private scroller: Scroller = new Scroller();
  /**
   * 列表数据源（R005 LazyForEach）：`List` 只支持 LazyForEach 做懒加载，
   * 数据经 `syncVersion()` 里的 `reset()` 整批换新。
   */
  private ds: ArrayDataSource<ChatMessage> = new ArrayDataSource<ChatMessage>([]);
  /** 当前首个可见项下标（onScrollIndex 维护），翻页后据此把视口锚回原内容。 */
  private firstIdx: number = 0;
  /** 视口在底部（贴底跟随的粘性开关；用户上滑即撤销）。 */
  @State atBottom: boolean = true;
  /** 粘性贴底意图：上滑置 false，回底/FAB 恢复；不能每帧用 isAtEnd()。 */
  private follow: boolean = true;
  /** 翻页瞬间的锚点快照：首个可见下标 + 当时的消息条数。 */
  private anchorIdx: number = -1;
  private anchorLen: number = 0;
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  @State docOpen: boolean = false;
  @State docPath: string = '';
  @State docTitle: string = '';
  /** 消息气泡最大宽（官方 user 气泡约 86.4% 屏宽）。 */
  private bubbleMaxWidth(): Length {
    return '86.4%';
  }
  /**
   * 流式块是否需要出现 —— 唯一判据是 store.streaming（安卓同口径：
   * app/lib/ui/chat_message_list.dart:302 `if (state.streaming)`）。
   *
   * 原来还兜了「残留增量未清」（streamTextView/streamReasoningView 非空），
   * 2026-11-17 真机证明这个兜底会把轮尾占位钉死：TURN_END 丢帧后
   * streaming 收口成 false，但两个缓冲还留着旧文本，兜底让本块继续存在，
   * 而缓冲被清成空串的那一帧 StreamingBlock 又正好走「两串皆空 → 正在思考…」
   * 分支 —— 服务端早已 running:false，屏上却永远挂着「正在思考…」。
   * 缓冲的清理归 core（TURN_END / TURN_FAILED / cancelTurnIn / resync 对账），
   * 视图层不再自作主张。
   */
  private streamingVisible(): boolean {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return false;
    }
    return st.streaming;
  }

  build() {
    if (this.store !== null) {
      this.renderList();
    }
  }
  @Builder
  renderList() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ scroller: this.scroller, space: 0 }) {
      // 历史翻页入口：官方口径是显式按钮（上滑触发不可靠）。
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
      if (this.truncated) {
        ListItem() {
          Row({ space: 6 }) {
            Text('ⓘ').fontSize(DsTypography.small.size).fontColor(this.c().labelSecondary)
            Text('会话过长，更早的部分未显示')
              .fontSize(DsTypography.small.size).fontColor(this.c().labelSecondary)
          }
          .width('100%').justifyContent(FlexAlign.Center)
          .padding({ top: 6, bottom: 6 })
        }
      }
      LazyForEach(this.ds, (m: ChatMessage, i: number) => {
        ListItem() {
          this.itemOf(m)
        }
        // 逐行变距（§4.12）：新轮首行 24 / 过程组 0 / 同轮消息 8。
        .padding({ top: i === 0 ? 0 : (m.isUser ? DsSpacing.chatGapNewTurn
          : (m.isProcess ? DsSpacing.chatGapProcess : DsSpacing.chatGapSameTurn)) })
      }, (m: ChatMessage) => this.keyOf(m))
      // 流式块：思考/正文增量，排在已提交消息之后；子组件入参必须 @Prop。
      if (this.streamingVisible()) {
        ListItem() {
          StreamingBlock({
            reasoning: this.streamReasoningView, text: this.streamTextView,
            showPreview: policyOf(parseWorkStepsDetail(this.detailProp)).settledReasoningPreview
          })
        }
        .padding({ top: DsSpacing.chatGapSameTurn })
      }
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
      .height('100%')
      .constraintSize({ maxWidth: this.columnWidth > 0 ? readableColumnWidth(this.columnWidth) : '100%' })
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.contentPadRight,
        top: DsSpacing.chatListTopPad, bottom: DsSpacing.chatListBottomPad })
      .scrollBar(BarState.Off)
      .onScrollIndex((first: number): void => {
        this.firstIdx = first;
      })
      .onScroll((delta: number, state: ScrollState) => {
        this.syncAtBottom();
        if (this.atBottom) {
          this.follow = true;
        } else if (state === ScrollState.Scroll && delta < 0) {
          this.follow = false;
        }
      })
      .onReachEnd(() => {
        this.follow = true;
        this.atBottom = true;
      })
      .onAppear(() => {
        this.jumpToBottom(false);
      })
      Column()
        .width('100%')
        .height(DsSpacing.chatListBottomPad)
        .linearGradient({
          angle: 180,
          colors: [[this.veilStart(), 0], [this.c().bgBase, 1]],
        })
        .hitTestBehavior(HitTestMode.None)
      if (!this.atBottom && this.msgs.length > 0) {
        Button('↓')
          .width(48)
          .height(48)
          .fontSize(20)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.c().brand)
          .borderRadius(24)
          .shadow({ radius: 12, color: this.c().shadow })
          .margin({ right: 16, bottom: DsSpacing.chatListBottomPad + 8 })
          .accessibilityText('回到最新消息')
          .onClick((): void => {
            this.follow = true;
            this.jumpToBottom(true);
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .bindContentCover(this.docOpen, this.docViewer(), {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.docOpen = false;
      }
    })
  }

  /** 渐隐带起始色 = bgBase 的同色透明（#00RRGGBB）；异常值退回全透明。 */
  private veilStart(): string {
    const base: string = this.c().bgBase;
    return base.length === 7 ? '#00' + base.substring(1) : '#00000000';
  }

  /** 视口是否贴底：ArkUI 的 isAtEnd 已含「差一像素也算」的语义。 */
  private syncAtBottom(): void {
    try {
      this.atBottom = this.scroller.isAtEnd();
    } catch (e) {
      this.atBottom = true;
    }
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
  /** version 变化：重抄派生数据并跟随贴底。 */
  syncVersion(): void {
    const st: ChatStore | null = this.store;
    // 折叠回复：final 档只看每轮最后一条正文；运行中轮始终全可见。
    const raw: ChatMessage[] = st === null ? [] : st.messages;
    this.msgs = st === null ? [] : visibleMessagesOf(raw, parseFoldedReplies(this.foldedRepliesProp), st.streaming);
    this.ds.reset(this.msgs);
    this.maxTokensNotice = st !== null && st.maxTokensNotice;
    this.streamTextView = st === null ? '' : st.streamText;
    this.streamReasoningView = st === null ? '' : st.streamReasoning;
    this.hasMore = st !== null && st.historyHasMore;
    this.truncated = st !== null && st.historyTruncated;
    this.loadingOlder = st !== null && st.loadingOlder;
    const justLoaded: boolean = st !== null && st.consumeHistoryPageJustLoaded();
    if (!justLoaded && (this.loadingOlder || this.anchorIdx >= 0)) {
      // 翻页期间不贴底（loadingOlder 阶段会连发两次 changed）。
      return;
    }
    if (justLoaded) {
      // 翻页 prepend：记下首可见下标，加载后把同一条消息滚回原位（不跳底）。
      const added: number = this.anchorIdx >= 0 ? this.msgs.length - this.anchorLen : 0;
      const target: number = this.anchorIdx >= 0 ? this.anchorIdx + added : added;
      // 推迟到布局完成（0ms 时索引会被夹到首尾）。
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
    // 新消息/流式增量：按粘性意图贴底，翻历史时不被拽走。
    setTimeout((): void => {
      if (this.follow) {
        this.jumpToBottom(false);
      }
      this.syncAtBottom();
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
      // store 已转成 lastError 并 changed()，这里吞掉避免未处理拒绝。
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
      UserBubble({ store: this.store, text: m.text, rawText: this.rawTextOf(m), images: m.images });
    } else if (m.isError) {
      ErrorBar({ text: m.text });
    } else if (m.role === 'command') {
      CommandCard({ text: m.text });
    } else if (m.role === 'files') {
      DeliverableCard({
        files: m.files,
        onOpenDoc: (path: string, title: string): void => {
          this.docPath = path;
          this.docTitle = title;
          this.docOpen = true;
        }
      });
    } else if (m.isProcess) {
      if (this.detailProp === STEP_GROUPING_NONE) {
        // verbose 平铺：无组标题、无折叠层，逐条工具行（默认收起详情，可展开）。
        this.flatToolRows(m);
      } else {
        ProcessGroup({ group: m, store: this.store });
      }
    } else {
      // 正文 + 轮尾行必须同容器：ListItem 多子组件时会被 Stack 叠放。
      Column() {
        this.assistantBlock(m);
        // 轮尾行（官方 TurnProcessNodeView）：闭合轮给「已完成，用时 N/处理失败」，可点开整轮过程组。
        TurnProcessRow({ store: this.store, msg: m, version: this.version })
        TurnCards({ store: this.store, msg: m, version: this.version })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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

  /** LazyForEach key：禁带 index（翻页会全量重建并重置滚动位置），只用稳定内容值。 */
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
  /** 版本变化后贴底（streaming / 新历史到达时由 ChatView 触发）。 */
  jumpToBottom(animate: boolean): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // 未挂载时忽略。
    }
  }
}
