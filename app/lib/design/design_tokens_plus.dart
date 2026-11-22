part of 'tokens.dart';

/// 「+」附件面板的尺寸与宫格配色（docs/design-tokens.md §4.19）。
///
/// 结构与数值对照 dsh-Go `app/lib/ui/chat/widgets/plus_panel.dart` 的
/// `PlusPanelMetrics`（side=16 / gap=8 / square=60）；本仓只留两格
/// （相册、文件），彩色方块用语义色淡染，不引入 dsh-Go 的 identity 调色板。
///
/// 单独拆文件而不塞进 design_tokens_layout.dart：后者已被并行改动顶到
/// 501 行，再加就破宪法 §7 的单文件 500 行硬限；这里同样是 tokens.dart 的
/// part，引用方只 import `design/tokens.dart`。
abstract final class DsPlusPanel {
  /// 面板左右边距：宫格首/末格与分组卡片都对齐这条线。
  static const side = 16.0;

  /// 宫格格间距（dsh-Go `PlusPanelMetrics.gap`）。
  static const gap = 8.0;

  /// 彩色方块边长（dsh-Go `PlusPanelMetrics.square`=60）。
  static const tileSize = 60.0;

  /// 方块内图标边长（dsh-Go `size: 26`）。
  static const tileIconSize = 26.0;

  /// 方块圆角（dsh-Go `AppShape.lg` 的 Squircle；Flutter 侧用同值圆角）。
  static const tileRadius = 18.0;

  /// 单格的上下内边距（dsh-Go `EdgeInsets.symmetric(vertical: 10)`）。
  static const tilePadV = 10.0;

  /// 方块与下方文字的间距（dsh-Go `SizedBox(height: 8)`）。
  static const tileLabelGap = 8.0;

  /// 宫格上内距（dsh-Go `fromLTRB(16, 4, 16, 0)` 的 4）。
  static const tilesTop = 4.0;

  /// 宫格与「本对话」卡片的间距（dsh-Go `SizedBox(height: 16)`）。
  static const cardGap = 16.0;

  /// 分组标题相对卡片的左缩（比卡片左缘再进 4，与设置页分区标题同观感）。
  static const cardTitlePadH = 4.0;

  /// 分组标题与卡片之间的间距。
  static const cardTitleGap = 8.0;

  /// 行标题与右侧取值之间的间距。
  static const rowGap = 12.0;

  /// 行尾 › 的边长。
  static const chevronSize = 18.0;

  /// 面板底部留白（dsh-Go `SizedBox(height: 20)`）。
  static const bottomPad = 20.0;

  /// 拖拽把手的宽 / 高 / 上边距。
  static const handleWidth = 36.0;
  static const handleHeight = 4.0;
  static const handleTop = 8.0;

  /// 把手与宫格之间的间距。
  static const handleBottom = 6.0;
}

/// 宫格两格的配色：底色是语义色淡染，图标取原色（与 dsh-Go 的
/// identity/onIdentity 一对同构，但色值全部来自本仓既有语义 token）。
extension DsPlusTileColors on DsColors {
  /// 相册格底色：品牌蓝淡染（浅 10% / 深 18%，与 `thinkGlyphBg` 同法）。
  Color get plusAlbumBg => brand.withValues(alpha: dark ? 0.18 : 0.10);

  /// 相册格图标色。
  Color get plusAlbumFg => brand;

  /// 文件格底色：正常态绿淡染，与「相册」区分开。
  Color get plusFilesBg => chatStatusOk.withValues(alpha: dark ? 0.18 : 0.12);

  /// 文件格图标色。
  Color get plusFilesFg => chatStatusOk;
}
