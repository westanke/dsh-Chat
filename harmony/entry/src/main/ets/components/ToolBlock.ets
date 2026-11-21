/// 工具行（官方 ToolRow 结构）：[图标][标题][2px 分隔点][摘要][suffix:退出码徽标
/// 或 +N -M diffStat][chevron]。状态词不再占行——并入 accessibilityText（无障碍
/// 口径）；error 态摘要首行红字（官方 errorSummary 口径）；preparing 不给展开；
/// 详情卡拆至 ToolBlockDetail.ets。
import { ToolCallInfo } from '../core/ToolCall';
import { TOOL_STATUS_PREPARING, TOOL_STATUS_STOPPED, TOOL_STATUS_CANCELLED, ExitBadge, exitBadgeOf } from '../core/StreamTools';
import { toolTitleOf, stripToolPrefix } from '../core/ToolTitles';
import { kindIcon, toolSummaryOf, firstLineOf } from '../core/ToolPresent';
import { detailModeOf, ioInputOf, askSummaryOf, askQuestions, searchSummaryOf, webSummaryOf } from '../core/ToolDetails';
import { fileDiffOfCall, diffStatOf } from '../core/CodeDiff';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { ToolBlockDetail } from './ToolBlockDetail';

@Component
export struct ToolBlock {
  @Prop call: ToolCallInfo =
    new ToolCallInfo('', '', [], null, false, null, null, null);
  /** 行内展开态（关详情即销毁 ToolBlockDetail，重开自动复位行内展开）。 */
  @State detail: boolean = false;
  /** 标准档不展开（foldCompletedTurns 口径），父级按档位传。 */
  allowDetail: boolean = true;
  /** 挂起询问回调（ask 详情 verdict 用）。 */
  answerable: (callId: string) => boolean = (_callId: string): boolean => false;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshStreamToolsVersion') @Watch('onStreamBump') streamVersion: number = 0;
  @StorageProp('dshExpandedVersion') @Watch('onExpandedBump') expandedVersion: number = 0;

  /** 流式刷新占位（@StorageProp 自身变更已触发重渲染）。 */
  onStreamBump(): void {
  }

  onExpandedBump(): void {
  }

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column() {
      Row({ space: 0 }) {
        Text(kindIcon(stripToolPrefix(this.call.name)))
          .fontSize(DsSpacing.processIconSize)
          .width(DsSpacing.processIconSize)
          .textAlign(TextAlign.Center)
        Text(toolTitleOf(this.call.name))
          .fontSize(DsTypography.small.size)
          .fontWeight(FontWeight.Normal)
          .fontColor(this.c().labelSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(0)
          .margin({ left: DsSpacing.processIconGap })
        if (this.rowSummary() !== '') {
          Divider().vertical(true).strokeWidth(2).color(this.c().labelCaption)
            .height(DsSpacing.todoProgressHeight).borderRadius(2)
            .margin({ left: DsSpacing.chatGapSameTurn, right: DsSpacing.chatGapSameTurn })
          Text(this.rowSummary())
            .fontSize(DsTypography.caption.size)
            .fontColor(this.summaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .flexShrink(1)
        } else {
          Blank().layoutWeight(1)
        }
        if (this.suffixText() !== '') {
          Text(this.suffixText())
            .fontSize(DsTypography.caption.size)
            .fontFamily('monospace')
            .fontColor(this.suffixColor())
            .flexShrink(0)
            .margin({ left: 6 })
        }
        if (this.expandable()) {
          Text(this.detail ? '⌃' : '⌄')
            .fontSize(DsSpacing.processIconSize)
            .fontColor(this.c().labelTertiary)
            .flexShrink(0)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .height(DsSpacing.processRowHeight)
      .padding({ left: 4, right: 4 })
      .borderRadius(4)
      .opacity(this.call.status === TOOL_STATUS_PREPARING ? 0.7 : 1)
      .accessibilityText(this.a11yText())
      .onClick((): void => {
        if (this.expandable() && this.allowDetail) {
          this.detail = !this.detail;
        }
      })
      if (this.detail && this.allowDetail) {
        ToolBlockDetail({
          call: this.call,
          answerable: this.answerable
        })
      }
    }
    .width('100%')
  }

  /** a11y 口径：标题 + 状态词 + 展开提示（状态词不再渲染进行内）。 */
  private a11yText(): string {
    let t: string = toolTitleOf(this.call.name) + this.statusWord();
    t += this.expandable() ? (this.detail ? '，收起详情' : '，展开详情') : '';
    return t;
  }

  private statusWord(): string {
    if (this.call.status === TOOL_STATUS_PREPARING) {
      return '，准备中';
    }
    if (this.call.status === TOOL_STATUS_STOPPED) {
      return '，已停止';
    }
    if (this.call.status === TOOL_STATUS_CANCELLED) {
      return '，已取消';
    }
    if (this.call.failed) {
      return '，失败';
    }
    return '';
  }

  /** 行内摘要：ask verdict / search 匹配行 / web 首行 / 错误首行红 / 参数摘要。 */
  private rowSummary(): string {
    const mode: string = detailModeOf(this.call);
    if (mode === 'ask') {
      return askSummaryOf(this.call, this.answerable(this.call.callId));
    }
    if (this.call.failed && this.call.resultText !== null &&
      exitBadgeOf(this.call.resultText) === null) {
      return firstLineOf(this.call.resultText);
    }
    if (mode === 'search' && this.call.resultText !== null) {
      return searchSummaryOf(this.call);
    }
    if (mode === 'web' && this.call.resultText !== null &&
      this.call.resultText.trim() !== '') {
      return webSummaryOf(this.call);
    }
    return toolSummaryOf(this.call);
  }

  private summaryColor(): string {
    if (this.call.failed && this.call.resultText !== null &&
      exitBadgeOf(this.call.resultText) === null) {
      return this.c().danger;
    }
    if (this.call.resultText === null) {
      return this.c().labelSecondary;
    }
    return this.c().labelTertiary;
  }

  /** error/stopped 有「红摘要/停止徽」cue 时不再另显 suffix（官方口径）。 */
  private settledWithCue(): boolean {
    if (this.call.resultText !== null && exitBadgeOf(this.call.resultText) !== null) {
      return false;
    }
    return this.call.failed || this.call.status === TOOL_STATUS_STOPPED ||
      this.call.status === TOOL_STATUS_CANCELLED;
  }

  /** suffix：退出码/信号徽标 → +N -M diffStat → 空。 */
  private suffixText(): string {
    if (this.settledWithCue()) {
      return '';
    }
    if (this.call.resultText !== null) {
      const badge = exitBadgeOf(this.call.resultText);
      if (badge !== null) {
        return this.badgeText(badge);
      }
    }
    if (detailModeOf(this.call) === 'diff') {
      const d = fileDiffOfCall(this.call);
      if (d !== null) {
        return diffStatOf(d);
      }
    }
    return '';
  }

  /** 徽标文案（官方 terminalExitLabel）：信号→「信号 X」、未正常退出→
   * 「未正常退出」（terminal.noExitCode）、非 0→「退出码 N」。 */
  private badgeText(badge: ExitBadge): string {
    if (badge.kind === 'signal') {
      return '信号 ' + badge.value;
    }
    if (badge.kind === 'noExit') {
      return '未正常退出';
    }
    return '退出码 ' + badge.value;
  }

  private suffixColor(): string {
    if (this.call.resultText !== null) {
      const badge = exitBadgeOf(this.call.resultText);
      if (badge !== null && badge.failed && this.call.failed) {
        return this.c().danger;
      }
    }
    return this.c().labelTertiary;
  }

  /** 可展开 = 非 preparing 且有可见正文（官方 ToolRow expandable 口径）。 */
  private expandable(): boolean {
    if (this.call.status === TOOL_STATUS_PREPARING) {
      return false;
    }
    if (detailModeOf(this.call) === 'ask') {
      return askQuestions(this.call.rawArguments) !== null;
    }
    if (ioInputOf(this.call) !== '') {
      return true;
    }
    if (this.call.resultText !== null && this.call.resultText.trim() !== '') {
      return true;
    }
    if (detailModeOf(this.call) === 'diff') {
      return fileDiffOfCall(this.call) !== null;
    }
    return false;
  }
}
