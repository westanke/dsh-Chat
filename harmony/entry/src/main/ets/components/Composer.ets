/**
 * 输入条 —— 对照安卓 composer.dart 阶段 2 基础版：
 * 多行输入 + 发送钮；流式中变「停止」（cancelTurn）。
 * 命令面板 / 图片 / @引用 / 工作目录 chip 是阶段 4（PORT-MAP ☐）。
 * 视觉：inputFill 圆角 22，高随内容 3 行封顶；发送钮 brand 底白箭头。
 */

import { ChatStore } from '../core/ChatStore';
import { GatewayState } from '../core/GatewayEvents';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct Composer {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  @Prop version: number = 0;
  /** 受控草稿（发完清空）。 */
  @State draft: string = '';
  private maxLines: number = 5;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private st(): ChatStore | null {
    return this.store;
  }

  private connected(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.connectionState === GatewayState.READY;
  }

  private streaming(): boolean {
    const st: ChatStore | null = this.store;
    return st !== null && st.streaming;
  }

  private send(): void {
    const st: ChatStore | null = this.store;
    if (st === null) {
      return;
    }
    const text: string = this.draft.trim();
    if (text === '') {
      return;
    }
    this.draft = '';
    st.send(text);
  }

  private stop(): void {
    const st: ChatStore | null = this.store;
    if (st !== null) {
      st.cancelTurn();
    }
  }

  build() {
    Column() {
      if (this.lastError() !== null) {
        Text(this.lastError() as string)
          .fontSize(13)
          .fontColor(this.c().danger)
          .maxLines(2)
          .width('100%')
          .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
            bottom: 6 })
      }
      Row({ space: 10 }) {
        TextArea({ text: this.draft, placeholder: '给 DSH 发送消息',
          controller: new TextAreaController() })
          .placeholderFont(DsTypography.inputPlaceholder)
          .fontColor(this.c().labelPrimary)
          .placeholderColor(this.c().inputHintText)
          .backgroundColor(this.c().inputFill)
          .borderRadius(22)
          .border({ width: 1, color: this.c().inputBorder })
          .fontSize(16)
          .caretColor(this.c().brand)
          .constraintSize({ minHeight: 44, maxHeight: 132 })
          .layoutWeight(1)
          .padding({ left: 14, right: 12, top: 11, bottom: 11 })
          .onChange((v: string) => {
            this.draft = v;
          })
          .enabled(this.connected())
        if (this.streaming()) {
          Button('停止', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.c().inputFill)
            .fontColor(this.c().labelPrimary)
            .fontSize(13)
            .onClick(() => {
              this.stop();
            })
        } else {
          Button('发送', { type: ButtonType.Circle })
            .width(44)
            .height(44)
            .backgroundColor(this.draft.trim() === '' || !this.connected()
              ? this.c().borderL2 : this.c().brand)
            .fontColor(this.draft.trim() === '' || !this.connected()
              ? this.c().labelTertiary : this.c().onBrand)
            .fontSize(13)
            .enabled(this.draft.trim() !== '' && this.connected())
            .onClick(() => {
              this.send();
            })
        }
      }
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad,
        bottom: 10 })
    }
  }

  private lastError(): string | null {
    const st: ChatStore | null = this.store;
    return st === null ? null : st.lastError;
  }
}
