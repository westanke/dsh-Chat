/**
 * 待发送图片 chip 行（安卓 composer_widgets 多图预览口径）：
 * 横排可滚，每个 chip 图标 + 文件名（超 16 字截断）+ 移除钮，最大宽 128。
 */

import { DsColors, DsSpacing } from '../ui/theme';

@Component
export struct ImageChips {
  @Prop names: string[] = [];
  onRemove: ((index: number) => void) | null = null;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private shortName(name: string): string {
    return name.length > 16 ? name.substring(0, 16) + '…' : name;
  }

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.names, (name: string, i: number) => {
          Row({ space: 4 }) {
            Text('🖼')
              .fontSize(12)
              .fontColor(this.c().chipSelectedFg)
            Text(this.shortName(name))
              .fontSize(12)
              .fontColor(this.c().chipSelectedFg)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 96 })
            Text('✕')
              .fontSize(12)
              .fontColor(this.c().labelTertiary)
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
              .accessibilityText('移除第 ' + (i + 1) + ' 张图片')
              .onClick((): void => {
                if (this.onRemove !== null) {
                  this.onRemove(i);
                }
              })
          }
          .padding({ left: 8, right: 6, top: 4, bottom: 4 })
          .constraintSize({ maxWidth: 128 })
          .borderRadius(DsSpacing.chipRadius)
          .backgroundColor(this.c().chipSelectedBg)
        }, (name: string, i: number) => i + '-' + name)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 6 })
  }
}
