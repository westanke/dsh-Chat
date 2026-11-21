/**
 * 输入文本框 —— 从 Composer.ets 拆出（宪法 §7 单文件 ≤500 行）。
 *
 * 只负责一屏文本域：受控 text + 占位文案 + 光标回调；面板与发送逻辑仍在
 * Composer.ets。样式与拆分前逐值一致（字号 16 / 圆角 2 / 最小高 44 / 最大高 120）。
 */

import { DsColors, DsTypography } from '../ui/theme';

@Component
export struct ComposerInput {
  @Prop text: string = '';
  /** 可用态（不能叫 enabled：与 CustomComponent 基类属性冲突）。 */
  @Prop inputEnabled: boolean = true;
  /** 文本变化（面板据此重算）。 */
  onChanged: (v: string) => void = (): void => {};
  /** 光标位置变化（@ 片段解析依赖真实位置）。 */
  onCaret: (start: number) => void = (): void => {};
  /** 失焦（点输入框外）：命令面板跟着收起，与 dsh-go 点面板外关闭同口径。 */
  onBlurred: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    TextArea({
      text: this.text,
      placeholder: '发消息或创建任务，/ 调用指令，@ 文件或对话',
      controller: new TextAreaController(),
    })
      .placeholderFont(DsTypography.inputPlaceholder)
      .fontColor(this.c().labelPrimary)
      .placeholderColor(this.c().inputHintText)
      .backgroundColor(Color.Transparent)
      // ArkUI TextArea 默认圆角 20；这里要跟外层胶囊贴合走直角，取最小合法档 2
      //（R003 的圆角档位不含 0）。
      .borderRadius(2)
      .fontSize(16)
      .caretColor(this.c().brand)
      .constraintSize({ minHeight: 44, maxHeight: 120 })
      .width('100%')
      .padding({ left: 6, right: 6, top: 12, bottom: 2 })
      .onChange((v: string) => {
        this.onChanged(v);
      })
      .onTextSelectionChange((start: number, end: number) => {
        this.onCaret(start);
      })
      .onBlur(() => {
        this.onBlurred();
      })
      .enabled(this.inputEnabled)
  }
}
