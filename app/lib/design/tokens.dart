import 'package:flutter/material.dart';

/// 设计 token 单一来源（宪法 §4）。
/// 数值依据 docs/design-tokens.md（官方 Web CSS + App 真机实测）。
/// UI 代码禁止裸颜色/字号，一律经本文件。

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

/// 间距（App 实测 dp + Web 布局规则）。
class DsSpacing {
  const DsSpacing._();
  static const screenPad = 22.0; // 页面左右基础边距（官方 MD 内容左起 22.7dp）
  static const contentPadRight = 15.0; // 官方用户气泡右缘距屏右 15dp（比左边距小 7dp）
  static const msgPad = 30.0; // MD 内容 x30dp（App 实测）
  static const hMargin = 32.0; // md h1-h3 margin-top
  static const hMarginBottom = 16.0; // md h1-h3 margin-bottom
  static const blockGap = 16.0; // pre/code-block/表格 上下 16
  static const liGap = 6.0; // li:not(:first-child) margin-top
  static const nestedListGap = 4.0; // li>ul/ol margin-top
  static const quotePadLeft = 14.0; // blockquote padding-left
  static const quoteBarWidth = 2.0; // blockquote 左线（App 实测）
  static const cellPadV = 10.0; // 表格 cell padding
  static const cellPadH = 16.0;
  static const cellMinWidth = 100.0;
  static const inlineCodeRadius = 6.0;
  static const inlineCodePadH = 5.0;
  static const bubbleRadius = 16.0;
  static const topBarHeight = 44.0;
  static const thinkHMargin = 12.0; // 思考流内 h* margin

  // 助手消息底部操作条（官方实测：图标 30px/3.0 ≈ 10dp 视觉，间距 20dp）
  static const actionIconSize = 17.0;
  static const actionIconGap = 20.0;
  static const codeBlockRadius = 8.0; // 代码块圆角（App 实测）
  static const codeBlockPad = 12.0; // 代码块内边距
  static const codeBlockPadH = 15.0; // 官方代码首墨 x112px≈15.3dp
  static const codeBlockPadV = 10.0; // 代码上下内边距
  static const codeBlockBannerPadV = 8.0; // banner 上下内边距

  // 工具调用过程组（折叠一行；官方是 14sp 灰字 + 小图标，行高紧凑）
  static const processRowHeight = 28.0;
  static const processIconSize = 15.0;
  static const processIconGap = 6.0;
  static const processIndent = 2.0;

  // ---- 输入条（官方 ref/md-shot-2-lists.png 像素实测）----
  /// 容器左右外边距：容器左缘 x36px≈12dp。
  static const composerMargin = 12.0;

  /// 容器圆角：官方胶囊化大圆角（高约 207px≈69dp，圆角约 26dp）。
  static const composerRadius = 26.0;

  /// 输入条容器左右内边距（官方 chip 行左缘 x66px=22dp，减容器左缘 12dp = 10dp）。
  static const composerPadH = 10.0;

  /// 占位文字相对 chip 行再内缩的量（官方占位首墨 x82px=27.3dp − chip 22dp ≈ 5dp）。
  static const composerTextInset = 5.0;

  /// 输入框顶部内边距：容器顶 y2088 → 占位文字基线区约 24dp。
  static const composerPadTop = 10.0;

  /// chip 高度：y2207..2295 = 88px ≈ 29dp。
  static const chipHeight = 29.0;

  /// chip 内图标尺寸（官方实测 13.3dp）。
  static const chipIconSize = 14.0;

  /// chip 内图标到文字间距（官方 (156-140)/3 ≈ 5.3dp）。
  static const chipIconGap = 4.0;

  /// chip 圆角（全圆角胶囊）。
  static const chipRadius = 15.0;

  /// chip 左右内边距：chip 左缘 x66 → 图标首墨 x102 ≈ 12dp。
  static const chipPadH = 8.0;

  /// chip 之间间距：深度思考 chip 右缘 x304 → 智能搜索左缘 x361 ≈ 19dp。
  static const chipGap = 19.0;

  /// 加号/语音圆按钮直径：x810..878 = 68px ≈ 23dp 图标 + 内边距。
  static const composerButtonSize = 24.0;

  /// 两个圆按钮中心间距（官方 (931-878)/3 ≈ 17.7dp → 按钮间空隙约 10dp）。
  static const composerButtonGap = 17.0;

  /// 输入条底部免责提示与容器间距。
  static const composerHintGap = 10.0;

  // ---- 侧边抽屉（官方 ref/official-drawer.png 实测，1080px/3=dp）----
  /// 抽屉宽度：右缘 x864px ≈ 288dp（屏宽 360dp 的 80%）。
  static const drawerWidth = 288.0;

  /// 推挤式抽屉：菜单按钮点击热区宽（从左缘滑入可拖出抽屉）。
  static const drawerEdgeDragWidth = 20.0;

  /// 推挤式抽屉：聊天页被推出的位移 = `drawerWidth`（整页滑到屏外，
  /// 右缘与抽屉右缘对齐，官方 official-drawer.png 页面残条为空对齐）。
  static const drawerPageShift = drawerWidth;

  /// 搜索框高度：y117..248 = 132px ≈ 44dp。
  static const drawerSearchHeight = 44.0;

  /// 搜索框左距：x45px = 15dp；宽 269dp。
  static const drawerSearchPadH = 15.0;

  /// 搜索框右距：官方 x852 → 抽屉右缘 864，仅 4dp（左侧 15dp，故意不对称）。
  static const drawerSearchPadRight = 4.0;

  /// 搜索框顶距：官方 y117px = 39dp（已扣状态栏，SafeArea 内约 11dp）。
  static const drawerSearchPadTop = 11.0;

  /// 搜索框圆角（全胶囊）。
  static const drawerSearchRadius = 22.0;

  /// 搜索框内图标到文字间距（官方图标右缘 43.7dp → 文字首墨 52dp）。
  static const drawerSearchIconGap = 6.0;

  /// 搜索框内容左内边距（官方框左缘 15dp、图标墨起 28dp → 13dp，扣图标内缩取 11）。
  static const drawerSearchInset = 11.0;

  /// 分组标题左距：x64px ≈ 21dp。
  static const drawerGroupPadH = 21.0;

  /// 空态品牌标记尺寸（官方 116x88px / 3.0）。
  static const brandMarkWidth = 40.0;
  static const brandMarkHeight = 31.5;

  /// 空态标记与问候语的垂直间隔（官方 66px / 3.0）。
  static const brandMarkGap = 22.0;

  /// 分组标题行上下内边距。
  static const drawerGroupPadV = 15.0;

  /// 分组标题与首个条目间距。
  static const drawerGroupGap = 0.0;

  /// 会话条目左距：x65px ≈ 22dp。
  static const drawerItemPadH = 20.0;

  /// 会话条目上下内边距（行高约 96px ≈ 32dp）。
  static const drawerItemPadV = 12.0;

  /// 抽屉内文字行高（官方会话条目墨高 33px，行高约 24dp）。
  static const drawerLineHeight = 24.0;

  /// 底部账号栏左右内边距：头像 x44px ≈ 14.7dp（官方 1080 实测）。
  static const drawerFooterPadH = 15.0;

  /// 底部头像直径：官方 88px ≈ 29.3dp。
  static const drawerAvatarSize = 29.0;

  /// 头像到文字间距：官方头像右 43.7dp → 手机号左 54dp。
  static const drawerAvatarGap = 10.0;

  // ---- 设置页（本工程自定义布局，docs/design-tokens.md §4.4）----
  /// 设置页内容最大宽度（仿 companion SettingsScreen widthIn(max=720.dp)）。
  static const settingsMaxWidth = 720.0;

  /// 设置页根左右 / 上下外边距（仿 companion padding(h20, v28)）。
  static const settingsPadH = 20.0;
  static const settingsPadV = 28.0;

  /// 分区标题与内容/分区之间的垂直间距。
  static const settingsSectionGap = 22.0;

  /// 分区卡片圆角 / 内边距。
  static const settingsCardRadius = 14.0;
  static const settingsCardPadH = 16.0;
  static const settingsCardPadV = 6.0;

  /// 行内最小高度（仿官方 56dp 触控行）。
  static const settingsRowMinHeight = 52.0;

  /// 行内图标与文字间距、药丸间距。
  static const settingsIconGap = 14.0;
  static const settingsChipGap = 7.0;
  static const settingsChipPadH = 10.0;
  static const settingsChipPadV = 6.0;
  static const settingsChipRadius = 16.0;

  // ---- 跳转最新 FAB（本工程自定义，docs/design-tokens.md §4.6）----
  /// 圆形按钮直径（仿 companion ChatDetail.kt:697 size 48.dp）。
  static const fabSize = 48.0;

  /// FAB 到右下角的间距（仿 companion padding 16.dp）。
  static const fabMargin = 16.0;

  /// FAB 内箭头图标尺寸。
  static const fabIconSize = 24.0;
}

/// 聊天页滚动相关动效（本工程自定义，docs/design-tokens.md §4.6）。
class DsMotion {
  const DsMotion._();

  /// 跳转最新 FAB 渐显 / 渐隐时长（仿 companion ChatDetail.kt:696 tween(140)）。
  static const Duration fabFade = Duration(milliseconds: 140);

  /// 推挤式抽屉滑入/滑出时长（官方体感 ~250ms，easeOutCubic）。
  static const Duration drawerShift = Duration(milliseconds: 250);

  /// FAB 目标不透明度（仿 companion ChatDetail.kt:693 0.88f）。
  static const double fabOpacity = 0.88;

  /// 滚动停止后多久解除冻结快照（仿 companion ChatScrollFreeze.kt delay(80)）。
  static const Duration freezeSettle = Duration(milliseconds: 80);

  /// 非流式自动贴底滚动时长（点击 FAB / 新消息落地）。
  static const Duration scrollSettle = Duration(milliseconds: 140);
}
