// ---------- 引用追问：QuoteTarget 模型 / 引用横幅 / 发给模型的文本 ----------
//
// 定位：输入条上方的「引用横幅」与消息操作条的「引用」入口共用的数据与渲染。
// 引用状态本身（当前有没有选中的 QuoteTarget、清空、发送时拼接）由调用方
// （ChatState / composer 装配层）持有；本文件不碰任何全局状态。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 引用来源：谁说的。
///
/// 官方界面的引用横幅用「你 / 助手」区分；存枚举而不是字符串，
/// 免得调用方各自写 '你' / 'user' 造成口径漂移。
enum QuoteAuthor {
  you('你'),
  assistant('助手');

  const QuoteAuthor(this.label);

  /// 展示与发送文案里的称呼。
  final String label;
}

/// 一条被引用的消息（不可变）。
///
/// [text] 只用于横幅展示（最多 [previewMaxChars] 字，超出补「…」）；
/// [fullText] 保留原文全文，`composeQuotedMessage` 发送时用它，避免长文
/// 被 280 字预览截断后模型看不到后半段。
class QuoteTarget {
  QuoteTarget({
    required this.messageSeq,
    required this.author,
    required String text,
    this.messageId,
  }) : fullText = text,
       text = _clip(text);

  /// 从消息角色字符串构造（'user' → 你，其它 → 助手）。
  ///
  /// 便于调用方直接拿 `ChatMessage.role` 转换，不用在两处写映射。
  factory QuoteTarget.fromRole({
    required int messageSeq,
    required String role,
    required String text,
    String? messageId,
  }) {
    return QuoteTarget(
      messageSeq: messageSeq,
      author: role == 'user' ? QuoteAuthor.you : QuoteAuthor.assistant,
      text: text,
      messageId: messageId,
    );
  }

  /// 横幅预览最多保留多少字（按 Unicode 码点算，不会切坏 emoji）。
  static const previewMaxChars = 280;

  /// 服务端消息序号（流式消息为 -1）。
  final int messageSeq;

  /// 引用来源。
  final QuoteAuthor author;

  /// 横幅展示用文本：≤ [previewMaxChars] 字，超出部分以「…」收尾。
  final String text;

  /// 原文全文（不截断），发送给模型时使用。
  final String fullText;

  /// 服务端消息 id（协议里有就带上，便于后续按 id 定位；可空）。
  final String? messageId;

  /// 称呼（「你」/「助手」），给不 import 枚举的调用方用。
  String get authorLabel => author.label;

  static String _clip(String raw) {
    final runes = raw.runes;
    if (runes.length <= previewMaxChars) return raw;
    return '${String.fromCharCodes(runes.take(previewMaxChars))}…';
  }

  @override
  bool operator ==(Object other) =>
      other is QuoteTarget &&
      other.messageSeq == messageSeq &&
      other.author == author &&
      other.fullText == fullText &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(messageSeq, author, fullText, messageId);

  @override
  String toString() =>
      'QuoteTarget(#$messageSeq ${author.label}, ${fullText.length} 字)';
}

/// 8 行以内不折叠；超过 20 行时保留首尾各 8 行，中间用「…」占一行。
const _foldThreshold = 20;
const _foldHead = 8;
const _foldTail = 8;

/// 把引用目标 + 用户输入拼成发给模型的文本。
///
/// 格式：`> 引用（#seq 助手）：原文\n\n用户输入`；原文多行时每行补 `> `，
/// 超过 20 行折叠成「首 8 行 + … + 尾 8 行」。用户输入为空（含全空白）时
/// 只回引用块——空发送由调用方拦，这里只负责格式。
String composeQuotedMessage(QuoteTarget quote, String input) {
  final shown = _foldLines(quote.fullText);
  final buf = StringBuffer()
    ..write('> 引用（#${quote.messageSeq} ${quote.author.label}）：')
    ..write(shown.first);
  for (final line in shown.skip(1)) {
    buf
      ..write('\n')
      ..write('> ')
      ..write(line);
  }
  if (input.trim().isEmpty) return buf.toString();
  return '$buf\n\n$input';
}

List<String> _foldLines(String raw) {
  final lines = raw.split('\n');
  if (lines.length <= _foldThreshold) return lines;
  return [
    ...lines.take(_foldHead),
    '…',
    ...lines.skip(lines.length - _foldTail),
  ];
}

/// 输入条上方的引用横幅。
///
/// 左侧竖线 + 「引用 #seq 你/助手」+ 两行截断原文 + 关闭按钮。
/// 横幅本身点击默认不做事（[onTap] 留给「滚动到原消息」这类后续需求）；
/// 关闭按钮只回 [onClear]，不会冒泡到 [onTap]。
class QuotePreview extends StatelessWidget {
  const QuotePreview({
    super.key,
    required this.quote,
    required this.onClear,
    this.colors = const DsColors(false),
    this.onTap,
  });

  final QuoteTarget quote;
  final VoidCallback onClear;

  /// 配色（跟随页面主题；不传按浅色）。
  final DsColors colors;

  /// 点横幅（不是关闭按钮）的回调；null 时横幅不接手势。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final banner = Container(
      // 左右与输入条同边距（composerMargin）——横幅要像输入条的一部分。
      margin: const EdgeInsets.symmetric(horizontal: DsSpacing.composerMargin),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.mdCitationBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧竖线：与 markdown blockquote 同一 token（2dp / quoteBar）。
            Container(width: DsSpacing.quoteBarWidth, color: c.quoteBar),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DsSpacing.codeBlockPad,
                  DsSpacing.actionIconGap,
                  DsSpacing.actionIconGap,
                  DsSpacing.actionIconGap,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '引用 #${quote.messageSeq} ${quote.author.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.smallStrong.copyWith(
                              color: c.labelSecondary,
                            ),
                          ),
                          Text(
                            quote.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.small.copyWith(
                              color: c.labelTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ClearButton(colors: c, onClear: onClear),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return banner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: banner,
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.colors, required this.onClear});

  final DsColors colors;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // 28 点击格：36 会把两行横幅撑得过高，28 仍比关闭图标（16）大一圈。
    return Tooltip(
      message: '取消引用',
      child: InkResponse(
        onTap: onClear,
        radius: 16,
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: Icon(Icons.close, size: 16, color: colors.labelTertiary),
          ),
        ),
      ),
    );
  }
}
