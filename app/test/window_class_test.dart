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

    test('HITL 卡宽：手机不限、宽窗收在正文读宽上', () {
      // 手机上返回无穷大 = 卡片照旧铺满正文列（与改动前逐字相同）；
      // 平板横屏收在 720，否则一张审批卡会被拉成一整条横幅。
      expect(DsWindowClass.compact.hitlMaxWidth, double.infinity);
      expect(DsWindowClass.medium.hitlMaxWidth, DsSpacing.hitlPanelMaxWidth);
      expect(DsWindowClass.expanded.hitlMaxWidth, DsSpacing.hitlPanelMaxWidth);
      expect(DsSpacing.hitlPanelMaxWidth, DsSpacing.chatReadingWidth);
    });

    test('二级页正文列：手机不限、宽窗收在 720', () {
      expect(DsWindowClass.compact.pageColumnMaxWidth, double.infinity);
      expect(
        DsWindowClass.expanded.pageColumnMaxWidth,
        DsSpacing.pageColumnMaxWidth,
      );
      expect(DsSpacing.pageColumnMaxWidth, DsSpacing.settingsMaxWidth);
    });

    test('内容列宽与输入条同一列', () {
      for (final cls in DsWindowClass.values) {
        expect(cls.contentMaxWidth, DsSpacing.chatFloatingWidth);
      }
    });
  });
}
