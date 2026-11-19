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
  /** 列宽缓存（普通成员，不进 @State：build 期间写普通成员不会触发重渲染）。 */
  private colCacheKey: string = '';
  private colCache: number[] = [];
  /** 表格外框实测宽（vp）：窄表等比放大铺满用；onAreaChange 量到后写它触发一次重算。 */
  @State frameWidth: number = 0;

  /** 普通方法而非 getter：@Builder/ForEach 生成器里 `private get c()` 取到 undefined
   * （真机 TypeError: Cannot read property 'labelPrimary' of undefined 整进程崩）。 */
  private c(): DsColors {
    return new DsColors(this.dark);
  }

  /** 同样避开 getter（@Builder 内 getter 取值不可靠）。 */
  private columns(): number {
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

  /** 估算单行文本像素宽（**估算值，真机再校**）：中文/全角 ≈ 字号 × 1.0、ASCII ≈ 字号 × 0.55。 */
  private estimateWidth(text: string, fontSize: number): number {
    let w = 0;
    for (let i = 0; i < text.length; i++) {
      w += text.charCodeAt(i) > 0x2E80 ? fontSize : fontSize * 0.55;
    }
    return w;
  }

  /** 列宽缓存键：行数 + 每行长度 + 总字符数，够了就复用上次算好的列宽。 */
  private colKey(): string {
    let chars = 0;
    let lens = '';
    for (const row of this.rows) {
      lens += row.length.toString() + ',';
      for (const cell of row) {
        chars += cell.length;
      }
    }
    return this.rows.length.toString() + '|' + chars.toString() + '|' + lens;
  }

  /**
   * 全表统一列宽（vp 数值数组，所有行共用同一组 → 各行列边界必然对齐）。
   *
   * 旧实现每格 `layoutWeight(1)` 是在**每行内部**等分：行长短不同 / 文本长短不同，
   * 同一列在不同行里落在不同 x 位置，视觉上「表格对齐不准确」（2026-11-17 用户反馈）。
   * 现改为：逐列取各单元格估算宽（+ 2×cellPadH）的最大值 → 夹在 [cellMinWidth, tableColMaxWidth]
   * → 所有行用同一组固定 vp 宽度。安卓基线是 gpt_markdown TableStyle（defaultColumnWidth 统一算
   * 列宽），口径一致。表头所在行用 tableHead 字号、其余用 table 字号参与估算。
   *
   * 为什么不用百分比：表格体在横向 `Scroll` 里，Scroll 的子节点宽度由内容决定，
   * 百分比没有确定的参照宽度（会把多列表格压扁而不是横向滚动）。窄表则靠
   * `frameWidth`（onAreaChange 量到的表格外框宽）等比放大铺满，避免右侧留白。
   */
  private colWidths(): number[] {
    const cols = this.columns();
    if (cols === 0) {
      return [];
    }
    const key = this.colKey() + '|' + this.frameWidth.toFixed(0);
    if (key === this.colCacheKey) {
      return this.colCache;
    }
    const widths: number[] = [];
    for (let c = 0; c < cols; c++) {
      let w = 0;
      for (let r = 0; r < this.rows.length; r++) {
        const row = this.rows[r];
        const text = c < row.length ? row[c] : '';
        const fs = r === 0 ? DsTypography.tableHead.size : DsTypography.table.size;
        const need = this.estimateWidth(text, fs) + DsSpacing.cellPadH * 2;
        if (need > w) {
          w = need;
        }
      }
      if (w < DsSpacing.cellMinWidth) {
        w = DsSpacing.cellMinWidth;
      }
      if (w > DsSpacing.tableColMaxWidth) {
        w = DsSpacing.tableColMaxWidth;
      }
      widths.push(w);
    }
    let total = 0;
    for (const w of widths) {
      total += w;
    }
    // 自然宽度不够铺满时等比放大（宽表不动，保持横向滚动）。
    // 外框左右各 1vp 边框（build 里 borderWidth(1)），内容可用宽 = 外框 − 2，否则会多出 2vp 横向滚动余量。
    const inner = this.frameWidth - 2;
    if (inner > 0 && total < inner) {
      const k = inner / total;
      for (let i = 0; i < widths.length; i++) {
        widths[i] = widths[i] * k;
      }
    }
    this.colCacheKey = key;
    this.colCache = widths;
    return widths;
  }

  /** 表格自然总宽（vp）：供 Scroll 内的 Column 定宽，超出外框时就能横向滚动。 */
  private colTotalWidth(): number {
    let total = 0;
    for (const w of this.colWidths()) {
      total += w;
    }
    return total;
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
          .fontColor(this.c().labelTertiary)
          .layoutWeight(1)
        Text(this.copied ? '✓' : '⧉')
          .fontSize(DsTypography.base.size)
          .fontColor(this.c().labelTertiary)
        Text(this.copied ? '已复制' : '复制')
          .fontSize(DsTypography.codeBlockLabel.size)
          .fontColor(this.c().labelTertiary)
          .margin({ left: 4 })
          .accessibilityText(this.copied ? '已复制' : '复制表格')
          .onClick(() => this.copy())
      }
      .padding({
        left: DsSpacing.codeBlockPadH,
        right: DsSpacing.codeBlockPadH - 4,
        top: DsSpacing.codeBlockBannerPadV,
        bottom: DsSpacing.codeBlockBannerPadV,
      })
      Divider()
        .color(this.c().tableBorder)
        .strokeWidth(1)
      // 表体：横向滚动。Column 取「自然总宽」——比外框宽就横向滚，比外框窄则列宽已等比放大铺满。
      Scroll() {
        Column() {
          Repeat<string[]>(this.rows)
            .each((entry: RepeatItem<string[]>) => {
              this.renderRow(entry.item, entry.index)
            })
            .key((entry: string[], index: number) => index.toString() + '-' + entry.length.toString())
        }
        .width(this.colTotalWidth())
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .constraintSize({ minWidth: '100%' })
    .backgroundColor(this.c().mdCodeBlockBg)
    .borderRadius(DsSpacing.codeBlockRadius)
    .borderWidth(1)
    .borderColor(this.c().tableBorder)
    .clip(true)
    .margin({ top: DsSpacing.blockGap, bottom: DsSpacing.blockGap })
    .onAreaChange((_oldV: Area, newV: Area) => {
      // Area.width 的静态类型是 Length（string | number | Resource），回调里实测给 vp 数值；
      // 用 typeof 收窄两种形态（不用 as 强转，ArkTS 不允许 number↔string 互转）。
      // 拿不到数值（未布局 / Resource）就跳过：退化成自然列宽，列边界依然对齐，只是不铺满。
      const raw = newV.width;
      let w = 0;
      if (typeof raw === 'number') {
        w = raw;
      } else if (typeof raw === 'string') {
        w = parseFloat(raw);
      }
      if (w > 0 && Math.abs(w - this.frameWidth) >= 1) {
        this.frameWidth = w;
      }
    })
  }

  /** 单元格显示文本：缺列（这行比全表列数短）补空串，空串渲染成一个空格占位以保住行高。 */
  private cellDisplay(row: string[], col: number): string {
    const text = col < row.length ? row[col] : '';
    return text.length > 0 ? text : ' ';
  }

  /** 该格是不是真实存在的格子：false 表示补位空格子，透明占位、且不画右边线。 */
  private cellPresent(row: string[], col: number): boolean {
    return col < row.length;
  }

  /** 单元格。抽 @Builder 让 Repeat 帧里只有一行调用。
   *  `colW` 来自 colWidths()（全表统一，单位 vp）。
   *  派生值（text / bordered）走上面的普通方法而不是在 each 的花括号里写 `const` ——
   *  ArkUI 规定 Repeat/ForEach 的生成器体里只能写 UI 组件语法，写局部声明会编译报
   *  10905209「Only UI component syntax can be written here」。 */
  @Builder
  cellView(row: string[], rowIdx: number, colIdx: number, colW: number) {
    Text(this.cellDisplay(row, colIdx))
      .fontSize(rowIdx === 0 ? DsTypography.tableHead.size : DsTypography.table.size)
      .fontWeight(rowIdx === 0 ? FontWeight.Medium : FontWeight.Normal)
      .lineHeight(rowIdx === 0 ? DsTypography.tableHead.lineHeight : DsTypography.table.lineHeight)
      .fontColor(this.c().labelPrimary)
      .textAlign(this.cellAlign(colIdx))
      .padding({
        left: DsSpacing.cellPadH,
        right: DsSpacing.cellPadH,
        top: DsSpacing.cellPadV,
        bottom: DsSpacing.cellPadV,
      })
      .width(colW)
      .border({
        width: this.cellPresent(row, colIdx)
          ? { right: colIdx < this.columns() - 1 ? 1 : 0, top: rowIdx === 0 ? 0 : 1 }
          : { right: 0, top: rowIdx === 0 ? 0 : 1 },
        color: this.c().tableBorder,
      })
  }

  @Builder
  renderRow(row: string[], rowIdx: number) {
    Row() {
      Repeat<number>(this.colWidths())
        .each((entry: RepeatItem<number>) => {
          this.cellView(row, rowIdx, entry.index, entry.item)
        })
        .key((entry: number, index: number) => index.toString() + '-' + entry.toFixed(1))
    }
    .alignItems(VerticalAlign.Center)
    // 必须是「列宽总和」这个具体数值，不能写 '100%'：百分比会被解析成 Scroll 视口宽，
    // 于是各格 Text 被 flexShrink 压缩（真机 dump 实测第 3 列从 100vp 挤到 52vp，「山东烟台」
    // 只露出「山东」两字），且 Scroll 内容宽 == 外框宽 → 横向滚不动，被裁的列永远看不到。
    .width(this.colTotalWidth())
  }
}
