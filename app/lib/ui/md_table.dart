/// 表格 —— 官方 App 实测复刻（ref/md-shot-4-table.png 像素采样）。
///
/// 官方结构（1080x2400 @3.0 → dp）：
///   banner 行：左上「表格」灰字（#7d7f85）+ 右侧 复制/下载/展开 三个灰图标，
///              底色 #fafafa，下面一条 1px 分隔线（#dcdcdc）
///   表头行 A/B/C：白底、深色字（w500）、有列分隔线
///   数据行：白底 #191b23、列分隔线 x=383/701（2px 物理 ≈1dp）
///   外框与所有行/列线统一 #dcdcdc，行高约 123px ≈ 41dp
///   → 15sp/25 行高 + 上下各 8dp 内边距 = 41dp ✓
///
/// 为什么不用 gpt_markdown 内置表格：它的表头底色默认取
/// `colorScheme.surfaceContainerHighest`（浅色主题下是淡紫粉，官方是白），
/// 而且没有官方那条 banner。这里用 tableBuilder 完全自绘。
///
/// 单元格必须自己再做一次行内解析：gpt_markdown 1.4.1 的 tableBuilder
/// 只把单元格拍平成纯文本（plusparse/renderer.dart `_plainText`），裸 URL
/// 原本是黑色死字、点不动（真机反馈 2026-11-21 问题 1）。这里把 data 重新
/// 交给 plusparse 行内渲染，经 config.getRich 拿到 onLinkTap 的点击区。
library;

import 'package:material_ui/material_ui.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../design/tokens.dart';

/// 官方表格块：banner（表格 + 复制/下载/展开）+ 表头 + 数据行。
class DsTable extends StatelessWidget {
  const DsTable({
    super.key,
    required this.rows,
    required this.colors,
    required this.config,
  });

  final List<CustomTableRow> rows;
  final DsColors colors;

  /// tableBuilder 的文档级配置：单元格重解析时继承同一套行内样式与
  /// onLinkTap（链接点击由此生效）。
  final GptMarkdownConfig config;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    // 列数：gpt_markdown 的 tableBuilder 会把 `|---|---|` 分隔行也塞进来
    // （字段全空，且比表头多一列），直接取 rows.first 会多出一整列空白。
    // 以「有内容的行」的字段数最大值定列数。
    final bodyRows = rows.where((r) {
      if (r.isHeader) return true;
      return r.fields.any((f) => f.data.trim().isNotEmpty);
    }).toList();
    if (bodyRows.isEmpty) return const SizedBox.shrink();
    // 行末还可能多一个空字段（`| A | B | C |` 尾管道会解析出空 cell），
    // 所以先裁掉每行末尾的空字段再取最大列数。
    final trimmed = <CustomTableRow>[
      for (final r in bodyRows) _trimTrailingEmpty(r),
    ];
    final columns = trimmed
        .map((r) => r.fields.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (columns == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
      decoration: BoxDecoration(
        // 官方表格整体底色 #fafafa（与代码块同款 neutral-50），不是纯白。
        color: colors.mdCodeBlockBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        border: Border.all(color: colors.tableBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(colors: colors),
          Container(height: 1, color: colors.tableBorder),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // 至少撑满容器宽度：否则 Table 只按 minWidth 排版，
                // 右侧会空出一截底色，看起来像多了一列。
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth > DsSpacing.cellMinWidth * 3
                      ? constraints.maxWidth
                      : DsSpacing.cellMinWidth * 3,
                ),
                child: Table(
                  defaultColumnWidth: const FlexColumnWidth(),
                  border: TableBorder.all(color: colors.tableBorder),
                  children: [
                    for (final row in trimmed) _tableRow(context, row, columns),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 裁掉行末的空字段（尾管道 / 分隔行遗留）。
  CustomTableRow _trimTrailingEmpty(CustomTableRow row) {
    final fields = [...row.fields];
    while (fields.isNotEmpty && fields.last.data.trim().isEmpty) {
      fields.removeLast();
    }
    if (fields.isEmpty) return row;
    return CustomTableRow(isHeader: row.isHeader, fields: fields);
  }

  TableRow _tableRow(BuildContext context, CustomTableRow row, int columns) {
    final isHead = row.isHeader;
    final style = (isHead ? DsTypography.tableHead : DsTypography.table)
        .copyWith(color: colors.labelPrimary);
    return TableRow(
      children: [
        for (var i = 0; i < columns; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.cellPadH,
              vertical: DsSpacing.cellPadV,
            ),
            child: _cell(
              context,
              i < row.fields.length ? row.fields[i] : null,
              style,
            ),
          ),
      ],
    );
  }

  /// 单元格：先按行内 Markdown 重解析纯文本，再交给 getRich 渲染。
  /// 只有 getRich 会把链接做成 InlineTapTargets 的点击区（直接 Text.rich
  /// 会把链接降级成普通文字，且不报错）。
  Widget _cell(BuildContext context, CustomTableField? field, TextStyle style) {
    final data = field?.data ?? '';
    if (data.trim().isEmpty) return const SizedBox.shrink();
    final cellConfig = config.copyWith(
      style: style,
      textAlign: field?.alignment ?? TextAlign.start,
      scope: MarkdownScope.tableCell,
    );
    final spans = PlusparseRenderer.render(
      context,
      data,
      cellConfig,
      inlineOnly: true,
    );
    return cellConfig.getRich(TextSpan(style: style, children: spans));
  }
}

/// 官方表格 banner：左「表格」，右三个动作图标（复制 / 下载 / 展开）。
class _Banner extends StatelessWidget {
  const _Banner({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final color = colors.labelTertiary;
    return Container(
      color: colors.mdCodeBlockBg,
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.codeBlockPadH,
        DsSpacing.codeBlockBannerPadV,
        DsSpacing.codeBlockPadH - 4,
        DsSpacing.codeBlockBannerPadV,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '表格',
              style: DsTypography.codeBlockLabel.copyWith(color: color),
            ),
          ),
          _BannerIcon(icon: Icons.content_copy_rounded, color: color),
          const SizedBox(width: 12),
          _BannerIcon(icon: Icons.file_download_outlined, color: color),
          const SizedBox(width: 12),
          _BannerIcon(icon: Icons.open_in_full_rounded, color: color),
        ],
      ),
    );
  }
}

class _BannerIcon extends StatelessWidget {
  const _BannerIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 15, color: color);
}
