/// reasoning_text.dart 纯函数单测（官方 client.js 8126-8150 逐字对照）：
/// firstLineOf/latestCompletedParagraphFirstLine/reasoningTextOf/
/// reasoningHidden/reasoningSummaryOf。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/ui/reasoning_text.dart';

void main() {
  group('firstLineOf', () {
    test('无换行返回原文', () {
      expect(firstLineOf('只有一行'), '只有一行');
    });
    test('有换行取首行', () {
      expect(firstLineOf('首行\n次行'), '首行');
      expect(firstLineOf('\n次行'), '');
    });
  });

  group('latestCompletedParagraphFirstLine', () {
    test('未收尾段（无换行结尾）不产出摘要（官方逐字语义）', () {
      expect(latestCompletedParagraphFirstLine('你好'), '');
      expect(latestCompletedParagraphFirstLine('\n\n  正文 '), '');
    });
    test('多段取最后一个已完成段的首行', () {
      expect(latestCompletedParagraphFirstLine('第一段\n\n第二段开始\n还没完'), '第二段开始');
    });
    test('最后一段未收尾 → 仍是上一已完成段（官方逐字语义）', () {
      expect(latestCompletedParagraphFirstLine('段A\n\n\n\n段B'), '段A');
    });
    test('全文无段落分隔时取首行', () {
      expect(latestCompletedParagraphFirstLine('首行\n次行'), '首行');
    });
    test('全空白返回空串', () {
      expect(latestCompletedParagraphFirstLine('  \n\n  '), '');
    });
  });

  group('reasoningTextOf', () {
    test('非 < 开头原样返回', () {
      expect(reasoningTextOf('普通思考\n正文'), '普通思考\n正文');
      expect(reasoningTextOf('前缀<signature>不是开头'), '前缀<signature>不是开头');
    });
    test('< 开头但非 signature 开始标签 → 原样（官方逐字口径）', () {
      expect(reasoningTextOf('<think>内容'), '<think>内容');
      expect(reasoningTextOf('<'), ''); // 未写完的 <signature> 前缀
      expect(reasoningTextOf('<sign'), '');
      expect(reasoningTextOf('<signature'), '');
    });
    test('signature 包裹剥除并跳过结尾换行', () {
      expect(reasoningTextOf('<signature>abc</signature>\n思考正文'), '思考正文');
      expect(reasoningTextOf('<signature>abc</signature>\r\n\r\n两行'), '两行');
    });
    test('未闭合 signature → 空串；仅标签 → 空串', () {
      expect(reasoningTextOf('<signature>abc'), '');
      expect(reasoningTextOf('<signature>'), '');
      expect(reasoningTextOf('<signature></signature>尾巴'), '尾巴');
    });
  });

  group('reasoningHidden', () {
    test('剥签后全空白 → 隐藏', () {
      expect(reasoningHidden('<signature>abc</signature>\n\n  '), isTrue);
      expect(reasoningHidden('<signature>abc'), isTrue);
    });
    test('剥签后有正文或原文无签 → 不隐藏', () {
      expect(reasoningHidden('<signature>abc</signature>正文'), isFalse);
      expect(reasoningHidden('普通思考'), isFalse);
    });
  });

  group('reasoningSummaryOf', () {
    test('running 取最后已完成段首行，否则首行；** 全剥', () {
      expect(reasoningSummaryOf('**加粗**段\n\n最终段', running: true), '加粗段');
      expect(reasoningSummaryOf('**首行**\n次行', running: false), '首行');
      // 官方逐字语义：无换行的未收尾段不产出摘要（流式首行尚未完成）。
      expect(reasoningSummaryOf('纯文本', running: true), '');
    });
    test('先剥 signature 再取摘要', () {
      expect(
        reasoningSummaryOf(
          '<signature>abc</signature>\n**签名后**首行',
          running: false,
        ),
        '签名后首行',
      );
    });
  });
}
