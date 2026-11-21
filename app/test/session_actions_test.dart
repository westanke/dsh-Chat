/// 会话操作（重命名 / 归档）的纯逻辑单测。
library;

import 'package:dshchat/ui/session_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeSessionTitle', () {
    test('去掉首尾空白', () {
      expect(normalizeSessionTitle('  周报整理  '), '周报整理');
    });

    test('空白标题不可保存', () {
      expect(normalizeSessionTitle(''), isNull);
      expect(normalizeSessionTitle('   \n '), isNull);
    });

    test('超过 80 字截断到 80', () {
      final long = '标' * 120;
      expect(normalizeSessionTitle(long)!.length, 80);
      expect(normalizeSessionTitle('标' * 80), '标' * 80);
    });
  });
}
