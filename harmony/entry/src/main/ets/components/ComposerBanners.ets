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
