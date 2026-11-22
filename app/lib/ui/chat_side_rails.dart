/// 会话页两侧推挤侧栏的公共件（左＝会话列表，右＝会话面板）。
///
/// 抽出来是为了让 `chat_page.dart` 不越过 AGENTS §7 的 500 行线：这里只有
/// 「按 shift 展开的容器」和「手势结果判定」两块纯逻辑，不含页面状态。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 一次水平滑动的意图。
enum SwipeIntent { openDrawer, closePanel, openPanel, none }

/// 按位移与速度判定这次横滑要干什么。
///
/// 规则（与 dsh-go 的手感口径一致）：
/// - 抽屉开着 → 不接管（用户要求：在会话列表里左滑不要自动关）；
/// - 面板开着 → 只有明显右滑才收；
/// - 否则右滑过阈值开抽屉，左滑过阈值开面板。
SwipeIntent swipeIntent({
  required double dx,
  required double velocity,
  required bool drawerOpen,
  required bool panelOpen,
}) {
  if (drawerOpen) return SwipeIntent.none;
  if (panelOpen) {
    final back = dx <= -DsSpacing.drawerSwipeMinTravel || velocity < -500;
    return back ? SwipeIntent.none : SwipeIntent.closePanel;
  }
  if (dx >= DsSpacing.drawerSwipeOpenDistance ||
      (dx > DsSpacing.drawerSwipeMinTravel &&
          velocity >= DsSpacing.drawerSwipeOpenVelocity)) {
    return SwipeIntent.openDrawer;
  }
  if (dx <= -DsSpacing.drawerSwipeOpenDistance || velocity <= -900) {
    return SwipeIntent.openPanel;
  }
  return SwipeIntent.none;
}

/// 侧栏容器：`shift` 0→1 时从一侧展开（配合外层 ClippedRect 做推挤观感）。
Widget sideRail({
  required Animation<double> shift,
  required Alignment alignment,
  required double width,
  required Widget child,
}) {
  return ClipRect(
    child: AnimatedBuilder(
      animation: shift,
      builder: (context, kid) => Align(
        alignment: alignment,
        widthFactor: shift.value,
        child: kid,
      ),
      child: SizedBox(width: width, child: child),
    ),
  );
}
