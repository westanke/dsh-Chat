/**
 * 输入条三块浮层 —— 对照安卓 composer_panels.dart（阶段 4）：
 * 命令面板 / @ 文件面板 / 权限档位面板。面板壳=inputFill 圆角+边框+阴影，
 * maxHeight 320 可滚，高亮行 chipSelectedBg，单行省略 description。
 */

import { SlashCommand } from '../core/Content';
import { PermissionOption } from '../core/Permissions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

/** @ 面板条目（多根时 name 已带 label/ 前缀，安卓 fetchAtEntries 口径）。 */
export class AtEntry {
  name: string = '';
  path: string = '';
  kind: string = '';
  isDirectory: boolean = false;
}

/** 命令补全面板。 */
@Component
export struct CommandPanel {
  commands: SlashCommand[] = [];
  onPick: (cmd: SlashCommand) => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Scroll() {
      Column() {
        ForEach(this.commands, (cmd: SlashCommand, idx: number) => {
          Row({ space: 8 }) {
            Text('›')
              .fontSize(15)
              .fontColor(this.c().chipSelectedFg)
            Text('/' + cmd.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c().labelPrimary)
              .maxLines(1)
            if (cmd.description.length > 0) {
              Text(cmd.description)
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
          .backgroundColor(idx === 0 ? this.c().chipSelectedBg : Color.Transparent)
          .onClick(() => {
            this.onPick(cmd);
          })
        }, (cmd: SlashCommand) => cmd.name)
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
  entries: AtEntry[] = [];
  loading: boolean = false;
  failed: boolean = false;
  dirPath: string = '';
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
            .fontSize(13).fontColor(this.c().labelTertiary)
            .width('100%').padding(12)
        } else if (this.failed) {
          Text('目录加载失败，点按重试')
            .fontSize(13).fontColor(this.c().danger)
            .width('100%').padding(12)
            .onClick(() => {
              this.onRetry();
            })
        } else if (this.entries.length === 0) {
          Text('没有匹配的文件')
            .fontSize(13).fontColor(this.c().labelTertiary)
            .width('100%').padding(12)
        } else {
          ForEach(this.entries, (e: AtEntry, idx: number) => {
            Row({ space: 8 }) {
              Text(e.isDirectory ? '📁' : '📄')
                .fontSize(14)
              Text(e.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c().labelPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(idx === 0 ? this.c().chipSelectedBg : Color.Transparent)
            .onClick(() => {
              this.onPick(e);
            })
          }, (e: AtEntry) => e.kind + ':' + e.path)
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
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c().labelPrimary)
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      ForEach(this.options, (o: PermissionOption) => {
        Row({ space: 10 }) {
          Text(this.current === o.value ? '✓' : '○')
            .fontSize(16)
            .fontColor(this.current === o.value ? this.c().brand : this.c().labelTertiary)
          Column({ space: 2 }) {
            Text(o.label)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c().labelPrimary)
            if (o.descriptionLabel !== null) {
              Text(o.descriptionLabel)
                .fontSize(12)
                .fontColor(this.c().labelTertiary)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 11, bottom: 11 })
        .onClick(() => {
          this.onPick(o.value);
        })
      }, (o: PermissionOption) => o.value)
    }
    .width('100%')
    .backgroundColor(this.c().bgBase)
    .padding({ bottom: 12 })
  }
}
