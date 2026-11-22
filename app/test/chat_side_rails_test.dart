// 会话页横滑意图（ui/chat_side_rails.dart）：右滑开抽屉、左滑开面板。
import 'package:dshchat/ui/chat_side_rails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('swipeIntent', () {
    test('抽屉开着不接管（抽屉内左滑不自动关）', () {
      expect(
        swipeIntent(dx: -200, velocity: -2000, drawerOpen: true, panelOpen: false),
        SwipeIntent.none,
      );
    });

    test('右滑过阈值开抽屉', () {
      expect(
        swipeIntent(dx: 80, velocity: 0, drawerOpen: false, panelOpen: false),
        SwipeIntent.openDrawer,
      );
    });

    test('小幅右滑但速度够也算开', () {
      expect(
        swipeIntent(dx: 30, velocity: 900, drawerOpen: false, panelOpen: false),
        SwipeIntent.openDrawer,
      );
    });

    test('左滑开面板', () {
      expect(
        swipeIntent(dx: -80, velocity: 0, drawerOpen: false, panelOpen: false),
        SwipeIntent.openPanel,
      );
    });

    test('面板开着时右滑收起', () {
      expect(
        swipeIntent(dx: 40, velocity: 200, drawerOpen: false, panelOpen: true),
        SwipeIntent.closePanel,
      );
    });

    test('面板开着时继续左滑不动', () {
      expect(
        swipeIntent(dx: -60, velocity: -800, drawerOpen: false, panelOpen: true),
        SwipeIntent.none,
      );
    });

    test('幅度与速度都不够什么都不做', () {
      expect(
        swipeIntent(dx: 10, velocity: 50, drawerOpen: false, panelOpen: false),
        SwipeIntent.none,
      );
    });
  });
}
