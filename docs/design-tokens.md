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

### 2.1 鸿蒙行高落位（`harmony/entry/src/main/ets/ui/theme.ets`）

安卓 `DsTypography` 每个 TextStyle 自带 `height`；鸿蒙原先的 `Font` 结构没有行高字段（ArkTS 严格类型，
不能给内置 `Font` 加第三字段），故 theme.ets 用自定义 `DsFont { size, weight, lineHeight }` 承载，
由 UI 落点显式 `.lineHeight(f.lineHeight)` 施加（**`Span` 没有 lineHeight 属性，行高必须落在宿主 `Text` 上**）。
既有 `DsTypography.x.size` / `.weight` 用法不受影响。字号仍受鸿蒙 R023 阶梯约束（{8,9,10,12,14,16,18,20,22,24,28,30,36,38,46,48,56}），**行高不受该阶梯约束**（vp 数值自由）。

| 鸿蒙 token | size (fp) | lineHeight (vp) | 安卓对应（size/height） | 偏差说明 |
|---|---|---|---|---|
| h1 | 24 | 34 | md-h1 24/34 | 一致 |
| h2 | 22 | 32 | md-h2 22/32 | 一致 |
| h3 | 20 | 30 | md-h3 20/30 | 一致 |
| h4 | 16 | 28 | md-h4 16/28 | 一致 |
| base | 16 | 28 | md-base 16/28 | 一致 |
| baseStrong | 16 | 28 | md-base strong 16/28 | 一致 |
| small | 14 | 24 | md-small 14/24 | 一致 |
| smallStrong | 14 | 24 | md-small strong 14/24 | 一致 |
| inlineCode | 14 | 22 | md-code 14/22 | 一致 |
| codeBlock | 12 | 22 | md-code-block 13/22 | 13 不在 R023 阶梯 → 落 12 |
| codeBlockLabel | 12 | 20 | banner 语言标签 13/20 | 同上落 12 |
| table | 16 | 26 | md-table 15/25 | 15 不在 R023 阶梯 → 落 16，行高等比 +1 |
| tableHead | 16 | 26 | md-table head 15/25 | 同上 |
| caption | 12 | 18 | 11–12sp，无显式行高 | 取 1.5× 字号 |
| greeting | 18 | 26 | 18sp，无显式行高 | 取 ≈1.44× 字号 |
| pageTitle | 16 | 24 | 16sp，无显式行高 | 取 1.5× 字号 |
| inputPlaceholder | 16 | 24 | 16sp，无显式行高 | 取 1.5× 字号 |

落点（真正 `.lineHeight()` 的地方）：`harmony/entry/src/main/ets/components/md/MdView.ets`（标题 / 正文宿主 Text / 列表圆点与序号 / 链接）、
`harmony/entry/src/main/ets/components/md/MdTable.ets`（单元格）、`harmony/entry/src/main/ets/components/md/MdCodeBlock.ets`（代码行）、
`harmony/entry/src/main/ets/components/MessageCards.ets`、`harmony/entry/src/main/ets/components/ToolBlockDetail.ets`（明细正文 / 代码行 / 问答）。

**有意不加行高的地方**：

- `ProcessGroup.ets` / `ToolBlock.ets` / `TurnProcessRow.ets` 的单行折叠条：`maxLines(1)` + 固定高度
  `DsSpacing.processRowHeight = 28` / 33vp，单行文本行高在这类行里没有可见收益；而 `TurnProcessRow`
  的内容盒只有 33−2−8 = 23vp，小于 `small.lineHeight = 24`，加行高会被裁切，故整排保持「高度驱动」。
- `components/md/MdLatex.ets` 是自绘符号流（分式靠 `minHeight` + 1vp 横线叠出、根式靠上边框），
  加行高会让上下标与根号线错位，inline 公式随宿主行高即可。

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

### 3.2 鸿蒙表格列宽（`harmony/entry/src/main/ets/components/md/MdTable.ets`）

官方 Web 的表格列宽由浏览器按内容自动分配；安卓走 `gpt_markdown` 的 `TableStyle`（`defaultColumnWidth`
统一算列宽）。鸿蒙早期实现是每格 `layoutWeight(1)` —— 那是**在每行内部**等分，行长短不同、
单元格文本长短不同时同一列在不同行落在不同 x 位置，视觉上就是「表格对齐不准确」（2026-11-17 用户反馈）。

现口径（全表统一列宽 + 超宽横向滚动）：
1. `columns()` 取全表最大列数（表头缺列的行按空串补位，补位格子不画边框，避免右侧多一条悬空竖线）。
2. 逐列取各单元格「估算文本宽 + 2×`cellPadH`(16)」的最大值；估算 = 中日韩/全角字符 `字号×1.0`、
   ASCII `字号×0.55`（**估算值，真机再校**）。表头行用 `tableHead.size`、其余用 `table.size`。
3. 夹在 [`cellMinWidth` 100, `tableColMaxWidth` 240]（安卓 max-width `min(30vw,320px)` 在手机宽度下约 240dp，
   故 token 取 240vp）。
4. 自然总宽 < 外框实测宽（`onAreaChange` 量的 `frameWidth`）→ 各列等比放大铺满；否则保持自然宽，
   外层 `Scroll(scrollable: Horizontal)` 横向滚动。
5. 所有行共用同一组绝对 vp 宽度 → 列边界必然对齐；列宽按 `rows` 内容算一次并缓存。

不用百分比的原因：表格体在横向 `Scroll` 里，Scroll 的子节点宽度由内容决定，百分比没有确定的参照宽度，
会把多列表格压扁而不是横向滚动。

**行宽必须写数值 `colTotalWidth()`，不能写 `'100%'`**（2026-11-17 真机踩坑）：写百分比时该行被解析成
Scroll 视口宽（1080px 屏上 = 956px），但列宽总和比它大，各格 `Text` 被 flexShrink 压缩 ——
真机 `dumpLayout` 实测第 3 列从 100vp 挤到 52vp，「山东烟台」只露出「山东」两字；同时 Scroll 的内容宽
== 外框宽，横向滚不动，被裁的列永远看不到。改数值宽后实测三列稳定 100/156/100vp、内容宽 1114px
超出外框 956px，横向拖动可完整看到第 3 列。

## 4. 聊天页 App 实测布局（1080x2400 / 3.0x → dp = px/3）
- 顶栏：侧边栏按钮 x24dp y52dp 高 44dp；标题居中 16sp；右侧自动朗读 + 新对话。
- 消息区左右 padding：MD 内容左起 x68px = **22.7dp**（`screenPad = 22`）；右侧因用户气泡右缘到屏右仅 **15dp**（`contentPadRight = 15`）。
- 用户气泡：右对齐，bg #edf3fe，radius 约 16dp（视觉），文字 #0f0f0f→1000；宽度 = 可见内容区 × **0.864**（`userBubbleMaxFraction`，官方 279dp ÷ 内容区 323dp，360dp 屏 ≈ 279dp；宽屏/平板分栏随可见宽度自适应，不再固定 280dp）。
- 底部输入条（终版实测）：白浮层圆角容器（左右外边距 12dp、圆角 26dp、顶部 10dp、底部 0）+ 纯白底 + 柔和投影；占位文字 16sp（墨高 44px vs 官方 43px）、相对 chip 行再内缩 5dp（首墨 x83 vs 官方 82）；chip 高 29dp、chip 行左缘 x100px vs 官方 101px；选中 chip 淡蓝底 #edf3fe + 前景 #426efe；右侧加号/语音圆按钮 24dp、间距 17dp；容器下方「回答由 AI 生成，仅供参考」caption + c400。
- 底部提示「回答由 AI 生成，仅供参考」11-12sp tertiary 居中。
- HITL 挂起卡面板（提问/审批，无官方基准，App 自定）：整面板最大高度 = 屏高 × **0.5**（`hitlPanelMaxFraction`），超高部分面板内上下滚动（2026-11-15 用户反馈：题目/选项过多时提交按钮被推出屏幕不可见）。
- 空态（`ref/official-chat-home.png` vs `ref/app-empty-final.png`）：品牌标记墨 116x88px（我们 115x87）、居中 cx538.5（我们 530.5，差 2.7dp）、纯色 #426efe；标记底到问候语顶 **22dp**（`brandMarkGap`；鸿蒙已落 `DsSpacing.brandMarkWidth=40 / brandMarkHeight=30 / brandMarkGap=22`，用自绘 SVG 鲸形）；问候语 **18sp** 墨宽 524px（我们 522px）。
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
| **推挤式打开** | 抽屉滑入时**聊天页整体（含顶栏）被推向右侧屏外**，页面右缘与抽屉右缘对齐后停在屏外，浅色模式无灰幕；非 Flutter `Scaffold.drawer` 的覆盖式（页面不动） | 自绘 `AnimationController` + `Transform.translate`：页面位移 = `drawerWidth × Curves.easeOutCubic(t)`，抽屉同曲线滑入；**无 scrim**（浅色 `drawerScrim` 本就是全透明），点击页面残条或系统返回关闭 |
| 搜索框 | y117..248（顶 39dp、高 44dp）、x44..852（左 15dp、**右距仅 4dp**） | `drawerSearchPadTop = 11`、`drawerSearchHeight = 44`、`drawerSearchPadH = 15`、`drawerSearchPadRight = 4` |
| 搜索框底色 | (245,245,245) 全圆角胶囊 | `DsColors.drawerSearchFill`（浅 `#F5F5F5` / 深 `c800`）、`drawerSearchRadius = 22` |
| 搜索图标 | 墨 x84..131 y159..206（20dp） | `Icons.search size: 20`、`drawerSearchInset = 11`、`drawerSearchIconGap = 6` |
| 搜索占位文字 | 墨 x156..451、墨高 13dp（14sp） | `DsTypography.small` + `drawerGroupLabel` |
| 分组标题 | 「昨天」墨 y310..344、x64..136；右侧 tune 图标右距 22.7dp | `drawerGroupPadH = 21`、`drawerGroupPadV = 15`、`Icons.tune size: 16` |
| 会话条目 | 墨 y415..448（顶 138.3dp）、x65..、纯文字无 card | `drawerItemPadH = 20`、`drawerItemPadV = 12`、`DsTypography.base` + 行高 `drawerLineHeight = 24` |
| 工作区小节标题（2026-11-16 反馈：时间优先分组） | 桶内同工作区聚簇、首个会话上方显示工作区名（「未分组」兜底），左距复用条目左距 | `drawerSectionPadTop = 8`、`drawerSectionPadBottom = 2` + `DsTypography.caption` 染 `drawerGroupLabel`（安卓用 12sp caption，鸿蒙 11 号，PORT-MAP 记差异） |
| 「更早」折叠组标题（2026-11-16 反馈：超 2 天收缩） | 标题右侧「N 条 · 展开/收起」，整行可点切换；搜索时该组自动展开 | `DsTypography.caption` 染 `DsColors.labelTertiary`，padding 沿用 `drawerGroupPadH/PadV/Gap` |
| 底部账号栏 | 头像 x44..131（左 14.7dp、直径 29.3dp）+ 号码 x162..814 + 三点 x770..814 | `drawerFooterPadH = 15`、`drawerAvatarSize = 29`、`drawerAvatarGap = 10` |

## 4.3 终验结论（官方 6 屏逐项）

| 区域 | 结论 | 对照截图 |
|---|---|---|
| 空态（品牌标记 + 问候语） | 逐像素对齐（标记 ±1px、问候语墨宽 ±2px、中心 ±2.7dp） | official-chat-home.png / app-empty-final.png |
| 顶栏（汉堡 / 标题 16sp / 静音 / 加圈） | 对齐（标题墨高 32px、图标位置一致） | md-shot-1-headings.png / app-md-1.png |
| 用户气泡（#edf3fe / 右缘 15dp / 行高 24dp） | 对齐（宽 = 内容区 × 0.864 自适应，360dp 屏 ≈ 279dp，官方 279dp） | md-shot-1-headings.png / app-md-1.png |
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
| 内容列宽 | 随窗口：≤720dp 铺满，更宽按 0.9 缩放（§4.16） | `readableColumnWidth()` |
| 根外边距 | 左右 20 / 上下 28（仿 companion `padding(h20,v28)`） | `settingsPadH=20` / `settingsPadV=28` |
| 分区间距 | 22dp | `settingsSectionGap` |
| 卡片圆角 / 内边距 | 14dp / 左右 16、上下 6 | `settingsCardRadius` / `settingsCardPadH` / `settingsCardPadV` |
| 行最小高度 | 52dp（仿官方 56dp 触控行） | `settingsRowMinHeight` |
| 图标-文字 / 药丸间距 | 14dp / 7dp | `settingsIconGap` / `settingsChipGap` |
| 药丸内边距 / 圆角 | 左右 10、上下 6 / 16dp | `settingsChipPadH` / `settingsChipPadV` / `settingsChipRadius` |
| **鸿蒙偏差**：根外边距 | 左右 22 / 上下 26（ArkUI 触屏边缘余量略大于安卓 20/28 的上下、左右各 +2；`harmony/.../ui/theme.ets`） | `DsSpacing.settingsPadH=22` / `settingsPadV=26` |
| **鸿蒙偏差**：内容列宽 | 与安卓同一条尺：`core/Breakpoints.readableColumnWidth(实测宽)`（≤720 用满、更宽按 0.9 缓增，见 §4.16）；原「MD 档 720 / LG 档 840」的 `contentMaxWidth(bp)` 已删 | `harmony/entry/src/main/ets/core/Breakpoints.ts` |
| **鸿蒙偏差**：信息行 label 固定宽 | 72vp：鸿蒙 `infoRow` 是 label/value 左右两列（安卓 `_InfoRow` 是上下两行），不给 label 定宽时长 value（设备 UUID）会把「设备」挤成竖排 | `DsSpacing.settingsLabelWidth=72` |

字号 / 主题 / 发送模式等行为偏好见 `lib/design/app_settings.dart`（对照 companion `AppPreferences`）：`normalizeFontScale` 夹 0.8–1.5 且 NaN/Inf→1.0，`effectiveFontScale` 与系统字号相乘（对齐 `AppFontScale.kt` 的 `base.fontScale * appScale`，Flutter 侧用自定义 `TextScaler` 包装 `MediaQuery` 平台 scaler，不覆盖系统无障碍字号）。

## 4.5 聊天页新增交互（本工程自定义，复用既有 token）

提交 B 的聊天页新增元素全部**复用 §4 既有语义 token，无新增色值/字号/间距**（宪法 §4 单一来源）。登记其来源与对照实现：

| 新增元素 | 对照 companion | 取值 / 协议 |
|---|---|---|
| 顶栏「会话统计」入口 | `ChatHeader.kt` ⋯ 菜单 → `ChatStatsSheet.kt` | 静音图标改为可点；Sheet 用 `DsColors.bgLayer1/labelPrimary/labelSecondary`、`DsTypography.h4/small/smallStrong`，`showModalBottomSheet`；统计由 `chatStatsOf(messages)` 本地计算，零请求 |
| 双击复制整条消息 | `ChatMessageItems.kt` `combinedClickable onDoubleClick` | `GestureDetector(onDoubleTap)` 包气泡/正文，**刻意不挂 onLongPress**（否则选词手柄不出），`Clipboard.setData` + SnackBar |
| 发送键三态 | `ChatComposer.kt` `ComposerSendPolicy.resolve` | `enum _SendKeyState { send, stop, disabled }`：有正文→`Icons.arrow_upward`、运行中且空→`Icons.stop` 发 `session-cancel`、其余→`+`/`graphic_eq` 占位；复用 `DsSpacing.composerButtonSize` / `_RoundIconButton` |
| 待发送图片 chip 宽度上限 | `DsSpacing.composerImageChipMaxWidth` | 128.0 | 真机反馈 2026-11-17：长文件名把 chip 撑成无界宽，挤掉右侧加图钮与发送键（`RenderFlex overflowed`）。取值推导：360dp − 2×`screenPad`(22) − 2×`composerPadH`(10) = 296dp 可用；同排还有权限 chip≈80 + 加图/文件夹两钮 48 + `composerButtonGap`(17) + `composerButtonSize`(24) ≈ 169dp，余 127dp → 封顶 128dp。配套 `Expanded`(右对齐) + label `maxLines:1`/`ellipsis` 双保险 |
| 「重新生成 / 失败重试」 | `ChatRetry.kt`（重发最后一条有正文用户消息） | 协议无 regenerate 帧、未接 fork → 采用「重新提问」语义；`lastUserTextBefore()` 纯函数跳过空正文，`regenerateAt(int)` / `retryLast()` |
| 停止运行 | `ChatHeader.kt` → WS `session-cancel` | `GatewayClient.cancelTurn(sessionId)` → `request('session-cancel', {'sessionId'})`；应答 `session-cancelled` 会回显 requestId（不在排除表）可 await |
| 朗读 / 分享 | companion 无对应能力（全仓 grep 核实） | 官方 App 像素图标保留视觉，但明确 SnackBar「暂不支持」，不留 `() {}` 空实现 |

### 4.5.1 鸿蒙发送键禁用态：**禁用视觉不得依赖 `.enabled(false)`**

真机反馈 2026-11-17「鸿蒙发送键是灰色的，不明显」。排查结论与口径：

| 项 | 取值 / 结论 |
|---|---|
| 禁用底色 `sendDisabledBg` | 亮 `c100` / 暗 `c800`（沿用既有） |
| 禁用前景 `sendDisabledFg` | **亮 `c700` / 暗 `c300`**（原亮 `c500` / 暗 `c400`；c500 在 c100 上仅 2.35:1） |
| 实测对比度（修前） | **1.91:1** —— 圆内填充 `#F7F8FA`、箭头 `#B5B6B8` |
| 实测对比度（修后） | **6.95:1** —— 圆内填充 `#EDEEF2`、箭头 `#4F5054` |
| 可用态对照 | 品牌蓝底 + 白箭头，4.74:1（未改动） |

**关键机制（踩坑记录）**：ArkUI 对 `.enabled(false)` 的组件会**整层叠加大约 0.4 的透明度**，把 token 颜色与背景一起混白（`0.4×#EBEEF2 + 0.6×#FFFFFF = #F7F8FA`、`0.4×#61666B + 0.6×#FFFFFF = #C0C2C4`，与实测吻合）。因此**在 `.enabled(false)` 下无论把前景灰调多深都到不了 WCAG AA 4.5:1 —— 纯黑混白后是 `#999999`，在 `#F7F8FA` 底上上限也只有 2.6:1**。

所以鸿蒙侧禁用发送键：**不写 `.enabled(false)`**，改为保持可点、在 `onClick` 里判 `if (this.sendEnabled())` 决定是否执行，禁用视觉完全由 `.backgroundColor` / `.fontColor` 两个 token 决定（`harmony/entry/src/main/ets/components/Composer.ets` 发送键分支有注释锚点）。同理，其它需要精确控制禁用对比度的图标按钮不要走 `.enabled(false)`，需要弱化时自行用 `.opacity()` 显式指定。


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

## 4.8 连接页历史主机删除入口（本工程自定义，复用既有 token）

连接页「历史主机」卡片右侧删除按钮 + 二次确认对话框 + 直连失败后的「删除这条失效记录」入口，全部**复用 §4 既有语义 token，无新增色值/字号/间距**（宪法 §4 单一来源）：

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| 卡片底色 / 描边 | `DsColors.inputFill` / `borderL2` | 语义别名 | 沿用原 `_HostCard`，无裸色 |
| 删除图标 / 失效记录按钮图标 | `Icons.delete_outline` + `DsColors.labelTertiary` / `danger` | 语义别名 | 常规危险/弱化操作色 |
| 失效记录文字按钮 | `DsTypography.small` + `DsColors.danger` | 语义别名 | 与错误文本同色同字号 |
| 卡片显示名 / 地址 | `DsTypography.base` / `small` + `DsColors.labelPrimary` / `labelTertiary` | 语义别名 | 沿用原卡片 |
| 按钮 / 卡片内距 | `EdgeInsets.symmetric(horizontal:16, vertical:12)` 等 | 常规尺寸 | 沿用原卡片，未新增 DsSpacing 常量 |
| 删除确认 | `AlertDialog` + `TextButton('取消'/'删除')` | Material 默认 | 系统组件，未自定义样式 |

命中区约束：删除按钮是卡片 `Row` 里独立的 `IconButton`（`minWidth/minHeight:40`），`InkWell` 只包左侧 `Expanded` 区域，**两者不重叠**——点删除不会触发「点击直连」（避免误连）。删除若命中 `DshCredentials.baseUrl`，顺手 `DshCredentials.clear()`，避免下次启动拿过期 token 静默直连失败。

## 4.9 代码工作视图 · diff 行色（本工程自定义，取官方 Web diff 配色）

「显示代码工作视图」开启后，聊天页 ⋯ 菜单出现「代码工作视图」抽屉；其中「本轮代码差异」把 edit/write 工具参数渲染成 +/- 行色代码块。取色实测官方 Web CSS（`ref/main.pretty.css`）：inserted 行前景浅 `#50a14f`（行2334）/ 深 `#91d076`（行2310），deleted 行前景浅 `#e45649`（行2333）/ 深 `#cd6660`（行2282）；深色 diff 行另铺 12% 前景透明度底色（行2310-2311），浅色无行底。

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| diff 新增行（+）前景 | `DsColors.diffAdd` | 浅 `#50A14F` / 深 `#91D076` | 官方 Web `.hljs-addition`/inserted fg 实测 |
| diff 删除行（-）前景 | `DsColors.diffRemove` | 浅 `#E45649` / 深 `#CD6660` | 官方 Web `.hljs-deletion`/deleted fg 实测 |
| diff 新增行底色 | `DsColors.diffAddBg` | 深：`#91D076` @12%；浅：透明 | 官方 Web rgba(145,208,118,.12) |
| diff 删除行底色 | `DsColors.diffRemoveBg` | 深：`#CD6660` @12%；浅：透明 | 官方 Web rgba(205,102,96,.12) |

同一抽屉的轨迹段（复用 §4.7 运行轨迹面板）、Agent 预设列表（名称/描述/默认标记/当前勾选）与底部说明，全部复用既有语义 token（`bgLayer1`/`labelPrimary`/`labelSecondary`/`labelTertiary`/`brand`/`settingsSurface`/`chipSelectedBg`），无新增色值/字号/间距。diff 代码块沿用 `DsTypography.codeBlock`/`codeBlockPad`/`codeBlockRadius`，仅行前景/底色按上表。

## 4.10 工具调用展示与审批卡 · 复用既有 token（2026-11-17 官方 Web 对齐批次，无新增色值）

工具行五态（`DsToolRow`）、聚合标题、详情特化（`process_detail.dart`）与审批卡 strip/verdict 全部复用既有语义 token：

| 元素 | token |
|---|---|
| 工具行标题 / 摘要 / 状态字「运行中」 | `labelPrimary` / `codeBlockLabel` / `labelTertiary` + `DsTypography.small/caption` |
| 失败图标与「失败」状态字、错误输出、diff 后缀 `-M` | `DsColors.danger` / `DsColors.diffRemove` |
| diff 后缀 `+N`、diff 详情行色 | `DsColors.diffAdd` / `DsColors.diffRemove`（+ 对应 *Bg，见 §4.9） |
| 审批卡 strip 圆点与「等待审批」 | `DsColors.settingsWarnFg`（黄底沿用 `settingsWarnBg`） |
| kind 图标 / 折叠行箭头 / 耗时与「显示 8 / N 行」 | `labelSecondary` / `labelTertiary` + `DsSpacing.processIconSize/processRowHeight` |
| 代码块（BASH/CODE/read 正文/diff 行） | `DsTypography.codeBlock` + `mdCodeBlockBg`/`mdCodeBlockText`/`codeBlockRadius` |


## 4.11 官方展示细节批 · 轮尾行/思考行/ioCard（2026-11-17 task-5，全部复用既有色值无新增色）

官方 Web 尺寸/间距实测值（token 已登记 `design/design_tokens_layout.dart`）：

| 元素 | token | 值（官方） | 依据 |
|---|---|---|---|
| 轮尾行高 / 底部留白 | `DsSpacing.turnRowHeight` / `turnRowPadBottom` | 33 / 8 | TurnProcessNodeView height calc(33px+delta)、padding 0 0 8px |
| 思考行高 | `DsSpacing.thinkRowHeight` | 24 | ReasoningRow .root:not([data-expanded]) |
| 标题-摘要分隔圆点 / 间距 | `DsSpacing.sepDot` / `sepGap` | 2 / 8 | .sep 2×2、margin 0 8px、radius 1px、label-caption |
| 退出徽标红点 / 点-文间距 / 左间距 | `DsSpacing.exitBadgeDot` / `exitBadgeGap` / `exitBadgeGapLeft` | 4 / 5 / 8 | ExitCodeBadge |
| diff 后缀与摘要间距 | `DsSpacing.diffStatGap` | 10 | .diffStat margin-left |
| ioCard 外边距 / 段落最大高 | `DsSpacing.ioCardGap` / `ioSectionMaxHeight` | 4 / 150 | margin 4px 0 4px 4px、ioSection max-height |
| ioCard 标签-正文列间距 / 段内边距 | `DsSpacing.ioColumnGap` / `ioSectionPadV`+`ioSectionPadH` | 14 / 12+16 | column-gap 14、ioSection padding 12px 16px |
| 过程组标题稳定窗口 / shimmer 周期 | `DsMotion.processTitleMinimum` / `shimmerCycle` | 150ms / 900ms | PROCESS_TITLE_MINIMUM_MS（shimmer 本工程未做动画，仅登记周期） |

ioCard/轮尾行/思考行全部复用既有语义色（mdCodeBlockBg/borderL1/borderL2/labelTertiary/labelSecondary/danger 等），无新增色值；分段布局 [label\|content] 在 Flutter 侧用 Row+Expanded 近似官方 grid（label sticky 偏差：App 侧标签随内容滚动）。


## 4.12 会话页整页移植 · dsh-go 结构（2026-11-20 task-6）

会话页的**结构**移植自 dsh-go（App 侧 `chat_screen.dart` 的 `_ChatLayout` 分槽外壳、
`chat_header.dart` 的标题+状态顶栏、`chat_rows.dart` 的行模型、`chat_list.dart` 的
居中锚定列表）。**颜色配方、既有组件与文案仍用本仓 token**，不复刻 dsh-go 的玻璃自绘顶栏；
本节只登记移植带来的新布局/动效/状态色。

外壳分槽（`ui/chat_shell.dart`）：`header`（顶栏）/ `body`（正文列表）/ `composer`（输入条）/
`veil`（底部渐隐带）。输入条先量高度，正文区因此从顶栏下沿开始、伸到输入条上沿以下
`chatListOverlap`；渐隐带盖住正文与输入条交界处，文字滑到输入条后面时淡出而不是被裁一刀。

列表两端各留一段呼吸空间（`ui/chat_list.dart`）：顶部是 `chatListTopGap`，底部是
`chatListBottomPad`——后者与 `anchor` 用同一个值（`chatListOverlap + chatVeilFeather`），
所以「滚到底时最后一条消息停在哪」与「零滚动线在哪」是同一处几何，不会一处改了一处没跟上。
没有这段尾部留白时，最后一条消息会紧贴渐隐带，被吃掉一截。

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| 正文列基准宽度 | `DsSpacing.readableBaseWidth` | 720 | 屏宽 ≤ 此值用满；更宽按 `readableScale` 缓增（§4.16，**不是上限**） |
| 浮层控件离阅读列两边距离 | `DsSpacing.chatFloatInset` | 14 | 手机态边距 22，浮层比正文窄 4（各边 2） |
| 浮层控件列宽 | `floatingColumnWidth(页宽)` | 可读列 − 2×floatInset；没有富余时铺满 | 手机上 360（原 692 也比屏宽，效果相同） |
| 正文伸到输入条上沿以下的距离 | `DsSpacing.chatListOverlap` | 6 | dsh-go `_ChatLayout.overlap` |
| 底部渐隐带高度（羽化） | `DsSpacing.chatVeilFeather` | 14 | dsh-go `BackdropVeil.feather` |
| 列表底部留白（末尾 spacer，与 anchor 同值） | `DsSpacing.chatListOverlap` + `DsSpacing.chatVeilFeather` | 20 | dsh-go `chat_list.dart` 末尾 `SliverToBoxAdapter(SizedBox(height: bottomPad))`，其 bottomPad 同时喂给 anchor |
| 输入条底部安全区余量 | `DsSpacing.chatComposerBottomPad` | 8 | dsh-go composer 槽 SafeArea minimum |
| 顶栏状态点直径 | `DsSpacing.chatStatusDot` | 6 | dsh-go `chat_header.dart` `_dot` |
| 状态点与文字间距 | `DsSpacing.chatStatusDotGap` | 5 | dsh-go `_dotGap` |
| 顶栏状态行高 | `DsSpacing.chatStatusRowHeight` | 20 | 本工程自定（官方单行顶栏 44 + 状态行） |
| 换轮竖向间距 | `DsSpacing.chatGapNewTurn` | 24 | dsh-go page-design 组间 24 |
| 同轮内部间距 | `DsSpacing.chatGapSameTurn` | 8 | 本工程自定 |
| 相邻过程行间距 | `DsSpacing.chatGapProcess` | 0 | 过程行成组，不额外拉开 |
| 卡片与上下内容间距 | `DsSpacing.chatGapCard` | 12 | 本工程自定 |
| 脚注行上方间距 | `DsSpacing.chatGapFootnote` | 4 | 本工程自定 |
| 列表行入场淡入 | `DsMotion.rowFadeIn` | 160ms | 本工程自定 |
| 视口尺寸变化后的滚动校正上限 | `DsMotion.viewportCorrectionLimit` | 240 | dsh-go `_glideReach` 同量级 |
| 状态点呼吸周期（busy） | `DsMotion.statusPulse` | 1200ms | dsh-go `StatusDot` 呼吸 1200ms |
| 状态点颜色（正常 / 进行中 / 警告 / 错误 / 空闲） | `DsColors.chatStatusOk` / `brand` / `DsColors.chatStatusWarn` / `danger` / `labelTertiary` | 浅 #337250 / #3964FE / #936123 / #D93F3F / #ADB2B8；深 #8BCCA6 / #5686FE / #E6BD7C / #CFD3D6 / #81858C | dsh-go `semantic_colors.dart`（success/warning）+ 本仓 danger/brand |

顶栏状态机（`ui/chat_header_status.dart`）：未连接→idle「未连接」；连接中→busy「连接中」；
已断开/鉴权失败→error「已断开」；等待审批→warn「等待审批」；等待回答→warn「等待回答」；
生成中→busy「生成中」；正常→ok（显示主机名）。颜色只是辅助，状态一律带文字。


### 4.12.1 鸿蒙落点（2026-11-21 移植）

鸿蒙没有 Flutter 的 `CustomMultiChildLayout`，落点改为「Column + 绝对定位渐隐带」：
`Column[TopBar, MessageList(layoutWeight 1), Composer]`，Stack 末尾叠一条
`chatVeilFeather + chatListOverlap` 高的 `LinearGradient`（`bgBase` α0 → 实心，
`hitTestBehavior: None`），列表尾部再加与 `chatListOverlap + chatVeilFeather` 等高的留白。
行距不走 `List.space`（统一值做不到「换轮 24 / 同轮 8 / 过程 0 / 卡片 12」），
改为每个 `ListItem` 按 `chatRowGapBefore` 自己加 `padding.top`。

`ui/theme.ets` 的 `DsSpacing` 对应常量：

| token | 值 | 说明 |
|---|---|---|
| `chatListOverlap` | 6 | 列表底边压进 composer |
| `chatVeilFeather` | 14 | 渐隐羽化高 |
| `chatListBottomPad` | 20 | = overlap + feather |
| `chatListTopPad` | 8 | 列表顶部留白 |
| `chatComposerBottomPad` | 8 | composer 底部最小安全区 |
| `chatGapNewTurn` | 24 | 新轮首行 |
| `chatGapSameTurn` | 8 | 同轮消息 |
| `chatGapProcess` | 0 | 过程组贴同轮消息 |
| `chatGapCard` | 12 | 改动卡 / 生成卡 |
| `chatGapFootnote` | 4 | 脚注 / 轮尾行 |
| `chatStatusDot` / `chatStatusGap` / `chatStatusRow` | 6 / 6 / 20 | 顶栏状态行（安卓 gap 5 → R003 就近 6） |
| `changeCardRadius` / `changeCardIcon` / `changeCardThumb` | 16 / 16 / 40 | 两张卡与 diff 页（§4.17） |

## 4.13 会话页思考行 · dsh-go 形态（2026-11-20 task-7）

思考行的**结构**移植自 dsh-go（`app/lib/ui/chat/widgets/thinking_pill.dart` +
`stream_row.dart`）：图形列 + 标签 + 实时窗口 + 展开全文，过程行与工具行同一套解剖。
**颜色仍用本仓 brand 配方**（`DsColors.brand`），图标与光点环为本工程自绘，
不复用官方素材、不搬 dsh-go 的 orb 引擎。

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| 图形列宽度 | `DsSpacing.thinkLeadWidth` | 24 | dsh-go `StreamRow.lead` |
| 图形列与文字列间距 | `DsSpacing.thinkColumnGap` | 8 | dsh-go `StreamRow.gap` |
| 展开正文左缩进 | `DsSpacing.thinkBodyIndent` | 32 | dsh-go `StreamRow.indent`（图形列 + 间距） |
| 展开正文上下留白 | `DsSpacing.thinkBodyPadTop` / `thinkBodyPadBottom` | 4 / 8 | dsh-go ThinkingPill body padding |
| 展开内容左侧细线宽 | `DsSpacing.thinkRailWidth` | 1 | dsh-go `_RailPainter` |
| 实时窗口行数 | `DsSpacing.thinkTickerRows` | 3 | dsh-go `ThinkingTicker.rows` |
| 静止图标直径 | `DsSpacing.thinkGlyphSize` | 15 | dsh-go `ThinkGlyph` size 15 |
| 呼吸光点环直径 | `DsSpacing.thinkOrbSize` | 18 | dsh-go `ThinkingOrb` displaySize 18 |
| 图形底色 | `DsColors.thinkGlyphBg` | brand 浅色 10% / 深色 18% | dsh-go ThinkingPill 图形底 |
| 实时窗口滚动时长 | `DsMotion.thinkingTicker` | 160ms | dsh-go `AppMotion.quick` |
| 标签扫光时长 / 周期 / 首次延迟 | `DsMotion.thinkingSweep` / `thinkingSweepPeriod` / `thinkingSweepLead` | 1000ms / 4000ms / 600ms | dsh-go `ThinkingLabel` |
| 呼吸光点环周期 | `DsMotion.thinkingBreath` | 2400ms | dsh-go `AppMotion.breath` |

思考行三态（`ui/chat_thinking.dart`）：

- **思考中**（助手正文还没开始）：图形列是呼吸光点环，标签「思考中」带横向扫光；
  下方是**三行恒高实时窗口**——写满一行整段匀速上滑一行，块高从头到尾不变，
  列表不会一行一行地追底。
- **正文开始后**：思考行收成一行摘要（正文首行），点行展开全文。
- **轮结束**：思考过程并进这一轮的助手消息，思考行折叠、只留首行预览，点行展开全文。

展开态左侧有一条 1px 细线走图形列中线，正文从缩进 32 起——与工具行展开同一套解剖。
颜色只是辅助，状态一律带文字。

## 4.14 会话内容搜索 · 抽屉正文命中（2026-11-20 task-8）

抽屉搜索框原先只按**标题**本地过滤；本轮接上内核端点 `session/search`（走
`dshrb-v1` 通用调用面，见 docs/protocol-conformance.md §4.1），正文命中单独成节。

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| 命中条目标题与片段间距 | `DsSpacing.drawerItemSubtitleGap` | 2 | 片段是标题的注脚，比条目上下内边距（12）小一档，行不被撑成两段等重内容 |
| 片段字体 | `DsTypography.caption` 染 `labelSecondary` | 12 | 比标题（`DsTypography.small` / `labelPrimary`）轻一级——它回答「为什么命中」，不抢标题 |
| 节标题 | `DsTypography.caption` 染 `drawerGroupLabel` | 12 | 与时间分组标题、工作区小节标题同一套（抽屉里所有小节标题一个样式） |
| 行尾角标 | `DsTypography.small` 染 `brand` | 14 | 复用既有会话条目的「待回答/待审批」角标位置与样式，正文命中写「正文」、已归档写「已归档」 |

**三件套**（接入一个能力的成本，缺一不可）：
- **入口**：搜索框输入即搜，300ms 防抖（`SessionSearchController.debounce`）。
- **降级**：桥不提供 `dshrb-v1`、或内核没装该端点 ⇒ `supported == false` ⇒ 整节不出现，
  列表退回原来的标题本地过滤——行为与接这条之前逐字相同。
- **空态**：三种结局分开写——「搜索中…」/「搜索不可用：<原因>」/「没有匹配」。
  **不承诺索引可用**：本机部署可能把内核会话索引设成 `openAt "never"`，
  那时端点调得通、结果必然为空，所以空态文案只说「没有匹配」，不写「该会话不存在」。

> 能力位判据是 `kernel-call-v1` + 目录里有 `session/search`，不是「我声明了子协议」。
> 参数键名以 `kernel-endpoints` 的 `wires` 为准（内核 strict codec 既拒缺键也拒多键）。


## 4.15 宽窗适配 · 手机与平板同一套布局（2026-11-20 task-9）

会话页从手机（360dp 宽）搬到平板（横屏 1181×738dp）后暴露的问题不是「控件太小」，
而是**同一条几何在两种窗口上说了两种话**：正文被 720 的读宽居中限宽，
顶栏却横铺整屏；抽屉按手机的 80% 屏宽写死 288、推挤位移也写死 288。所以适配的
落点不是给平板另做一套，而是**先把窗口分成尺寸类，再让既有几何按类取参数**——
手机上的每一个数值都不变。

尺寸类照 Material 3 断点，外加 dsh-go 的一条规则（app/lib/ui/shell/adaptive/adaptive_layout.dart）：
**高度 < [compactHeight] 一律紧凑**。手机横屏是 915×412——够宽，但状态栏、顶栏、
输入条一去只剩几行，键盘再吃掉一半，分栏后每条列就剩下一条缝；一根居中的列反而
把宽度全留给代码和表格。这也是 Android 一直以来按最短边分手机和平板的理由。

| 元素 | token | 取值 | 依据 |
|---|---|---|---|
| 中等窗起（宽） | `DsSpacing.windowMediumMin` | 600 | M3 medium 断点；dsh-go `WindowClass.mediumMin` |
| 扩展窗起（宽） | `DsSpacing.windowExpandedMin` | 840 | M3 expanded 断点；dsh-go `WindowClass.expandedMin` |
| 紧凑窗高上限 | `DsSpacing.windowCompactHeight` | 480 | M3 compact height；手机横屏（412 高）因此仍是紧凑类 |
| 平板抽屉宽 | `DsSpacing.drawerSidebarWidth` | 320 | dsh-go `AdaptiveMetrics.sidebarWidth`；比手机抽屉（288）宽一档，会话标题多显示几个字 |
| 顶栏 / 输入条内容列宽 | `floatingColumnWidth(页宽)` | 可读列（§4.16）两侧各再窄 `chatFloatInset`；手机 = 屏宽 | 三者共用一列：≡ 与正文左缘对齐，⊕/⋮ 与右缘对齐；宽窗按可读屏宽缩放 |
| 页面让出距离 | `DsWindowClass.pageInsetFor(窗口宽)` | = 抽屉宽 | 让路距离必须跟抽屉走：手机上让 288 剩 72（官方残条），平板横屏让 320 剩 861，会话页整页可见 |

**三档行为（三档共用同一套抽屉）**：

1. **紧凑**（宽 < 600 或高 < 480）——就是今天手机上的样子：抽屉式推挤，
   正文、顶栏、输入条都按屏宽排（≤720 时 `readableColumnWidth` 返回屏宽，
   与改动前逐字相同）。
2. **中等**（600 ≤ 宽 < 840）——抽屉改用 `drawerSidebarWidth`；正文列按
   §4.16 的 `readableColumnWidth` 缩放（738 宽时是 720），顶栏与输入条
   再窄两侧各 `chatFloatInset`。
3. **扩展**（宽 ≥ 840）——同上，抽屉宽 320。**页面只让出抽屉那一条**，
   右侧剩下的整页宽（横屏 1181 − 320 = 861）给会话页，不会被推出屏外；
   正文列在这 861 里按可读屏宽算（775），两侧只留少量余量，不再二次居中收窄。

> **为什么不常驻侧栏**：真机反馈 2026-11-20——平板横屏要的是「显示完整」，
> 抽屉式会话列表够方便；常驻侧栏白占 320dp，换来的只是少点一次。所以三种窗口
> 一律抽屉式，尺寸类只决定「抽屉多宽」和「页面让出多少」。
>
> **让路的距离为什么不能写死 288**：手机的 288 是屏宽的 80%，推完只剩一条残条；
> 平板上若还让 288，抽屉宽 320 就比页面让出的多 32，右侧错出一条——所以
> `pageInsetFor` 直接取抽屉宽，让出多少就占多少，两边严丝合缝。
>
> **宽窗为什么不再收在 720**：真机反馈 2026-11-21——平板横屏把正文居中收在 720，
> 两侧各空出 230dp，看着像一列邮票贴在白纸上。用户口径（2026-11-21）：
> 整个 App 所有界面都不再限制 720 宽，按可读屏宽缩放少量——尺子见 §4.16。
>
> **手机上「推走」、宽窗上「缩窄」**：紧凑窗整页 `Transform.translate` 推走，
> 页面宽度不变，右边露出残条（官方 official-drawer.png 的样子）；中等 / 扩展窗
> 改为 `Padding(left:)` 把页面**缩窄**到剩余宽度。真机反馈 2026-11-20：
> 平板横屏若整页推 320，顶栏右侧的 ⊕/⋮ 会越出右缘被裁掉。


## 4.16 全 App 可读列宽 · 不再固定 720（2026-11-21 task-11）

§4.15 定外壳怎么分槽、抽屉怎么让路；这一节管**内容列到底多宽**。会话页正文、
HITL 卡片、设置、Markdown 阅读、子会话历史、目录浏览，以及所有模态 sheet，
全部走同一条尺（`lib/ui/window_class.dart`）：

```text
readableColumnWidth(可用宽)
  = 可用宽                                   （可用宽 ≤ 720）
  = min(可用宽, 可用宽 × readableScale)        （可用宽 > 720，readableScale = 0.9）
```

| 窗口宽 | 列宽 | 两侧各留 |
|---|---|---|
| 360（手机） | 360 | 0 |
| 738（平板竖屏） | 720 | 9 |
| 861（横屏 · 抽屉打开后） | 775 | 43 |
| 1181（平板横屏） | 1063 | 59 |
| 1600 | 1440 | 80 |

- **手机上列宽就是屏宽**，与改动前逐字相同（旧值 720 / 692 都比 360 大，
  经 `ConstrainedBox` 后一样铺满，所以手机不需要回归新数值）。
- **超过 720 后按 0.9 跟着屏宽长，没有第二道上限**。用户口径（2026-11-21）：
  「整个 App 所有都不应该限制 720 宽，应该按照可读屏幕视图缩放少量」。
  这是对 dsh-go 的有意偏离（`app/lib/ui/theme/shapes.dart:83` 仍是 720 硬上限）。
- 浮层控件（顶栏、输入条）比正文列再窄两侧各 `chatFloatInset`（14）：
  `floatingColumnWidth`。屏幕上没有富余时（手机）直接铺满，不缩。

| 位置 | 取值 | 说明 |
|---|---|---|
| 正文行（会话页） | `readableColumnWidth(LayoutBuilder 实际宽)` | 抽屉缩窄页面时跟着收，不看向整窗宽 |
| 顶栏 / 输入条 | `floatingColumnWidth(同宽)` | 比正文窄 14/侧；手机 = 屏宽 |
| HITL 卡（审批 / 提问） | `readableColumnWidth(同宽)` | 与正文同轴，卡片右缘对得上消息 |
| 二级页 | `readableColumnWidth(MediaQuery 窗宽)` | 全屏路由，没有抽屉，直接用窗宽 |
| 模态 sheet | `modalSheetConstraints(context)` | 覆盖 M3 默认的 `maxWidth: 640` |

> **为什么不直接写 0.9 × 屏宽**：屏宽 360 时 0.9 只剩 324，手机反而更窄。
> 先「不足 720 用满」再缩放，手机逐字不变，平板才开始长。
>
> **为什么不是 `double.infinity`**：上一轮 WIP 曾用无穷大直接铺满，
> 一行 1181dp 读起来要来回摆头；0.9 正是用户要的「缩放少量」。
>
> **sheet 为什么要显式传 constraints**：M3 的模态 bottom sheet 默认
> `BoxConstraints(maxWidth: 640)`（`bottom_sheet.dart` 的 `_BottomSheetDefaultsM3`），
> 宽窗下比正文列还窄；不覆盖就会在平板中间留一条比正文窄的「浮岛」。
>
> **二级页为什么也用同一条尺**：设置、Markdown、子会话历史、目录浏览都从会话页
> 推出去，翻进翻出若横向跳宽，观感像两个 App。同一个函数各页各算，得到的是同一个数。

### 4.16.1 鸿蒙端（`harmony/`）同一条尺

鸿蒙版原先按断点取固定上限：`contentMaxWidth(bp)` → MD 档 720、LG 档 840（SM 不约束），
平板横屏再宽也停在 840。2026-11-21 跟随安卓改成同一条尺：

```text
readableColumnWidth(可用宽)   = 可用宽                         （≤ 720）
                              = min(可用宽, 可用宽 × 0.9)        （> 720，无第二道上限）
floatingColumnWidth(可用宽)   = 列有富余 ? 列 − 2×14 : 可用宽     （顶栏 / 输入条）
```

- 纯函数在 `harmony/entry/src/main/ets/core/Breakpoints.ts`（`READABLE_BASE_WIDTH=720`、
  `READABLE_SCALE=0.9`、`FLOAT_INSET=14`），与安卓 `readableBaseWidth/readableScale/chatFloatInset` 同值；
  原 `contentMaxWidth` / `sheetMaxWidth` 已删，`sheetMaxWidth` 本来就无调用。
- 可用宽实测：`ChatView.chatScaffold()` 的根 Column 与 `SettingsView` 的根 Column 各挂
  `.onAreaChange`，`Area.width` 用 `typeof` 收窄成 vp 数值（ArkTS 不许 number↔string 强转），
  差值 ≥1 才写 `@State columnWidth`；未量到（0）时约束退回 `'100%'`，首帧不会闪窄列。
- 落到哪：`MessageList`（正文列）、`ChatView.topBar()` 与 `Composer`（浮层列）、`HitlPanel`
  （与正文同轴，`maxHeight:'50%'` 保持）、`SettingsView`（二级页）。都是
  `.constraintSize({ maxWidth })`，父 Column 默认居中。
- 与安卓的差异：①紧凑档抽屉仍是整页 `translate` 推挤（medium/expanded 已改 `padding.left`
  缩窄页面，列宽按缩窄后的可用宽算，与安卓 `pageInsetFor` 同口径）；
  ②`bindSheet` 内容已套 `constraintSize({maxWidth: readableColumnWidth(窗宽)})`（窄窗 100%），
  等价于安卓 `modalSheetConstraints`；③手机档列宽 = 屏宽，外观与改动前逐字相同。
- 单测：`harmony/test/cases/breakpoints.test.ts`（360→360、720→720、861→774.9、1181→1062.9、
  1600→1440、2000 继续长、0/负数→0、单调不减且 ≤ 可用宽；floating 738→692、1181→1034.9）。

## 4.17 本轮改动卡 · 生成文件卡 · 查看改动（2026-11-21 task-12）

会话页轮尾在「已完成，用时 N 秒」之后追加两类卡（正在跑的一轮不出卡，计数会跳）：

| 卡 | 触发 | 结构 |
|---|---|---|
| 改动了 N 个文件 | 本轮有成功的 edit/write | 标题 + 多文件时合计 `+N −M`；最多 3 行（文件名 / 弱化目录 / `+N −M`）；底栏「查看改动」+「还有 N 个文件」 |
| 生成了 N 个文件 | 本轮 write 新建了文件，或回复里有 markdown 图片/文件链接 | 最多 4 行（40×40 缩略图 / 文件名 / 「图片 · PNG」）；超出收进「全部 N 个文件 ⌄」；行尾 ⋯ 开复制路径 / 分享 |

两张卡都复用既有视觉：`bgLayer1` 底、`bubbleRadius` 圆角、`borderL2` 描边、
`DsTypography.smallStrong/small/codeBlockLabel`，**不新增颜色与字号**；
行间距走 `chatGapCard`（与交付文件卡同一档）。

**「查看改动」页**：顶栏（返回 / 「本轮改动」/ 合计 / 复制路径）、横向文件 chips、
正文文件绝对路径 + `+N −M 修改 K 次`、每个 hunk 标「第 i 次修改」并画红绿行
（`diffAdd`/`diffRemove`/`mdCodeBlockText`，等宽字体）。

**数据从哪来**（桥没有 workspace-changes 查询面，客户端自己推导）：

```text
turnChangesOf(messages, turn)
  只认成功的 edit/write（failed 跳过）
  meta.diffs[{path, oldText, newText}]      ← tool/result 的 data.meta，桥原样透传
  拿不到 → 参数 file_path / old_string / new_string / content
  write 且 meta.operation=create（或 oldText 空）→ created
  同文件多次编辑：合并 +N/−M，逐次留 hunk（「第 i 次修改」）
```

- 行级差异用 `diffLinesOf`（`code_diff.dart`）：先裁公共前后缀再做 LCS，
  中间的公共行也标 ctx——只做前后缀会把改一行算成「后半段全删全加」；
  表超过 40 万格的大文件退回前后缀裁剪，不拿内存换精度。
- 「生成文件」里 markdown 相对路径按**本轮最后一次 bash 的 `meta.cwd`** 拼绝对；
  没有 cwd 就跳过，不猜路径。
- 正在跑的轮次不出卡（`input.streaming && identical(turns.last, turn)`）。
- 这是对 dsh-go 的对齐实现（dsh-go 的 change_card / artifact_card
  / turn_summary），**没有**接 `.dsh-mobile` 新插件的
  `workspace-changes-v1`（REST `/api/changes.summary`、`/api/changes.diff`）——
  本仓桥 2.13.0 还没有那组端点，等桥升级再切。

## 4.18 输入条：多图 · @ 引用 · 任务条（2026-11-21 工单 1–5）

**多图（工单 2）**：待发送图片从单个字段改成列表，最多 6 张；chip 横排、右对齐、
超出可横滑，单个 chip 仍受 `composerImageChipMaxWidth` 封顶（沿用 11-17 的防溢出
修法）；每张单独删。发送时逐张校验 8 MiB（companion `MAX_SOURCE_IMAGE_BYTES` 口径），
一帧里多张 `PromptPart.image`，文本可空。

**「+」与文件夹常驻（工单 5）**：两个圆钮不再跟发送键三态联动（旧实现
`showAddImage: sendKey != stop` 会让运行中空输入时整排消失），改为常驻、
只在「未连接」时置灰。文件夹钮点一下聚焦输入框并插入 `@`（官方「选择项目中的内容」
同一路径）。

**@ 面板（工单 3、4）**：

| 分组 | 数据源 | 插入文本 |
|---|---|---|
| 对话 | `ChatState.sessions`（抽屉同一份，最多 6 条、去掉当前会话） | `@[标题](dsh-session:<id>)` |
| 文件与文件夹 | 授权根目录页（`gatewayListEntries`） | `@path`；含空白 `@"path"`；目录以 `/` 结尾 |

- 目录下钻：草稿里的 `/` 之前当目录、之后当过滤片段，按父目录拉一层，不再全树扫。
- mention 语法以内核为准：文件 `@path`（官方 `formatFileMention`）、会话
  `@[label](dsh-session:id)`（`renderSessionMention`）。桥的 kernel 白名单没有
  `fileReferences/list` 与 `sessionReferenceResolver/candidates`，所以客户端自己拼。
- 多根合并时 `path` 保持根内相对路径（以前拼了 label 前缀，导致 mention 与下钻都错）。

**任务条（工单 6，移植 dsh-go 的 dock/todo_bar（ArkTS 无关的 Flutter 参考实现））**：输入条上方一行摘要
「2/4 · 正在：跑测试」+ 2px 进度线，点一下原地展开清单（卡内滚动，最高 168vp）。
全完成显示「全部完成」；运行中且当前项进行中显示「正在：…」；否则「下一步：…」。
数据走既有投影 `todoItems(state.projections)`，不额外请求内核；无清单时不占位。
视觉复用 `bgLayer1` / `borderL2` / `brand` / `diffAdd` / `settingsCardRadius`，
不新增颜色字号。

**斜杠面板（2026-11-21，逐条对齐 dsh-go `slash_palette.dart`）**：三态（候选 /
参数提示 / 不显示）与关闭语义（点外部 · 返回键 · Esc 只关面板、文本不变不重弹）
见 `docs/FEATURE-PARITY.md`；视觉全部走新增的 `DsSpacing.palette*` 与
`DsColors.paletteRowHighlight`，无裸值：

| 位置 | token | 值（= dsh-go） | 说明 |
|---|---|---|---|
| 容器圆角 | `DsSpacing.paletteRadius` | 28 | `AppShape.xl` |
| 容器最大高 | `DsSpacing.paletteMaxHeight` | 308 | 行高 56 × 5.5 行 |
| 行内缩 | `DsSpacing.paletteRowInset` | 6 | 左右各 6，同时是列表上下 padding |
| 行圆角 | `DsSpacing.paletteRowRadius` | 22 | `paletteRadius − paletteRowInset` |
| 行最小高 | `DsSpacing.paletteRowMinHeight` | 52 | 两行文字 + 上下 8 |
| 行内边距 | `paletteRowPadLeft/Right/Top/Bottom` | 2/12/8/8 | 图标槽左缘 2 |
| 图标槽 / 图标 | `paletteIconSlot` / `paletteIconSize` | 32 / 20 | 槽宽 32 居中 20 号图标 |
| 图标/文字间距 | `paletteIconGap` | 10 | 图标槽与文字列 |
| 回车提示 | `paletteEnterSize` / `paletteEnterGap` | 16 / 8 | 只在「已输入名字且是第一行」显形 |
| 选中底色 | `DsColors.paletteRowHighlight` | 黑 6% / 白 6% | dsh-go `onSurface.withAlpha(0.06)` |
| 空态内边距 | `paletteEmptyPadTop/Left/Right` | 14 / 14 / 18 | 「没有匹配的指令，按普通消息发送」 |

第二行文案口径（dsh-go `activitySlash*`）：`命令 · 执行` / `命令 · 填入` / `技能 · 填入`，
再拼 ` · <description>`；参数提示态写 `<description> · 输入参数后发送`。鸿蒙端
（`harmony/entry/.../ui/theme.ets` 的 `paletteRowHighlight` + `ComposerPanels.ets`）
同一套数值，行高与圆角逐值相同。

**历史加载错误条（工单 1）**：断链（`NOT_CONNECTED`）不再写成「加载历史失败」红条
（顶栏已有连接态，重连成功会自动重拉）；重拉成功后会把残留的「加载历史失败」清掉。

## 4.19 「+」附件面板 · 彩色宫格 + 本对话分组（2026-11-22 task-13）

结构对照 dsh-Go `app/lib/ui/chat/widgets/plus_panel.dart`（`PlusPanelMetrics`：
side=16 / gap=8 / square=60），**不 import 其组件**，尺寸与配色全部落本仓 token。
落点：`app/lib/ui/plus_panel.dart`（面板）+ `app/lib/design/design_tokens_plus.dart`
（`DsPlusPanel` 尺寸与 `DsPlusTileColors` 宫格配色，同为 `tokens.dart` 的 part ——
`design_tokens_layout.dart` 已 501 行，再加就破宪法 §7 的单文件 500 行）。

**格子取舍（宁缺勿假）**：只留本仓真有能力的「相册」（`DshPlatform.pickImage`，
Android 侧 `ACTION_GET_CONTENT`）与「文件」（输入条既有 `@` 提及插入）。
dsh-Go 的「拍照」（本仓原生通道无相机 Intent）、「生成」「语音通话」整格删除；
「手机操控 · 确认方式」是 dsh-Go 的原生 `setPolicies`，本仓没有，整块删除。

| 位置 | token | 值 | 说明 |
|---|---|---|---|
| 面板左右边距 | `DsPlusPanel.side` | 16 | 宫格首/末格与分组卡片对齐（dsh-go side） |
| 格间距 | `DsPlusPanel.gap` | 8 | 两格之间（dsh-go gap） |
| 彩色方块 | `DsPlusPanel.tileSize` | 60 | dsh-go `square` |
| 方块图标 | `DsPlusPanel.tileIconSize` | 26 | dsh-go `Icon(size: 26)` |
| 方块圆角 | `DsPlusPanel.tileRadius` | 18 | dsh-go `AppShape.lg` Squircle 同值圆角 |
| 单格上下内距 | `DsPlusPanel.tilePadV` | 10 | dsh-go `symmetric(vertical: 10)` |
| 方块↔文字 | `DsPlusPanel.tileLabelGap` | 8 | dsh-go `SizedBox(height: 8)` |
| 宫格上内距 | `DsPlusPanel.tilesTop` | 4 | dsh-go `fromLTRB(16, 4, 16, 0)` |
| 宫格↔卡片 | `DsPlusPanel.cardGap` | 16 | dsh-go `SizedBox(height: 16)` |
| 分组标题左缩/下距 | `cardTitlePadH` / `cardTitleGap` | 4 / 8 | 比卡片左缘再进 4 |
| 行标题↔取值 | `DsPlusPanel.rowGap` | 12 | 行内弹性空隙 |
| 行尾 › | `DsPlusPanel.chevronSize` | 18 | 与设置页行尾同观感 |
| 面板底部留白 | `DsPlusPanel.bottomPad` | 20 | dsh-go 末尾 `SizedBox(20)` |
| 拖拽把手 | `handleWidth` / `handleHeight` / `handleTop` / `handleBottom` | 36 / 4 / 8 / 6 | 纯装饰把手，sheet 本身可下拉 |
| 相册格底色/图标 | `DsColors.plusAlbumBg` / `plusAlbumFg` | `brand` 淡染 10%（深 18%）/ `brand` | 无新色值，取品牌语义色 |
| 文件格底色/图标 | `DsColors.plusFilesBg` / `plusFilesFg` | `chatStatusOk` 淡染 12%（深 18%）/ `chatStatusOk` | 与相册格区分开的第二色 |
| 卡片底/圆角/行高 | `DsColors.settingsSurface` / `DsSpacing.settingsCardRadius` / `settingsRowMinHeight` | 复用 | 与设置页分区同一套 |
| 文字 | `DsTypography.smallStrong`（分组标题）/ `base`（行标题）/ `small`（取值、格名） | 复用 | 无新增字号 |

「本对话」卡片两行：`权限 → <当前档位> ›`（叠一层既有 `_PermissionSheet`，
换完重读当前档位）、`计划模式 → Switch`（`/plan` / `/plan off`）。本仓 ChatState
尚未折叠 `plan/mode` 投影，开关读不回服务端当前值，只记本会话最近一次发出的命令
（`plus_panel.dart` 的 `_planMemoValue`），真实结果以命令卡 ✓/✗ 为准。

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
