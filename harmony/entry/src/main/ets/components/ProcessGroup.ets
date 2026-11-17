/// 过程组标题行 —— 与工具行（ToolBlock）/消息列表（MessageList）拆开
/// （宪法 §7 单文件 ≤500 行）。对齐官方 Web processTitle：
/// - 进行中：最新 running 工具的「正在…」词表 + detail 附加（liveProcessDetail
///   档位开关，concise 不带 detail；无 running 工具取组内 reasoning 尾段）；
/// - 完成：按 kind 聚合 counts 降序取前 3 类，done 词组合（2 类「并」、
///   ≥3 类「，」、>3 类加「等」、空组「已完成分析」）。
/// - 恒展开（alwaysOpen）：组所属轮未结束 / 组后同轮有 user 消息（core/
///   ToolPresent.isGroupForceOpen），此时无视收起集合强制展开。
import { ChatMessage } from '../core/HistoryPage';
import { ToolCallInfo, formatDuration } from '../core/ToolCall';
import { processGroupKey, parseWorkStepsDetail } from '../core/WorkSteps';
import { ChatStore } from '../core/ChatStore';
import { GroupTitleOptions, hasRunningCall, processGroupTitle } from '../core/ToolPresent';
import { policyOf, isGroupForceOpen } from '../core/ToolDetails';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { ToolBlock } from './ToolBlock';
/**
 * 过程组 —— 三层折叠：①整组折成一行标题（官方 processTitle 口径）；②展开后
 * 逐条工具行（ToolBlock，五态）；③单条再展开详情（diff/命令/行窗口/IN-OUT）。
 *
 * 工作步骤展示档（通用设置①，AppStorage dshWorkStepsDetail，语义见 core/WorkSteps
 * 与 core/ToolDetails.policyOf）：
 * - concise：只渲染折叠行，不可展开，标题不带 detail；
 * - standard：可展开，工具行不带详情卡；
 * - detailed：现状（默认档，三层齐全）+ 完成轮组照旧折叠、最新一轮 deferCollapse
 *   （收起时机在 core/ChatWorkSteps.collapseTurnOnCompletion）；
 * - verbose：平铺（MessageList 直接逐条渲染 ToolBlock，不走本组件），永不自动收起。
 *
 * 展开状态收口在 ChatStore.workSteps（ChatWorkSteps，node 直测），组件层不持状态：
 * 展开/收起经 AppStorage dshExpandedVersion（ChatView.setNotify 写）@Watch 回读，
 * 绕开 LazyForEach 同 key 不重建的坑位（@StorageProp 变化对已挂载组件始终生效）。
 */
@Component
export struct ProcessGroup {
  group: ChatMessage = new ChatMessage();
  /** 所属 store（展开状态/档位/挂起询问都在 store；null 兜底为收起不可点）。 */
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshWorkStepsDetail') detailProp: string = 'detailed';
  /// 展开集合版本（ChatView.setNotify 每次 changed 时写；初始值由 aboutToAppear 对账）。
  @StorageProp('dshExpandedVersion') @Watch('syncExpanded') expandedVersion: number = 0;
  /// 工具调用实时流版本：流式行就地 mutate（无新 key），靠它触发组头标题重算。
  @StorageProp('dshStreamToolsVersion') @Watch('onStreamBump') streamVersion: number = 0;
  @State expanded: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.syncExpanded();
  }

  /** 恒展开判定：组后同轮有 user（插话）或所属轮未结束。 */
  private forceOpen(): boolean {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return false;
    }
    const idx: number = st.messages.indexOf(this.group);
    if (idx < 0) {
      return false;
    }
    return isGroupForceOpen(st.messages, idx, st.streaming);
  }

  /** 从 store.workSteps 对账展开状态（key=组内首个 callId，无 callId 用 seq）。 */
  private syncExpanded(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      this.expanded = false;
      return;
    }
    this.expanded = this.forceOpen() || st.workSteps.isExpanded(processGroupKey(this.group));
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

  /** 实时流版本 bump：流式行是就地 mutate（无新 key），靠状态变化触发组头重渲染。 */
  private onStreamBump(): void {
  }

  /** 官方 processTitle：进行中「正在…」词表（+detail），完成组 done 词组合。 */
  private titleText(): string {
    const opts: GroupTitleOptions = new GroupTitleOptions();
    opts.liveProcessDetail = policyOf(parseWorkStepsDetail(this.detailProp)).liveProcessDetail;
    opts.reasoning = this.group.reasoning;
    return processGroupTitle(this.group.toolCalls, hasRunningCall(this.group.toolCalls), opts);
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

  /** 挂起询问回调：挂起表有同 callId → 可回答（ask_user_question 五态用）。 */
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

  build() {
    Column() {
      Row({ space: 0 }) {
        Text('🔧')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.headColor())
          .margin({ right: DsSpacing.processIconGap })
        Text(this.titleText())
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
      .accessibilityText(this.titleText() + (this.expanded ? '，收起' : '，展开'))
      .onClick((): void => {
        this.toggle();
      })
      if (this.expanded) {
        Column() {
          Repeat<ToolCallInfo>(this.group.toolCalls)
            .each((item: RepeatItem<ToolCallInfo>) => {
              ToolBlock({ call: item.item, answerable: this.answerableOf })
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
