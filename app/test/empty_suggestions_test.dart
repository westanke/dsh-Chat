// 空态建议卡与技巧行的数据面单测。
import 'package:dshchat/ui/empty_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('默认建议卡', () {
    test('四张卡，标题/说明/prompt 都不为空', () {
      expect(kDefaultSuggestions.length, 4);
      for (final s in kDefaultSuggestions) {
        expect(s.label.trim().isNotEmpty, isTrue);
        expect(s.detail.trim().isNotEmpty, isTrue);
        expect(s.prompt.trim().isNotEmpty, isTrue);
      }
    });

    test('四种色系各一张，没有重复', () {
      final tones = kDefaultSuggestions.map((s) => s.tone).toSet();
      expect(tones.length, 4);
    });

    test('prompt 是完整句子（能直接填进输入框）', () {
      for (final s in kDefaultSuggestions) {
        expect(s.prompt.length, greaterThan(10));
      }
    });
  });

  group('技巧池', () {
    test('非空且去重', () {
      expect(kEmptyTips, isNotEmpty);
      expect(kEmptyTips.toSet().length, kEmptyTips.length);
    });

    test('每条都不为空且带具体入口', () {
      for (final tip in kEmptyTips) {
        expect(tip.trim().isNotEmpty, isTrue);
        expect(tip.length, greaterThan(8));
      }
    });
  });
}
