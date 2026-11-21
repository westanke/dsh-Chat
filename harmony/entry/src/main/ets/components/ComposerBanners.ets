/**
 * 输入条上方的三行提示（错误 / 权限提示 / 图片错误）—— 从 Composer.ets 切出，
 * 让 Composer 保持在单文件 ≤500 行。对照安卓 composer.dart 的提示条。
 */
import { DsColors, DsSpacing } from '../ui/theme';

@Component
export struct ErrorBanner {
  @Prop message: string = '';
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Text(this.message)
      .fontSize(12)
      .fontColor(this.c().danger)
      .maxLines(2)
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
      .accessibilityText('错误提示，点按查看')
  }
}

@Component
export struct HintBanner {
  @Prop message: string = '';
  /** true 用 danger 色（图片错误），false 用次级色（权限提示）。 */
  @Prop danger: boolean = false;
  @Prop a11y: string = '';
  onDismiss: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Text(this.message)
      .fontSize(12)
      .fontColor(this.danger ? this.c().danger : this.c().labelSecondary)
      .width('100%')
      .padding({ left: DsSpacing.screenPad, right: DsSpacing.screenPad, bottom: 6 })
      .accessibilityText(this.a11y)
      .onClick(() => {
        this.onDismiss();
      })
  }
}

/** 三条提示合一（Composer.build 里一行调用）：各自空串即不显示。 */
@Component
export struct ComposerBanners {
  /** 会话错误（空串 = 没有）。 */
  @Prop error: string = '';
  /** 权限切换结果提示。 */
  @Prop permHint: string = '';
  /** 选图失败提示（危险色）。 */
  @Prop imageError: string = '';
  onDismissPerm: () => void = (): void => {};
  onDismissImage: () => void = (): void => {};

  build() {
    Column() {
      if (this.error.length > 0) {
        ErrorBanner({ message: this.error })
      }
      if (this.permHint.length > 0) {
        HintBanner({
          message: this.permHint,
          a11y: '权限提示，点按关闭',
          onDismiss: (): void => this.onDismissPerm(),
        })
      }
      if (this.imageError.length > 0) {
        HintBanner({
          message: this.imageError,
          danger: true,
          a11y: '图片错误提示，点按关闭',
          onDismiss: (): void => this.onDismissImage(),
        })
      }
    }
  }
}
