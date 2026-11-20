import 'package:material_ui/material_ui.dart';

/// 设计 token 单一来源（宪法 §4）。
/// 数值依据 docs/design-tokens.md（官方 Web CSS + App 真机实测）。
/// UI 代码禁止裸颜色/字号，一律经本文件。
///
/// DsSpacing/DsMotion 体量大，拆在 part 文件 design_tokens_layout.dart；
/// 引用方只 import 本文件即可（part 成员随库可见）。

part 'design_tokens_layout.dart';

/// neutral-bluish 静态色阶（官方变量原值）。
class DsPalette {
  const DsPalette._();
  static const c00 = Color(0xFFFFFFFF);
  static const c50 = Color(0xFFF9FAFB);
  static const c60 = Color(0xFFF5F6F7);
  static const c75 = Color(0xFFF1F3F5);
  static const c100 = Color(0xFFEBEEF2);
  static const c150 = Color(0xFFE9ECF2);
  static const c200 = Color(0xFFE1E5EE);
  static const c300 = Color(0xFFCFD3D6);
  static const c400 = Color(0xFFADB2B8);
  static const c500 = Color(0xFF979DA6);
  static const c600 = Color(0xFF81858C);
  static const c700 = Color(0xFF61666B);
  static const c750 = Color(0xFF43454A);
  static const c800 = Color(0xFF353638);
  static const c850 = Color(0xFF2C2C2E);
  static const c875 = Color(0xFF232324);
  static const c900 = Color(0xFF1B1B1C);
  static const c950 = Color(0xFF151517);
  static const c1000 = Color(0xFF0F1115);

  /// 品牌主色：浅 #3964fe / 暗 #5686fe（官方品牌 500/450）。
  static const brandLight = Color(0xFF3964FE);
  static const brandDark = Color(0xFF5686FE);

  /// App 端正文链接实测 #426efe（1000px 采样，design-tokens.md §1）。
  static const linkLight = Color(0xFF426EFE);

  /// App 实测 blockquote 竖线 #e5e5e5（比 Web label-caption 更浅，取 App）。
  static const quoteBarLight = Color(0xFFE5E5E5);

  /// 表格边框 App 实测 #dcdcdc ≈ border-l2 on white。
  static const tableBorderLight = Color(0xFFDCDCDC);

  /// 用户气泡实测 #edf3fe（官方品牌 50）。
  static const bubbleLight = Color(0xFFEDF3FE);

  /// 代码块暗色文字与选区（官方 Web）。
  static const codeTextDark = Color(0xFFE3EAF2);
  static const codeSelectionDark = Color(0xFF3C526D);

  /// 语法高亮 Atom One Light（App 实测）。
  static const synKeyword = Color(0xFFA626A4);
  static const synString = Color(0xFF50A14F);
  static const synFunction = Color(0xFFE45649);
  static const synNumber = Color(0xFF4078F2);
  static const synComment = Color(0xFFA0A1A7);
  static const synPlain = Color(0xFF383A42);

  // ---- 官方 App 深色实测（ref/official-dark-1.png，PIL 取色）----
  /// 深色页面底色：官方 App 实测 (15,15,15)，比 Web token 950(#151517) 更黑。
  static const appDarkBg = Color(0xFF0F0F0F);

  /// 深色输入条/未选中 chip 底：官方实测 (36,36,36)。
  static const appDarkSurface = Color(0xFF242424);

  /// 深色 chip 描边：官方实测 (71,72,73)。
  static const appDarkChipBorder = Color(0xFF474849);

  /// 深色「智能搜索」选中底 = 官方品牌 900。
  static const chipSelectedDark = Color(0xFF283142);

  /// 深色选中 chip 前景 = 官方品牌 400（实测 103,153,254）。
  static const chipSelectedFgDark = Color(0xFF679EFE);

  /// 浅色选中 chip 前景（官方实测 66,110,254）。
  static const chipSelectedFgLight = Color(0xFF426EFE);
}

/// 语义别名（亮/暗两套，官方 alias 表）。
class DsColors {
  const DsColors(this.dark);
  final bool dark;

  Color get bgBase => dark ? DsPalette.appDarkBg : DsPalette.c00;
  Color get bgLayer1 => dark ? DsPalette.c875 : DsPalette.c00;
  Color get bgLayer2 => dark ? DsPalette.c850 : DsPalette.c00;
  Color get bgOverlay => dark ? DsPalette.c750 : DsPalette.c150;

  Color get borderL1 =>
      dark ? const Color(0x0FFFFFFF) : const Color(0x0A000000); // .06 / .04
  Color get borderL2 =>
      dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000); // .12 / .10
  Color get borderL3 =>
      dark ? const Color(0x29FFFFFF) : const Color(0x1F000000); // .16 / .12

  Color get labelPrimary => dark ? DsPalette.c50 : DsPalette.c1000;
  Color get labelSecondary => dark ? DsPalette.c300 : DsPalette.c700;
  Color get labelTertiary => dark ? DsPalette.c400 : DsPalette.c600;
  Color get brand => dark ? DsPalette.brandDark : DsPalette.brandLight;

  /// 空态品牌标记主体色：官方空态鲸鱼实测 #426EFE（浅）= linkLight。
  Color get brandMark => dark ? DsPalette.brandDark : DsPalette.linkLight;
  Color get link => dark ? DsPalette.brandDark : DsPalette.linkLight;

  Color get userBubble => dark ? DsPalette.c850 : DsPalette.bubbleLight;
  Color get userBubbleText => dark ? DsPalette.c50 : DsPalette.c1000;

  // markdown 专用 alias
  Color get mdInlineCodeBg => dark ? DsPalette.c850 : DsPalette.c100;
  Color get mdCodeBlockBg => dark ? DsPalette.c900 : DsPalette.c50;
  Color get mdCodeBlockBannerBg => dark ? DsPalette.c850 : DsPalette.c50;
  Color get mdCodeBlockText =>
      dark ? DsPalette.codeTextDark : DsPalette.synPlain;

  /// banner 与代码之间的分隔线（官方实测 #ebebeb）。
  Color get mdCodeBlockDivider => dark ? DsPalette.c800 : DsPalette.c150;
  Color get mdCodeBlockSelection =>
      dark ? DsPalette.codeSelectionDark : const Color(0x33A626A4);
  Color get mdCitationBg => dark ? DsPalette.c800 : DsPalette.c100;
  Color get quoteBar => dark ? DsPalette.c600 : DsPalette.quoteBarLight;
  Color get tableBorder =>
      dark ? const Color(0x29FFFFFF) : DsPalette.tableBorderLight;
  Color get listMarker => dark ? DsPalette.c300 : DsPalette.c700;

  /// 输入条容器底色：官方浅色为纯白浮层（App 实测 255,255,255）+ 阴影，不是灰块。
  Color get inputFill => dark ? DsPalette.appDarkSurface : DsPalette.c00;

  /// 输入条容器描边（官方 chip 描边 237,237,237）。
  Color get inputBorder =>
      dark ? DsPalette.appDarkChipBorder : const Color(0xFFEDEDED);

  /// 输入条底部免责提示文字（官方浅灰）。
  Color get inputHintText => dark ? DsPalette.c600 : DsPalette.c400;

  /// chip 选中态底色（浅 品牌50 / 深 品牌900）。
  Color get chipSelectedBg =>
      dark ? DsPalette.chipSelectedDark : DsPalette.bubbleLight;

  /// chip 选中态前景（浅 #426EFE / 深 #679EFE）。
  Color get chipSelectedFg =>
      dark ? DsPalette.chipSelectedFgDark : DsPalette.chipSelectedFgLight;

  /// 品牌实心控件上的前景（白，两套主题一致）。
  Color get onBrand => DsPalette.c00;

  /// 悬浮层阴影（官方输入条柔和投影）。
  Color get shadow => const Color(0x14000000);

  /// 错误提示文字。
  Color get danger => dark ? DsPalette.c300 : const Color(0xFFD93F3F);

  /// 透明（用于显式声明无描边/无底色）。
  Color get none => const Color(0x00000000);

  /// 抽屉搜索框底色（官方浅色实测 245,245,245）。
  Color get drawerSearchFill => dark ? DsPalette.c800 : const Color(0xFFF5F5F5);

  /// 抽屉分组标题（「昨天」等，官方浅灰）。
  Color get drawerGroupLabel => dark ? DsPalette.c500 : DsPalette.c400;

  /// 抽屉遮罩：官方浅色抽屉打开时页面仍是白底（无灰幕），深色保留淡遮罩。
  Color get drawerScrim =>
      dark ? const Color(0x50000000) : const Color(0x00000000);

  // ---- 设置页（本工程自定义功能色，非官方截图实测，docs/design-tokens.md §4.4）----
  /// 设置页分区卡片底色（浅 #F9FAFB / 深 #232324）。
  Color get settingsSurface => dark ? DsPalette.c875 : DsPalette.c50;

  /// 设置页只读信息行 / 权限药丸底色（浅纯白 / 深 #2C2C2E）。
  Color get settingsField => dark ? DsPalette.c850 : DsPalette.c00;

  /// 设置页明文 HTTP 警告条底色（暖色半透明，浅/深通用）。
  Color get settingsWarnBg => const Color(0x1AF5A623);

  /// 设置页明文 HTTP 警告条文字（浅棕 / 深暖黄）。
  Color get settingsWarnFg =>
      dark ? const Color(0xFFFFC24B) : const Color(0xFF8A5A00);

  // ---- 代码工作视图 · diff 行色（官方 Web diff 配色，docs/design-tokens.md §4.9）----
  /// diff 新增行前景（浅 #50A14F / 深 #91D076）。
  Color get diffAdd =>
      dark ? const Color(0xFF91D076) : const Color(0xFF50A14F);

  /// diff 删除行前景（浅 #E45649 / 深 #CD6660）。
  Color get diffRemove =>
      dark ? const Color(0xFFCD6660) : const Color(0xFFE45649);

  /// diff 行底色：官方深色为前景 12% 透明度铺底，浅色无行底（返回透明）。
  Color get diffAddBg =>
      dark ? const Color(0xFF91D076).withValues(alpha: 0.12) : none;

  /// diff 删除行底色：同上（浅色无行底）。
  Color get diffRemoveBg =>
      dark ? const Color(0xFFCD6660).withValues(alpha: 0.12) : none;

  // ---- 会话页顶栏状态点（dsh-go 语义色，docs/design-tokens.md §4.12）----
  /// 顶栏状态点「正常」色（浅 #337250 / 深 #8BCCA6）。
  Color get chatStatusOk =>
      dark ? const Color(0xFF8BCCA6) : const Color(0xFF337250);

  /// 顶栏状态点「等待审批 / 等待回答」色（浅 #936123 / 深 #E6BD7C）。
  Color get chatStatusWarn =>
      dark ? const Color(0xFFE6BD7C) : const Color(0xFF936123);

  // ---- 思考行（docs/design-tokens.md §4.13）----
  /// 思考行图形列的底色：品牌色淡染（浅 10% / 深 18%）。
  Color get thinkGlyphBg =>
      brand.withValues(alpha: dark ? 0.18 : 0.10);
}

/// 字号（官方 token，sp；行高随 dp 换算）。
class DsTypography {
  const DsTypography._();
  static const h1 = TextStyle(
    fontSize: 24,
    height: 34 / 24,
    fontWeight: FontWeight.w700,
  );
  static const h2 = TextStyle(
    fontSize: 22,
    height: 32 / 22,
    fontWeight: FontWeight.w700,
  );
  static const h3 = TextStyle(
    fontSize: 20,
    height: 30 / 20,
    fontWeight: FontWeight.w700,
  );
  static const h4 = TextStyle(
    fontSize: 16,
    height: 28 / 16,
    fontWeight: FontWeight.w600,
  );
  static const base = TextStyle(fontSize: 16, height: 28 / 16);
  static const baseStrong = TextStyle(
    fontSize: 16,
    height: 28 / 16,
    fontWeight: FontWeight.w600,
  );
  static const table = TextStyle(fontSize: 15, height: 25 / 15);
  static const tableHead = TextStyle(
    fontSize: 15,
    height: 25 / 15,
    fontWeight: FontWeight.w500,
  );
  static const small = TextStyle(fontSize: 14, height: 24 / 14);
  static const smallStrong = TextStyle(
    fontSize: 14,
    height: 24 / 14,
    fontWeight: FontWeight.w600,
  );
  static const inlineCode = TextStyle(fontSize: 14, height: 22 / 14);
  static const codeBlock = TextStyle(fontSize: 13, height: 22 / 13);

  /// 代码块 banner 的语言名 / 复制文字（官方 13px 灰）。
  static const codeBlockLabel = TextStyle(fontSize: 13, height: 20 / 13);
  static const inputPlaceholder = TextStyle(fontSize: 16);
  static const pageTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontSize: 12);

  /// chip 文字：官方「深度思考」四字占 49dp → 约 12.5sp。
  static const chipLabel = TextStyle(fontSize: 12.5, height: 16 / 12.5);
  static const greeting = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  static const citation = TextStyle(fontSize: 9, height: 14 / 9);

  /// 等宽字体族（官方 --ds-font-family-code 的 Android/iOS 兜底序）。
  static const codeFamily = 'monospace';
}
