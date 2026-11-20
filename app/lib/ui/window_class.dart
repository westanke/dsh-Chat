// 窗口尺寸类：手机 / 平板同一套布局，按窗口分档取参数。
//
// 断点与规则照 Material 3，外加 dsh-go 的一条（app/lib/ui/shell/adaptive/adaptive_layout.dart）：
// **矮窗一律算紧凑**。手机横屏是 915×412——够宽，但状态栏、顶栏、输入条一去只剩几行，
// 键盘再吃掉一半；分栏后每条列只剩一条缝，一根居中的列反而把宽度全留给代码和表格。
// 这也是 Android 按最短边分手机和平板的理由。
//
// 三种窗口共用同一套**抽屉式**列表（真机反馈 2026-11-20：平板横屏也不要常驻侧栏，
// 抽屉式够用，且不该把会话页整个推出屏外）。尺寸类只决定两件事：
// 抽屉多宽、页面被推走多少。docs/design-tokens.md §4.15。

library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// 窗口尺寸类（docs/design-tokens.md §4.15）。
enum DsWindowClass {
  /// 宽 < [DsSpacing.windowMediumMin]，或高 < [DsSpacing.windowCompactHeight]。
  /// 手机（竖屏、横屏都是）：抽屉覆盖式推挤，正文与输入条各自居中限宽。
  compact,

  /// 600 ≤ 宽 < 840：折叠屏展开、小平板竖屏。抽屉式，宽度用平板侧栏宽。
  medium,

  /// 宽 ≥ 840：横屏平板、大屏。抽屉式，但页面只让出抽屉宽，不推出屏外。
  expanded;

  /// 按窗口尺寸判断；[size] 取 `MediaQuery.sizeOf(context)`。
  static DsWindowClass of(Size size) {
    if (size.height < DsSpacing.windowCompactHeight) return compact;
    if (size.width >= DsSpacing.windowExpandedMin) return expanded;
    if (size.width >= DsSpacing.windowMediumMin) return medium;
    return compact;
  }

  /// 会话列表这一列的宽度：手机 288（屏宽 80% 的官方值），
  /// 平板/折叠屏 320（会话标题多显示几个字）。
  double get sidebarWidth =>
      this == compact ? DsSpacing.drawerWidth : DsSpacing.drawerSidebarWidth;

  /// 抽屉打开时，页面左边要让出多宽（= 抽屉宽）。
  ///
  /// 同一个数有两种用法，取决于窗口：
  /// - **紧凑**（手机）：整页用 `Transform.translate` 推走这么远，页面宽度不变，
  ///   右边露出那条残条——就是官方 official-drawer.png 的样子；
  /// - **中等 / 扩展**：页面**缩窄**这么宽（`Padding(left:)`），而不是被推出去。
  ///   真机反馈 2026-11-20：平板横屏把整页推走时，顶栏右侧的 ⊕/⋮ 会被裁到屏外
  ///   ——「抽屉式列表很方便，只要别把会话推出屏外」。
  double pageInsetFor(double windowWidth) =>
      windowWidth > sidebarWidth ? sidebarWidth : windowWidth;

  /// 顶栏与输入条共用的内容列宽上限：紧凑窗比这更窄，自然退化为整屏宽。
  double get contentMaxWidth => DsSpacing.chatFloatingWidth;
}

/// 当前窗口的尺寸类（随旋转、分屏、折叠展开而变化）。
DsWindowClass windowClassOf(BuildContext context) =>
    DsWindowClass.of(MediaQuery.sizeOf(context));
