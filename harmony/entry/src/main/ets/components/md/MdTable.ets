/// 表格组件 —— 官方 App 实测复刻（banner「表格」+ 复制 + 表头深字 + 全边框）。
/// 解析在 core/MdParser.ts（rows 首行表头、align 列对齐），本组件只画。
import { DsColors, DsTypography, DsSpacing } from '../../ui/theme';
import { pasteboard } from '@kit.BasicServicesKit';

@Component
export struct MdTable {
  rows: string[][] = [];
  /** 列对齐 'l'|'c'|'r'（来自分隔行 :--/:--:/--:）。 */
  aligns: string[] = [];
  @StorageProp('dshDark') dark: boolean = false;
  @State copied: boolean = false;

  private get c(): DsColors {
    return new DsColors(this.dark);
  }

  private get columns(): number {
    let max = 0;
    for (const row of this.rows) {
      if (row.length > max) {
        max = row.length;
      }
    }
    return max;
  }

  private cellAlign(col: number): TextAlign {
    const a = col < this.aligns.length ? this.aligns[col] : 'l';
    if (a === 'c') {
      return TextAlign.Center;
    }
    if (a === 'r') {
      return TextAlign.End;
    }
    return TextAlign.Start;
  }

  private copy(): void {
    let text = '';
    for (const row of this.rows) {
      text += row.join('\t') + '\n';
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.copied = true;
    }).catch(() => {
      this.copied = false;
    });
  }

  build() {
    Column() {
      // banner：左「表格」+ 右复制（下载/展开首版不做，安卓全量在阶段 4）
      Row() {
        Text('表格')
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontColor(this.c.labelTertiary)
          .layoutWeight(1)
        Text(this.copied ? '✓' : '⧉')
          .fontSize(15)
          .fontColor(this.c.labelTertiary)
        Text(this.copied ? '已复制' : '复制')
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontColor(this.c.labelTertiary)
          .margin({ left: 4 })
          .onClick(() => this.copy())
      }
      .padding({
        left: DsSpacing.codeBlockPadH,
        right: DsSpacing.codeBlockPadH - 4,
        top: DsSpacing.codeBlockBannerPadV,
        bottom: DsSpacing.codeBlockBannerPadV,
      })
      Divider()
        .color(this.c.tableBorder)
        .strokeWidth(1)
      // 表体（横向滚动；列宽按 flex 撑满）
      Scroll() {
        Column() {
          ForEach(this.rows, (row: string[], rowIdx: number) => {
            this.renderRow(row, rowIdx)
          }, (row: string[], rowIdx: number) => rowIdx + '-' + row.length)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .constraintSize({ minWidth: '100%' })
    .backgroundColor(this.c.mdCodeBlockBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .borderWidth(1)
    .borderColor(this.c.tableBorder)
    .clip(true)
    .margin({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
  }

  @Builder
  renderRow(row: string[], rowIdx: number) {
    Row() {
      ForEach(row, (cell: string, colIdx: number) => {
        Text(cell.length > 0 ? cell : ' ')
          .fontSize(rowIdx === 0 ? DsTypography.tableHead.size : DsTypography.table.size)
          .fontWeight(rowIdx === 0 ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.c.labelPrimary)
          .textAlign(this.cellAlign(colIdx))
          .padding({
            left: DsSpacing.cellPadH,
            right: DsSpacing.cellPadH,
            top: DsSpacing.cellPadV,
            bottom: DsSpacing.cellPadV,
          })
          .constraintSize({ minWidth: DsSpacing.cellMinWidth })
          .layoutWeight(1)
          .border({
            width: { right: colIdx < row.length - 1 ? 1 : 0, top: rowIdx === 0 ? 0 : 1 },
            color: this.c.tableBorder,
          })
      }, (cell: string, colIdx: number) => rowIdx + '-' + colIdx + '-' + cell.length)
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }
}
