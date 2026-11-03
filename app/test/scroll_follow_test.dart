import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/ui/scroll_follow.dart';

void main() {
  // 构造一个最小可用的 ScrollMetrics，供通知断言使用。
  FixedScrollMetrics metrics({
    double minScrollExtent = 0,
    double maxScrollExtent = 1000,
    double pixels = 0,
    double viewportDimension = 600,
  }) {
    return FixedScrollMetrics(
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
      pixels: pixels,
      viewportDimension: viewportDimension,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );
  }

  group('shouldAutoFollow', () {
    test('只有粘性意图 + 有内容才跟随', () {
      expect(
        shouldAutoFollow(wantsBottom: true, hasItems: true, streaming: true),
        isTrue,
      );
      expect(
        shouldAutoFollow(wantsBottom: true, hasItems: true, streaming: false),
        isTrue,
      );
    });

    test('用户拖拽撤销意图后不再跟随（即使仍在底部）', () {
      // 关键回归：companion 曾用瞬时 isAtBottom 当守卫，流式一来就自锁；
      // 这里 hasItems/streaming 都为真，但 wantsBottom=false 必须拒绝。
      expect(
        shouldAutoFollow(wantsBottom: false, hasItems: true, streaming: true),
        isFalse,
      );
    });

    test('空列表不跟随', () {
      expect(
        shouldAutoFollow(wantsBottom: true, hasItems: false, streaming: false),
        isFalse,
      );
    });
  });

  group('shouldAnimateFollow', () {
    test('流式 jumpTo（动画追不上 token），非流式 animateTo', () {
      expect(shouldAnimateFollow(true), isFalse);
      expect(shouldAnimateFollow(false), isTrue);
    });
  });

  group('shouldShowFab', () {
    test('离开底部且非滚动中才显示', () {
      expect(shouldShowFab(atBottom: false, scrolling: false), isTrue);
      expect(shouldShowFab(atBottom: true, scrolling: false), isFalse);
      expect(shouldShowFab(atBottom: false, scrolling: true), isFalse);
      expect(shouldShowFab(atBottom: true, scrolling: true), isFalse);
    });
  });

  group('computeAtBottom', () {
    test('extentAfter 在容差内算贴底', () {
      expect(
        computeAtBottom(maxScrollExtent: 1000, pixels: 1000 - 48),
        isTrue,
      );
      expect(
        computeAtBottom(maxScrollExtent: 1000, pixels: 1000 - 47.9),
        isTrue,
      );
    });

    test('超过容差不算贴底', () {
      expect(
        computeAtBottom(maxScrollExtent: 1000, pixels: 1000 - 49),
        isFalse,
      );
    });

    test('内容不足一屏（maxScrollExtent 为负/0）也算贴底', () {
      expect(computeAtBottom(maxScrollExtent: 0, pixels: 0), isTrue);
    });
  });

  group('freezeSnapshot', () {
    test('空表返回 null（companion 固化空表事故防线）', () {
      expect(freezeSnapshot<int>(<int>[]), isNull);
    });

    test('非空表返回不可修改的副本，源表后续改动不影响快照', () {
      final source = <int>[1, 2, 3];
      final snap = freezeSnapshot(source);
      expect(snap, isNotNull);
      expect(snap, equals(<int>[1, 2, 3]));
      source.add(4);
      expect(snap, equals(<int>[1, 2, 3]));
      expect(() => snap!.add(9), throwsUnsupportedError);
    });

    test('单条也有效', () {
      expect(freezeSnapshot<String>(['a']), equals(['a']));
    });
  });

  group('isUserScrollGesture', () {
    test('用户拖拽（dragDetails 非空）才撤销意图', () {
      final m = metrics();
      final start = ScrollStartNotification(
        metrics: m,
        context: _FakeContext(),
        dragDetails: DragStartDetails(),
      );
      final update = ScrollUpdateNotification(
        metrics: m,
        context: _FakeContext(),
        dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
      );
      expect(isUserScrollGesture(start), isTrue);
      expect(isUserScrollGesture(update), isTrue);
    });

    test('程序滚动（dragDetails 为 null）不算用户手势', () {
      final m = metrics();
      final start = ScrollStartNotification(metrics: m, context: _FakeContext());
      final update = ScrollUpdateNotification(metrics: m, context: _FakeContext());
      expect(isUserScrollGesture(start), isFalse);
      expect(isUserScrollGesture(update), isFalse);
    });

    test('UserScrollNotification 在程序滚动也会发，绝不当用户手势', () {
      final m = metrics();
      final user = UserScrollNotification(
        metrics: m,
        context: _FakeContext(),
        direction: ScrollDirection.reverse,
      );
      expect(isUserScrollGesture(user), isFalse);
    });

    test('其它通知类型一律不算', () {
      final m = metrics();
      expect(
        isUserScrollGesture(ScrollEndNotification(metrics: m, context: _FakeContext())),
        isFalse,
      );
    });
  });

  group('kInitialWantsBottom', () {
    test('会话切换重置为真', () {
      expect(kInitialWantsBottom, isTrue);
    });
  });
}

/// 仅供构造通知用：ScrollNotification.context 是必填但判据不读它。
/// 用 implements + 自定义 noSuchMethod，让 Dart 为缺失成员生成转发器。
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
