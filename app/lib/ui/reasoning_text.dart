/// 思考行纯函数（官方 ReasoningRow 逐字移植，task-5）。
///
/// 官方 client.js 8126-8150：
/// - `firstLine(text)`：首个换行前文本；
/// - `latestCompletedParagraphFirstLine(text)`：取最后一个已完成段落的
///   首个非空行（段落分隔符 = 空行，含空白行）；
/// - `reasoningText(text)`：剥 `<signature>…</signature>` 包裹；
/// - `hidden`：剥签前后文本非原样且全空白 → 整块不渲染。
library;

/// `firstLine(text)`：无换行返回原文。
String firstLineOf(String text) {
  final newline = text.indexOf('\n');
  return newline == -1 ? text : text.substring(0, newline);
}

/// `latestCompletedParagraphFirstLine(text)`：官方原文逻辑——
/// 以空行（`\r?\n(?:[\t ]*\r?\n)+`）分段，逐段取段内首个非空行；
/// 最后一段的段尾视为文本末尾；仅当候选行 trim 后非空才更新摘要。
String latestCompletedParagraphFirstLine(String text) {
  var summary = '';
  var paragraphStart = 0;
  final matches = RegExp(r'\r?\n(?:[\t ]*\r?\n)+').allMatches(text).toList();
  for (var i = 0; ; i++) {
    final match = i < matches.length ? matches[i] : null;
    final paragraphEnd = match == null
        ? text.length
        : match.start + (match.group(0) ?? '').indexOf('\n');
    final newline = text.indexOf('\n', paragraphStart);
    if (newline != -1 && newline <= paragraphEnd) {
      final candidate = text.substring(paragraphStart, newline).trim();
      if (candidate.isNotEmpty) summary = candidate;
    }
    if (match == null) return summary;
    paragraphStart = match.end;
  }
}

/// `reasoningText(text)`：剥 `<signature>…</signature>` 包裹。
/// - 首字符不是 `<` → 原样；
/// - 文本是 `<signature>` 的**未写完前缀**（流式半截标签）→ 空串；
/// - 以 `<` 开头但不是 `<signature>` → **原样返回**（官方逐字口径，
///   兄弟分支不是 signature 时不吞正文）；
/// - 找到 `</signature>` 结尾后跳过紧随换行返回剩余；找不到 → 空串。
String reasoningTextOf(String text) {
  if (text.isEmpty || text[0] != '<') return text;
  const openTag = '<signature>';
  if (openTag.startsWith(text)) return '';
  if (!text.startsWith(openTag)) return text;
  final closeIndex = text.indexOf('</signature>', openTag.length);
  if (closeIndex == -1) return '';
  var start = closeIndex + '</signature>'.length;
  // 官方：逐个跳过 '\n'；遇 '\r\n' 一次跳两个；其余（含孤立 '\r'）停止。
  while (start < text.length) {
    if (text[start] == '\n') {
      start++;
    } else if (text[start] == '\r' &&
        start + 1 < text.length &&
        text[start + 1] == '\n') {
      start += 2;
    } else {
      break;
    }
  }
  return text.substring(start);
}

/// 官方 `hidden = text !== rawText && text.trim() === ''`：
/// 签名剥除后不剩正文 → 整块不渲染。
bool reasoningHidden(String rawText) {
  final text = reasoningTextOf(rawText);
  return text != rawText && text.trim().isEmpty;
}

/// 思考摘要（官方 ReasoningRow）：
/// running → 最后已完成段落首行；否则首行；`**` 全剥。
String reasoningSummaryOf(String text, {required bool running}) {
  final body = reasoningTextOf(text);
  final source = running
      ? latestCompletedParagraphFirstLine(body)
      : firstLineOf(body);
  return source.replaceAll('**', '');
}
