/**
 * 输入条三块浮层 —— 对照安卓 composer_panels.dart（阶段 4）：
 * 命令面板 / @ 文件面板 / 权限档位面板。面板壳=inputFill 圆角+边框+阴影，
 * maxHeight 320 可滚，高亮行 chipSelectedBg，单行省略 description。
 */

import { SlashCommand } from '../core/Content';
import { AtEntry } from '../core/AtMention';
import { PermissionOption } from '../core/Permissions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

/** 命令补全面板。 */
@Component
export struct CommandPanel {
  /** @Prop：普通成员只在首次创建时赋值，父层 @State 换新数组不重建子组件
   * （实测表现：命令清单回来了面板仍显示空/旧候选）。 */
  @Prop commands: SlashCommand[] = [];
  onPick: (cmd: SlashCommand) => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Scroll() {
      Column() {
        Repeat<SlashCommand>(this.commands)
          .each((item: RepeatItem<SlashCommand>) => {
            Row({ space: 8 }) {
              Text('›')
                .fontSize(16)
                .fontColor(this.c().chipSelectedFg)
              Text('/' + item.item.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c().labelPrimary)
                .maxLines(1)
              if (item.item.description.length > 0) {
                Text(item.item.description)
                  .fontSize(12)
                  .fontColor(this.c().labelTertiary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              } else {
                Blank().layoutWeight(1)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(item.index === 0 ? this.c().chipSelectedBg : Color.Transparent)
            .accessibilityText('/' + item.item.name +
              (item.item.description.length > 0 ? '：' + item.item.description : ''))
            .onClick(() => {
              this.onPick(item.item);
            })
          })
          .key((item: SlashCommand) => item.name)
      }
      .width('100%')
    }
    .height(Math.min(320, Math.max(44, this.commands.length * 40)))
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(this.c().inputFill)
    .borderRadius(12)
    .border({ width: 1, color: this.c().borderL2 })
    .margin({ bottom: 6 })
  }
}

/** @ 文件面板（空态三态：加载中 / 失败点按重试 / 没有匹配）。 */
@Component
export struct AtFilePanel {
  /** @Prop 四件套：普通成员不随父层 @State 更新 —— 实测 @ 面板永远停在
   * 「正在加载目录…」（entries 已到、loading 却不再变）。 */
  @Prop entries: AtEntry[] = [];
  @Prop loading: boolean = false;
  @Prop failed: boolean = false;
  @Prop dirPath: string = '';
  onPick: (e: AtEntry) => void = (): void => {};
  onRetry: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Scroll() {
      Column() {
        if (this.loading) {
          Text('正在加载目录…')
            .fontSize(12).fontColor(this.c().labelTertiary)
            .width('100%').padding(12)
        } else if (this.failed) {
          Text('目录加载失败，点按重试')
            .fontSize(12).fontColor(this.c().danger)
            .width('100%').padding(12)
            .accessibilityText('目录加载失败，点按重试')
            .onClick(() => {
              this.onRetry();
            })
        } else if (this.entries.length === 0) {
          Text('没有匹配的文件')
            .fontSize(12).fontColor(this.c().labelTertiary)
            .width('100%').padding(12)
        } else {
          Repeat<AtEntry>(this.entries)
            .each((item: RepeatItem<AtEntry>) => {
              Row({ space: 8 }) {
                Text(item.item.isDirectory ? '📁' : '📄')
                  .fontSize(14)
                Text(item.item.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c().labelPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(item.index === 0 ? this.c().chipSelectedBg : Color.Transparent)
              .accessibilityText('/' + item.item.path)
              .onClick(() => {
                this.onPick(item.item);
              })
            })
            .key((item: AtEntry) => item.kind + ':' + item.path)
        }
      }
      .width('100%')
    }
    .height(Math.min(320, Math.max(44, this.entries.length * 40)))
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(this.c().inputFill)
    .borderRadius(12)
    .border({ width: 1, color: this.c().borderL2 })
    .margin({ bottom: 6 })
  }
}

/** 权限档位面板（bindSheet 内容；当前档位打勾）。 */
@Component
export struct PermissionPanel {
  options: PermissionOption[] = [];
  current: string = '';
  onPick: (v: string) => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Column() {
      Text('会话权限档位')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      Repeat<PermissionOption>(this.options)
        .each((item: RepeatItem<PermissionOption>) => {
          Row({ space: 10 }) {
            Text(this.current === item.item.value ? '✓' : '○')
              .fontSize(16)
              .fontColor(this.current === item.item.value ? this.c().brand : this.c().labelTertiary)
            Column({ space: 2 }) {
              Text(item.item.label)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c().labelPrimary)
              if (item.item.descriptionLabel !== null) {
                Text(item.item.descriptionLabel)
                  .fontSize(12)
                  .fontColor(this.c().labelTertiary)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .accessibilityText(item.item.label +
            (item.item.descriptionLabel !== null ? '：' + item.item.descriptionLabel : ''))
          .onClick(() => {
            this.onPick(item.item.value);
          })
        })
        .key((item: PermissionOption) => item.value)
    }
    .width('100%')
    .backgroundColor(this.c().bgBase)
    .padding({ bottom: 12 })
  }
}
