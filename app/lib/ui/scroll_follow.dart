/// 滚动跟随判据（纯函数，可单测）。
///
/// 对照 companion 的两份滚动实现：
/// - `ChatDetail.kt:443-450` 的 atBottom 判据与 `ChatDetail.kt:691-717` 的 FAB；
/// - `ChatScrollDiag.kt:254-273` 的 wantsBottom 粘性意图；
/// - `ChatScrollFreeze.kt:108-109` 的 freezeSnapshot。
///
/// companion 把判据全内联在 @Composable / ViewModel 里（只有 freezeSnapshot 有机检），
/// 这里把「用户手势 → 意图 → 贴底跟随 → FAB 显隐」抽成可单测纯函数，避免
/// 真机才暴露的自锁 bug（PITFALLS.md:574-616：用瞬时 isAtBottom 当跟随守卫，
/// 一来新内容 isAtBottom 翻 false 就永久不再贴底）。
library;

import 'package:flutter/widgets.dart';

/// 距底部多少逻辑像素算「贴底」。
///
/// companion 没有固定 dp 阈值（用最后可见 item index ≥ totalItemsCount-3），
/// 但 dsh-Chat 用 ScrollController + extentAfter，取其精神：给一个小容差，
/// 让「几乎到底」也算贴底，避免亚像素抖动导致 FAB 闪烁。
const double kAtBottomTolerance = 48.0;

/// 自动贴底跟随的唯一守卫：粘性意图 + 有内容。
///
/// 刻意不用「此刻 atBottom」当守卫——companion 的教训：流式每 token 重建列表，
/// atBottom 会瞬间翻 false，跟随就自锁。只有用户真拖拽才撤销意图（wantsBottom=false），
/// 用户滚回底部 atBottom 翻 true 才恢复。
bool shouldAutoFollow({
  required bool wantsBottom,
  required bool hasItems,
  required bool streaming,
}) =>
    wantsBottom && hasItems;

/// 是否执行动画滚动：流式瞬间 jumpTo（动画追不上 token），非流式 animateTo。
bool shouldAnimateFollow(bool streaming) => !streaming;

/// 跳转最新 FAB 是否显示（对照 ChatDetail.kt:692：`!isAtBottom && !scrolling`）。
bool shouldShowFab({required bool atBottom, required bool scrolling}) =>
    !atBottom && !scrolling;

/// 由 ScrollPosition 计算 atBottom（FAB 显隐 / 意图恢复 / 跟随守卫三处同一口径）。
bool computeAtBottom({
  required double maxScrollExtent,
  required double pixels,
}) =>
    maxScrollExtent - pixels <= kAtBottomTolerance;

/// 滚动冻结快照：只在列表非空时冻结。
///
/// 对照 ChatScrollFreeze.kt:108-109 `items.takeIf { it.isNotEmpty() }`。
/// 初版 companion 曾把空表固化进 remember → 列表清空 → 位置归零 → atBottom 永久 false
/// → 跟随自锁，故空表必须返回 null 回到实时列表。
List<T>? freezeSnapshot<T>(List<T> items) =>
    items.isEmpty ? null : List<T>.unmodifiable(items);

/// 用户手势通知是否应撤销「想贴底」意图。
///
/// 对照 companion 的 DragInteraction.Start 唯一可靠判据
/// （ChatScrollDiag.kt:247,263-269）：不能用 isScrollInProgress，因为程序滚动
/// （animateTo/jumpTo）对它同样为 true。
///
/// Flutter 的 `DragScrollActivity`（用户手指拖动）发出的
/// ScrollStartNotification / ScrollUpdateNotification 带非空 `dragDetails`；
/// 程序滚动走基类 `ScrollActivity.dispatch*Notification`，`dragDetails == null`。
/// `UserScrollNotification` 也会在程序滚动（didUpdateScrollDirection）时发出，
/// 故**不**把它当作真手势，只看 dragDetails。
bool isUserScrollGesture(ScrollNotification notification) {
  if (notification is ScrollStartNotification) {
    return notification.dragDetails != null;
  }
  if (notification is ScrollUpdateNotification) {
    return notification.dragDetails != null;
  }
  return false;
}

/// 会话切换时重置的初始意图。
const bool kInitialWantsBottom = true;
