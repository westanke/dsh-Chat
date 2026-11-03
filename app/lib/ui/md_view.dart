/// Markdown 渲染视图 —— 与官方 App 对齐的核心。
/// 布局/间距/配色全部依据 docs/design-tokens.md（官方 Web token + 真机 6 屏像素实测）。
/// 渲染引擎 gpt_markdown 1.4.0；语法高亮用其内置 val_highlight（随 Brightness 切换）。
library;

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../design/tokens.dart';
import 'md_code_block.dart';
import 'md_table.dart';

/// 把 `- [x] foo` / `* [ ] foo` 规整成 `[x] foo`。
///
/// gpt_markdown 1.4.0 的任务列表标记只认行首的 `[x] `（plusparse/scanner.dart:318
/// checkboxMarker），带 `- ` 前缀的行会先被 listMarker 吃掉变成普通无序列表项，
/// 于是屏幕上出现「圆点 + 勾选框」叠加 —— 官方只有勾选框、没有圆点。
String normalizeTaskLists(String text) {
  if (!text.contains('[x]') && !text.contains('[X]') && !text.contains('[ ]')) {
    return text;
  }
  final buffer = StringBuffer();
  for (final line in text.split('\n')) {
    final match = _taskListLine.firstMatch(line);
    if (match != null) {
      buffer
        ..write(match.group(1))
        ..write(' ')
        ..write(match.group(2));
    } else {
      buffer.write(line);
    }
    buffer.write('\n');
  }
  // 去掉循环末尾多加的一个换行（split 已保留原有行数）。
  final out = buffer.toString();
  return out.substring(0, out.length - 1);
}

/// 行首缩进 + 列表符号 + 勾选框 → 只留勾选框。
final RegExp _taskListLine = RegExp(r'^\s*[-*+]\s+(\[[ xX]\])\s+(.*)$');

/// 对话里的一条 Markdown 内容（助手回复 / 思考流共用）。
class DsMarkdownView extends StatelessWidget {
  const DsMarkdownView({
    super.key,
    required this.text,
    required this.colors,
    this.streaming = false,
    this.small = false,
  });

  final String text;
  final DsColors colors;
  final bool streaming;

  /// 思考流样式（官方 .ds-think-content：14/24，块间距收紧）。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final base = small
        ? DsTypography.small.copyWith(color: colors.labelPrimary)
        : DsTypography.base.copyWith(color: colors.labelPrimary);
    final brightness = colors.dark ? Brightness.dark : Brightness.light;

    final theme = GptMarkdownThemeData(
      brightness: brightness,
      linkColor: colors.link,
      autoAddDividerLineAfterH1: false,
      h1: DsTypography.h1.copyWith(color: colors.labelPrimary),
      h2: DsTypography.h2.copyWith(color: colors.labelPrimary),
      h3: DsTypography.h3.copyWith(color: colors.labelPrimary),
      h4: DsTypography.h4.copyWith(color: colors.labelPrimary),
      h5: DsTypography.h4.copyWith(color: colors.labelPrimary),
      h6: DsTypography.h4.copyWith(color: colors.labelPrimary),
      hrLineThickness: 1,
      hrLineColor: colors.borderL2,
      hrLinePadding: EdgeInsets.zero,
      inlineCode: InlineCodeStyle(
        fontFamily: DsTypography.codeFamily,
        fontSizeFactor: 0.875,
        color: colors.labelPrimary,
        backgroundColor: colors.mdInlineCodeBg,
        borderRadius: const Radius.circular(DsSpacing.inlineCodeRadius),
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.inlineCodePadH,
        ),
      ),
      styleSheet: GptMarkdownStyleSheet(
        blockSpacing: DsSpacing.blockGap.toDouble(),
        heading: HeadingStyle(
          // top 16 + 块间距 16 = 官方标题上边距 32；下方块间距 16 即官方 16。
          padding: const EdgeInsets.only(top: DsSpacing.blockGap),
          showDivider: false,
        ),
        blockQuote: BlockQuoteStyle(
          barWidth: DsSpacing.quoteBarWidth.toDouble(),
          barColor: colors.quoteBar,
          padding: const EdgeInsets.only(
            left: DsSpacing.quotePadLeft - DsSpacing.quoteBarWidth,
          ),
          margin: const EdgeInsets.only(top: DsSpacing.blockGap),
        ),
        codeBlock: CodeBlockStyle(
          backgroundColor: colors.mdCodeBlockBg,
          borderColor: colors.none,
          borderRadius: const Radius.circular(DsSpacing.codeBlockRadius),
          padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
          headerPadding: const EdgeInsets.fromLTRB(
            DsSpacing.codeBlockPad,
            DsSpacing.codeBlockPad,
            DsSpacing.codeBlockPad,
            0,
          ),
          fontSize: DsTypography.codeBlock.fontSize,
          textColor: colors.labelPrimary,
          showLanguageLabel: true,
          showCopyButton: true,
        ),
        table: TableStyle(
          borderColor: colors.tableBorder,
          borderWidth: 1,
          cellPadding: const EdgeInsets.symmetric(
            vertical: DsSpacing.cellPadV,
            horizontal: DsSpacing.cellPadH,
          ),
          headerTextStyle: DsTypography.tableHead.copyWith(
            color: colors.labelPrimary,
          ),
        ),
        hr: HrStyle(thickness: 1, color: colors.borderL2),
        list: ListStyle(
          markerTextStyle: DsTypography.base.copyWith(color: colors.listMarker),
        ),
        sourceTag: SourceTagStyle(
          backgroundColor: colors.mdCitationBg,
          textStyle: DsTypography.citation.copyWith(color: colors.labelPrimary),
        ),
        link: LinkStyle(color: colors.link, decoration: TextDecoration.none),
      ),
    );

    return GptMarkdownTheme(
      gptThemeData: theme,
      child: GptMarkdown(
        normalizeTaskLists(text),
        style: base,
        isStreaming: streaming,
        useDollarSignsForLatex: true,
        // 代码块自绘：官方是灰底 + 「python … 复制」纯文字 banner + 分隔线，
        // 内置 CodeField 的语言标签是 surfaceContainerHighest 粉色 pill，
        // 高亮主题也写死成 val_highlight 默认色，与官方 Atom One Light 不符。
        codeBuilder: (context, name, code, closed) =>
            DsCodeBlock(name: name, code: code, colors: colors),
        // 表格自绘：官方有「表格 + 复制/下载/展开」banner，表头白底，
        // 内置表格表头取 surfaceContainerHighest（淡紫粉）且无 banner。
        tableBuilder: (context, rows, textStyle, config) =>
            DsTable(rows: rows, colors: colors),
        // 上游 bug 绕行：gpt_markdown 1.4.0 把 Material Checkbox 塞进 WidgetSpan，
        // 中文行高下会算出 ~10 万像素宽度 → RenderFlex 溢出（debug 屏上那块红底黄黑斜纹）。
        // 自己画方框 + Expanded 文本，顺便贴近官方的「☑ 已完成」观感。
        checkboxBuilder: (context, checked, content, style) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: checked ? colors.brand : colors.listMarker,
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
