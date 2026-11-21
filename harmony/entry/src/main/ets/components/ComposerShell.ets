/**
 * 输入容器（安卓 composer_bar.dart 同口径）：文本框 + 图片 chip 行 + 底部按钮行
 * 共处一个圆角容器。2026-11-21 从 Composer.ets 抽出，守单文件 ≤500 行纪律；
 * 状态与网络全部留在 Composer，这里只做展示 + 回调上行。
 */

import { DsColors, DsSpacing } from '../ui/theme';
import { ImageChips } from './ImageChips';
import { ComposerActions } from './ComposerActions';
import { ComposerInput } from './ComposerInput';

@Component
export struct ComposerShell {
  @Prop text: string = '';
  @Prop inputEnabled: boolean = true;
  /** 待发送图片的名字（chip 行只显示名字）。 */
  @Prop imageNames: string[] = [];
  @Prop hasPending: boolean = false;
  @Prop streaming: boolean = false;
  @Prop sendEnabled: boolean = false;
  @Prop permissionLabel: string = '';
  /** 宽窗：权限 chip 显示完整文案。 */
  @Prop wide: boolean = false;
  onChanged: (v: string) => void = (): void => {};
  onCaret: (start: number) => void = (): void => {};
  onBlurred: () => void = (): void => {};
  onRemoveImage: (index: number) => void = (): void => {};
  onPickImage: () => void = (): void => {};
  onProject: () => void = (): void => {};
  onPermission: () => void = (): void => {};
  onSend: () => void = (): void => {};
  onStop: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column({ space: 0 }) {
      ComposerInput({
        text: this.text,
        inputEnabled: this.inputEnabled,
        onBlurred: (): void => this.onBlurred(),
        onChanged: (v: string): void => this.onChanged(v),
        onCaret: (start: number): void => this.onCaret(start),
      })
      if (this.imageNames.length > 0) {
        ImageChips({
          names: this.imageNames,
          onRemove: (index: number): void => this.onRemoveImage(index),
        })
      }
      ComposerActions({
        hasPending: this.hasPending,
        streaming: this.streaming,
        sendEnabled: this.sendEnabled,
        permissionLabel: this.permissionLabel,
        wide: this.wide,
        onPickImage: (): void => this.onPickImage(),
        onProject: (): void => this.onProject(),
        onPermission: (): void => this.onPermission(),
        onSend: (): void => this.onSend(),
        onStop: (): void => this.onStop(),
      })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 8 })
    .backgroundColor(this.c().inputFill)
    .borderRadius(24)
    .border({ width: 1, color: this.c().inputBorder })
    .margin({ left: DsSpacing.screenPad, right: DsSpacing.screenPad })
  }
}
