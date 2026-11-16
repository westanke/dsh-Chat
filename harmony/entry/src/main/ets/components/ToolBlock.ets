/// 工具调用过程组 —— 对齐安卓 process_group.dart（折叠一行摘要，点开展开逐条，
/// 再点单条看完整详情：耗时 + 参数 + 结果；bash 命令按代码块渲染）。
/// 措辞来自 core/ToolCall.ts 的 toolPhrases（与 companion ChatToolPresentation 同源）。
import { ToolCallInfo } from '../../core/ToolCall';
import { JsonAccess, JsonMap } from '../../core/JsonAccess';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';
import { MdCodeBlock } from './md/MdCodeBlock';

@Component
export struct ToolBlock {
  group: ToolCallInfo[] = [];
  failed: boolean = false;
  phraseText: string = '';
  @StorageProp('dshDark') dark: boolean = false;
  @State expanded: boolean = false;
  /** 单条详情展开的下标（-1 = 全收起）。 */
  @State detailIdx: number = -1;

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private headColor(): ResourceColor {
    return this.failed ? this.c().labelTertiary : this.c().labelSecondary;
  }

  build() {
    Column() {
      // 摘要行：扳手图标 + 短语 + 展开箭头
      Row() {
        Text('⚒')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(this.headColor())
          .margin({ right: DsSpacing.processIconGap })
        Text(this.phraseText)
          .fontSize(DsTypography.small.size)
          .fontColor(this.headColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.group.length > 0) {
          Text(this.expanded ? '⌃' : '⌄')
            .fontSize(14)
            .fontColor(this.headColor())
        }
      }
      .height(DsSpacing.processRowHeight)
      .width('100%')
      .accessibilityText(this.phraseText + (this.expanded ? '，收起' : '，展开'))
      .onClick(() => {
        if (this.group.length > 0) {
          this.expanded = !this.expanded;
        }
      })

      if (this.expanded) {
        Column() {
          ForEach(this.group, (t: ToolCallInfo, idx: number) => {
            this.toolRow(t, idx)
          }, (t: ToolCallInfo, i: number) => i + '-' + t.name + '-' + (t.resultText === null ? 0 : t.resultText.length))
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: DsSpacing.blockGap })
  }

  @Builder
  toolRow(t: ToolCallInfo, idx: number) {
    Column() {
      Row() {
        Text(t.failed ? '✗' : '✓')
          .fontSize(DsSpacing.processIconSize)
          .fontColor(t.failed ? this.c().labelTertiary : this.c().labelSecondary)
          .margin({ right: DsSpacing.processIconGap, top: 4 })
        Column() {
          Text(t.phrases.join('，'))
            .fontSize(DsTypography.small.size)
            .fontColor(t.failed ? this.c().labelTertiary : this.c().labelSecondary)
          if (t.summary !== null) {
            Text(t.summary)
              .fontSize(DsTypography.codeBlockLabel.size)
              .fontColor(this.c().labelTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.hasDetail(t)) {
          Text(this.detailIdx === idx ? '⌃' : '⌄')
            .fontSize(12)
            .fontColor(this.c().labelTertiary)
        }
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .accessibilityText('展开详情')
      .onClick(() => {
        if (this.hasDetail(t)) {
          this.detailIdx = this.detailIdx === idx ? -1 : idx;
        }
      })

      if (this.detailIdx === idx) {
        this.toolDetail(t)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 4 })
  }

  private hasDetail(t: ToolCallInfo): boolean {
    return t.resultText !== null || t.durationMs !== null || t.rawArguments !== null;
  }

  @Builder
  toolDetail(t: ToolCallInfo) {
    Column() {
      if (this.durationText(t) !== null) {
        Text('耗时 ' + this.durationText(t))
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
          .margin({ bottom: 4 })
      }
      if (this.bashCommand(t) !== null) {
        MdCodeBlock({ lang: 'BASH', code: this.bashCommand(t) as string })
      } else if (this.prettyArgs(t) !== null) {
        Text('输入')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
        Text(this.prettyArgs(t) as string)
          .fontSize(DsTypography.codeBlock.size)
          .fontColor(this.c().labelSecondary)
          .margin({ top: 2, bottom: 6 })
      }
      if (t.resultText !== null) {
        Text(t.failed ? '错误' : '输出')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
        Text(t.resultText)
          .fontSize(DsTypography.codeBlock.size)
          .fontColor(t.failed ? this.c().danger : this.c().labelSecondary)
          .maxLines(24)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      } else if (!t.failed && t.durationMs !== null) {
        Text('结果为空')
          .fontSize(DsTypography.caption.size)
          .fontColor(this.c().labelTertiary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: DsSpacing.processIconSize + DsSpacing.processIconGap + 3,
      top: 4,
      bottom: 4,
    })
  }

  /// 参数美化：JSON 对象逐行 `k: v`（值截 200），坏 JSON 原样。
  private prettyArgs(t: ToolCallInfo): string | null {
    const raw = t.rawArguments;
    if (raw === null || raw.trim().length === 0) {
      return null;
    }
    const parsed = JsonAccess.parse(raw);
    const map = JsonAccess.asMap(parsed);
    if (map !== null) {
      const out: string[] = [];
      const keys = Object.keys(map);
      for (const k of keys) {
        let vText = `${map[k]}`;
        if (vText.length > 200) {
          vText = vText.substring(0, 200) + '…';
        }
        out.push(k + ': ' + vText);
      }
      return out.length === 0 ? null : out.join('\n');
    }
    return raw;
  }

  /// bash/tools.bash 的 command 字段原文（按代码块渲染）。
  private bashCommand(t: ToolCallInfo): string | null {
    if (t.name !== 'bash' && t.name !== 'tools.bash') {
      return null;
    }
    const raw = t.rawArguments;
    if (raw === null || raw.trim().length === 0) {
      return null;
    }
    const parsed = JsonAccess.parse(raw);
    const map = JsonAccess.asMap(parsed);
    if (map !== null) {
      const cmd = JsonAccess.str(map, 'command');
      if (cmd !== null && cmd.trim().length > 0) {
        return cmd;
      }
    }
    return null;
  }

  private durationText(t: ToolCallInfo): string | null {
    const ms = t.durationMs;
    if (ms === null || ms < 0) {
      return null;
    }
    if (ms < 1000) {
      return ms + 'ms';
    }
    if (ms < 60000) {
      return (Math.round(ms / 100) / 10).toFixed(1) + 's';
    }
    return Math.floor(ms / 60000) + 'm' + Math.floor((ms % 60000) / 1000) + 's';
  }
}
