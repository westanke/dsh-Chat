/**
 * 设计 token —— app/lib/design/tokens.dart 的鸿蒙对应翻译。
 * 数值依据 docs/design-tokens.md（官方 Web CSS + App 真机实测）——改样式先改
 * token 文档，再改本文件，再改 UI（宪法 §4）；UI 代码禁止裸颜色/裸字号。
 */

/// neutral-bluish 静态色阶（官方变量原值）。
export class DsPalette {
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
    return this.dark ? '#E3EAF2' : '#383A42';
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

  get chipSelectedFg(): string {
    return this.dark ? DsPalette.chipSelectedFgDark : DsPalette.chipSelectedFgLight;
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

  get drawerSearchFill(): string {
    return this.dark ? DsPalette.c800 : '#F5F5F5';
  }

  get drawerGroupLabel(): string {
    return this.dark ? DsPalette.c500 : DsPalette.c400;
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
}

/// 字号（官方 token，fp；行高换算）。
export class DsTypography {
  static readonly h3: Font = { size: 20, weight: FontWeight.Bold };
  static readonly h4: Font = { size: 16, weight: FontWeight.Medium };
  static readonly base: Font = { size: 16, weight: FontWeight.Normal };
  static readonly baseStrong: Font = { size: 16, weight: FontWeight.Medium };
  static readonly small: Font = { size: 14, weight: FontWeight.Normal };
  static readonly smallStrong: Font = { size: 14, weight: FontWeight.Medium };
  static readonly inlineCode: Font = { size: 14, weight: FontWeight.Normal };
  static readonly codeBlock: Font = { size: 13, weight: FontWeight.Normal };
  static readonly codeBlockLabel: Font = { size: 13, weight: FontWeight.Normal };
  static readonly inputPlaceholder: Font = { size: 16, weight: FontWeight.Normal };
  static readonly pageTitle: Font = { size: 16, weight: FontWeight.Medium };
  static readonly caption: Font = { size: 12, weight: FontWeight.Normal };
  static readonly greeting: Font = { size: 18, weight: FontWeight.Medium };
  /// 等宽字体族（官方 --ds-font-family-code 兜底序）。
  static readonly codeFamily: string = 'monospace';
}

/// 间距（App 实测 vp + Web 布局规则）。
export class DsSpacing {
  static readonly screenPad: number = 22;
  static readonly contentPadRight: number = 15;
  static readonly msgPad: number = 30;
  static readonly blockGap: number = 16;
  static readonly bubbleRadius: number = 16;
  static readonly topBarHeight: number = 44;
  static readonly codeBlockRadius: number = 8;
  static readonly codeBlockPad: number = 12;
  static readonly codeBlockPadH: number = 15;
  static readonly codeBlockPadV: number = 10;
  static readonly processRowHeight: number = 28;
  static readonly processIconSize: number = 15;
  static readonly processIconGap: number = 6;
  /// 用户气泡 maxWidth = 可见内容区宽 × 0.864（官方基准）。
  static readonly userBubbleMaxFraction: number = 0.864;
  /// HITL 挂起卡面板最大高度占屏比。
  static readonly hitlPanelMaxFraction: number = 0.5;
}
