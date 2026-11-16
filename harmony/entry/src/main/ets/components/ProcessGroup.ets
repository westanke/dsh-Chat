/// 过程组与工具行 —— 与 MessageList 拆开（宪法 §7 单文件 ≤500 行）。
/// 对齐安卓 `app/lib/ui/process_group.dart`。
import { ChatMessage } from '../core/HistoryPage';
import { ToolCallInfo, formatDuration, bashCommandOf, prettyArguments } from '../core/ToolCall';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdCodeBlock } from './md/MdCodeBlock';
/**
 * 过程组 —— 对齐安卓 `app/lib/ui/process_group.dart`（真机反馈 2026-11-04：
 * 「执行了命令」要点开能查看；2026-11-16 用户再次要求「像官方那样，有时间、
 * 可折叠、命令按 BASH 式显示」）。
 *
 * 三层折叠：①整组折成一行短语摘要（默认收起）；②展开后逐条工具行（图标 +
 * 短语 + 参数摘要）；③单条再展开详情（BASH 代码块 / 参数 JSON / 输出 / 耗时）。
 */
@Component
export struct ProcessGroup {
  group: ChatMessage = new ChatMessage();
  @StorageProp('dshDark') dark: boolean = false;
  @State expanded: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 组头耗时（两端齐全才显示，时钟倒退不算）。 */
  private headDuration(): string | null {
    const calls: ToolCallInfo[] = this.group.toolCalls;
    if (calls.length === 0) {
      return null;
    }
    return formatDuration(this.group.durationMs);
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
        if (this.group.toolCalls.length > 0) {
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
        if (this.group.toolCalls.length > 0) {
          this.expanded = !this.expanded;
        }
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

/** 展开后的单条工具调用：图标 + 短语 + 参数摘要；点整行再展开详情。 */
@Component
export struct ToolRow {
  call: ToolCallInfo = new ToolCallInfo('', '', [], null, false, null, null, null);
  @StorageProp('dshDark') dark: boolean = false;
  @State detail: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
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
        if (this.hasDetail()) {
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
        if (this.hasDetail()) {
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
