// 窗口尺寸类（docs/design-tokens.md §4.15）：断点边界与各档取值。
//
// 这几个数字决定了「同一套布局在手机上不变、在平板上分栏」，所以边界
// （599/600、839/840）和「矮窗优先」都要钉住，改 token 时测试会先响。

library;

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/window_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('DsWindowClass.of 的断点', () {
    test('窄于 600 是紧凑：手机竖屏 360×800', () {
      expect(DsWindowClass.of(const Size(360, 800)), DsWindowClass.compact);
    });

    test('599 仍是紧凑，600 才进中等（边界不重叠）', () {
      expect(DsWindowClass.of(const Size(599, 900)), DsWindowClass.compact);
      expect(DsWindowClass.of(const Size(600, 900)), DsWindowClass.medium);
    });

    test('839 仍是中等，840 才进扩展', () {
      expect(DsWindowClass.of(const Size(839, 900)), DsWindowClass.medium);
      expect(DsWindowClass.of(const Size(840, 900)), DsWindowClass.expanded);
    });

    test('横屏平板 1181×738 是扩展', () {
      expect(DsWindowClass.of(const Size(1181, 738)), DsWindowClass.expanded);
    });
  });

  group('矮窗一律紧凑（dsh-go 的规则）', () {
    test('手机横屏 915×412 够宽但仍算紧凑', () {
      expect(DsWindowClass.of(const Size(915, 412)), DsWindowClass.compact);
    });

    test('479 高算紧凑，480 高才看宽度', () {
      expect(DsWindowClass.of(const Size(1200, 479)), DsWindowClass.compact);
      expect(DsWindowClass.of(const Size(1200, 480)), DsWindowClass.expanded);
    });

    test('分屏后的矮窗不会因为宽而分栏', () {
      expect(DsWindowClass.of(const Size(1000, 400)), DsWindowClass.compact);
    });
  });

  group('抽屉与推挤（三种窗口都是抽屉式）', () {
    test('页面让出的宽度等于抽屉宽', () {
      // 手机 360 让 288 后剩 72，仍是官方的残条观感（整页推走）；
      // 平板横屏 1181 让 320 后还剩 861，页面把这一条让出去而不是被推出屏。
      expect(DsWindowClass.compact.pageInsetFor(360), DsSpacing.drawerWidth);
      expect(360 - DsWindowClass.compact.pageInsetFor(360), 72);
      expect(
        DsWindowClass.expanded.pageInsetFor(1181),
        DsSpacing.drawerSidebarWidth,
      );
      expect(1181 - DsWindowClass.expanded.pageInsetFor(1181), 861);
      expect(
        DsWindowClass.medium.pageInsetFor(738),
        DsSpacing.drawerSidebarWidth,
      );
    });

    test('窗口比抽屉还窄时不让出比窗口更多的距离', () {
      expect(DsWindowClass.compact.pageInsetFor(200), 200);
    });
  });

  group('各档取值', () {
    test('紧凑窗用官方抽屉宽 288，其余用 320', () {
      expect(DsWindowClass.compact.sidebarWidth, DsSpacing.drawerWidth);
      expect(DsWindowClass.medium.sidebarWidth, DsSpacing.drawerSidebarWidth);
      expect(DsWindowClass.expanded.sidebarWidth, DsSpacing.drawerSidebarWidth);
      expect(DsSpacing.drawerSidebarWidth, greaterThan(DsSpacing.drawerWidth));
    });
  });

  group('可读列宽：全 App 不再钉死 720（§4.16）', () {
    test('屏宽不超过 720 时用满：手机逐字不变', () {
      expect(readableColumnWidth(360), 360);
      expect(readableColumnWidth(600), 600);
      expect(readableColumnWidth(720), 720);
    });

    test('超过 720 后按 0.9 随屏宽长，不设第二道上限', () {
      // 738×0.9 = 664.2 < 720，仍取 720；再宽才真正开始长。
      expect(readableColumnWidth(738), DsSpacing.readableBaseWidth);
      expect(readableColumnWidth(861), closeTo(774.9, 1e-9));
      expect(readableColumnWidth(1181), closeTo(1062.9, 1e-9));
      expect(readableColumnWidth(1600), closeTo(1440.0, 1e-9));
      expect(
        readableColumnWidth(2000),
        greaterThan(readableColumnWidth(1600)),
        reason: '没有上限，宽屏继续长',
      );
    });

    test('列宽单调不减，且永远不超过可用宽', () {
      var previous = 0.0;
      for (var w = 200.0; w <= 2400; w += 7) {
        final column = readableColumnWidth(w);
        expect(column, greaterThanOrEqualTo(previous));
        expect(column, lessThanOrEqualTo(w));
        previous = column;
      }
    });

    test('无界输入（父约束缺省）仍返回无界，由上层兜底', () {
      expect(readableColumnWidth(double.infinity), double.infinity);
    });

    test('浮层列宽：手机没有富余就铺满，宽窗才窄两侧各 14', () {
      expect(floatingColumnWidth(360), 360);
      expect(floatingColumnWidth(600), 600);
      expect(floatingColumnWidth(738), closeTo(692, 1e-9));
      expect(floatingColumnWidth(1181), closeTo(1062.9 - 28, 1e-9));
    });

    testWidgets('模态 sheet 不再被 M3 默认的 640 卡住', (tester) async {
      tester.view.physicalSize = const Size(1181, 738);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      showModalBottomSheet<void>(
        context: pageContext,
        constraints: modalSheetConstraints(pageContext),
        builder: (_) => const SizedBox(
          key: ValueKey('sheetBody'),
          width: double.infinity,
          height: 100,
        ),
      );
      await tester.pumpAndSettle();
      // BottomSheet 自己仍吃满整屏（Align），限宽后内容才落在那一列上。
      expect(
        tester.getSize(find.byKey(const ValueKey('sheetBody'))).width,
        closeTo(1062.9, 0.5),
      );
    });
  });
}
