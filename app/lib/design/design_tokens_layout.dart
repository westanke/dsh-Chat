part of 'tokens.dart';

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

  /// 用户气泡 maxWidth = 可见内容区宽 × 0.864（官方基准 279dp ÷ 内容区
  /// 323dp；360dp 屏 ≈ 279dp 与官方一致，宽屏/平板分栏随可见宽度自适应，
  /// 不再固定 280dp——issue #1 会话气泡宽度反馈）。
  static const userBubbleMaxFraction = 0.864;

  /// HITL 挂起卡面板（提问/审批）最大高度占屏比；超出面板内滚动。
  /// （无官方基准，App 自定；2026-11-15 用户反馈提交按钮被推出屏幕。）
  static const hitlPanelMaxFraction = 0.5;
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

  /// 待发送图片 chip 的宽度上限（真机反馈 2026-11-17）。
  /// 输入条内容宽 = 360dp 屏 - 2×screenPad(22) - 2×composerPadH(10) = 296dp；
  /// 同一行还有权限 chip(≈80)、加图/文件夹两钮(48)、按钮间距(17)、发送钮(24)，
  /// 合计约 169dp，余 127dp；文件名 chip 封顶 128dp 保证右侧按钮永远不被挤出。
  /// Android 侧原先没有上限（长文件名会把 Spacer 与发送钮顶出 Row ⇒ 发不出去）。
  static const composerImageChipMaxWidth = 128.0;

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

  // ---- task-5 对齐官方 Web 轮尾/思考行/工具行细节（官方 css 实测值）----
  /// 轮尾行高（TurnProcessNodeView height calc(33px+delta)）。
  static const turnRowHeight = 33.0;

  /// 轮尾行底部内边距（padding 0 0 8px）。
  static const turnRowPadBottom = 8.0;

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
  /// 正文最大阅读宽度：宽屏（平板 / 横屏）时正文居中，两侧留白。
  /// 与官方 Web 的 `--dsh-chat-content-width: 748px` 同档。
  static const chatReadingWidth = 720.0;

  /// 浮在阅读列上的控件（输入条、待办条）离阅读列两边的距离：
  /// 和手机上离屏幕两边一样 22，所以比正文两边各宽 4。
  static const chatFloatInset = 14.0;

  /// 浮层控件的最大宽度 = 阅读列减两边 [chatFloatInset]。
  static const chatFloatingWidth = chatReadingWidth - 2 * chatFloatInset;

  /// 列表视口伸到输入条上沿以下的距离：底色在那里已经是实心，看不见裁切。
  static const chatListOverlap = 6.0;

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
