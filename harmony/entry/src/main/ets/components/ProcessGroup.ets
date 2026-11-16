/// 过程组与工具行 —— 与 MessageList 拆开（宪法 §7 单文件 ≤500 行）。
/// 对齐安卓 `app/lib/ui/process_group.dart`。
import { ChatMessage } from '../core/HistoryPage';
import { ToolCallInfo, formatDuration, bashCommandOf, prettyArguments } from '../core/ToolCall';
import { processGroupKey } from '../core/WorkSteps';
import { ChatStore } from '../core/ChatStore';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdCodeBlock } from './md/MdCodeBlock';
/**
 * 过程组 —— 对齐安卓 `app/lib/ui/process_group.dart`（真机反馈 2026-11-04：
 * 「执行了命令」要点开能查看；2026-11-16 用户再次要求「像官方那样，有时间、
 * 可折叠、命令按 BASH 式显示」）。
 *
 * 三层折叠：①整组折成一行短语摘要（默认收起）；②展开后逐条工具行（图标 +
 * 短语 + 参数摘要）；③单条再展开详情（BASH 代码块 / 参数 JSON / 输出 / 耗时）。
 *
 * 工作步骤展示档（通用设置①，AppStorage dshWorkStepsDetail，语义见 core/WorkSteps）：
 * - concise：只渲染折叠行，不可展开（无箭头，点击无效）；
 * - standard：可展开，但工具行不带详情卡（无第三层）；
 * - detailed：现状（默认档，三层齐全）；
 * - verbose：默认全展开（未手工收起的组都展开），永不自动收起。
 *
 * 展开状态收口在 ChatStore.workSteps（ChatWorkSteps，node 直测），组件层不持状态：
 * 展开/收起经 AppStorage dshExpandedVersion（ChatView.setNotify 写）@Watch 回读，
 * 绕开 LazyForEach 同 key 不重建的坑位（@StorageProp 变化对已挂载组件始终生效）。
 */
@Component
export struct ProcessGroup {
  group: ChatMessage = new ChatMessage();
  /** 所属 store（展开状态/档位都在 store.workSteps；null 兜底为收起不可点）。 */
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshWorkStepsDetail') detailProp: string = 'detailed';
  /// 展开集合版本（ChatView.setNotify 每次 changed 时写；初始值由 aboutToAppear 对账）。
  @StorageProp('dshExpandedVersion') @Watch('syncExpanded') expandedVersion: number = 0;
  @State expanded: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.syncExpanded();
  }

  /** 从 store.workSteps 对账展开状态（key=组内首个 callId，无 callId 用 seq）。 */
  private syncExpanded(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      this.expanded = false;
      return;
    }
    this.expanded = st.workSteps.isExpanded(processGroupKey(this.group));
  }

  private toggle(): void {
    // concise 档只渲染折叠行且不可展开。
    if (this.detailProp === 'concise' || this.group.toolCalls.length === 0) {
      return;
    }
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    st.workSteps.toggle(processGroupKey(this.group));
    st.changed();
  }

  /** 组头耗时（两端齐全才显示，时钟倒退不算）。 */
  private headDuration(): string | null {
    const calls: ToolCallInfo[] = this.group.toolCalls;
    if (calls.length === 0) {
      return null;
    }
    return formatDuration(this.group.durationMs);
  }

  private chevronVisible(): boolean {
    return this.detailProp !== 'concise' && this.group.toolCalls.length > 0;
  }

  build() {
    Column() {
      Row({ space: 0 }) {
        Text('🔧')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.headColor())
          .margin({ right: DsSpacing.processIconGap })
        Text(this.group.phraseText)
          .fontSize(DsTypography.small.size)
          .fontColor(this.headColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.headDuration() !== null) {
          Text(this.headDuration() as string)
            .fontSize(DsTypography.caption.size)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 6 })
        }
        if (this.chevronVisible()) {
          Text(this.expanded ? '⌃' : '⌄')
            .fontSize(16)
            .fontColor(this.headColor())
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .height(DsSpacing.processRowHeight)
      .accessibilityText(this.group.phraseText + (this.expanded ? '，收起' : '，展开'))
      .onClick((): void => {
        this.toggle();
      })
      if (this.expanded) {
        Column() {
          Repeat<ToolCallInfo>(this.group.toolCalls)
            .each((item: RepeatItem<ToolCallInfo>) => {
              ToolRow({ call: item.item })
            })
            .key((item: ToolCallInfo) => item.callId)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: DsSpacing.blockGap })
  }

  private headColor(): string {
    for (const t of this.group.toolCalls) {
      if (t.failed) {
        return this.c().labelTertiary;
      }
    }
    return this.c().labelSecondary;
  }
}

/** 展开后的单条工具调用：图标 + 短语 + 参数摘要；点整行再展开详情。
 *  standard 档不带详情层（读 AppStorage 档位自判，绕开同 key 不重建的坑位）。 */
@Component
export struct ToolRow {
  call: ToolCallInfo = new ToolCallInfo('', '', [], null, false, null, null, null);
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshWorkStepsDetail') detailProp: string = 'detailed';
  @State detail: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private allowDetail(): boolean {
    return this.detailProp !== 'standard';
  }

  private hasDetail(): boolean {
    return this.call.resultText !== null || this.call.durationMs !== null
      || (this.call.rawArguments !== null && this.call.rawArguments.trim() !== '');
  }

  private rowColor(): string {
    return this.call.failed ? this.c().labelTertiary : this.c().labelSecondary;
  }

  build() {
    Column() {
      Row() {
        Text(this.call.failed ? '⊘' : '○')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.rowColor())
          .margin({ top: 2, right: DsSpacing.processIconGap })
        Column() {
          Text(this.call.phrases.length === 0 ? this.call.name : this.call.phrases.join('，'))
            .fontSize(DsTypography.small.size)
            .fontColor(this.rowColor())
            .width('100%')
          if (this.call.summary !== null) {
            Text(this.call.summary as string)
              .fontSize(DsTypography.codeBlockLabel.size)
              .fontFamily('monospace')
              .fontColor(this.c().labelTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.allowDetail() && this.hasDetail()) {
          Text(this.detail ? '⌃' : '⌄')
            .fontSize(14)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 4, bottom: 4 })
      .accessibilityText((this.call.phrases.length === 0 ? this.call.name : this.call.phrases.join('，')) + (this.detail ? '，收起详情' : '，展开详情'))
      .onClick((): void => {
        if (this.allowDetail() && this.hasDetail()) {
          this.detail = !this.detail;
        }
      })
      if (this.detail) {
        this.detailBlock()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 详情卡片 —— 对齐官方 web 端工具卡的观感：整块灰底描边卡片，工具名
   * monospace 小字头，命令走 BASH 代码块，输入/输出分节。 */
  @Builder
  detailBlock() {
    Column({ space: 0 }) {
      // 卡片头：工具名 + 状态 + 耗时（官方 web：`bash` 12.3s ✓）
      Row() {
        Text(this.call.name === '' ? 'tool' : this.call.name)
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontFamily('monospace')
          .fontColor(this.c().labelSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (formatDuration(this.call.durationMs) !== null) {
          Text(formatDuration(this.call.durationMs) as string)
            .fontSize(DsTypography.caption.size)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 6 })
        }
        Text(this.call.failed ? '✗' : '✓')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.call.failed ? this.c().danger : this.c().labelTertiary)
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })

      Divider().color(this.c().inputBorder).strokeWidth(1)

      Column({ space: 6 }) {
        if (bashCommandOf(this.call.name, this.call.rawArguments) !== null) {
          MdCodeBlock({
            lang: 'BASH',
            code: bashCommandOf(this.call.name, this.call.rawArguments) as string
          })
        } else if (prettyArguments(this.call.rawArguments) !== null) {
          this.section('参数', prettyArguments(this.call.rawArguments) as string,
            this.c().labelSecondary)
        }
        if (this.call.resultText !== null) {
          this.section(this.call.failed ? '错误' : '输出', this.call.resultText as string,
            this.call.failed ? this.c().danger : this.c().labelSecondary)
        } else if (!this.call.failed && this.call.durationMs !== null) {
          Text('结果为空')
            .fontSize(DsTypography.caption.size)
            .fontColor(this.c().labelTertiary)
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 8, bottom: 10 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, left: DsSpacing.processIconSize + DsSpacing.processIconGap })
    .backgroundColor(this.c().bgLayer1)
    .borderRadius(DsSpacing.codeBlockRadius)
    .borderWidth(1)
    .borderColor(this.c().inputBorder)
  }

  /** 一节的标题 + 正文（正文等宽、最多 24 行，超出省略）。 */
  @Builder
  section(label: string, body: string, bodyColor: string) {
    Column() {
      Text(label)
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
      Text(body)
        .fontSize(DsTypography.codeBlock.size)
        .fontFamily('monospace')
        .fontColor(bodyColor)
        .maxLines(24)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
