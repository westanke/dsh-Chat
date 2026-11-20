// 会话列表的「居中锚定」几何回归测试。
//
// dsh-go 的不变量（app/lib/ui/chat/chat_list.dart）：
//   before 段的 delegate 下标 i → 行数组 rows[split-1-i]；
//   前插 n 条更早历史时行数组头部多 n、split 同样多 n，于是
//     rows_new[split_new-1-i] == rows_old[split_old-1-i]
//   老内容的 delegate 下标不变 → 反向段里离零滚动线的距离不变 → 不跳位。
//
// 这条不变量在 Flutter 3.50 原生语义下成立（CustomScrollView.center +
// anchor），本测试把它钉住：前插更早历史后，可见行的位置一格都不许动。
//
// （本文件早先是量数据的探针，只打印不断言；移植落地后它是硬依赖，
// 改成断言式回归测试。）

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('前插更早历史：可见内容不跳位，滚动范围不变', (tester) async {
    final centerKey = GlobalKey();

    // 行数组按「老 → 新」排（与 deriveRows 的顺序一致）。
    var rows = List<String>.generate(20, (i) => 'r$i');
    var split = rows.length;

    Widget build() {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              center: centerKey,
              anchor: 0.9767,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Container(
                      key: ValueKey<String>(rows[split - 1 - i]),
                      height: 100,
                      color: const Color(0xFF3366FF),
                    ),
                    childCount: split,
                  ),
                ),
                SliverList(
                  key: centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Container(
                      key: ValueKey<String>('c$i'),
                      height: 100,
                      color: const Color(0xFFFF6600),
                    ),
                    childCount: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pump();

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    final pos = scroll.position;

    // 视口里能看到的所有行（不管溢出与否）。
    Map<String, double> visibleTops() {
      final out = <String, double>{};
      for (final name in rows) {
        final f = find.byKey(ValueKey<String>(name));
        if (f.evaluate().isEmpty) continue;
        out[name] = tester.getRect(f).top;
      }
      for (final name in ['c0', 'c1']) {
        final f = find.byKey(ValueKey<String>(name));
        if (f.evaluate().isNotEmpty) out[name] = tester.getRect(f).top;
      }
      return out;
    }

    final before = visibleTops();
    // 前提：确实有可见行可量，否则这个测试没意义。
    expect(before, isNotEmpty);

    final pixelsBefore = pos.pixels;
    final minBefore = pos.minScrollExtent;
    final maxBefore = pos.maxScrollExtent;

    // 前插 3 条更早的历史：行数组头部多 3、split 同样多 3。
    rows = [...List<String>.generate(3, (i) => 'old$i'), ...rows];
    split = rows.length;
    await tester.pumpWidget(build());
    await tester.pump();

    final after = visibleTops();
    for (final entry in before.entries) {
      final now = after[entry.key];
      expect(
        now,
        isNotNull,
        reason: '前插后老行 ${entry.key} 不该消失',
      );
      expect(
        now! - entry.value,
        closeTo(0, 0.01),
        reason: '前插后老行 ${entry.key} 跳位了',
      );
    }

    // 滚动范围不因前插而变（反向段的 extent 由「离零滚动线的距离」决定，
    // 不由行数决定）。
    expect(pos.pixels, closeTo(pixelsBefore, 0.01));
    expect(pos.minScrollExtent, closeTo(minBefore, 0.01));
    expect(pos.maxScrollExtent, closeTo(maxBefore, 0.01));
  });

  testWidgets('center 之前的 sliver 反向生长，之后正向生长', (tester) async {
    final centerKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              center: centerKey,
              anchor: 0.875,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SizedBox(
                      key: ValueKey<String>('b$i'),
                      height: 100,
                    ),
                    childCount: 5,
                  ),
                ),
                SliverList(
                  key: centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SizedBox(
                      key: ValueKey<String>('c$i'),
                      height: 100,
                    ),
                    childCount: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    double topOf(String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key))).top;

    // before 段：下标 0 离零滚动线最近，往上长（top 依次变小）。
    expect(topOf('b0'), greaterThan(topOf('b1')));
    expect(topOf('b1'), greaterThan(topOf('b2')));

    // 滚到底，center 段整段都铺开了：它往下长（top 依次变大）。
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();

    expect(topOf('c1'), greaterThan(topOf('c0')));
    expect(topOf('c2'), greaterThan(topOf('c1')));
  });

  // 尾部留白：滚到底时最后一条消息要停在视口底之上 bottomPad 处，
  // 不能贴着底边（否则会被输入条上沿的渐隐带吃掉一截）。
  // dsh-go 的做法是末尾挂一个 SliverToBoxAdapter(SizedBox(height: bottomPad))，
  // 且这个 bottomPad 与 anchor 用同一个值。
  testWidgets('末尾留白：滚到底时最后一行不贴视口底', (tester) async {
    const bottomPad = 20.0;
    final centerKey = GlobalKey();

    Widget build({required double tail}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              center: centerKey,
              anchor: (600 - bottomPad) / 600,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SizedBox(
                      key: ValueKey<String>('b$i'),
                      height: 100,
                    ),
                    childCount: 3,
                  ),
                ),
                SliverList(
                  key: centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SizedBox(
                      key: ValueKey<String>('c$i'),
                      height: 100,
                    ),
                    childCount: 6,
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: tail)),
              ],
            ),
          ),
        ),
      );
    }

    double lastBottom() =>
        tester.getRect(find.byKey(const ValueKey<String>('c5'))).bottom;

    await tester.pumpWidget(build(tail: 0));
    await tester.pump();
    var scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final noTail = lastBottom();

    await tester.pumpWidget(build(tail: bottomPad));
    await tester.pump();
    scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final withTail = lastBottom();

    // 没有尾部留白时，末行底边正好压在视口底（600）。
    expect(noTail, closeTo(600, 0.01));
    // 有留白时，末行底边被抬高 bottomPad。
    expect(withTail, closeTo(600 - bottomPad, 0.01));
    expect(withTail, lessThan(noTail));
  });
}
