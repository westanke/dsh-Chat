# PORT-MAP —— 安卓版 → 鸿蒙版移植对照与坑位索引

> 鸿蒙版唯一的移植对照文档。每个阶段开工前先对着安卓版 `docs/STRUCTURE.md` 相应
> 小节列清单，完成后在这里登记落点与差异；踩坑随时往 §3 追加（名字 = 触发词，
> 与根仓 `AGENTS.md` §11 同款式）。

## 0. 工具链

- 共享工具链：`/media/wangke/OFFICE/TRae_work/_toolchain/`（command-line-tools 5.1.0.840 =
  hvigor 5.18.5 / ohpm 5.1.3 / hdc 3.1.0e，HarmonyOS SDK 5.1.0 / API 18，JDK17，Node 20.19.5，
  全国内源；UOS glibc2.28 兼容已实测）。
- 构建：`source harmony/scripts/toolchain-env.sh && hvigorw assembleHap --no-daemon`
  （或直接 `harmony/scripts/package.sh` 双闸门）。`WARN: No signingConfig` 是预期输出。
- 工具链被清理时：`harmony/scripts/install-harmony-toolchain.sh` 可重放（分钟级）。

## 1. 移植对照（阶段推进时逐行补「落点」）

| 安卓版（app/lib/…） | 鸿蒙版（entry/src/main/ets/…） | 阶段 | 状态 |
|---|---|---|---|
| design/tokens.dart | resources color/string + ui/tokens（阶段 3 登记） | 3 | ☐ 计划 |
| bridge/models.dart（协议帧模型） | ets/core/Models.ts + test/cases/models.test.ts | 1 | ◐ core 首批已落 |
| bridge/content.dart（内容部件/命令/@草稿） | ets/core/Content.ts + test/cases/content.test.ts | 1 | ✅ 2026-11-15 |
| bridge/image_media_type.dart（图片魔数/白名单） | ets/core/ImageMediaType.ts + test/cases | 1 | ✅ 2026-11-15 |
| bridge/gateway.dart（WS 状态机） | ets/core/GatewayClient.ts + Transport.ts（注入分层） | 1 | ✅ 2026-11-15 |
| bridge/gateway_events.dart（事件/状态枚举） | ets/core/GatewayEvents.ts | 1 | ✅ 2026-11-15 |
| bridge/questions.dart（HITL 模型） | ets/core/Questions.ts | 1 | ✅ 2026-11-15 |
| bridge/gateway_api.dart（WS 端点 19 个） | ets/core/GatewayApi.ts（含 history/subagentHistory） | 1 | ✅ 2026-11-15 |
| bridge/gateway_rest.dart + gateway_http.dart | ets/core/GatewayApi.ts restJson/fetchAttachment/fetchImageHandoff（配对走 REST，不走 dsh-pair 子协议——@ohos 配不了双子协议，姊妹仓口径） | 1 | ◐ roots/content 端点待补 |
| bridge/history_page.dart（历史装配） | ets/core/HistoryPage.ts（fromEvents 分组语义 + 文件卡轮尾 + 错误卡） | 1 | ✅ 2026-11-15 |
| bridge/tool_call.dart（工具措辞/合并） | ets/core/ToolCall.ts（短语表/摘要/结果正文） | 1 | ✅ 2026-11-15 |
| bridge/hosts.dart（DSH1 导入/主机库） | ets/core/Hosts.ts（纯逻辑；preferences 落库留 entry 层） | 1/4 | ✅ 2026-11-15 |
| bridge/models_view.dart（models 收敛） | ets/core/ModelsView.ts | 1 | ✅ 2026-11-15 |
| bridge/permissions.dart（权限目录） | ets/core/Permissions.ts | 1 | ✅ 2026-11-15 |
| bridge/projections.dart（轨迹/团队投影） | ets/core/Projections.ts | 1 | ✅ 2026-11-15 |
| bridge/release_check.dart（新版检测） | ets/core/ReleaseCheck.ts（纯解析；HTTP/下载安装留 entry——鸿蒙不自安装 APK，只引导 Gitee/AGC） | 1/4 | ◐ 2026-11-15 |
| bridge/platform.dart（TTS/分享/选图/下载） | entry/src/main/ets/platform/（@ohos 能力） | 4 | ☐ 阶段 4 |
| bridge/dlog.dart（文件日志） | entry/src/main/ets/debug.ets（hilog 封装；core 不 import @kit） | 4 | ☐ 阶段 4 |
| bridge/credentials.dart / device.dart | ets/core/Credentials.ts ✅ / platform/（阶段 4） | 1 / 4 | ◐ credentials 已落 |

> **WS 帧口径（实测抓包对齐）**：响应帧字段是 `kind`、请求帧才是 `type`；requestId 在 data 里
>（应答 `{kind,data:{requestId,…}}`，安卓顶层/data 双兜底同款）；连接代数 attempt 防迟到
> catch 覆盖新连接状态（微任务时序实证）；READY 掉线才退避重连，hello 成功归零 index。

> ⚠️ **core 落位（2026-11-15 定案）**：core 物理放在 `entry/src/main/ets/core/`（entry 模块内），
> 不是工程根 `harmony/core/` —— ArkTS 禁跨模块相对 import（Error00309001 实证），
> 与姊妹仓 dsh-companion-harmony 同款结构（90+ core .ts 全在模块内，已过真机+AGC）。
| ui/connect_page.dart | ui/ConnectScreen.ets | 2 | ☐ 计划 |
| ui/chat_page.dart + composer | pages/ + ui/ChatScreen.ets | 2 | ☐ 计划 |
| ui/md_view 系（Markdown 全家福） | ui/MarkdownView.ets + InlineText.ets 等 | 3 | ☐ 计划 |
| **公式渲染（行内/块级）** | ui/LaTeX（轻量渲染，自研子集） | 3 | ☐ 计划 |
| ui/md_code_block.dart | ui/CodeBlock.ets（Atom One Light 同款配色） | 3 | ☐ 计划 |
| ui/md_table.dart | ui/DataTable.ets | 3 | ☐ 计划 |
| ui/process_group.dart（工具折叠组） | ui/ToolBlockBody.ets | 3 | ☐ 计划 |
| ui/sessions_drawer.dart | ui/SessionsDrawer.ets | 4 | ☐ 计划 |
| ui/message_actions.dart | ui/MessageActions.ets | 4 | ☐ 计划 |
| HITL（question/approval 卡） | ui/HitlCards.ets | 4 | ☐ 计划 |
| 投影面板（轨迹/团队/待办） | ui/ProjectionPanels.ets | 4 | ☐ 计划 |
| 7 个 MethodChannel | platform/（i18n 时区、Core Speech TTS、systemShare、photoViewPicker、startAbility 打开文件、request.agent 下载、bundleManager 版本） | 4 | ☐ 计划 |
| 检查更新（下载 APK 直装） | **改口径**：查新版 + 跳 Gitee/AGC（鸿蒙不能自安装） | 4 | ☐ 计划 |
| settings_page.dart | ui/SettingsScreen.ets | 4 | ☐ 计划 |

## 2. 决策记录（用户 2026-11-15 拍板）

1. **方案 A ArkTS 原生重写**（否决 Flutter for OpenHarmony：本仓 Flutter 3.50 拆包依赖
   SIG 未适配，详见 workspace 根《鸿蒙版方案-dshChat-20261115.md》§三）。
2. **公式渲染首版就上轻量 LaTeX**（不降级等宽文本）：阶段 3 自研 TeX 子集渲染
   （行内 `$…$`、块级 `$$…$$`、常用符号/上下标/分数/根号起步），node 用例先行。
   代价 +2~3 轮，用户已确认。
3. **bundleName `com.dsh.dshchat`**（与安卓 applicationId 对齐，零 DeepSeek 合规；
   姊妹仓因含 DeepSeek 字样被 AGC 驳回过，本名直接规避）。
4. **鸿蒙版独立版本线 1.0.0 起**（AppScope/app.json5 versionCode 1000000）。
5. **平台差异**：检查更新不做「下载直装」（鸿蒙无自安装通道），只做查新版 + 跳转。

## 3. 坑位索引（名字 = 触发词；新坑加这里）

- `hvigor 拒明文口令` —— SignHap 要求 ≥32 字符 DevEco 加密串，命令行环境填明文口令
  直接构建失败（00303116）。签名一律走 `hap-sign-tool.jar`（见 docs/RELEASE.md）。
- `READ_PASTEBOARD 装机即拒` —— 受限权限，普通应用写进 requestPermissions **安装失败**
  （9568329）。复制走写接口（不需权限），粘贴提示用户长按系统粘贴。
- `深色跟随要显式声明` —— `onCreate` 里必须 `setColorMode(COLOR_MODE_NOT_SET)`，否则
  后台切深色回来整屏白底（onConfigurationUpdate 后台不回调）。骨架 EntryAbility 已做对。
- `PATCH 枚举不存在` —— API 18 `http.RequestMethod` 无 PATCH，workspace 改名等
  PATCH 请求需字符串转型绕过（姊妹仓坑 1，阶段 1 移植时验证）。
- `图标双名防覆盖` —— AppScope 与 entry 两侧分层图标资源名必须不同（同名时 entry 被
  AppScope 覆盖）；AGC 要求前景/背景 1024×1024 且背景不许透明。
- `图标暂为放大位图` —— 鸿蒙侧前景/启动图标由本工程安卓自绘图标 192→1024 LANCZOS
  放大 + 锐化生成（合规：自绘资产自用）。真机阶段前按安卓同款视觉矢量精绘。
- `test node_modules 不进 CI 缓存外目录` —— npm 用 npmmirror（toolchain-env.sh 已配）。
