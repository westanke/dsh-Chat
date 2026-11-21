/**
 * 权限 chip（输入条左起第三个）：盾牌 + 权限档位中文 + 展开箭头。
 * 点击由父层打开权限弹层（Composer 的 permSheetOpen）。
 */

import { DsColors } from '../ui/theme';

@Component
export struct PermissionChip {
  @Prop label: string = '权限';
  onTap: (() => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Row({ space: 4 }) {
      Text('🛡')
        .fontSize(12)
        .fontColor(this.c().labelSecondary)
      Text(this.label)
        .fontSize(12)
        .fontColor(this.c().labelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('⌄')
        .fontSize(12)
        .fontColor(this.c().labelSecondary)
    }
    .constraintSize({ maxWidth: 200 })
    .accessibilityText('会话权限：' + this.label)
    .onClick((): void => {
      if (this.onTap !== null) {
        this.onTap();
      }
    })
  }
}
