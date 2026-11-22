part of 'tokens.dart';

/// 间距（App 实测 dp + Web 布局规则）。
class DsSpacing {
  const DsSpacing._();
  static const screenPad = 12.0; // 页面左右基础边距（dsh-go AppSpace.floatInset = 12）
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
  static const bubbleRadius = 20.0;

  /// 用户气泡 maxWidth = 可见内容区宽 × 0.864（官方基准 279dp ÷ 内容区
  /// 323dp；360dp 屏 ≈ 279dp 与官方一致，宽屏/平板分栏随可见宽度自适应，
  /// 不再固定 280dp——issue #1 会话气泡宽度反馈）。
  static const userBubbleMaxFraction = 0.82;

  /// HITL 挂起卡面板（提问/审批）最大高度占屏比；超出面板内滚动。
  /// （无官方基准，App 自定；2026-11-15 用户反馈提交按钮被推出屏幕。）
  static const hitlPanelMaxFraction = 0.5;
  /// 顶栏条高度（不含状态栏安全区）。dsh-go `chat_header.dart:89`
  /// `barHeight = 56.0`——2026-11-22 按用户要求逐项对齐源码尺寸，原本 44。
  static const topBarHeight = 56.0;
  static const thinkHMargin = 12.0; // 思考流内 h* margin

  // 助手消息底部操作条（官方实测：图标 30px/3.0 ≈ 10dp 视觉，间距 20dp）
  static const actionIconSize = 17.0;
  static const actionIconGap = 8.0;
  static const codeBlockRadius = 8.0; // 代码块圆角（App 实测）
  static const codeBlockPad = 12.0; // 代码块内边距
  static const codeBlockPadH = 15.0; // 官方代码首墨 x112px≈15.3dp
  static const codeBlockPadV = 10.0; // 代码上下内边距
  static const codeBlockBannerPadV = 8.0; // banner 上下内边距

  // 工具调用过程组（折叠一行；官方是 14sp 灰字 + 小图标，行高紧凑）
  static const processRowHeight = 32.0;
  static const processIconSize = 15.0;
  static const processIconGap = 6.0;

  /// 工具行左侧的色块图标（dsh-go 会话流：圆角方块底 + 描线图标）。
  static const toolGlyphSize = 24.0;
  static const toolGlyphRadius = 7.68;
  static const toolGlyphIconSize = 14.4;
  static const processIndent = 2.0;

  // ── 过程行骨架（dsh-go StreamRow，2026-11-22 完整复刻）──
  /// 图形列宽：工具图标 / 思考图形都居中在这一格。
  static const streamLead = 24.0;
  /// 图形列 → 文字列间距。
  static const streamGap = 8.0;
  /// 文字列起点 = lead + gap，展开体也从这里起。
  static const streamIndent = 32.0;
  /// 单行最小高：24 图形 + 上下各 4。
  static const streamMinHeight = 32.0;
  /// 点按高亮向两侧溢出的宽度。
  static const streamBleed = 8.0;

  // ---- 输入条（官方 ref/md-shot-2-lists.png 像素实测）----
  /// 容器左右外边距：容器左缘 x36px≈12dp。
  static const composerMargin = 12.0;

  /// 容器圆角。dsh-go `composer.dart:651` 收起态用 `AppShape.radiusXl = 28`
  /// （多行展开时 lerp 到 `AppShape.lg = 20`），2026-11-22 对齐为 28（原 26）。
  static const composerRadius = 28.0;

  /// 多行展开时的容器圆角（dsh-go `composer.dart:646` `_opened = AppShape.lg`）。
  static const composerRadiusOpen = 20.0;

  /// 输入条两侧圆键（+ / 发送）尺寸，dsh-go `composer.dart:174` `_keySize = 36`。
  static const composerKeySize = 36.0;

  /// 键与容器边缘/键之间的间隙，dsh-go `composer.dart:175` `_keyGap = 6`。
  static const composerKeyGap = 6.0;

  /// 输入文字字号，dsh-go `composer.dart:178` `_fontSize = 15.0`。
  static const composerFontSize = 15.0;

  /// 输入文字行高倍数，dsh-go `composer.dart:28` `_lineHeight = 1.45`。
  static const composerLineHeight = 1.45;

  /// 输入条容器左右内边距（官方 chip 行左缘 x66px=22dp，减容器左缘 12dp = 10dp）。
  static const composerPadH = 10.0;

  /// 占位文字相对 chip 行再内缩的量（官方占位首墨 x82px=27.3dp − chip 22dp ≈ 5dp）。
  static const composerTextInset = 8.0;

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
  static const composerButtonGap = 6.0;

  /// 待发送图片 chip 的宽度上限（真机反馈 2026-11-17）。
  /// 输入条内容宽 = 360dp 屏 - 2×screenPad(22) - 2×composerPadH(10) = 296dp；
  /// 同一行还有权限 chip(≈80)、加图/文件夹两钮(48)、按钮间距(17)、发送钮(24)，
  /// 合计约 169dp，余 127dp；文件名 chip 封顶 128dp 保证右侧按钮永远不被挤出。
  /// Android 侧原先没有上限（长文件名会把 Spacer 与发送钮顶出 Row ⇒ 发不出去）。
  static const composerImageChipMaxWidth = 128.0;

  /// 输入条上的模型 chip 最大宽度（dsh-go 输入条那枚 `V4.1 Flash` 胶囊）。
  /// 手机 360dp 宽度下，权限 chip + 模型 chip + 两个圆钮 + 环形 + 发送键刚好挤满，
  /// 所以这里卡 96——长模型名截断，绝不把右侧按钮顶出屏幕。
  static const composerModelChipMaxWidth = 140.0;

  // ---- 顶栏标题胶囊（2026-11-22 对齐 dsh-go chat_header）----
  /// 胶囊高（两行：会话名 + 状态行）。
  static const topBarCapsuleHeight = 44.0;

  /// 胶囊圆角（全胶囊）。
  static const topBarCapsuleRadius = 22.0;

  /// 顶栏「新对话」方形钮边长与圆角。
  static const topBarNewChatSize = 34.0;
  static const topBarNewChatRadius = 10.0;

  /// 输入条底部免责提示与容器间距。
  static const composerHintGap = 10.0;

  // ---- 抽屉工具条 / 筛选胶囊（2026-11-22 对齐 dsh-go sessions_drawer + drawer_filter_bar）----
  /// 工具条高度（品牌标 + 两个圆钮 + 「新对话」胶囊一行）。
  static const drawerToolbarHeight = 56.0;

  /// 工具条左右内距（与搜索框左边 15 对齐）。
  static const drawerToolbarPadH = 15.0;

  /// 品牌标与圆钮 / 圆钮之间的间距。
  static const drawerToolbarGap = 8.0;

  /// 圆钮直径（dsh-go DrawerViewButton.size = 36）。
  static const drawerRoundButtonSize = 36.0;

  /// 「新对话」胶囊高 / 左右内距 / 图标与文字间距。
  static const drawerNewChatHeight = 36.0;
  static const drawerNewChatPadH = 14.0;
  static const drawerNewChatIconGap = 6.0;

  /// 筛选胶囊行内距（dsh-go `fromLTRB(10, 2, 10, 4)`）。
  static const drawerFilterPadH = 10.0;
  static const drawerFilterPadTop = 2.0;
  static const drawerFilterPadBottom = 4.0;

  /// 胶囊高度 / 左右内距 / 胶囊间距（dsh-go gap = 8）。
  static const drawerFilterChipHeight = 30.0;
  static const drawerFilterChipPadH = 14.0;
  static const drawerFilterGap = 8.0;

  /// 「全部对话」那一行高（文字 + 下拉箭头 + 右侧「…」）。
  static const drawerScopeRowHeight = 40.0;

  /// 会话行尾状态点直径（dsh-go SessionTile.dot = 7）。
  static const drawerStatusDot = 7.0;

  // ---- 侧边抽屉（官方 ref/official-drawer.png 实测，1080px/3=dp）----
  /// 抽屉宽度：右缘 x864px ≈ 288dp（屏宽 360dp 的 80%）。
  static const drawerWidth = 288.0;

  /// 推挤式抽屉：菜单按钮点击热区宽（从左缘滑入可拖出抽屉）。
  static const drawerEdgeDragWidth = 20.0;

  /// 屏内右滑呼出抽屉（问题 3）：水平位移达到这个值就开（逻辑像素）。
  static const drawerSwipeOpenDistance = 64.0;

  /// 屏内右滑的轻扫通道：位移至少先超过这个值，速度才作数，
  /// 防止竖向滚动时手指的轻微横向抖动误开抽屉。
  static const drawerSwipeMinTravel = 24.0;

  /// 轻扫通道的速度阈值（逻辑像素/秒）。
  static const drawerSwipeOpenVelocity = 700.0;

  /// 推挤式抽屉：聊天页被推出的位移 = `drawerWidth`（整页滑到屏外，
  /// 右缘与抽屉右缘对齐，官方 official-drawer.png 页面残条为空对齐）。
  ///
  /// 只在紧凑窗（手机）用得到：正常按 `DsWindowClass.pageInsetFor(窗口宽)`
  /// 取抽屉宽 —— 让路的距离必须跟着抽屉宽度走，否则平板横屏让 288 会在右侧
  /// 多出 32dp 的错位（docs §4.15）。
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

  /// 工作区小节标题行距（真机反馈 2026-11-16：时间优先分组后，桶内按
  /// 工作区聚簇、小节标题「左 20 / 上 8 / 下 2」；左距复用 drawerItemPadH）。
  static const drawerSectionPadTop = 8.0;
  static const drawerSectionPadBottom = 2.0;

  /// 会话条目左距：x65px ≈ 22dp。
  static const drawerItemPadH = 20.0;

  /// 会话条目上下内边距（行高约 96px ≈ 32dp）。
  static const drawerItemPadV = 12.0;

  /// 抽屉内文字行高（官方会话条目墨高 33px，行高约 24dp）。
  static const drawerLineHeight = 24.0;

  /// 内容命中条目的标题与片段之间的间距（docs/design-tokens.md §4.14）。
  /// 比条目上下内边距小一档：片段是标题的注脚，不该把行撑成两段等重内容。
  static const drawerItemSubtitleGap = 2.0;

  /// 底部账号栏左右内边距：头像 x44px ≈ 14.7dp（官方 1080 实测）。
  static const drawerFooterPadH = 15.0;

  /// 底部头像直径：官方 88px ≈ 29.3dp。
  static const drawerAvatarSize = 29.0;

  /// 头像到文字间距：官方头像右 43.7dp → 手机号左 54dp。
  static const drawerAvatarGap = 10.0;

  // ---- 设置页（本工程自定义布局，docs/design-tokens.md §4.4）----
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

  /// 斜杠面板的行基准高（dsh-go `_rowHeight`=56，仅用于算面板最大高度）。
  static const paletteRowHeight = 56.0;

  // ---- 斜杠命令面板（全部对齐 dsh-go slash_palette.dart，docs §4.7）----
  /// 面板容器圆角（dsh-go `AppShape.xl`=28，与输入条同一圆角）。
  static const paletteRadius = 28.0;

  /// 面板最大高度（dsh-go `_rowHeight * _maxRows` = 56 × 5.5 = 308）。
  static const paletteMaxHeight = 308.0;

  /// 行左右内缩（dsh-go `rowInset`=6：行高亮块比容器窄 6，与容器圆角同心）。
  static const paletteRowInset = 6.0;

  /// 行圆角（dsh-go `radius - rowInset` = 28 - 6 = 22）。
  static const paletteRowRadius = 22.0;

  /// 行最小高度（dsh-go `_CommandTile` minHeight=52）。
  static const paletteRowMinHeight = 52.0;

  /// 行左右内边距（dsh-go L2 / R12）与上下内边距（8）。
  static const paletteRowPadLeft = 2.0;
  static const paletteRowPadRight = 12.0;
  static const paletteRowPadV = 8.0;

  /// 行首图标槽宽 / 图标边长（dsh-go 32 / 20，图标中心与输入条 ＋ 键对齐）。
  static const paletteIconSlot = 32.0;
  static const paletteIconSize = 20.0;

  /// 图标槽与文字的间距（dsh-go 10）。
  static const paletteIconGap = 10.0;

  /// 尾部回车符号边长（dsh-go 16）与其左内距（8）。
  static const paletteEnterSize = 16.0;
  static const paletteEnterGap = 8.0;

  /// 空态行内边距（dsh-go fromLTRB(14, 14, 18, 14)）。
  static const paletteEmptyPadTop = 14.0;
  static const paletteEmptyPadLeft = 14.0;
  static const paletteEmptyPadRight = 18.0;

  /// 行内图标与文字间距、药丸间距。
  static const settingsIconGap = 14.0;
  static const settingsChipGap = 7.0;
  static const settingsChipPadH = 10.0;
  static const settingsChipPadV = 6.0;
  static const settingsChipRadius = 16.0;

  // ---- 跳转最新 FAB（本工程自定义，docs/design-tokens.md §4.6）----
  /// 圆形按钮直径（仿 companion ChatDetail.kt:697 size 48.dp）。
  static const fabSize = 44.0;

  /// FAB 到右下角的间距（仿 companion padding 16.dp）。
  static const fabMargin = 12.0;

  /// FAB 内箭头图标尺寸。
  static const fabIconSize = 20.0;

  // ---- 输入条上方的「当前活动」条（dsh-go activity_strip） ----
  /// 条子圆角（胶囊）。
  static const activityStripRadius = 18.0;
  /// 会话面板顶部 TAB 胶囊的固定宽度：等宽才能让选中项稳稳定在正中。
  static const tabChipWidth = 78.0;

  /// TAB 胶囊之间的间距（与居中偏移计算共用）。
  static const tabChipGap = 8.0;

  /// 条子左右内衬。
  static const activityStripPadH = 12.0;

  /// 条子上下内衬。
  static const activityStripPadV = 7.0;

  /// 条子与输入条之间的竖直间距。
  static const activityStripGap = 6.0;

  /// 图形与文字之间的间距。
  static const activityStripIconGap = 8.0;

  /// 图形尺寸。
  static const menuIconSize = 18.0;

  // ---- 空态建议卡与技巧行（dsh-go empty_actions） ----
  /// 卡片圆角。
  static const suggestionRadius = 20.0;

  /// 卡片内衬。
  static const suggestionPad = 14.0;

  /// 卡片最小高（dsh-go minCell 150 宽、纵向由内容撑）。
  static const suggestionMinHeight = 104.0;

  /// 卡片间距（横向与纵向同值）。
  static const suggestionRowGap = 8.0;

  /// 图标方块边长。
  static const suggestionBadge = 34.0;

  /// 图标本体尺寸。
  static const suggestionGlyph = 18.0;

  /// 图标块与标题之间的间距。
  static const suggestionTitleGap = 8.0;

  /// 建议卡区与工作目录 chip 之间的间距（dsh-go suggestionsGap 28）。
  static const suggestionsGap = 28.0;

  /// 建议卡区的最大宽度，桌面宽窗下两列不被拉长。
  static const suggestionsMaxWidth = 420.0;

  /// 建议卡与技巧行之间的间距（dsh-go tipGap 6）。
  static const emptyTipGap = 6.0;

  // ---- task-5 对齐官方 Web 轮尾/思考行/工具行细节（官方 css 实测值）----
  /// 轮尾行高（TurnProcessNodeView height calc(33px+delta)）。
  static const turnRowHeight = 36.0;

  /// 轮尾行底部内边距（padding 0 0 8px）。
  static const turnRowPadBottom = 0.0;

  /// 思考折叠行高（ReasoningRow :not([data-expanded]) height 24px）。
  static const thinkRowHeight = 24.0;

  /// 工具行/思考行标题与摘要之间的分隔点（2×2px 圆点）。
  static const sepDot = 2.0;

  /// 分隔点两侧留白（margin 0 8px）。
  static const sepGap = 8.0;

  /// exit 徽标圆点直径（ExitCodeBadge dot 4px）。
  static const exitBadgeDot = 4.0;

  /// exit 徽标点与文字间距（badge gap 5px）。
  static const exitBadgeGap = 5.0;

  /// exit 徽标与摘要的左距（badge margin-left 8px）。
  static const exitBadgeGapLeft = 8.0;

  /// diff 统计与摘要的左距（diffStat margin-left 10px）。
  static const diffStatGap = 10.0;

  /// io 卡四向外边距（margin 4px 0 4px 4px）。
  static const ioCardGap = 4.0;

  /// io 卡内输入/输出两段的最大高度（ioSection max-height 150px）。
  static const ioSectionMaxHeight = 150.0;

  /// io 卡标签列与正文列间距（column-gap 14px）。
  static const ioColumnGap = 14.0;

  /// ioCard 分段内边距（官方 .ioSection{padding:12px 16px}）。
  static const ioSectionPadV = 12.0;
  static const ioSectionPadH = 16.0;

  /// 命令卡输出最大高度（terminalBody --dsl-terminal-output-max-height）。
  static const terminalMaxHeight = 224.0;

  /// 展开详情整体滚动最大高度（bodyScroll max-height 260px）。
  static const bodyScrollMaxHeight = 260.0;

  // ---- 会话页外壳（整页移植自 dsh-go 的分槽外壳，docs/design-tokens.md §4.12）----
  /// 正文列基准宽度：屏宽不超过它时正文用满，超过后从这里按 [readableScale]
  /// 缓增。**这是起点，不是上限**（用户 2026-11-21：整个 App 不再限制 720 宽）。
  /// 数值与官方 Web 的 `--dsh-chat-content-width: 748px` 同档。
  static const readableBaseWidth = 720.0;

  /// 宽窗下正文列随屏宽缩放的斜率：屏宽每多 1dp，列宽多 0.9dp。
  /// 用户口径「按可读屏宽缩放少量」；不是「最多占 90%」的硬规则。
  static const readableScale = 0.9;

  /// 浮在阅读列上的控件（顶栏、输入条、待办条）离阅读列两边的距离：
  /// 和手机上离屏幕两边一样 22，所以比正文两边各宽 4。
  static const chatFloatInset = 14.0;

  /// 列表视口伸到输入条上沿以下的距离：底色在那里已经是实心，看不见裁切。
  static const chatListOverlap = 6.0;

  /// 正文与顶栏之间的呼吸位。顶栏胶囊是不透明容器，正文紧贴会让第一行
  /// 像被胶囊压住（2026-11-22 真机反馈「思考的位置被挡住」）。
  static const chatBodyTopGap = 8.0;

  /// 列表顶部留白（顶栏之下）。
  static const chatListTopGap = 8.0;

  // ---- 会话页行距阶梯（docs/design-tokens.md §4.12）----
  /// 换轮（上一轮回答 → 下一条用户消息）的竖向间距。
  static const chatGapNewTurn = 24.0;

  /// 同一轮内部（工具行 ↔ 正文）的竖向间距。
  static const chatGapSameTurn = 8.0;

  /// 相邻过程行之间没有间距（它们是一组）。
  static const chatGapProcess = 0.0;

  /// 卡片（改动卡 / 产物卡 / 审批卡）与上下内容的间距。
  static const chatGapCard = 12.0;

  /// 脚注行与上方内容的间距。
  static const chatGapFootnote = 4.0;

  // ---- 会话页外壳细部（docs/design-tokens.md §4.12）----
  /// 底部渐隐带的羽化高度：正文滑到输入条后面时淡出而不是被裁一刀。
  static const chatVeilFeather = 14.0;

  /// 输入条底部的安全区余量（键盘弹起时贴着键盘上沿）。
  static const chatComposerBottomPad = 8.0;

  /// 顶栏状态点直径。
  static const chatStatusDot = 6.0;

  /// 状态点与状态文字之间的间距。
  static const chatStatusDotGap = 5.0;

  /// 顶栏状态行高（标题下方那一行）。
  static const chatStatusRowHeight = 20.0;

  // ---- 宽窗适配（docs/design-tokens.md §4.15）----
  /// 中等窗起点：宽 ≥ 此值（且高度不是紧凑）算平板/折叠屏展开态。
  static const windowMediumMin = 600.0;

  /// 扩展窗起点：宽 ≥ 此值时抽屉宽用 [drawerSidebarWidth]（M3 expanded 断点）。
  static const windowExpandedMin = 840.0;

  /// 紧凑窗高度上限：矮于此值一律算紧凑（手机横屏 412 高因此仍是紧凑类，
  /// 分栏后每列只剩一条缝，不如一根居中的列）。
  static const windowCompactHeight = 480.0;

  /// 平板/折叠屏的抽屉宽度：比手机（[drawerWidth] 288）宽一档，
  /// 会话标题能多显示几个字（dsh-go AdaptiveMetrics.sidebarWidth = 320）。
  /// 注意**不是常驻侧栏宽**：三种窗口都是抽屉式（docs §4.15）。
  static const drawerSidebarWidth = 320.0;

  // ---- 思考行（docs/design-tokens.md §4.13）----
  /// 图形列宽度：原子图标 / 呼吸光点环待在这列里。
  static const thinkLeadWidth = 24.0;

  /// 图形列与文字列之间的间距。
  static const thinkColumnGap = 8.0;

  /// 展开正文的左缩进（图形列 + 间距）。
  static const thinkBodyIndent = 32.0;

  /// 展开正文上下的留白。
  static const thinkBodyPadTop = 4.0;
  static const thinkBodyPadBottom = 8.0;

  /// 展开内容左侧细线的宽度。
  static const thinkRailWidth = 1.0;

  /// 实时窗口的行数（流式思考固定露出几行）。
  static const thinkTickerRows = 3;

  /// 静止态原子图标的直径。
  static const thinkGlyphSize = 15.0;

  /// 呼吸光点环的直径。
  static const thinkOrbSize = 18.0;
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

  /// 过程组标题稳定窗口（官方 useStableLiveProcessTitle
  /// PROCESS_TITLE_MINIMUM_MS=150：标题保持展示至少 150ms 再提交变更）。
  static const Duration processTitleMinimum = Duration(milliseconds: 150);

  /// 标题/摘要 shimmer 呼吸周期（官方 TextShimmer 循环 ~0.9s）。
  static const Duration shimmerCycle = Duration(milliseconds: 900);

  /// 列表行入场淡入时长（新行落地时淡入，避免整块闪出）。
  static const Duration rowFadeIn = Duration(milliseconds: 160);

  /// 视口尺寸变化后校正滚动位置的最长单帧修正量（居中锚定）。
  static const double viewportCorrectionLimit = 240.0;

  /// 顶栏状态点呼吸周期（busy 态淡入淡出）。
  static const Duration statusPulse = Duration(milliseconds: 1200);

  /// 实时窗口上移一行的时长（匀速）。
  static const Duration thinkingTicker = Duration(milliseconds: 160);

  /// 思考标签扫光一次的长度。
  static const Duration thinkingSweep = Duration(milliseconds: 1000);

  /// 思考标签两次扫光之间的间隔。
  static const Duration thinkingSweepPeriod = Duration(milliseconds: 4000);

  /// 思考标签开始扫光前的延迟（开始思考后先静一会儿）。
  static const Duration thinkingSweepLead = Duration(milliseconds: 600);

  /// 呼吸光点环的周期。
  static const Duration thinkingBreath = Duration(milliseconds: 2400);
}
