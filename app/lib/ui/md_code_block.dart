/// 代码块 —— 官方 App 实测复刻（ref/md-shot-3-code.png 像素采样）。
///
/// 官方结构（1080x2400 @3.0 → dp）：
///   块左 66px=22dp、块右 1018px=339dp（宽 317dp）
///   顶部 y=274、banner 底分隔线 y=395（#ebebeb 1px）、块底 y=594
///   banner 内「python」左起 109px（≈14dp 内边距）、文字色 #7d7f85
///   代码左起 112px（≈15dp）、正文 #191b23、圆角 8dp
/// 高亮 = Atom One Light（keyword #a626a4 / string #50a14f /
/// function #e45649 / number #4078f2 / comment #a0a1a7 / plain #383a42）。
///
/// 为什么不直接用 gpt_markdown 的 CodeField：它把语言标签画成
/// surfaceContainerHighest 的粉色 pill（还带 terminal 图标），且高亮主题
/// 写死为 val_highlight 的默认 lightTheme（#b0226e 等），两者都与官方不符，
/// 且没有从外部替换主题的入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:val_highlight/languages/all.dart';
import 'package:val_highlight/val_highlight.dart';
import 'package:val_highlight_flutter/val_highlight_flutter.dart'
    show CodeStyles, Highlighter, LanguageRegistry, documentSpans;

import '../design/tokens.dart';

/// Atom One Light —— 官方 App 代码块配色（真机像素实测，见文件头）。
final ValTheme _atomOneLight = ValTheme(
  name: 'atom-one-light',
  root: Style(color: DsPalette.synPlain.toARGB32()),
  styles: {
    Scopes.comment: Style(color: DsPalette.synComment.toARGB32(), italic: true),
    Scopes.commentDoc: Style(
      color: DsPalette.synComment.toARGB32(),
      italic: true,
    ),
    Scopes.string: Style(color: DsPalette.synString.toARGB32()),
    Scopes.stringEscape: Style(color: DsPalette.synNumber.toARGB32()),
    Scopes.number: Style(color: DsPalette.synNumber.toARGB32()),
    Scopes.keyword: Style(color: DsPalette.synKeyword.toARGB32()),
    Scopes.literal: Style(color: DsPalette.synNumber.toARGB32()),
    Scopes.type: Style(color: DsPalette.synFunction.toARGB32()),
    Scopes.typeBuiltin: Style(color: DsPalette.synNumber.toARGB32()),
    Scopes.function: Style(color: DsPalette.synFunction.toARGB32()),
    Scopes.variable: Style(color: DsPalette.synFunction.toARGB32()),
    Scopes.meta: Style(color: DsPalette.synComment.toARGB32()),
    Scopes.property: Style(color: DsPalette.synNumber.toARGB32()),
    Scopes.tag: Style(color: DsPalette.synKeyword.toARGB32()),
    Scopes.attribute: Style(color: DsPalette.synFunction.toARGB32()),
  },
);

/// 语言表（与官方一致的常用围栏标签；未知标签退化为纯文本，不炸渲染）。
final LanguageRegistry _languages = LanguageRegistry(allLanguages)
  ..add(pythonLanguage, aliases: const ['python3'])
  ..add(bashLanguage, aliases: const ['shellscript']);

final Highlighter _highlighter = Highlighter(registry: _languages);
final CodeStyles _atomStyles = CodeStyles(_atomOneLight);

/// 官方风格的代码块：灰底 + 顶部「语言名 … 复制」+ 分隔线 + 高亮代码。
class DsCodeBlock extends StatefulWidget {
  const DsCodeBlock({
    super.key,
    required this.name,
    required this.code,
    required this.colors,
    this.style,
  });

  final String name;
  final String code;
  final DsColors colors;
  final CodeBlockStyle? style;

  @override
  State<DsCodeBlock> createState() => _DsCodeBlockState();
}

class _DsCodeBlockState extends State<DsCodeBlock> {
  bool _copied = false;
  List<TextSpan>? _spans;

  @override
  void initState() {
    super.initState();
    _spans = _highlight();
  }

  @override
  void didUpdateWidget(DsCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code || oldWidget.name != widget.name) {
      _spans = _highlight();
    }
  }

  /// 官方用 Atom One Light；未知语言（含空标签）走纯文本，颜色交给正文样式。
  List<TextSpan> _highlight() {
    final tag = widget.name.trim().toLowerCase();
    if (tag.isEmpty) return [TextSpan(text: widget.code)];
    final grammar = _languages.lookup(tag);
    if (grammar == null) return [TextSpan(text: widget.code)];
    try {
      final result = _highlighter.highlight(widget.code, language: grammar);
      return documentSpans(result, _atomStyles);
    } catch (_) {
      // 语法解析失败绝不能让整条回复渲染不出来。
      return [TextSpan(text: widget.code)];
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final label = widget.name.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
      decoration: BoxDecoration(
        color: colors.mdCodeBlockBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // banner：语言名（纯文字灰）+ 右侧复制
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.codeBlockPadH,
              DsSpacing.codeBlockBannerPadV,
              DsSpacing.codeBlockPadH - 6,
              DsSpacing.codeBlockBannerPadV,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label.isEmpty ? 'text' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.codeBlockLabel.copyWith(
                      color: colors.labelTertiary,
                    ),
                  ),
                ),
                _CopyButton(copied: _copied, colors: colors, onTap: _copy),
              ],
            ),
          ),
          // banner 与代码之间那条 1px 分隔线（官方 #ebebeb）
          Container(height: 1, color: colors.mdCodeBlockDivider),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.codeBlockPadH,
              DsSpacing.codeBlockPadV,
              DsSpacing.codeBlockPadH,
              DsSpacing.codeBlockPadV,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text.rich(
                TextSpan(
                  style: DsTypography.codeBlock.copyWith(
                    fontFamily: DsTypography.codeFamily,
                    color: colors.mdCodeBlockText,
                  ),
                  children: _spans,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 官方 banner 右侧的「复制」：图标 + 文字，labelTertiary，无底色。
class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.copied,
    required this.colors,
    required this.onTap,
  });

  final bool copied;
  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colors.labelTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              copied ? Icons.check_rounded : Icons.content_copy_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              copied ? '已复制' : '复制',
              style: DsTypography.codeBlockLabel.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
