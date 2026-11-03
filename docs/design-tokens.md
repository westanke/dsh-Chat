# DeepSeek 官方设计基准（Web CSS + App 6.2" 实测）

> 来源：`ref/main.pretty.css`（官方 Web 权威 token）+ `ref/md-shot-*.png`（vivo V2080A 1080x2400 density 3.0 实测取色）。
> App 与 Web 数值一致处直接采用；不一致处以 App 实测优先（我们复刻的是 App）。

## 1. 色彩

### neutral-bluish 静态色阶
| 档 | 值 | 档 | 值 |
|---|---|---|---|
| 00 | #ffffff | 750 | #43454a |
| 50 | #f9fafb | 800 | #353638 |
| 60 | #f5f6f7 | 850 | #2c2c2e |
| 75 | #f1f3f5 | 875 | #232324 |
| 100 | #ebeef2 | 900 | #1b1b1c |
| 150 | #e9ecf2 | 950 | #151517 |
| 200 | #e1e5ee | 1000 | #0f1115 |
| 300 | #cfd3d6 | 400 | #adb2b8 |
| 500 | #979da6 | 600 | #81858c |
| 700 | #61666b | | |

### deepseek 品牌色（实测 + CSS）
- brand-primary 浅 #3964fe（deepseek-500）/ 暗 #5686fe（deepseek-450）
- 用户气泡 bubble 浅 **#edf3fe**（App 实测，即 deepseek-50）/ 暗 neutral-850
- 气泡高亮 highlight 浅 deepseek-200 / 暗 750
- App 端正文链接实测 **#426efe**（1000px 采样）；Web 链接用 brand-text #3964fe。Flutter 用 #426efe。

### 语义别名（浅 / 暗）
| alias | 浅 | 暗 |
|---|---|---|
| bg-base | 00 #fff | 950 #151517 |
| bg-layer-1 | 00 | 875 #232324 |
| bg-layer-2 | 00 | 850 #2c2c2e |
| bg-layer-3 | 00 | 800 #353638 |
| bg-overlay | 150 | 750 |
| bg-mask-1 | rgba(0,0,0,.24) | rgba(0,0,0,.5) |
| border-l1 | rgba(0,0,0,.04) | rgba(255,255,255,.06) |
| border-l2 | rgba(0,0,0,.10) | rgba(255,255,255,.12) |
| border-l3 | rgba(0,0,0,.12) | rgba(255,255,255,.16) |
| border-l4 | rgba(0,0,0,.16) | rgba(255,255,255,.20) |
| label-primary（正文） | 1000 #0f1115 | 50 #f9fafb |
| label-secondary | 700 #61666b | 300 #cfd3d6 |
| label-tertiary | 600 #81858c | 400 #adb2b8 |
| label-caption（blockquote 线） | 400 #adb2b8 | 600 #81858c |
| markdown-inline-code bg | 100 #ebeef2 | 850 #2c2c2e |
| markdown-code-block bg | 50 #f9fafb | 900 #1b1b1c |
| markdown-code-block-banner bg | 50 #f9fafb | 850 #2c2c2e |
| markdown-citation bg | 100 #ebeef2 | 800 #353638 |
| placeholder | 60 #f5f6f7 | 850 |
| specific-input-major | 00 | 850 |
| specific-sidebar-fill | 50 | 900 |

- App 实测正文墨色 #191b23 ≈ 抗锯齿后的 1000；取 1000。
- App 代码块语法高亮 = **Atom One Light**：keyword #a626a4、string #50a14f、function/entity #e45649、number/literal #4078f2、comment #a0a1a7、plain #383a42。
- 代码块暗色文字 #e3eaf2、暗选区 #3c526d。
- 表格边框 App 实测 #dcdcdc ≈ border-l2（rgba(0,0,0,.1) on #fff）。
- blockquote 竖线：App 实测 4px 物理宽 ≈ 1.3dp→取 2dp、色 #e5e5e5 实测（Web 用 label-caption 400 #adb2b8）；App 更浅 → 用 #e5e5e5。

## 2. 字体（Web 权威 + App density 3.0 实测验证）
| 用途 | 字体 |
|---|---|
| 正文 family | "quote-cjk-patch","Inter",system-ui,… → Flutter 用系统默认 + Inter 优先 |
| code family | Menlo, Monaco, Consolas, "Cascadia Mono", "Ubuntu Mono", "DejaVu Sans Mono", monospace → Flutter 用 monospace |

| token | 值 |
|---|---|
| md-h1 | 700 24/34 |
| md-h2 | 700 22/32 |
| md-h3 | 700 20/30 |
| md-h4 | 600 16/28 |
| md-base | 400 16/28（strong 600 16/28） |
| md-table | 400 15/25（head 500 15/25） |
| md-small（思考流） | 400 14/24（strong 600 14/24） |
| md-code（行内） | 400 14/22 mono（.875em） |
| md-code-block | 400 13/22 mono |

App 实测墨迹高（density 3.0）：H1 71px、H2 61px、H3 57px、正文 45px —— 与上表完全吻合（24/22/20/16 sp）。

## 3. Markdown 布局（Web 权威）
- h1-h3 margin: 32px 0 16px；思考流内 h* margin 12px 0。
- p 段落 margin：默认 0（.ds-markdown-paragraph 自身无 margin，块间距由 line-height + 相邻 margin 决定）；li:not(:first-child) margin-top 6px；li>ul/ol margin-top 4px；li::marker color label-secondary。
- pre margin: 16px 0。
- 行内 code：radius 6px、padding 0 5px、font .875em、bg inline-code(100/850)。
- 表格：th 下边框 border-l3、td border-l2、padding 10px 16px、min-width 100px、max-width min(30vw,320px)、cell font 15/25。
- blockquote：左 2px 线 + padding-left 14px、margin 16px 0 0（App 实测 padding-left ≈ 14dp ✓、线宽 2dp、margin-top 16dp ✓）。
- cite 引用角标：11px/14px、radius 6px 6px 6px 0、bg markdown-citation、top -5px。
- .md-code-block margin 16px 0。
- 代码块 banner：语言标签 13px + 右侧「复制」按钮（App 实测 banner 与 body 同色 #fafafa ≈ 50）。

### 3.1 代码块 / 表格 App 像素精测（ref/md-shot-3-code.png、md-shot-4-table.png @1080x2400 / 3.0x）
| 项 | 实测 px | 换算 dp | 说明 |
|---|---|---|---|
| 代码块左边界 | x=66 | 22 | 与 MD 内容左边距一致 |
| 代码块右边界 | x=1018 | 339.3 | 宽 317dp |
| 代码块顶部 | y=274 | — | 与上文间距 16dp |
| banner 分隔线 | y=395–396 | 1px | 色 **#ebebeb**（banner 与 body 之间那条线） |
| banner 文字左起 | x=109 | 14.3 | 「python」灰字 #7d7f85，13px |
| 代码左起 | x=112 | 15.3 | 代码首墨，正文 #191b23 |
| banner 右内边距 | x=969 | 16 | 复制图标右缘 |
| 代码块圆角 | — | 8 | |
| 表格左右边框 | x=66 / x=1017 | 22 / 339 | 与代码块同宽 |
| 表头行高 | y=651–776 | 41.7 | 15sp/25 行高 + 上下 10dp |
| 表头背景 | (250,250,250) | — | **#fafafa**（同代码块，非白非粉） |
| 表头文字色 | (125,127,133) | — | ≈ #7d7f85（label-secondary） |
| 数据行文字色 | (25,27,35) | — | #191b23 |
| 表格线色 | (220,220,220) | 1px | **#dcdcdc** |
| 列分隔线 | x=383 / x=701 | — | **仅数据行有**，表头通栏 |
| 表格 banner | 左上「表格」+ 右侧 复制/下载/展开 三图标 | — | 灰 #7d7f85，底色 #fafafa |

> 表格 banner 与表头之间也有一条 1px #dcdcdc 分隔线；官方任务列表**无圆点**（勾选框与无序列表同起点 x=68–74，文字 x≈99–112）。

## 4. 聊天页 App 实测布局（1080x2400 / 3.0x → dp = px/3）
- 顶栏：侧边栏按钮 x24dp y52dp 高 44dp；标题居中 16sp；右侧自动朗读 + 新对话。
- 消息区左右 padding：MD 内容左起 x68px = **22.7dp**（`screenPad = 22`）；右侧因用户气泡右缘到屏右仅 **15dp**（`contentPadRight = 15`）。
- 用户气泡：右对齐，bg #edf3fe，radius 约 16dp（视觉），文字 #0f0f0f→1000。
- 底部输入条（终版实测）：白浮层圆角容器（左右外边距 12dp、圆角 26dp、顶部 10dp、底部 0）+ 纯白底 + 柔和投影；占位文字 16sp（墨高 44px vs 官方 43px）、相对 chip 行再内缩 5dp（首墨 x83 vs 官方 82）；chip 高 29dp、chip 行左缘 x100px vs 官方 101px；选中 chip 淡蓝底 #edf3fe + 前景 #426efe；右侧加号/语音圆按钮 24dp、间距 17dp；容器下方「回答由 AI 生成，仅供参考」caption + c400。
- 底部提示「回答由 AI 生成，仅供参考」11-12sp tertiary 居中。
- 空态（`ref/official-chat-home.png` vs `ref/app-empty-final.png`）：品牌标记墨 116x88px（我们 115x87）、居中 cx538.5（我们 530.5，差 2.7dp）、纯色 #426efe；标记底到问候语顶 **22dp**（`brandMarkGap`）；问候语 **18sp** 墨宽 524px（我们 522px）。
- 消息底部操作条：复制/喜欢/不喜欢/朗读/分享/重新生成 图标 40dp 间隔 20dp，颜色 tertiary。

## 4.1 深色模式 App 实测（ref/official-dark-1.png，PIL 取色）

官方 App 深色与 Web CSS token **有偏差**，以 App 实测为准（已固化进 `lib/design/tokens.dart` 的 `DsPalette.appDark*`）：

| 元素 | 实测色值 | token |
|---|---|---|
| 页面底色 | (15,15,15) | `DsPalette.appDarkBg` ← 比 Web 950 `#151517` 更黑 |
| 输入条 / 未选中 chip 底 | (36,36,36) | `DsPalette.appDarkSurface` |
| 未选中 chip 描边 | (71,72,73) | `DsPalette.appDarkChipBorder` |
| 「智能搜索」选中 chip 底 | (40,49,66) | `chipSelectedDark` = deepseek-900 `#283142` |
| 选中 chip 前景（图标+文字） | (103,153,254) | `chipSelectedFgDark` = deepseek-400 `#679efe` |
| 顶栏图标 | (248,248,248) | labelPrimary → c50 |

浅色对照：选中 chip 前景实测 (66,110,254) = `#426efe`（`chipSelectedFgLight`）；输入条容器为**纯白浮层** (255,255,255) + 柔和投影，不是灰块。

主题切换（`ui/settings_page.dart` 落地后）：`MaterialApp.themeMode` 由 `AppSettings.themeMode`（system/light/dark 三档）受控，`theme`/`darkTheme` 仍是 `DsColors(false)/DsColors(true)` 两套；`DsColors(dark)` 由 `Theme.of(context).brightness` 决定并下传给各页面，全部样式走语义别名，UI 层零裸色（宪法 §4，`grep -rn "Colors\.\|Color(0x" app/lib/ui` 应无输出）。默认 `ThemeMode.system` 与加机制前逐字段一致。

## 4.2 侧边抽屉 App 实测（ref/official-drawer.png vs app-drawer8.png）

官方抽屉 = 顶部**胶囊搜索框** + 日期分组（今天/昨天/更早，右侧 `tune` 图标）+ **纯文字会话条目**（无 card、无分割线，选中蓝字）+ 底部账号栏（头像 + 号码 + 三点）。我们按像素对齐：

| 元素 | 官方实测 | 我们的 token / 实现 |
|---|---|---|
| 抽屉宽度 | 右缘 x864px = 288dp（屏宽 80%） | `DsSpacing.drawerWidth = 288` |
| 搜索框 | y117..248（顶 39dp、高 44dp）、x44..852（左 15dp、**右距仅 4dp**） | `drawerSearchPadTop = 11`、`drawerSearchHeight = 44`、`drawerSearchPadH = 15`、`drawerSearchPadRight = 4` |
| 搜索框底色 | (245,245,245) 全圆角胶囊 | `DsColors.drawerSearchFill`（浅 `#F5F5F5` / 深 `c800`）、`drawerSearchRadius = 22` |
| 搜索图标 | 墨 x84..131 y159..206（20dp） | `Icons.search size: 20`、`drawerSearchInset = 11`、`drawerSearchIconGap = 6` |
| 搜索占位文字 | 墨 x156..451、墨高 13dp（14sp） | `DsTypography.small` + `drawerGroupLabel` |
| 分组标题 | 「昨天」墨 y310..344、x64..136；右侧 tune 图标右距 22.7dp | `drawerGroupPadH = 21`、`drawerGroupPadV = 15`、`Icons.tune size: 16` |
| 会话条目 | 墨 y415..448（顶 138.3dp）、x65..、纯文字无 card | `drawerItemPadH = 20`、`drawerItemPadV = 12`、`DsTypography.base` + 行高 `drawerLineHeight = 24` |
| 底部账号栏 | 头像 x44..131（左 14.7dp、直径 29.3dp）+ 号码 x162..814 + 三点 x770..814 | `drawerFooterPadH = 15`、`drawerAvatarSize = 29`、`drawerAvatarGap = 10` |

## 4.3 终验结论（官方 6 屏逐项）

| 区域 | 结论 | 对照截图 |
|---|---|---|
| 空态（品牌标记 + 问候语） | 逐像素对齐（标记 ±1px、问候语墨宽 ±2px、中心 ±2.7dp） | official-chat-home.png / app-empty-final.png |
| 顶栏（汉堡 / 标题 16sp / 静音 / 加圈） | 对齐（标题墨高 32px、图标位置一致） | md-shot-1-headings.png / app-md-1.png |
| 用户气泡（#edf3fe / 右缘 15dp / 行高 24dp） | 对齐（宽 280dp vs 官方 279dp） | md-shot-1-headings.png / app-md-1.png |
| 助手消息 / 思考折叠条 | 对齐（`已深度思考` 可展开，14sp c400） | app-md-1.png |
| 代码块（#fafafa / banner 语言名 + 复制 / Atom One Light） | 对齐（分隔线 #ebebeb、padding 15/10） | md-shot-3-code.png / app-md-H.png |
| 表格（整块 #fafafa、表头通栏、列线仅数据行、线 #dcdcdc） | 对齐（自绘 `DsTable`，banner「表格 + 复制/下载/展开」） | md-shot-4-table.png / app-md-H.png |
| 公式（行内 `$\frac{a}{b}$` / 块级积分式） | 对齐（`useDollarSignsForLatex: true`） | md-shot-6-math-link.png / app-math-1.png |
| 列表（有序 / 无序 / 嵌套 / 任务列表） | 对齐（任务列表无圆点，勾选框 18dp brand） | md-shot-2-lists.png / app-md-H-task-zoom.png |
| 操作条（复制/喜欢/不喜欢/朗读/分享 + 重新生成） | 对齐（图标 17dp、间距 20dp） | md-shot-3-code.png / app-actions3.png |
| 输入条（白浮层 / chips / 圆按钮 / 免责提示） | 对齐（chip 左缘 100 vs 101px、chip 顶 2202 vs 2207px） | md-shot-2-lists.png / app-composer8.png |
| 侧边抽屉（搜索框 / 分组 / 条目 / 账号栏） | 对齐（搜索框 y117..248、x45..851 完全一致） | official-drawer.png / app-drawer9.png |
| 深色模式（底色 #0f0f0f / 输入条 #242424 / 选中 chip #283142+#679efe） | 对齐 | official-dark-1.png / app-night5.png |
| 工具调用折叠（「执行了命令，读取了文件，已写入文件」一行） | 对齐（点开展开 3 条明细，去重正确） | app-tool-5.png |
| turn 失败提示（模型限流 / 额度耗尽） | 对齐（danger 底 8% + danger 文字，`role=error`） | app-error-banner2.png |

已知未覆盖：iOS 侧**未编译验证**（本机无 macOS/Xcode 工具链，代码已就位）；chip 宽度 64.3dp vs 官方 67.7dp（3.4dp 微差，来自中文字形宽度差异）。

## 4.4 设置页（本工程自定义，非官方截图实测）

设置页是 dsh-Chat 新增功能（对照 dsh-companion `ui/SettingsScreen.kt`，但全部为纯本地偏好，不照抄官方 App 视觉）。此处色值/spacing 无官方截图依据，故单独登记、不与 §4 官方实测混列；宪法 §4 要求「新 UI 元素先在本文档登记」，以下为 `lib/design/tokens.dart` 中 `DsColors` / `DsSpacing` 新增条目的唯一依据。

| 元素 | 取值 | token |
|---|---|---|
| 分区卡片底 | 浅 `#F9FAFB`(c50) / 深 `#232324`(c875) | `DsColors.settingsSurface` |
| 只读信息行 / 权限药丸底 | 浅纯白(c00) / 深 `#2C2C2E`(c850) | `DsColors.settingsField` |
| 明文 HTTP 警告条底 | `#F5A623` 10% 透明（浅/深通用） | `DsColors.settingsWarnBg` |
| 警告条文字 | 浅 `#8A5A00` / 深 `#FFC24B` | `DsColors.settingsWarnFg` |
| 内容最大宽度 | 720dp（仿 companion `widthIn(max=720.dp)`） | `DsSpacing.settingsMaxWidth` |
| 根外边距 | 左右 20 / 上下 28（仿 companion `padding(h20,v28)`） | `settingsPadH=20` / `settingsPadV=28` |
| 分区间距 | 22dp | `settingsSectionGap` |
| 卡片圆角 / 内边距 | 14dp / 左右 16、上下 6 | `settingsCardRadius` / `settingsCardPadH` / `settingsCardPadV` |
| 行最小高度 | 52dp（仿官方 56dp 触控行） | `settingsRowMinHeight` |
| 图标-文字 / 药丸间距 | 14dp / 7dp | `settingsIconGap` / `settingsChipGap` |
| 药丸内边距 / 圆角 | 左右 10、上下 6 / 16dp | `settingsChipPadH` / `settingsChipPadV` / `settingsChipRadius` |

字号 / 主题 / 发送模式等行为偏好见 `lib/design/app_settings.dart`（对照 companion `AppPreferences`）：`normalizeFontScale` 夹 0.8–1.5 且 NaN/Inf→1.0，`effectiveFontScale` 与系统字号相乘（对齐 `AppFontScale.kt` 的 `base.fontScale * appScale`，Flutter 侧用自定义 `TextScaler` 包装 `MediaQuery` 平台 scaler，不覆盖系统无障碍字号）。

## 4.5 聊天页新增交互（本工程自定义，复用既有 token）

提交 B 的聊天页新增元素全部**复用 §4 既有语义 token，无新增色值/字号/间距**（宪法 §4 单一来源）。登记其来源与对照实现：

| 新增元素 | 对照 companion | 取值 / 协议 |
|---|---|---|
| 顶栏「会话统计」入口 | `ChatHeader.kt` ⋯ 菜单 → `ChatStatsSheet.kt` | 静音图标改为可点；Sheet 用 `DsColors.bgLayer1/labelPrimary/labelSecondary`、`DsTypography.h4/small/smallStrong`，`showModalBottomSheet`；统计由 `chatStatsOf(messages)` 本地计算，零请求 |
| 双击复制整条消息 | `ChatMessageItems.kt` `combinedClickable onDoubleClick` | `GestureDetector(onDoubleTap)` 包气泡/正文，**刻意不挂 onLongPress**（否则选词手柄不出），`Clipboard.setData` + SnackBar |
| 发送键三态 | `ChatComposer.kt` `ComposerSendPolicy.resolve` | `enum _SendKeyState { send, stop, disabled }`：有正文→`Icons.arrow_upward`、运行中且空→`Icons.stop` 发 `session-cancel`、其余→`+`/`graphic_eq` 占位；复用 `DsSpacing.composerButtonSize` / `_RoundIconButton` |
| 「重新生成 / 失败重试」 | `ChatRetry.kt`（重发最后一条有正文用户消息） | 协议无 regenerate 帧、未接 fork → 采用「重新提问」语义；`lastUserTextBefore()` 纯函数跳过空正文，`regenerateAt(int)` / `retryLast()` |
| 停止运行 | `ChatHeader.kt` → WS `session-cancel` | `GatewayClient.cancelTurn(sessionId)` → `request('session-cancel', {'sessionId'})`；应答 `session-cancelled` 会回显 requestId（不在排除表）可 await |
| 朗读 / 分享 | companion 无对应能力（全仓 grep 核实） | 官方 App 像素图标保留视觉，但明确 SnackBar「暂不支持」，不留 `() {}` 空实现 |

## 4.6 跳转最新 FAB 与滚动跟随（本工程自定义，新增布局/动效 token）

提交 C 对照 companion `ChatDetail.kt:443-450 / 691-717`、`ChatScrollDiag.kt:254-273`、`ChatScrollFreeze.kt:42-82`。**新增的是尺寸与动效常量（本工程自定义，非官方截图实测），颜色全部复用 §1 语义别名**（宪法 §4）：

| 元素 | token | 取值 | 对照 companion / 依据 |
|---|---|---|---|
| 圆形 FAB 直径 | `DsSpacing.fabSize` | 48.0 | `ChatDetail.kt:697` `size 48.dp` |
| FAB 到右下角间距 | `DsSpacing.fabMargin` | 16.0 | `ChatDetail.kt:697` `padding 16.dp` |
| FAB 内箭头图标 | `DsSpacing.fabIconSize` | 24.0 | 常规 Icon 尺寸 |
| FAB 底色 / 描边 / 图标 | `DsColors.bgLayer2` / `borderL2` / `brand` | 语义别名 | 屏内浮层，无裸色 |
| FAB 渐显时长 / 目标不透明度 | `DsMotion.fabFade` / `DsMotion.fabOpacity` | 140ms / 0.88 | `ChatDetail.kt:693` 0.88f、`:696` `tween(140)`（`AnimatedOpacity`，刻意不用 `AnimatedVisibility` 避重载歧义） |
| 滚动停止后解冻延迟 | `DsMotion.freezeSettle` | 80ms | `ChatScrollFreeze.kt` `delay(80)` |
| 非流式自动贴底时长 | `DsMotion.scrollSettle` | 140ms | 与 FAB 渐显同节奏 |

行为判据（纯函数，`ui/scroll_follow.dart`，可单测）：`computeAtBottom`（容差 `kAtBottomTolerance=48`）、`shouldAutoFollow`（**唯一守卫是粘性 `wantsBottom`，刻意不用瞬时 atBottom**，避 `PITFALLS.md:574-616` 自锁）、`shouldAnimateFollow`（流式 jumpTo、非流式 animateTo）、`shouldShowFab`（`!atBottom && !scrolling`）、`freezeSnapshot`（空表返回 null，避 companion 固化空表事故）、`isUserScrollGesture`（**只认 `dragDetails != null`，不认 `UserScrollNotification`**，因程序滚动也发后者）。会话切换重置 `kInitialWantsBottom=true`。

## 4.7 运行轨迹 / 智能团队 / 待办任务面板（本工程自定义，复用既有 token）

提交 D 的三个面板全部**复用 §4 既有语义 token，无新增色值/字号/间距**（宪法 §4 单一来源），入口收进顶栏 ⋯ 溢出菜单（对照 companion `ChatHeader.kt` ⋯ 菜单）：

| 面板 | 对照 companion | 数据来源 | 样式 / 协议 |
|---|---|---|---|
| 运行轨迹 Sheet | `ChatTrajectorySheet.kt:56-176` + `Trajectory.kt:98-127` | `ChatState.rawEvents` 客户端按 `data.turn` 分组（组内按 seq 升序），零请求；点节点展开 `prettyJson(data)` 原始事件 | `DsColors.bgLayer1/labelPrimary/labelSecondary/brand/mdCodeBlockBg/mdCodeBlockText`、`DsTypography.h4/small/smallStrong/caption/codeBlock`、`DsSpacing.*`；无新 token |
| 智能团队 Sheet | `TeamPanelSheet.kt:79-198` + `AgentTeamProjection.kt:100-151` | 服务端 `projections.values.{agentTeam,subagentCatalog}` 只读展示；三枚指挥 chips 只发普通用户消息 | `ActionChip` 用 `DsColors.chipSelectedBg`；投影缺席显示空态，不隐藏入口 |
| 待办任务 Sheet | `ChatAttachments.kt:371-450` + `ChatPresentation.kt:77-85` | 服务端 `projections.values.todos`（只认 `{content,status}`）；空列表显示空态 | 三态图标 `Icons.check_circle_outline/timelapse/radio_button_unchecked`，颜色取 `brand/labelPrimary/labelTertiary` |
| ⋯ 溢出菜单 | `ChatHeader.kt:144-304` | 收纳会话统计 / 轨迹 / 团队 / 待办四个入口 | `PopupMenuButton`，`color: DsColors.settingsSurface`，图标 `Icons.more_vert` |

数据契约约束（bridge `API.md:165,167,766`）：`projections` 可选、内核没给基线时整个字段缺席（不是空对象）、只在 `history` 首屏应答带、翻页不带。三个面板对 null/缺席一律显示「本会话暂无数据」空态，**不把「读不到投影」当成「没有这个功能」**（v2.2.44 真机踩过）。纯函数 `trajectoryOf/todoItems/agentTeamProjectionOf/prettyJson` 在 `bridge/projections.dart`，零 Flutter 依赖，单测覆盖。

## 5. 截图资产（ref/）
- official-login-page.png 登录页（+86 152 1388 0002 / 验证码输入 / 发送验证码按钮）
- official-welcome.png 欢迎引导页（开启对话主按钮）
- official-chat-home.png 空聊天主页（问候语 + 底部输入）
- md-shot-1-headings.png H1-H3/粗斜删/有序+嵌套列表
- md-shot-2-lists.png 列表续
- md-shot-3-code.png python 代码块+表格+blockquote
- md-shot-4-table.png 表格
- md-shot-5-blockquote.png 引用/分割线
- md-shot-6-math-link.png 行内公式+链接+操作条
- official-dark-1.png 官方 App 深色空态（输入条深色基准）
- app-night5.png 本工程深色 MD 会话（验收对照）
- app-composer8.png 本工程输入条终版（chip 左缘 100px vs 官方 101px）
- official-drawer.png 官方 App 侧边抽屉（搜索框 + 分组 + 纯文字条目 + 账号栏）
- app-drawer8.png 本工程抽屉终版（搜索框 y117..248 与官方逐像素一致）
- captcha-screen.png 数美点选验证码（3D 球体）
- captcha-crop.png 验证码裁剪版
- app-empty-final.png 本工程空态终版（与官方逐像素对齐）
- app-md-1.png 本工程 MD 会话首屏（公式/嵌套列表/思考折叠）
- app-chat-final.png 本工程对话页（气泡/公式/操作条/输入条）
- md-preview.png 离屏渲染的 MD 全家福（`flutter test test/render_md_test.dart`）
- compare-official-vs-app.png 官方 vs 本工程 2×2 对比图
