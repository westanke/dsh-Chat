/// 工具行（五态）与展开详情 —— 官方 Web 会话页工具呈现口径（dsh-client-ui-tool
/// 的 ToolRow / AskQuestionRow / Diff 视图）。从 ProcessGroup 拆出（宪法 §7
/// 单文件 ≤500 行）；纯展示组件，状态推导全在 core/ToolPresent + core/ToolDetails（node 直测）。
/// 行结构：[kind 图标] + toolTitle + summary 同行 + [状态字] + [箭头]。
/// 五态（渲染层按 ToolCallInfo 现状推导，空字段兜底）：running（resultText===null
/// 且 !failed → 右侧「运行中」caption）；error（failed → 右侧「失败」红字，summary
/// 换 resultText 首行红字）；ok（有 result → 无状态字）。
/// 可展开 = resultText!==null || rawArguments!==null（running 也可展开）；standard 档不展开。
import { ToolCallInfo, formatDuration, bashCommandOf } from '../core/ToolCall';
import { kindIcon, toolTitle, toolSummaryOf } from '../core/ToolPresent';
import { DETAIL_DIFF_MAX_LINES, DETAIL_READ_WINDOW, ASK_NOT_ANSWERED, detailModeOf, ioInputOf, ioOutputOf, readLinesOf, askSummaryOf, askQuestions, answerEntries } from '../core/ToolDetails';
import { FileDiff, fileDiffOfCall, DIFF_LINE_ADD, DIFF_LINE_DEL } from '../core/CodeDiff';
import { UserQuestion } from '../core/Questions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdCodeBlock } from './md/MdCodeBlock';

@Component
export struct ToolBlock {
  call: ToolCallInfo = new ToolCallInfo('', '', [], null, false, null, null, null);
  /** 挂起询问回调（ask_user_question 状态机用）：挂起表有同 callId → true。 传查询回调而非整个 store（ChatStore 挂起表按 callId 查）。 */
  answerable: (callId: string) => boolean = (_callId: string): boolean => false;
  @StorageProp('dshDark') dark: boolean = false;
  @StorageProp('dshWorkStepsDetail') detailProp: string = 'detailed';
  @State detail: boolean = false;
  /** diff/read 详情的行内展开（各自独立，重开详情时复位）。 */
  @State diffExpanded: boolean = false;
  @State readExpanded: boolean = false;
  private c(): DsColors {
    return new DsColors(this.dark);
  }
  private allowDetail(): boolean {
    return this.detailProp !== 'standard';
  }

  /** 可展开：有结果或带参数（running 也可展开看参数）。 */
  private expandable(): boolean {
    return this.call.resultText !== null
      || (this.call.rawArguments !== null && this.call.rawArguments.trim() !== '');
  }

  /** 行摘要：ask 用五态状态机，failed 换 resultText 首行红字，其余官方键序摘要。 */
  private rowSummary(): string {
    if (detailModeOf(this.call) === 'ask') {
      return askSummaryOf(this.call, this.answerable(this.call.callId));
    }
    if (this.call.failed && this.call.resultText !== null) {
      return firstLineOfText(this.call.resultText);
    }
    return toolSummaryOf(this.call);
  }
  private toggle(): void {
    if (!this.allowDetail() || !this.expandable()) {
      return;
    }
    if (!this.detail) {
      this.diffExpanded = false;
      this.readExpanded = false;
    }
    this.detail = !this.detail;
  }

  build() {
    Column() {
      Row() {
        Text(kindIconOf(this.call))
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.rowColor())
          .margin({ top: 2, right: DsSpacing.processIconGap })
        Text(toolTitle(this.call.name))
          .fontSize(DsTypography.small.size)
          .fontColor(this.rowColor())
          .flexShrink(0)
        if (this.rowSummary() !== '') {
          Text(this.rowSummary())
            .fontSize(DsTypography.caption.size)
            .fontFamily('monospace')
            .fontColor(this.summaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 6 })
        } else {
          Blank().layoutWeight(1)
        }
        if (this.statusWord() !== '') {
          Text(this.statusWord())
            .fontSize(DsTypography.caption.size)
            .fontColor(this.call.failed ? this.c().danger : this.c().labelTertiary)
            .flexShrink(0)
            .margin({ left: 6 })
        }
        if (this.allowDetail() && this.expandable()) {
          Text(this.detail ? '⌃' : '⌄')
            .fontSize(14)
            .fontColor(this.c().labelTertiary)
            .flexShrink(0)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 4, bottom: 4 })
      .accessibilityText(toolTitle(this.call.name) + (this.detail ? '，收起详情' : '，展开详情'))
      .onClick((): void => {
        this.toggle();
      })
      if (this.detail) {
        this.detailBlock()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
  private rowColor(): string {
    return this.call.failed ? this.c().labelTertiary : this.c().labelSecondary;
  }
  private summaryColor(): string {
    if (this.call.failed) {
      return this.c().danger;
    }
    return this.c().labelTertiary;
  }

  /** 状态字：running → 「运行中」；failed → 「失败」；ok → 空。 */
  private statusWord(): string {
    if (this.call.failed) {
      return '失败';
    }
    return this.call.resultText === null ? '运行中' : '';
  }

  /** 详情卡片：头行（工具名 monospace + 耗时 + ✓/✗）+ 分派正文。 */
  @Builder
  detailBlock() {
    Column({ space: 0 }) {
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
        if (detailModeOf(this.call) === 'diff') {
          this.diffDetail()
        } else if (detailModeOf(this.call) === 'command') {
          this.commandDetail()
        } else if (detailModeOf(this.call) === 'read') {
          this.readDetail()
        } else if (detailModeOf(this.call) === 'ask') {
          this.askDetail()
        } else {
          this.ioDetail()
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

  /** edit/write 详情：本地 diff（−old/＋new 行色），默认 9 行 + 行内展开。 */
  @Builder
  diffDetail() {
    if (fileDiffOfCall(this.call) === null) {
      this.ioDetail()
    } else {
      this.diffLines(fileDiffOfCall(this.call) as FileDiff)
    }
  }
  @Builder
  diffLines(d: FileDiff) {
    ForEach(this.diffWindow(d), (l: DiffLineRow, idx: number) => {
      Row() {
        Text(l.prefix)
          .fontSize(DsTypography.codeBlock.size)
          .fontFamily('monospace')
          .fontColor(this.diffFg(l))
          .width(14)
        Text(l.text)
          .fontSize(DsTypography.codeBlock.size)
          .fontFamily('monospace')
          .fontColor(this.diffFg(l))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 1, bottom: 1, left: 4, right: 4 })
      .borderRadius(2)
      .backgroundColor(this.diffBg(l))
    }, (l: DiffLineRow, idx: number) => l.prefix + l.text + '-' + idx.toString())
    if (!this.diffExpanded && d.lines.length > DETAIL_DIFF_MAX_LINES) {
      Text('… 其余 ' + (d.lines.length - DETAIL_DIFF_MAX_LINES).toString() + ' 行'
        + '　+' + addCountOf(d).toString() + ' -' + delCountOf(d).toString())
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding({ top: 4 })
        .onClick((): void => {
          this.diffExpanded = true;
        })
    }
  }
  private diffWindow(d: FileDiff): DiffLineRow[] {
    const rows: DiffLineRow[] = [];
    const limit: number = this.diffExpanded
      ? d.lines.length
      : Math.min(DETAIL_DIFF_MAX_LINES, d.lines.length);
    for (let i = 0; i < limit; i++) {
      const line = d.lines[i];
      const prefix: string = line.type === DIFF_LINE_ADD ? '+' : (line.type === DIFF_LINE_DEL ? '-' : ' ');
      rows.push(new DiffLineRow(prefix, line.text, line.type));
    }
    return rows;
  }
  private diffFg(l: DiffLineRow): string {
    if (l.type === DIFF_LINE_ADD) {
      return this.c().diffAddFg;
    }
    if (l.type === DIFF_LINE_DEL) {
      return this.c().diffDelFg;
    }
    return this.c().labelSecondary;
  }
  private diffBg(l: DiffLineRow): string {
    if (l.type === DIFF_LINE_ADD) {
      return this.c().diffAddBg;
    }
    if (l.type === DIFF_LINE_DEL) {
      return this.c().diffDelBg;
    }
    return this.c().bgLayer1;
  }

  /** bash/pwsh 详情：命令 BASH 代码块 + 结果正文（失败红）。 */
  @Builder
  commandDetail() {
    if (bashCommandOf(this.call.name, this.call.rawArguments) !== null) {
      MdCodeBlock({
        lang: 'BASH',
        code: bashCommandOf(this.call.name, this.call.rawArguments) as string
      })
    }
    this.resultSection()
  }

  /** read 详情：结果按行切，默认 8 行 + 行内展开 + 行数说明。 */
  @Builder
  readDetail() {
    ForEach(this.readWindow(), (line: string, idx: number) => {
      Text(line === '' ? ' ' : line)
        .fontSize(DsTypography.codeBlock.size)
        .fontFamily('monospace')
        .fontColor(this.c().labelSecondary)
        .width('100%')
    }, (line: string, idx: number) => idx.toString() + '-' + line)
    if (!this.readExpanded && this.readTotal() > DETAIL_READ_WINDOW) {
      Text('… 其余 ' + (this.readTotal() - DETAIL_READ_WINDOW).toString() + ' 行')
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .padding({ top: 4 })
        .onClick((): void => {
          this.readExpanded = true;
        })
    }
    if (this.readTotal() > DETAIL_READ_WINDOW) {
      Text('显示 ' + this.readTotal().toString() + ' 行中的 '
        + (this.readExpanded ? this.readTotal() : DETAIL_READ_WINDOW).toString() + ' 行')
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
        .margin({ top: 2 })
    }
  }
  private readTotal(): number {
    return this.call.resultText === null ? 0 : readLinesOf(this.call.resultText).length;
  }
  private readWindow(): string[] {
    if (this.call.resultText === null) {
      return [];
    }
    const lines: string[] = readLinesOf(this.call.resultText);
    if (this.readExpanded) {
      return lines;
    }
    return lines.slice(0, DETAIL_READ_WINDOW);
  }

  /** ask_user_question 详情：已答 → 逐问卡；未答/等待 → verdict + 问题列表。 */
  @Builder
  askDetail() {
    if (toEntryItems(this.call.resultText) !== null
      && (toEntryItems(this.call.resultText) as AnswerEntries).length > 0) {
      ForEach(askQuestionsOf(this.call), (q: UserQuestion) => {
        this.askCard(q, toEntryItems(this.call.resultText) as AnswerEntries)
      }, (q: UserQuestion) => q.id)
    } else {
      Text(askSummaryOf(this.call, this.answerable(this.call.callId)))
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
      ForEach(askQuestionsOf(this.call), (q: UserQuestion) => {
        Text(q.question)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelSecondary)
          .width('100%')
      }, (q: UserQuestion) => q.id)
    }
  }
  @Builder
  askCard(q: UserQuestion, entries: AnswerEntries) {
    Column({ space: 4 }) {
      Text(q.question)
        .fontSize(DsTypography.small.size)
        .fontColor(this.c().brand)
        .width('100%')
      ForEach(this.answersOf(q, entries), (a: string) => {
        Text(a)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelPrimary)
          .width('100%')
      }, (a: string) => a)
      if (this.answersOf(q, entries).length === 0) {
        Text(ASK_NOT_ANSWERED)
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 6, bottom: 6, left: 8, right: 8 })
    .borderRadius(DsSpacing.inlineCodeRadius)
    .backgroundColor(this.c().inputFill)
  }
  private answersOf(q: UserQuestion, entries: AnswerEntries): string[] {
    const out: string[] = [];
    for (const e of entries) {
      if (e.id !== q.id) {
        continue;
      }
      for (const s of e.selected) {
        out.push(s);
      }
      if (e.custom !== '') {
        out.push(e.custom);
      }
    }
    return out;
  }

  /** 其余工具详情：输入（run_code 显示 code 正文，其余 JSON 美化截 200）+ 输出。 */
  @Builder
  ioDetail() {
    if (ioInputOf(this.call) !== '') {
      this.section('输入', ioInputOf(this.call), this.c().labelSecondary)
    }
    this.section(this.call.failed ? '错误' : '输出', ioOutputOf(this.call),
      this.call.failed ? this.c().danger : this.c().labelSecondary)
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

  /** 结果正文（command/io 共用）：空结果兜底「结果为空」。 */
  @Builder
  resultSection() {
    if (this.call.resultText !== null && this.call.resultText !== '') {
      this.section(this.call.failed ? '错误' : '输出', this.call.resultText as string,
        this.call.failed ? this.c().danger : this.c().labelSecondary)
    } else if (ioOutputOf(this.call) !== '') {
      this.section(this.call.failed ? '错误' : '输出', ioOutputOf(this.call),
        this.call.failed ? this.c().danger : this.c().labelSecondary)
    } else if (!this.call.failed) {
      Text('结果为空')
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .width('100%')
    }
  }
}
/** diff 行的渲染元组（prefix/type/text，扁平类，避免判别联合）。 */
class DiffLineRow {
  prefix: string;
  text: string;
  type: string;

  constructor(prefix: string, text: string, type: string) {
    this.prefix = prefix;
    this.text = text;
    this.type = type;
  }
}

type AnswerEntries = AnswerEntryItem[];

class AnswerEntryItem {
  id: string = '';
  selected: string[] = [];
  custom: string = '';
}
/** answerEntries 返回 QuestionAnswerItem[]；这里只要 id/selected/custom 三键， 单独映射成扁平类，避免 UI 层再 import 协议类。 */
function toEntryItems(resultText: string | null): AnswerEntries | null {
  const raw = answerEntries(resultText);
  if (raw === null) {
    return null;
  }
  const out: AnswerEntryItem[] = [];
  for (const e of raw) {
    const item: AnswerEntryItem = new AnswerEntryItem();
    item.id = e.id;
    item.selected = e.selected;
    item.custom = e.custom;
    out.push(item);
  }
  return out;
}
/** ask 问卡/列表的问题来源（解析失败 → 空列表，@Builder 内不判空对象）。 */
function askQuestionsOf(call: ToolCallInfo): UserQuestion[] {
  const questions = askQuestions(call.rawArguments);
  return questions === null ? [] : questions;
}

function kindIconOf(call: ToolCallInfo): string {
  return call.failed ? '⊘' : kindIcon(call.name);
}

function firstLineOfText(text: string): string {
  const lines: string[] = text.split('\n');
  for (const line of lines) {
    if (line.trim() !== '') {
      return line.trim();
    }
  }
  return '';
}

function addCountOf(d: FileDiff): number {
  let n: number = 0;
  for (const l of d.lines) {
    if (l.type === DIFF_LINE_ADD) {
      n += 1;
    }
  }
  return n;
}

function delCountOf(d: FileDiff): number {
  let n: number = 0;
  for (const l of d.lines) {
    if (l.type === DIFF_LINE_DEL) {
      n += 1;
    }
  }
  return n;
}
