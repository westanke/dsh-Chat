/**
 * 输入条底部操作行（从 Composer 抽出控行数）：
 * 左「＋」加图 →「📁」选择项目内容 → 权限 chip，右侧发送/停止圆键。
 * 发送键禁用态不用 .enabled(false)（ArkUI 会整体叠 0.4 透明度，对比度跌破
 * WCAG AA），改为保持可点、onClick 里判空。
 */

import { DsColors, DsSpacing } from '../ui/theme';
import { PermissionChip } from './PermissionChip';

@Component
export struct ComposerActions {
  @Prop hasImage: boolean = false;
  @Prop streaming: boolean = false;
  @Prop sendEnabled: boolean = false;
  @Prop permissionLabel: string = '权限';
  @Prop wide: boolean = false;
  onPickImage: (() => void) | null = null;
  onProject: (() => void) | null = null;
  onPermission: (() => void) | null = null;
  onSend: (() => void) | null = null;
  onStop: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Row({ space: 8 }) {
      Text('＋')
        .fontSize(20)
        .fontColor(this.hasImage ? this.c().onBrand : this.c().labelPrimary)
        .width(DsSpacing.composerButtonSize)
        .height(DsSpacing.composerButtonSize)
        .borderRadius(DsSpacing.composerButtonSize / 2)
        .backgroundColor(this.hasImage ? this.c().brand : this.c().bgLayer1)
        .border({ width: 1, color: this.c().borderL1 })
        .textAlign(TextAlign.Center)
        .accessibilityText('添加图片')
        .onClick((): void => {
          if (this.onPickImage !== null) {
            this.onPickImage();
          }
        })
      Text('📁')
        .fontSize(12)
        .fontColor(this.c().labelPrimary)
        .width(DsSpacing.composerButtonSize)
        .height(DsSpacing.composerButtonSize)
        .borderRadius(DsSpacing.composerButtonSize / 2)
        .backgroundColor(this.c().bgLayer1)
        .border({ width: 1, color: this.c().borderL1 })
        .textAlign(TextAlign.Center)
        .accessibilityText('选择项目中的内容')
        .onClick((): void => {
          if (this.onProject !== null) {
            this.onProject();
          }
        })
      PermissionChip({
        label: this.permissionLabel,
        onTap: (): void => {
          if (this.onPermission !== null) {
            this.onPermission();
          }
        }
      })
      Blank()
      if (this.streaming) {
        Button('■', { type: ButtonType.Circle })
          .width(this.wide ? 48 : 44)
          .height(this.wide ? 48 : 44)
          .backgroundColor(this.c().brand)
          .fontColor(this.c().onBrand)
          .fontSize(16)
          .accessibilityText('停止生成')
          .onClick((): void => {
            if (this.onStop !== null) {
              this.onStop();
            }
          })
      } else {
        Button('↑', { type: ButtonType.Circle })
          .width(44)
          .height(44)
          .backgroundColor(this.sendEnabled ? this.c().brand : this.c().sendDisabledBg)
          .fontColor(this.sendEnabled ? this.c().onBrand : this.c().sendDisabledFg)
          .fontSize(20)
          .fontWeight(this.sendEnabled ? FontWeight.Bold : FontWeight.Medium)
          .accessibilityText(this.sendEnabled ? '发送' : '发送（未就绪）')
          .onClick((): void => {
            if (this.sendEnabled && this.onSend !== null) {
              this.onSend();
            }
          })
      }
    }
    .width('100%')
    .margin({ top: 2 })
    .padding({ left: 2, right: 2, bottom: 2 })
  }
}
