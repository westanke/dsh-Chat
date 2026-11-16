/// HITL 交互卡 —— 对齐安卓 question_card.dart（提问卡 + 审批卡）。
/// 挂起面板放在消息列表上方：限高屏高一半（2026-11-15 用户反馈：题目/选项过多
/// 时提交按钮被撑出屏幕外，故面板可滚动）。审批卡先、提问卡后。
/// 提问卡：每题列选项点选（multiSelect 多选），支持「自定义回答」文本；
/// 审批卡：允许一次 / 拒绝两键（协议无「始终允许」）。
import { PendingQuestion, PendingApproval, QuestionAnswerItem, UserQuestion, UserQuestionOption } from '../core/Questions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct HitlPanel {
  /** 必须 @Prop：普通成员只在首次创建时赋值，父层 @State 换新数组不会重建子组件
   * （真机现象：提交后提问卡不消失、审批卡根本不出现）。 */
  @Prop questions: PendingQuestion[] = [];
  @Prop approvals: PendingApproval[] = [];
  onAnswer: (q: PendingQuestion, answers: QuestionAnswerItem[]) => void =
    (_q: PendingQuestion, _a: QuestionAnswerItem[]) => {};
  onDecide: (a: PendingApproval, allow: boolean) => void =
    (_a: PendingApproval, _allow: boolean) => {};
  @StorageProp('dshDark') dark: boolean = false;
  /**
   * 已选 label 集，编码成 `questionId + '\u0001' + label` 的字符串数组。
   * **不能用 Map**：ArkUI 对 Map 内部变更不建立观察依赖，`version++` 也不会让
   * chip 的样式表达式重新求值（真机现象：点选项无高亮、提交键恒灰）。
   * 用 @State 数组整体替换即可驱动重建。
   */
  @State picked: string[] = [];
  /** 每题自定义回答（同样用 @State 数组：`qid + '\u0001' + text`）。 */
  @State customs: string[] = [];

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
        ForEach(this.approvals, (a: PendingApproval, idx: number) => {
          this.approvalCard(a, idx)
        }, (a: PendingApproval, i: number) => 'a' + i + '-' + a.approvalId)
        ForEach(this.questions, (q: PendingQuestion, idx: number) => {
          this.questionCard(q, idx)
        }, (q: PendingQuestion, i: number) => 'q' + i + '-' + q.callId)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '50%' })
    .width('100%')
  }

  @Builder
  approvalCard(a: PendingApproval, idx: number) {
    Column() {
      Row() {
        Text('⚖')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.c().settingsWarnFg)
          .margin({ right: DsSpacing.processIconGap })
        Text('DSH 请求使用 ' + a.toolName)
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
          .fontColor(this.c().settingsWarnFg)
          .margin({ top: DsSpacing.liGap })
          .width('100%')
      }
      Row() {
        Blank()
        Text('拒绝')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().danger)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .accessibilityText('拒绝本次审批')
          .onClick(() => this.onDecide(a, false))
        Text('允许一次')
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().onBrand)
          .backgroundColor(this.c().link)
          .borderRadius(DsSpacing.chipRadius)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ left: DsSpacing.chipGap })
          .accessibilityText('允许本次审批')
          .onClick(() => this.onDecide(a, true))
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

  @Builder
  questionCard(q: PendingQuestion, qIdx: number) {
    Column() {
      ForEach(q.questions, (item: UserQuestion, idx: number) => {
        this.oneQuestion(item, qIdx, idx)
      }, (item: UserQuestion, i: number) => q.callId + '-' + i + '-' + item.question.length)
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
          ForEach(item.options, (opt: UserQuestionOption, oi: number) => {
            this.optionChip(item, opt, qIdx, idx, oi)
          }, (opt: UserQuestionOption, i: number) => item.id + '-' + i)
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
      .height(36)
      .width('100%')
      .onChange((value: string) => {
        this.setCustom(item.id, value);
      })
  }
}
