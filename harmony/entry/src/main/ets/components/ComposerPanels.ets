/**
 * 输入条三块浮层 —— 对照安卓 composer_palette.dart / composer_panels.dart：
 * 命令面板 / @ 文件面板 / 权限档位面板。
 * 命令面板视觉逐值对齐 dsh-go slash_palette.dart：容器圆角 28、最高 308（5.5 行×56），
 * 行左右内缩 6、行圆角 22、行最小高 52、图标槽 32、尾部回车符 16。
 */

import { SlashCommand, SlashCommandKind } from '../core/Content';
import { AtEntry, AtSessionHit } from '../core/AtMention';
import { PaletteContent, PaletteKind, paletteContentOf, slashPickInsertsText } from '../core/SlashCommands';
import { PermissionOption } from '../core/Permissions';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

/** 参数提示态的副标题（dsh-go：`{description} · 输入参数后发送`）。 */
function hintDetailOf(cmd: SlashCommand): string {
  return cmd.description.length === 0
    ? '输入参数后发送' : cmd.description + ' · 输入参数后发送';
}

/** 命令补全面板：三态（候选 / 参数提示 / 不显示由父层跳过）。 */
@Component
export struct CommandPanel {
  /** @Prop：普通成员只在首次创建时赋值，父层 @State 换新对象不重建子组件。 */
  @Prop content: PaletteContent = paletteContentOf([], '', 0);
  onPick: (cmd: SlashCommand) => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private rowCount(): number {
    if (this.content.kind === PaletteKind.Hint) {
      return 1;
    }
    return Math.max(1, this.content.matches.length);
  }

  build() {
    Scroll() {
      Column() {
        if (this.content.kind === PaletteKind.Hint) {
          this.commandRow(this.content.command as SlashCommand, false,
            hintDetailOf(this.content.command as SlashCommand))
        } else if (this.content.matches.length === 0) {
          this.emptyRow()
        } else {
          Repeat<SlashCommand>(this.content.matches)
            .each((item: RepeatItem<SlashCommand>) => {
              // 已经打了半个名字时第一行就是「回车会选中的那行」，高亮它。
              this.commandRow(item.item, this.content.typed && item.index === 0,
                commandIntent(item.item))
            })
            .key((item: SlashCommand) => item.name)
        }
      }
      .width('100%')
      // 行左右内缩 6（dsh-go rowInset）：高亮块比容器窄 6、圆角与容器同心。
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(this.c().inputFill)
    .borderRadius(28)
    .constraintSize({ maxHeight: 308 })
    .shadow({ radius: 12, color: this.c().shadow, offsetY: 2 })
    .margin({ bottom: 6 })
    // 容器语义（dsh-go `Semantics(container, label: 指令)`）：整块当一个「指令」区域。
    .accessibilityGroup(true)
    .accessibilityText('指令')
    // 出现时淡入（dsh-go AnimatedSwitcher + FadeTransition 同观感）。
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
  }

  @Builder
  commandRow(cmd: SlashCommand, selected: boolean, detail: string) {
    Column() {
      Row({ space: 10 }) {
        Text(commandGlyph(cmd))
          .fontSize(20)
          .fontColor(this.c().labelSecondary)
          .width(32)
          .textAlign(TextAlign.Center)
        if (cmd.displayLabel() !== cmd.name) {
          Text(cmd.displayLabel())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c().labelPrimary)
            .maxLines(1)
        }
        Text('/' + cmd.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(cmd.displayLabel() !== cmd.name
            ? this.c().labelSecondary : this.c().labelPrimary)
          .maxLines(1)
        if (cmd.inputHint !== null) {
          Text(cmd.inputHint as string)
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .maxLines(1)
        }
        Blank().layoutWeight(1)
        // 回车指示：这一行按回车就是它（dsh-go keyboard_return，16 号、带淡入）。
        Text('⏎')
          .fontSize(16)
          .fontColor(this.c().labelTertiary)
          .margin({ left: 8 })
          .opacity(selected ? 1 : 0)
          .animation({ duration: 150, curve: Curve.EaseOut })
      }
      .width('100%')
      Text(detail)
        .fontSize(12)
        .fontColor(this.c().labelTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minHeight: 52 })
    .padding({ left: 2, right: 12, top: 8, bottom: 8 })
    .borderRadius(22)
    .backgroundColor(selected ? this.c().paletteRowHighlight : Color.Transparent)
    .animation({ duration: 150, curve: Curve.EaseOut })
    .accessibilityText(commandA11y(cmd))
    .onClick(() => {
      this.onPick(cmd);
    })
  }

  /** 空态（dsh-go 单行：图标 + 一句「按普通消息发送」）。 */
  @Builder
  emptyRow() {
    Row({ space: 10 }) {
      Text('⌕')
        .fontSize(20)
        .fontColor(this.c().labelTertiary)
        .width(32)
        .textAlign(TextAlign.Center)
      Text('没有匹配的指令，按普通消息发送')
        .fontSize(12)
        .fontColor(this.c().labelTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 12, top: 8, bottom: 8 })
  }
}

/** 第二行的意图前缀（dsh-go 文案：技能 · 填入 / 命令 · 填入 / 命令 · 执行）。 */
function commandIntent(cmd: SlashCommand): string {
  if (cmd.kind === SlashCommandKind.Skill) {
    return cmd.description.length === 0 ? '技能 · 填入' : '技能 · 填入 · ' + cmd.description;
  }
  const intent: string = slashPickInsertsText(cmd, false) ? '命令 · 填入' : '命令 · 执行';
  return cmd.description.length === 0 ? intent : intent + ' · ' + cmd.description;
}

/** 命令行的前置符号：对齐安卓 `_commandIcon` 的语义分组（鸿蒙不引 Material 图标集）。 */
function commandGlyph(cmd: SlashCommand): string {
  const n: string = cmd.name;
  if (cmd.kind === SlashCommandKind.Skill) {
    return '✦';
  }
  if (n === 'new') {
    return '＋';
  }
  if (n === 'model') {
    return '◎';
  }
  if (n === 'export') {
    return '⇩';
  }
  if (n === 'features') {
    return '⊞';
  }
  if (n === 'compact') {
    return '…';
  }
  if (n === 'permission') {
    return '⚿';
  }
  if (n === 'plan') {
    return '☑';
  }
  if (n === 'goal') {
    return '⚑';
  }
  if (n === 'feedback') {
    return '✎';
  }
  return '›';
}

/** 读屏口径：中文名 + 裸名 + 参数占位 + 描述。 */
function commandA11y(cmd: SlashCommand): string {
  let out: string = cmd.displayLabel() !== cmd.name
    ? cmd.displayLabel() + ' ' + cmd.name : cmd.name;
  if (cmd.inputHint !== null) {
    out += ' 参数 ' + (cmd.inputHint as string);
  }
  if (cmd.description.length > 0) {
    out += '：' + cmd.description;
  }
  return out;
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
  /** @ 面板「对话」分组的命中（子串匹配，最多 6 条）。 */
  @Prop sessions: AtSessionHit[] = [];
  onPick: (e: AtEntry) => void = (): void => {};
  onPickSession: (h: AtSessionHit) => void = (): void => {};
  onRetry: () => void = (): void => {};
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  build() {
    Scroll() {
      Column() {
        // 对话分组在上（安卓 composer_at_sessions.dart 口径）。
        if (this.sessions.length > 0) {
          Text('对话')
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 4 })
          Repeat<AtSessionHit>(this.sessions)
            .each((item: RepeatItem<AtSessionHit>) => {
              Row({ space: 8 }) {
                Text('💬')
                  .fontSize(14)
                Text(item.item.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c().labelPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .accessibilityText('对话：' + item.item.title)
              .onClick(() => {
                this.onPickSession(item.item);
              })
            })
            .key((item: AtSessionHit) => item.id)
          if (this.entries.length > 0 || this.loading) {
            Divider()
              .color(this.c().borderL1)
              .margin({ left: 12, right: 12 })
          }
        }
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
        } else if (this.entries.length === 0 && this.sessions.length === 0) {
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
    .height(Math.min(320, Math.max(44, (this.entries.length + this.sessions.length) * 40 + 24)))
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
