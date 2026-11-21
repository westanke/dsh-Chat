/**
 * 设计 token —— app/lib/design/tokens.dart 的鸿蒙对应翻译。
 * 数值依据 docs/design-tokens.md（官方 Web CSS + App 真机实测）——改样式先改
 * token 文档，再改本文件，再改 UI（宪法 §4）；UI 代码禁止裸颜色/裸字号。
 */

/// neutral-bluish 静态色阶（官方变量原值）。
export class DsPalette {
  /** 全透明（渐隐带起点）。 */
  static readonly clear: string = '#00000000';
  static readonly c00: string = '#FFFFFF';
  static readonly c50: string = '#F9FAFB';
  static readonly c100: string = '#EBEEF2';
  static readonly c150: string = '#E9ECF2';
  static readonly c300: string = '#CFD3D6';
  static readonly c400: string = '#ADB2B8';
  static readonly c500: string = '#979DA6';
  static readonly c600: string = '#81858C';
  static readonly c700: string = '#61666B';
  static readonly c750: string = '#43454A';
  static readonly c800: string = '#353638';
  static readonly c850: string = '#2C2C2E';
  static readonly c875: string = '#232324';
  static readonly c900: string = '#1B1B1C';
  static readonly c1000: string = '#0F1115';

  /// 品牌主色：浅 #3964fe / 暗 #5686fe（官方品牌 500/450）。
  static readonly brandLight: string = '#3964FE';
  static readonly brandDark: string = '#5686FE';

  /// App 端正文链接实测 #426efe。
  static readonly linkLight: string = '#426EFE';

  /// 用户气泡实测 #edf3fe（官方品牌 50）。
  static readonly bubbleLight: string = '#EDF3FE';

  // ---- 官方 App 深色实测 ----
  static readonly appDarkBg: string = '#0F0F0F';
  static readonly appDarkSurface: string = '#242424';
  static readonly appDarkChipBorder: string = '#474849';
  static readonly chipSelectedDark: string = '#283142';
  static readonly chipSelectedFgDark: string = '#679EFE';
  static readonly chipSelectedFgLight: string = '#426EFE';
  // Atom One Light 语法高亮（安卓 tokens.dart 51-56 同源）
  static readonly synKeyword: string = '#A626A4';
  static readonly synString: string = '#50A14F';
  static readonly synFunction: string = '#E45649';
  static readonly synNumber: string = '#4078F2';
  static readonly synComment: string = '#A0A1A7';
  static readonly synPlain: string = '#383A42';
  static readonly codeTextDark: string = '#E3EAF2';
  // 暗色语法高亮（官方 App 深色实测；亮色那套直接复用 synKeyword…synPlain）。
  static readonly synDarkKeyword: string = '#CC99CD';
  static readonly synDarkString: string = '#7EC699';
  static readonly synDarkNumber: string = '#7EC699';
  static readonly synDarkComment: string = '#999999';
  static readonly synDarkPlain: string = '#D4D4D4';
  // App 实测 blockquote 竖线 / 表格边框
  static readonly quoteBarLight: string = '#E5E5E5';
  static readonly tableBorderLight: string = '#DCDCDC';
}

/// 语义别名（亮/暗两套，官方 alias 表）。
export class DsColors {
  readonly dark: boolean;

  constructor(dark: boolean) {
    this.dark = dark;
  }

  get bgBase(): string {
    return this.dark ? DsPalette.appDarkBg : DsPalette.c00;
  }

  /** 底色同色全透明（渐隐带起点），避免组件里写颜色字面量。 */
  get veilStart(): string {
    return DsPalette.clear;
  }

  get bgLayer1(): string {
    return this.dark ? DsPalette.c875 : DsPalette.c00;
  }

  get borderL1(): string {
    return this.dark ? '#0FFFFFFF' : '#0A000000';
  }

  get borderL2(): string {
    return this.dark ? '#1FFFFFFF' : '#1A000000';
  }

  get borderL3(): string {
    return this.dark ? '#29FFFFFF' : '#1F000000';
  }

  get labelPrimary(): string {
    return this.dark ? DsPalette.c50 : DsPalette.c1000;
  }

  get labelSecondary(): string {
    return this.dark ? DsPalette.c300 : DsPalette.c700;
  }

  get labelTertiary(): string {
    return this.dark ? DsPalette.c400 : DsPalette.c600;
  }

  /// 官方 label-caption：比 tertiary 更弱一档（2px 分隔点/思考圆点用）。
  get labelCaption(): string {
    return this.dark ? DsPalette.c500 : DsPalette.c400;
  }

  get brand(): string {
    return this.dark ? DsPalette.brandDark : DsPalette.brandLight;
  }

  /// 空态品牌标记主体色：官方空态鲸鱼实测 #426EFE（浅）。
  get brandMark(): string {
    return this.dark ? DsPalette.brandDark : DsPalette.linkLight;
  }

  get link(): string {
    return this.dark ? DsPalette.brandDark : DsPalette.linkLight;
  }

  get userBubble(): string {
    return this.dark ? DsPalette.c850 : DsPalette.bubbleLight;
  }

  get userBubbleText(): string {
    return this.dark ? DsPalette.c50 : DsPalette.c1000;
  }

  get mdInlineCodeBg(): string {
    return this.dark ? DsPalette.c850 : DsPalette.c100;
  }

  get mdCodeBlockBg(): string {
    return this.dark ? DsPalette.c900 : DsPalette.c50;
  }

  get mdCodeBlockText(): string {
    return this.dark ? DsPalette.codeTextDark : DsPalette.synPlain;
  }

  /// banner 与代码之间的分隔线（官方实测 #ebebeb）。
  get mdCodeBlockDivider(): string {
    return this.dark ? DsPalette.c800 : DsPalette.c150;
  }

  get mdCitationBg(): string {
    return this.dark ? DsPalette.c800 : DsPalette.c100;
  }

  get quoteBar(): string {
    return this.dark ? DsPalette.c600 : DsPalette.quoteBarLight;
  }

  get tableBorder(): string {
    return this.dark ? '#29FFFFFF' : DsPalette.tableBorderLight;
  }

  get listMarker(): string {
    return this.dark ? DsPalette.c300 : DsPalette.c700;
  }

  /// 输入条容器底色：官方浅色为纯白浮层，深色为 #242424。
  get inputFill(): string {
    return this.dark ? DsPalette.appDarkSurface : DsPalette.c00;
  }

  /// 输入条容器描边（官方 chip 描边 237,237,237）。
  get inputBorder(): string {
    return this.dark ? DsPalette.appDarkChipBorder : '#EDEDED';
  }

  get inputHintText(): string {
    return this.dark ? DsPalette.c600 : DsPalette.c400;
  }

  get chipSelectedBg(): string {
    return this.dark ? DsPalette.chipSelectedDark : DsPalette.bubbleLight;
  }

  /** 斜杠面板行高亮底色（dsh-go onSurface 6%：菜单行淡淡一层，非品牌色底）。 */
  get paletteRowHighlight(): string {
    return this.dark ? '#14FFFFFF' : '#0F000000';
  }

  get chipSelectedFg(): string {
    return this.dark ? DsPalette.chipSelectedFgDark : DsPalette.chipSelectedFgLight;
  }

  /// 发送键禁用态底/前景：官方是浅灰圆底 + 中灰箭头（浅色主题下不能用纯白底，
  /// 白底白箭头等于看不见，2026-11-16 真机反馈）。
  get sendDisabledBg(): string {
    return this.dark ? DsPalette.c800 : DsPalette.c100;
  }

  /// 禁用态箭头色（2026-11-17 用户真机反馈「灰色不明显」二次抬高对比度）：
  /// 原 c500(#979DA6) 在 c100(#EBEEF2) 浅灰底上对比度只有 2.35:1，
  /// 看上去「灰底灰箭头糊成一片」。改 c700(#61666B) 后 4.98:1（WCAG AA 正文 4.5:1）。
  /// 深色主题原 c400 在 c800 上为 5.67:1，一并抬到 c300(#CFD3D6) 得 8.03:1。
  /// 底仍是浅灰（不抢品牌色），箭头明显加深 ⇒ 形状看得清、也读得出「不可用」。
  get sendDisabledFg(): string {
    return this.dark ? DsPalette.c300 : DsPalette.c700;
  }

  /// 品牌实心控件上的前景（白，两套主题一致）。
  get onBrand(): string {
    return DsPalette.c00;
  }

  /// 悬浮层阴影（官方输入条柔和投影）。
  get shadow(): string {
    return '#14000000';
  }

  get danger(): string {
    return this.dark ? DsPalette.c300 : '#D93F3F';
  }

  /// 顶栏状态点：已连接（浅 #337250 / 深 #8BCCA6）。§4.12。
  get chatStatusOk(): string {
    return this.dark ? '#8BCCA6' : '#337250';
  }

  /// 顶栏状态点：等待审批 / 等待回答（浅 #936123 / 深 #E6BD7C）。§4.12。
  get chatStatusWarn(): string {
    return this.dark ? '#E6BD7C' : '#936123';
  }

  get drawerSearchFill(): string {
    return this.dark ? DsPalette.c800 : '#F5F5F5';
  }

  get drawerGroupLabel(): string {
    return this.dark ? DsPalette.c500 : DsPalette.c400;
  }

  /** 全屏图片查看器上的操作图标（黑底之上恒为半透明白）。 */
  get imageViewerAction(): string {
    return '#CCFFFFFF';
  }

  get drawerScrim(): string {
    return this.dark ? '#50000000' : '#00000000';
  }

  get settingsSurface(): string {
    return this.dark ? DsPalette.c875 : DsPalette.c50;
  }

  get settingsField(): string {
    return this.dark ? DsPalette.c850 : DsPalette.c00;
  }

  get settingsWarnBg(): string {
    return '#1AF5A623';
  }

  get settingsWarnFg(): string {
    return this.dark ? '#FFC24B' : '#8A5A00';
  }

  /// 会话列表「待回答」标记：桌面端是橙色小圆点/字，这里用橙字 + 极浅橙底。
  /// 语义与 settingsWarnFg 同族（提醒性质，非错误），故不引 danger 红。
  get markQuestion(): string {
    return this.dark ? '#FFB454' : '#B26A00';
  }

  get markQuestionBg(): string {
    return this.dark ? '#26F5A623' : '#1AF5A623';
  }

  // ---- 代码工作视图：本轮代码差异行色（+/- 语义，明暗各一档）----
  /// 新增行底/字：绿系（浅 #E6F4EA/#1A7F37，深 #1E3125/#7BC996）。
  get diffAddBg(): string {
    return this.dark ? '#1E3125' : '#E6F4EA';
  }

  get diffAddFg(): string {
    return this.dark ? '#7BC996' : '#1A7F37';
  }

  /// 删除行底/字：红系（浅 #FDEBEB/#C0392B，深 #3B2426/#E58C8C）。
  get diffDelBg(): string {
    return this.dark ? '#3B2426' : '#FDEBEB';
  }

  get diffDelFg(): string {
    return this.dark ? '#E58C8C' : '#C0392B';
  }
}

/// 字体 token 类型：字号 + 字重 + 行高（三者一体，对齐安卓 TextStyle）。
/// 不能用内置 `Font`（它没有 lineHeight 字段），故自定义 interface。
/// 它仍能直接喂给接受 `Font` 的 API（如 `TextInput.placeholderFont(...)`）—— 多出的
/// lineHeight 只是附加属性，结构化赋值不受影响（不能写成 `extends Font`：那会在
/// `size: number` 收窄 `size?: Length` 时编译报错）。
/// 既有 `DsTypography.x.size` / `.weight` 用法完全不变，只多一个 `.lineHeight`。
export interface DsFont {
  size: number;
  weight: FontWeight;
  /// 行高（vp）。安卓 tokens.dart 的 TextStyle.height = 行高/字号，此处直接给行高值；
  /// 用户反馈「行距有点小」（2026-11-17）后补齐，落位表见 docs/design-tokens.md §2.1。
  lineHeight: number;
}

/// 字号（官方 token，fp）+ 行高（vp）。行高由 UI 落点显式 `.lineHeight(f.lineHeight)`
/// 施加（Span 无 lineHeight，必须落在宿主 Text 上）。
/** 动效时长（官方档位 100/150/200/300/350 + 呼吸/扫光专用）。 */
export class DsMotion {
  static readonly fast: number = 100;
  static readonly normal: number = 200;
  static readonly slow: number = 300;
  /** 状态点/思考环呼吸一轮。 */
  static readonly pulse: number = 1200;
  /** 新行入场淡入（安卓 rowFadeIn 160ms，取官方档 150）。 */
  static readonly rowFade: number = 150;
}

export class DsTypography {
  static readonly h1: DsFont = { size: 24, weight: FontWeight.Bold, lineHeight: 34 };
  static readonly h2: DsFont = { size: 22, weight: FontWeight.Bold, lineHeight: 32 };
  static readonly h3: DsFont = { size: 20, weight: FontWeight.Bold, lineHeight: 30 };
  static readonly h4: DsFont = { size: 16, weight: FontWeight.Medium, lineHeight: 28 };
  static readonly base: DsFont = { size: 16, weight: FontWeight.Normal, lineHeight: 28 };
  static readonly baseStrong: DsFont = { size: 16, weight: FontWeight.Medium, lineHeight: 28 };
  static readonly small: DsFont = { size: 14, weight: FontWeight.Normal, lineHeight: 24 };
  static readonly smallStrong: DsFont = { size: 14, weight: FontWeight.Medium, lineHeight: 24 };
  static readonly inlineCode: DsFont = { size: 14, weight: FontWeight.Normal, lineHeight: 22 };
  // 13/15 不在鸿蒙 R023 字号阶梯内，按「规范就近落位」口径取 12/16（视觉差 ≤1vp）。
  static readonly codeBlock: DsFont = { size: 12, weight: FontWeight.Normal, lineHeight: 22 };
  static readonly codeBlockLabel: DsFont = { size: 12, weight: FontWeight.Normal, lineHeight: 20 };
  // 安卓 table 15/25 → 字号落 16（R023 无 15），行高按 25 同比放 1vp 取 26。
  static readonly table: DsFont = { size: 16, weight: FontWeight.Normal, lineHeight: 26 };
  static readonly tableHead: DsFont = { size: 16, weight: FontWeight.Medium, lineHeight: 26 };
  static readonly inputPlaceholder: DsFont = { size: 16, weight: FontWeight.Normal, lineHeight: 24 };
  static readonly pageTitle: DsFont = { size: 16, weight: FontWeight.Medium, lineHeight: 24 };
  static readonly caption: DsFont = { size: 12, weight: FontWeight.Normal, lineHeight: 18 };
  static readonly greeting: DsFont = { size: 18, weight: FontWeight.Medium, lineHeight: 26 };
  /// 等宽字体族（官方 --ds-font-family-code 兜底序）。
  static readonly codeFamily: string = 'monospace';
}

/// 间距（App 实测 vp + Web 布局规则）。
/// 间距/圆角一律落鸿蒙 R003 的 4/8 基数档位
/// {0,2,4,6,8,10,12,14,16,18,20,22,24,26,32,36,40,56,64}；
/// 13/15/17/19/7/5 这类安卓原值已按「规范就近落位」调整（差 ≤1vp）。
export class DsSpacing {
  static readonly screenPad: number = 22;
  static readonly contentPadRight: number = 16;
  static readonly msgPad: number = 30;
  static readonly blockGap: number = 16;
  // 空态品牌标（对照安卓 DsSpacing.brandMarkWidth/Height/Gap；官方实测 38.7×29.3dp）。
  static readonly brandMarkWidth: number = 40;
  static readonly brandMarkHeight: number = 30;
  static readonly brandMarkGap: number = 22;
  static readonly bubbleRadius: number = 16;
  static readonly topBarHeight: number = 44;
  static readonly actionIconSize: number = 16;
  static readonly actionIconGap: number = 20;
  static readonly codeBlockRadius: number = 8;
  static readonly codeBlockPad: number = 12;
  static readonly codeBlockPadH: number = 16;
  static readonly codeBlockPadV: number = 10;
  static readonly codeBlockBannerPadV: number = 8;
  static readonly cellPadV: number = 10;
  static readonly cellPadH: number = 16;
  static readonly cellMinWidth: number = 100;
  /// 表格单元格宽度上限（安卓 md_table 的 max-width min(30vw,320px) 收窄到 240vp）。
  /// 列宽由 MdTable 按全表内容估算后全表统一，见 docs/design-tokens.md §3.2。
  static readonly tableColMaxWidth: number = 240;
  static readonly quotePadLeft: number = 14;
  static readonly quoteBarWidth: number = 2;
  static readonly inlineCodeRadius: number = 6;
  static readonly inlineCodePadH: number = 6;
  /** 过程/工具行高（≥40 触控；原 28 触发 R009 小热区）。 */
  static readonly processRowHeight: number = 41;
  static readonly processIconSize: number = 16;
  static readonly processIconGap: number = 6;
  /// 用户气泡 maxWidth = 可见内容区宽 × 0.864（官方基准）。
  static readonly userBubbleMaxFraction: number = 0.864;
  /// HITL 挂起卡面板最大高度占屏比。
  static readonly liGap: number = 6; // li:not(:first-child) margin-top
  static readonly chipIconGap: number = 4;
  static readonly chipRadius: number = 16;
  /** 大按钮（断开连接等）：48 高、24 圆角（药丸）。 */
  static readonly buttonHeight: number = 48;
  static readonly buttonRadius: number = 24;
  static readonly chipGap: number = 18;
  static readonly composerButtonSize: number = 24;
  // 设置页根外边距（安卓 settingsPadH=20 / settingsPadV=28；
  // 鸿蒙按 R003 4/8 档位就近落位 22 / 26，见 docs/design-tokens.md §4.4）。
  // 内容列宽不再有 720 常量：统一走 core/Breakpoints.readableColumnWidth(实测宽)。
  static readonly settingsPadH: number = 22;
  static readonly settingsPadV: number = 26;
  // 设置卡/投影面板（安卓 tokens.dart:405-414）
  /**
   * 设置页信息行（label · value 同一行）的 label 固定最小宽。
   * 鸿蒙与安卓布局不同：安卓 `_InfoRow` 是 label/value 上下两行，鸿蒙是左右两列，
   * 不给 label 定宽时超长 value（设备 UUID）会把「设备」两字挤成竖排（真机反馈）。
   * 72 = 4 个「设备」字宽 + 余量，落在 4/8 档位附近。
   */
  static readonly settingsLabelWidth: number = 72;
  static readonly settingsCardRadius: number = 14;
  static readonly settingsCardPadH: number = 16;
  static readonly settingsCardPadV: number = 6;
  static readonly settingsChipGap: number = 6;
  static readonly thinkHMargin: number = 12;
  /** 思考行：环 18 + 内点 6；lead 列 24 + 列间距 8；窗口正文缩进 32。 */
  static readonly thinkOrbSize: number = 18;
  static readonly thinkDotSize: number = 6;
  static readonly thinkLeadGap: number = 8;
  static readonly thinkBodyIndent: number = 32;
  static readonly hitlPanelMaxFraction: number = 0.5;
  /** 卡片行尾操作钮热区（⋯/↵，≥40 触控规范）。 */
  static readonly cardActionSize: number = 40;
  /** 抽屉搜索框高度。 */
  static readonly drawerSearchHeight: number = 40;
  /** 卡片底部 6vp 空隙（展开入口上方）。 */
  static readonly cardFootGap: number = 6;
  /** 顶栏图标钮宽度（40vp 触控热区）。 */
  static readonly navButtonWidth: number = 40;
  /** 发送/停止钮直径（官方 44vp，≥40 触控）。 */
  static readonly sendButtonSize: number = 44;
  /** 任务条行高与图标热区（40vp 触控）。 */
  static readonly todoRowHeight: number = 40;
  /** 任务条进度线高度。 */
  static readonly todoProgressHeight: number = 2;
  /** 溢出菜单面板宽（官方 190vp）。 */
  static readonly menuWidth: number = 190;
  /** 过程行折叠箭头宽。 */
  static readonly processChevronSize: number = 14;
  /** diff 行前缀（+/-）列宽。 */
  static readonly diffPrefixWidth: number = 14;
  /** 文件 chip 高度（横向滚动条内）。 */
  static readonly chipHeight: number = 36;
  /** 图片 chip 移除钮热区（≥40vp 触控）。 */
  static readonly chipRemoveSize: number = 40;

  // ---- §4.12 dsh-go 外壳（鸿蒙落点，值见 docs/design-tokens.md §4.12）----
  /// 列表底边压进 composer 的量（渐隐带从这里往上羽化）。
  static readonly chatListOverlap: number = 6;
  /// 列表底部渐隐羽化高。
  static readonly chatVeilFeather: number = 14;
  /// 列表尾部留白 = overlap + feather（末条不被 composer 压住）。
  static readonly chatListBottomPad: number = 20;
  /// 列表顶部留白。
  static readonly chatListTopPad: number = 8;
  /// composer 底部安全区最小留白。
  static readonly chatComposerBottomPad: number = 8;
  /// 行距：新轮首行。
  static readonly chatGapNewTurn: number = 24;
  /// 行距：同一轮内的消息。
  static readonly chatGapSameTurn: number = 8;
  /// 行距：过程组紧贴同轮消息（0 合法）。
  static readonly chatGapProcess: number = 0;
  /// 行距：改动卡 / 生成文件卡前。
  static readonly chatGapCard: number = 12;
  /// 行距：脚注（轮尾行 / 截断提示）前。
  static readonly chatGapFootnote: number = 4;
  /// 顶栏状态行：圆点直径 / 圆点与文字间距 / 状态行高。
  /// 安卓 gap=5，鸿蒙 R003 无 5 档，就近落 6（差 1vp，见 §4.12）。
  static readonly chatStatusDot: number = 6;
  static readonly chatStatusGap: number = 6;
  static readonly chatStatusRow: number = 20;
  /// 卡容器圆角 / 图标 / 缩略图 / 缩略图圆角。
  static readonly changeCardRadius: number = 16;
  static readonly changeCardIcon: number = 16;
  static readonly changeCardThumb: number = 40;
  static readonly changeCardThumbRadius: number = 8;
  /// 改动卡最多展示文件行；生成卡默认展示行。
  static readonly changeCardMaxFiles: number = 3;
  static readonly artifactCardMaxFiles: number = 4;
}
