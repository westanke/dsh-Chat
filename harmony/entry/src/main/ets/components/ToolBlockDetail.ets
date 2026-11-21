/// 工具行展开详情卡 —— 从 ToolBlock 拆出（宪法 §7 ≤500 行）。官方 ToolRow 的
/// 详情正文：ask 问卡 / terminal(命令+结果) / diff / read 行窗 / search 匹配 /
/// web 正文 / io(输入+输出) 七路分派；正文统一等宽、Scroll maxHeight 150、
/// 0.5px 边 4 圆角（官方 ioCard/详情容器口径）。纯展示组件，解析全在 core。
import { ToolCallInfo, formatDuration, bashCommandOf } from '../core/ToolCall';
import { DETAIL_DIFF_MAX_LINES, DETAIL_READ_WINDOW, ASK_NOT_ANSWERED, detailModeOf,
  ioInputOf, ioOutputOf, readLinesOf, readWindowLabelOf, expandRestLabelOf,
  askSummaryOf, askQuestions, answerEntries, searchSummaryOf, webSummaryOf } from '../core/ToolDetails';
import { FileDiff, fileDiffOfCall, DIFF_LINE_ADD, DIFF_LINE_DEL } from '../core/CodeDiff';
import { UserQuestion } from '../core/Questions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdCodeBlock } from './md/MdCodeBlock';

const IO_CARD_MAX_HEIGHT: number = 150;

@Component
export struct ToolBlockDetail {
  @Prop call: ToolCallInfo =
    new ToolCallInfo('', '', [], null, false, null, null, null);
  /** 挂起询问回调（ask_user_question 状态机）：挂起表有同 callId → true。 */
  answerable: (callId: string) => boolean = (_callId: string): boolean => false;
  @StorageProp('dshDark') dark: boolean = false;
  /** diff/read 详情的行内展开（重开详情时由父组件复位）。 */
  @State diffExpanded: boolean = false;
  @State readExpanded: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text(this.call.name === '' ? 'tool' : this.call.name)
          .fontSize(DsTypography.codeBlockLabel.size)
          .lineHeight(DsTypography.codeBlockLabel.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.c().labelSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (formatDuration(this.call.durationMs) !== null) {
          Text(formatDuration(this.call.durationMs) as string)
            .fontSize(DsTypography.caption.size)
            .lineHeight(DsTypography.caption.lineHeight)
            .fontColor(this.c().labelTertiary)
            .margin({ left: 6 })
        }
        Text(this.call.failed ? '✗' : '✓')
          .fontSize(DsTypography.caption.size)
          .lineHeight(DsTypography.caption.lineHeight)
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
        } else if (detailModeOf(this.call) === 'search') {
          this.searchDetail()
        } else if (detailModeOf(this.call) === 'web') {
          this.webDetail()
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

  // ---- diff ---------------------------------------------------------------

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
    Repeat<DiffLineRow>(this.diffWindow(d)).each((item: RepeatItem<DiffLineRow>) => {
      Row() {
        Text(item.item.prefix)
          .fontSize(DsTypography.codeBlock.size)
          .lineHeight(DsTypography.codeBlock.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.diffFg(item.item))
          .width(DsSpacing.diffPrefixWidth)
        Text(item.item.text)
          .fontSize(DsTypography.codeBlock.size)
          .lineHeight(DsTypography.codeBlock.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.diffFg(item.item))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      // 纵向交给 lineHeight（22）撑出行距；原来 top/bottom 各 1 不在 R003 间距集（只有 0,2,4…），
      // 内联 1vp 也看不出差异，直接去掉。
      .padding({ left: DsSpacing.chatGapFootnote, right: DsSpacing.chatGapFootnote })
      .borderRadius(2)
      .backgroundColor(this.diffBg(item.item))
    }).key((l: DiffLineRow) => l.prefix + l.text.length.toString())
    if (!this.diffExpanded && d.lines.length > DETAIL_DIFF_MAX_LINES) {
      Text(expandRestLabelOf(d.lines.length - DETAIL_DIFF_MAX_LINES))
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
    return l.type === DIFF_LINE_ADD ? this.c().diffAddFg
      : (l.type === DIFF_LINE_DEL ? this.c().diffDelFg : this.c().labelSecondary);
  }

  private diffBg(l: DiffLineRow): string {
    return l.type === DIFF_LINE_ADD ? this.c().diffAddBg
      : (l.type === DIFF_LINE_DEL ? this.c().diffDelBg : this.c().bgLayer1);
  }

  // ---- command / read / search / web ---------------------------------------

  /** bash/pwsh 详情：命令 BASH 代码块 + 结果正文（失败红）。 */
  @Builder
  commandDetail() {
    if (bashCommandOf(this.call.name, this.call.rawArguments) !== null) {
      MdCodeBlock({
        lang: 'BASH',
        code: bashCommandOf(this.call.name, this.call.rawArguments) as string
      })
    }
    if (this.call.resultText !== null && this.call.resultText !== '') {
      this.ioCard(this.call.failed ? '错误' : '输出', this.call.resultText as string,
        this.call.failed ? this.c().danger : this.c().labelSecondary)
    }
  }

  /** read 详情：结果按行切，默认 8 行 + 行内展开 + 官方 read.window 行数标签。 */
  @Builder
  readDetail() {
    if (this.call.resultText === null) {
      this.ioDetail()
    } else {
      Repeat<string>(this.readWindow()).each((item: RepeatItem<string>) => {
        Text(item.item === '' ? ' ' : item.item)
          .fontSize(DsTypography.codeBlock.size)
          .lineHeight(DsTypography.codeBlock.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.c().labelSecondary)
          .width('100%')
      }).key((line: string) => line.length.toString() + '|' + line)
      if (!this.readExpanded && this.readTotal() > DETAIL_READ_WINDOW) {
        Text(expandRestLabelOf(this.readTotal() - DETAIL_READ_WINDOW))
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .padding({ top: 4 })
          .onClick((): void => {
            this.readExpanded = true;
          })
      }
      if (this.readTotal() > DETAIL_READ_WINDOW) {
        Text(readWindowLabelOf(this.readExpanded ? this.readTotal() : DETAIL_READ_WINDOW,
          this.readTotal()))
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .width('100%')
          .margin({ top: 2 })
      }
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
    return this.readExpanded ? lines : lines.slice(0, DETAIL_READ_WINDOW);
  }

  /** search 详情（grep/glob）：摘要行 + 匹配正文（等宽滚动卡）。 */
  @Builder
  searchDetail() {
    Text(searchSummaryOf(this.call))
      .fontSize(DsTypography.caption.size)
      .lineHeight(DsTypography.caption.lineHeight)
      .fontColor(this.c().labelTertiary)
      .width('100%')
    if (this.call.resultText !== null && this.call.resultText.trim() !== '') {
      this.ioCard('输出', this.call.resultText as string, this.c().labelSecondary)
    }
  }

  /** web 详情（webSearch/webFetch）：结果正文；空 → 未找到结果。 */
  @Builder
  webDetail() {
    if (this.call.resultText !== null && this.call.resultText.trim() !== '') {
      this.ioCard('输出', this.call.resultText as string, this.c().labelSecondary)
    } else {
      Text(webSummaryOf(this.call))
        .fontSize(DsTypography.caption.size)
        .lineHeight(DsTypography.caption.lineHeight)
        .fontColor(this.c().labelTertiary)
        .width('100%')
    }
  }

  // ---- ask / io -------------------------------------------------------------

  /** ask_user_question 详情：已答 → 逐问卡；未答/等待 → verdict + 问题列表。 */
  @Builder
  askDetail() {
    if (askQuestionsOf(this.call).length > 0) {
      Repeat<UserQuestion>(askQuestionsOf(this.call)).each((item: RepeatItem<UserQuestion>) => {
        this.askCard(item.item, this.askEntries())
      }).key((q: UserQuestion) => q.id)
    } else {
      Text(askSummaryOf(this.call, this.answerable(this.call.callId)))
        .fontSize(DsTypography.caption.size)
        .lineHeight(DsTypography.caption.lineHeight)
        .fontColor(this.c().labelTertiary)
        .width('100%')
      Repeat<UserQuestion>(askQuestionsOf(this.call)).each((item: RepeatItem<UserQuestion>) => {
        Text(item.item.question)
          .fontSize(DsTypography.small.size)
          .lineHeight(DsTypography.small.lineHeight)
          .fontColor(this.c().labelSecondary)
          .width('100%')
      }).key((q: UserQuestion) => q.id)
    }
  }

  @Builder
  askCard(q: UserQuestion, entries: AnswerEntries) {
    Column({ space: 4 }) {
      Text(q.question)
        .fontSize(DsTypography.small.size)
        .lineHeight(DsTypography.small.lineHeight)
        .fontColor(this.c().brand)
        .width('100%')
      Repeat<string>(this.answersOf(q, entries)).each((item: RepeatItem<string>) => {
        Text(item.item)
          .fontSize(DsTypography.small.size)
          .lineHeight(DsTypography.small.lineHeight)
          .fontColor(this.c().labelPrimary)
          .width('100%')
      }).key((a: string) => a)
      if (this.answersOf(q, entries).length === 0) {
        Text(ASK_NOT_ANSWERED)
          .fontSize(DsTypography.small.size)
          .lineHeight(DsTypography.small.lineHeight)
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

  /** 已答条目（解析失败 → 空列表，@Builder 内不判空对象）。 */
  private askEntries(): AnswerEntries {
    const entries: AnswerEntries | null = toEntryItems(this.call.resultText);
    return entries === null ? [] : entries;
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
      this.ioCard('输入', ioInputOf(this.call), this.c().labelSecondary)
    }
    this.ioCard(this.call.failed ? '错误' : '输出', ioOutputOf(this.call),
      this.call.failed ? this.c().danger : this.c().labelSecondary)
  }

  /** ioCard：标签 + 等宽正文（Scroll maxHeight 150）+ 0.5px 边 4 圆角。 */
  @Builder
  ioCard(label: string, body: string, bodyColor: string) {
    Column() {
      Text(label)
        .fontSize(DsTypography.caption.size)
        .lineHeight(DsTypography.caption.lineHeight)
        .fontColor(this.c().labelTertiary)
        .width('100%')
      Scroll() {
        Text(body)
          .fontSize(DsTypography.codeBlock.size)
          .lineHeight(DsTypography.codeBlock.lineHeight)
          .fontFamily('monospace')
          .fontColor(bodyColor)
          .width('100%')
      }
      .constraintSize({ maxHeight: IO_CARD_MAX_HEIGHT })
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderWidth(0.5)
    .borderColor(this.c().inputBorder)
    .borderRadius(4)
    .padding(8)
    .margin({ top: 4, right: 0, bottom: 4, left: 4 })
  }
}

/** diff 行的渲染元组（prefix/type/text，扁平类，避免判别联合）。 */
class DiffLineRow {
  prefix: string;
  text: string;
  type: string;
  constructor(prefix: string, text: string, type: string) {
    this.prefix = prefix; this.text = text; this.type = type;
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
  if (raw === null) { return null; }
  const out: AnswerEntryItem[] = [];
  for (const e of raw) {
    const item: AnswerEntryItem = new AnswerEntryItem();
    item.id = e.id; item.selected = e.selected; item.custom = e.custom;
    out.push(item);
  }
  return out;
}
/** ask 问卡/列表的问题来源（解析失败 → 空列表，@Builder 内不判空对象）。 */
function askQuestionsOf(call: ToolCallInfo): UserQuestion[] {
  const questions = askQuestions(call.rawArguments);
  return questions === null ? [] : questions;
}
