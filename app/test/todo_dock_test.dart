/// 任务条摘要的单测（移植 dsh-go `TodoDockSummary.of` 的口径）。
library;

import 'package:dshchat/bridge/projections.dart';
import 'package:dshchat/ui/todo_dock.dart';
import 'package:flutter_test/flutter_test.dart';

TodoItem _t(String content, String status) =>
    TodoItem(content: content, status: status);

void main() {
  group('TodoDockSummary.of', () {
    test('没有清单时不显示（返回 null）', () {
      expect(TodoDockSummary.of(const [], running: false), isNull);
    });

    test('计数与进度：完成数 / 总数', () {
      final s = TodoDockSummary.of([
        _t('a', 'completed'),
        _t('b', 'completed'),
        _t('c', 'in_progress'),
        _t('d', 'pending'),
      ], running: true)!;
      expect(s.total, 4);
      expect(s.done, 2);
      expect(s.count, '2/4');
      expect(s.fraction, closeTo(0.5, 1e-9));
      expect(s.isComplete, isFalse);
    });

    test('运行中且当前项进行中 → 「正在：…」', () {
      final s = TodoDockSummary.of([
        _t('跑测试', 'in_progress'),
        _t('写报告', 'pending'),
      ], running: true)!;
      expect(s.label, '正在：跑测试');
      expect(s.current!.content, '跑测试');
    });

    test('没在跑 → 「下一步：…」，即使有进行中项', () {
      final s = TodoDockSummary.of([
        _t('跑测试', 'in_progress'),
      ], running: false)!;
      expect(s.label, '下一步：跑测试');
    });

    test('没有进行中项 → 取第一个未完成作「下一步」', () {
      final s = TodoDockSummary.of([
        _t('a', 'completed'),
        _t('b', 'pending'),
        _t('c', 'pending'),
      ], running: false)!;
      expect(s.label, '下一步：b');
      expect(s.current!.content, 'b');
    });

    test('全部完成 → 「全部完成」，current 为 null', () {
      final s = TodoDockSummary.of([
        _t('a', 'completed'),
        _t('b', 'completed'),
      ], running: true)!;
      expect(s.label, '全部完成');
      expect(s.current, isNull);
      expect(s.isComplete, isTrue);
      expect(s.fraction, 1.0);
    });
  });
}
