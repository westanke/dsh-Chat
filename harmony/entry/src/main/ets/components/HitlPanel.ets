/// HITL 交互卡 —— 对齐安卓 question_card.dart（提问卡 + 审批卡）。
/// 挂起面板放在消息列表上方：限高屏高一半（2026-11-15 用户反馈：题目/选项过多
/// 时提交按钮被撑出屏幕外，故面板可滚动）。审批卡先、提问卡后。
/// 提问卡：每题列选项点选（multiSelect 多选），支持「自定义回答」文本；
/// 审批卡：允许一次 / 拒绝两键（协议无「始终允许」）。
import { PendingQuestion, PendingApproval, QuestionAnswerItem, UserQuestion, UserQuestionOption } from '../core/Questions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { mediaquery } from '@kit.ArkUI';
import {
  BP_SM, BP_QUERY_MD, BP_QUERY_LG, breakpointOf, atLeastMd, readableColumnWidth
} from '../core/Breakpoints';

@Component
export struct HitlPanel {
  /** 必须 @Prop：普通成员只在首次创建时赋值，父层 @State 换新数组不会重建子组件
   * （真机现象：提交后提问卡不消失、审批卡根本不出现）。 */
  @Prop questions: PendingQuestion[] = [];
  @Prop approvals: PendingApproval[] = [];
  /** 会话页实测可用宽（vp；0 = 未量到，退 100%）：HITL 卡与正文同轴。 */
  @StorageProp('dshColumnWidthVp') columnWidth: number = 0;
  onAnswer: (q: PendingQuestion, answers: QuestionAnswerItem[]) => void =
    (_q: PendingQuestion, _a: QuestionAnswerItem[]) => {};
  onDecide: (a: PendingApproval, allow: boolean) => void =
    (_a: PendingApproval, _allow: boolean) => {};
  @StorageProp('dshDark') dark: boolean = false;
  /** 窗口宽度断点（R007 一多）：自定义回答输入框高度按档放大。 */
  @StorageProp('dshBreakpoint') bp: string = BP_SM;
  /**
   * 已选 label 集，编码成 `questionId + '\u0001' + label` 的字符串数组。
   * **不能用 Map**：ArkUI 对 Map 内部变更不建立观察依赖，`version++` 也不会让
   * chip 的样式表达式重新求值（真机现象：点选项无高亮、提交键恒灰）。
   * 用 @State 数组整体替换即可驱动重建。
   */
  @State picked: string[] = [];
  /** 每题自定义回答（同样用 @State 数组：`qid + '\u0001' + text`）。 */
  @State customs: string[] = [];
  /** 已提交决定的审批 id（提交后按钮禁用，官方 answered 态）。 */
  @State decided: string[] = [];

  /** 窗口断点自读（R007 一多）：自定义回答输入框在宽屏加高。 */
  private refreshBreakpoint(): void {
    try {
      const md: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_MD);
      const lg: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync(BP_QUERY_LG);
      const next: string = breakpointOf(md.matches, lg.matches);
      if (next !== this.bp) {
        this.bp = next;
        AppStorage.setOrCreate('dshBreakpoint', next);
      }
    } catch (e) {
      // 拿不到 mediaquery 时按手机档渲染。
    }
  }

  private atLeastMd(): boolean {
    return atLeastMd(this.bp);
  }

  aboutToAppear(): void {
    this.refreshBreakpoint();
  }

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 该题已选 label 列表（从 @State picked 解出）。 */
  private pickedOf(qid: string): string[] {
    const out: string[] = [];
    const prefix: string = qid + '\u0001';
    for (const entry of this.picked) {
      if (entry.startsWith(prefix)) {
        out.push(entry.substring(prefix.length));
      }
    }
    return out;
  }

  /** 该题的自定义回答（无则 ''）。 */
  private customOf(qid: string): string {
    const prefix: string = qid + '\u0001';
    for (const entry of this.customs) {
      if (entry.startsWith(prefix)) {
        return entry.substring(prefix.length);
      }
    }
    return '';
  }

  /** 写自定义回答（整体替换 @State 数组触发重建）。 */
  private setCustom(qid: string, text: string): void {
    const prefix: string = qid + '\u0001';
    const next: string[] = [];
    for (const entry of this.customs) {
      if (!entry.startsWith(prefix)) {
        next.push(entry);
      }
    }
    if (text.length > 0) {
      next.push(prefix + text);
    }
    this.customs = next;
  }

  /// 能否提交：每题都要有选择（选项或自定义文本）。
  private canSubmit(): boolean {
    for (const q of this.questions) {
      for (const item of q.questions) {
        const picked: string[] = this.pickedOf(item.id);
        const text: string = this.customOf(item.id).trim();
        if (picked.length === 0 && text.length === 0) {
          return false;
        }
      }
    }
    return true;
  }

  private toggleOption(item: UserQuestion, label: string): void {
    const prefix: string = item.id + '\u0001';
    const current: string[] = this.pickedOf(item.id);
    const at: number = current.indexOf(label);
    const next: string[] = [];
    if (at >= 0) {
      // 再点一次取消。
      for (const l of current) {
        if (l !== label) {
          next.push(prefix + l);
        }
      }
    } else if (item.multiSelect) {
      for (const l of current) {
        next.push(prefix + l);
      }
      next.push(prefix + label);
    } else {
      // 单选：新选替换旧的。
      next.push(prefix + label);
    }
    // 保留其它题的已选项，整体替换本题的。
    const merged: string[] = [];
    for (const entry of this.picked) {
      if (!entry.startsWith(prefix)) {
        merged.push(entry);
      }
    }
    this.picked = merged.concat(next);
  }

  private submit(): void {
    const answers: QuestionAnswerItem[] = [];
    for (const q of this.questions) {
      for (const item of q.questions) {
        answers.push(new QuestionAnswerItem(item.id, this.pickedOf(item.id),
          this.customOf(item.id).trim()));
      }
    }
    this.onAnswer(this.questions[0], answers);
  }

  build() {
    Scroll() {
      Column() {
        Repeat<PendingApproval>(this.approvals)
          .each((entry: RepeatItem<PendingApproval>) => {
            this.approvalCard(entry.item, entry.index)
          })
          .key((entry: PendingApproval) => entry.approvalId)
        Repeat<PendingQuestion>(this.questions)
          .each((entry: RepeatItem<PendingQuestion>) => {
            this.questionCard(entry.item, entry.index)
          })
          .key((entry: PendingQuestion) => entry.callId)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '50%',
      maxWidth: this.columnWidth > 0 ? readableColumnWidth(this.columnWidth) : '100%' })
    .width('100%')
  }

  @Builder
  approvalCard(a: PendingApproval, idx: number) {
    Column() {
      // 顶部状态条：小圆点 + 「等待审批」（官方审批卡 strip；决定提交后整卡变 answered，
      // 按钮禁用）。注意协议只有「允许一次」，没有「始终允许」键（server 侧不存该状态）。
      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 }).fill(this.c().settingsWarnFg)
        Text(this.decided.includes(a.approvalId) ? '已处理' : '等待审批')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().settingsWarnFg)
      }
      .width('100%')
      .margin({ bottom: DsSpacing.liGap })
      Row() {
        Text('⚖')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.c().settingsWarnFg)
          .margin({ right: DsSpacing.processIconGap })
        Text(this.approvalTitle(a))
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(DsTypography.smallStrong.weight)
          .fontColor(this.c().settingsWarnFg)
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      if (a.reason !== null && a.reason.length > 0) {
        Text(a.reason)
          .fontSize(DsTypography.caption.size)
          .fontFamily('monospace')
          .fontColor(this.c().settingsWarnFg)
          .margin({ top: DsSpacing.liGap })
          .width('100%')
      }
      // 命令预览（bridge detail，args.command redact 1200；官方 ApprovalFlow body：
      // 等宽代码字体逐字换行 break-all，失败输出过长不截语义）。
      if (a.detail !== null && a.detail.length > 0) {
        Text(a.detail)
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontFamily('monospace')
          .fontColor(this.c().settingsWarnFg)
          .wordBreak(WordBreak.BREAK_ALL)
          .margin({ top: DsSpacing.liGap })
          .width('100%')
      }
      Row() {
        Blank()
        Text('拒绝')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().danger)
          .opacity(this.allowDecide(a) ? 1 : 0.5)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .accessibilityText(this.allowDecide(a) ? '拒绝本次审批' : '已处理，不可重复操作')
          .onClick(() => this.decide(a, false))
        Text('允许一次')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.allowDecide(a) ? this.c().link : this.c().drawerGroupLabel)
          .borderRadius(DsSpacing.chipRadius)
          .opacity(this.allowDecide(a) ? 1 : 0.5)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ left: DsSpacing.chipGap })
          .accessibilityText(this.allowDecide(a) ? '允许本次审批' : '已处理，不可重复操作')
          .onClick(() => this.decide(a, true))
      }
      .height(DsSpacing.composerButtonSize)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.c().settingsWarnBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .padding(DsSpacing.codeBlockPad)
    .margin({ top: DsSpacing.blockGap })
  }

  /** 审批标题：越权（risk=full-access）与普通授权不同文案（官方 escalation 口径）。 */
  private approvalTitle(a: PendingApproval): string {
    if (a.risk === 'full-access') {
      return '工具 ' + a.toolName + ' 请求越权执行';
    }
    return 'DSH 请求使用 ' + a.toolName;
  }

  /** 同一审批只允许决定一次：提交后禁用两键（重复点击直接忽略）。 */
  private allowDecide(a: PendingApproval): boolean {
    return !this.decided.includes(a.approvalId);
  }

  private decide(a: PendingApproval, allow: boolean): void {
    if (!this.allowDecide(a)) {
      return;
    }
    this.decided = this.decided.concat([a.approvalId]);
    this.onDecide(a, allow);
  }

  @Builder
  questionCard(q: PendingQuestion, qIdx: number) {
    Column() {
      Repeat<UserQuestion>(q.questions)
        .each((entry: RepeatItem<UserQuestion>) => {
          this.oneQuestion(entry.item, qIdx, entry.index)
        })
        .key((entry: UserQuestion) => entry.id + '-' + entry.question.length.toString())
      Row() {
        Blank()
        Text('提交')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.canSubmit() ? this.c().link : this.c().drawerGroupLabel)
          .borderRadius(DsSpacing.chipRadius)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .accessibilityText(this.canSubmit() ? '提交回答' : '提交回答（还没作答）')
          .onClick(() => {
            if (this.canSubmit()) {
              this.submit();
            }
          })
      }
      .width('100%')
      .margin({ top: DsSpacing.liGap })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.c().chipSelectedBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .padding(DsSpacing.codeBlockPad)
    .margin({ top: DsSpacing.blockGap })
  }

  @Builder
  oneQuestion(item: UserQuestion, qIdx: number, idx: number) {
    Column() {
      if (item.header !== null && item.header.length > 0) {
        Text(item.header)
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().drawerGroupLabel)
          .width('100%')
      }
      Text(item.question)
        .fontSize(DsTypography.smallStrong.size)
        .fontWeight(DsTypography.smallStrong.weight)
        .fontColor(this.c().labelPrimary)
        .width('100%')
        .margin({ top: 2 })
      if (item.detail !== null && item.detail.length > 0) {
        Text(item.detail)
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelSecondary)
          .margin({ top: DsSpacing.liGap })
          .width('100%')
      }
      if (item.options.length === 0) {
        this.customField(item, qIdx, idx)
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          Repeat<UserQuestionOption>(item.options)
            .each((entry: RepeatItem<UserQuestionOption>) => {
              this.optionChip(item, entry.item, qIdx, idx, entry.index)
            })
            .key((entry: UserQuestionOption) => entry.label)
        }
        .width('100%')
        .margin({ top: DsSpacing.chipIconGap })
        this.customField(item, qIdx, idx)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: DsSpacing.blockGap })
  }

  @Builder
  optionChip(item: UserQuestion, opt: UserQuestionOption, qIdx: number, idx: number, oi: number) {
    Text(opt.label)
      .fontSize(DsTypography.small.size)
      .fontColor(this.pickedOf(item.id).indexOf(opt.label) >= 0 ? this.c().chipSelectedFg : this.c().labelPrimary)
      .backgroundColor(this.pickedOf(item.id).indexOf(opt.label) >= 0 ? this.c().chipSelectedBg : Color.Transparent)
      .borderRadius(DsSpacing.chipRadius)
      .border({ width: 1, color: this.pickedOf(item.id).indexOf(opt.label) >= 0 ? this.c().chipSelectedFg : this.c().borderL2 })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: DsSpacing.chipIconGap, bottom: DsSpacing.chipIconGap })
      .accessibilityText(opt.label + (this.pickedOf(item.id).indexOf(opt.label) >= 0 ? '，已选中' : ''))
      .onClick(() => this.toggleOption(item, opt.label))
  }

  @Builder
  customField(item: UserQuestion, qIdx: number, idx: number) {
    TextInput({
      text: this.customOf(item.id),
      placeholder: '或输入自定义回答…',
    })
      .fontSize(DsTypography.small.size)
      .fontColor(this.c().labelPrimary)
      .placeholderColor(this.c().inputHintText)
      .backgroundColor(this.c().inputFill)
      .border({ width: 1, color: this.c().inputBorder })
      .borderRadius(DsSpacing.codeBlockRadius)
      .height(this.atLeastMd() ? 48 : 40)
      .width('100%')
      .onChange((value: string) => {
        this.setCustom(item.id, value);
      })
  }
}
