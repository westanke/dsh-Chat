/**
 * 设置页「断开连接」分区（从 pages/SettingsView.ets 拆出，让设置页在加入
 * 根外边距/一多约束后仍守住宪法 §7 的单文件 500 行上限）。
 *
 * 与安卓 settings_page.dart `_DisconnectSection` 同语义：红描边按钮 →
 * 二次确认 → 触发 onDisconnect 回连接页。二次确认改用系统 AlertDialog
 * （同 components/PermissionSheet.ets 的惯用法），自绘遮罩层在 Scroll 内
 * 定位不可靠（真机点按无反应），系统对话框在任意容器里都稳定。
 * 本组件不持状态、不碰 store，改动零风险。
 */

import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct SettingsDisconnectSection {
  @StorageProp('dshDark') dark: boolean = false;
  /** 用户确认断开：Index 负责清配对并回连接页。 */
  onDisconnect: (() => void) | null = null;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private askConfirm(): void {
    AlertDialog.show({
      title: '断开连接？',
      message: '本机配对信息会被清除，下次启动需重新输入配对码。',
      primaryButton: {
        value: '取消',
        action: (): void => {
        },
      },
      secondaryButton: {
        value: '断开',
        action: (): void => {
          if (this.onDisconnect !== null) {
            this.onDisconnect();
          }
        },
      },
    });
  }

  build() {
    Column() {
      Text('断开连接')
        .fontSize(DsTypography.caption.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().drawerGroupLabel)
        .width('100%')
        .padding({ top: DsSpacing.blockGap, bottom: DsSpacing.liGap })
      // 与安卓 `_DisconnectSection` 逐项对齐：OutlinedButton(baseStrong 16) +
      // 高度 50 + StadiumBorder（高 50 → 半径 25）。
      Button('断开连接')
        .fontSize(DsTypography.baseStrong.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().danger)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(this.c().danger)
        .borderRadius(DsSpacing.buttonRadius)
        .width('100%')
        .height(DsSpacing.buttonHeight)
        .accessibilityText('断开连接')
        .onClick((): void => {
          this.askConfirm();
        })
      Text('将断开当前连接、清除本机配对并回到连接页；下次启动需重新输入配对码。')
        .fontSize(DsTypography.caption.size)
        .fontColor(this.c().labelTertiary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 8, bottom: DsSpacing.blockGap })
    }
    .width('100%')
  }
}
