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
| design/tokens.dart | ui/theme.ets（DsPalette/DsColors/DsTypography/DsSpacing，色值逐一对应） | 3 | ✅ 2026-11-16 |
| bridge/models.dart（协议帧模型） | ets/core/Models.ts（8 类 + listFrom）+ test/cases/models.test.ts | 1 | ✅ 2026-11-16 |
| bridge/content.dart（内容部件/命令/@草稿） | ets/core/Content.ts + test/cases/content.test.ts | 1 | ✅ 2026-11-15 |
| bridge/image_media_type.dart（图片魔数/白名单） | ets/core/ImageMediaType.ts + test/cases | 1 | ✅ 2026-11-15 |
| bridge/gateway.dart（WS 状态机） | ets/core/GatewayClient.ts + Transport.ts（注入分层） | 1 | ✅ 2026-11-15 |
| bridge/gateway_events.dart（事件/状态枚举） | ets/core/GatewayEvents.ts | 1 | ✅ 2026-11-15 |
| bridge/questions.dart（HITL 模型） | ets/core/Questions.ts | 1 | ✅ 2026-11-15 |
| bridge/gateway_api.dart（WS 端点 19 个） | ets/core/GatewayApi.ts（含 history/subagentHistory） | 1 | ✅ 2026-11-15 |
| bridge/gateway_rest.dart + gateway_http.dart | ets/core/GatewayApi.ts restJson/fetchAttachment/fetchImageHandoff + roots 四件（listRootsRest/listEntriesRest/resolvePathRest/readFileBytes；配对走 REST——@ohos 配不了 dsh-pair 双子协议，姊妹仓口径） | 1 | ✅ 2026-11-16 |
| bridge/history_page.dart（历史装配） | ets/core/HistoryPage.ts（fromEvents 分组语义 + 文件卡轮尾 + 错误卡） | 1 | ✅ 2026-11-15 |
| bridge/tool_call.dart（工具措辞/合并） | ets/core/ToolCall.ts（短语表/摘要/结果正文） | 1 | ✅ 2026-11-15 |
| bridge/hosts.dart（DSH1 导入/主机库） | ets/core/Hosts.ts（纯逻辑；preferences 落库留 entry 层） | 1/4 | ✅ 2026-11-15 |
| bridge/models_view.dart（models 收敛） | ets/core/ModelsView.ts | 1 | ✅ 2026-11-15 |
| bridge/permissions.dart（权限目录） | ets/core/Permissions.ts | 1 | ✅ 2026-11-15 |
| bridge/projections.dart（轨迹/团队投影） | ets/core/Projections.ts | 1 | ✅ 2026-11-15 |
| bridge/release_check.dart（新版检测） | ets/core/ReleaseCheck.ts（解析+比较+fetchLatestRelease Gitee→GitHub 落级；鸿蒙不自安装 APK，只提示跳转） | 1 | ✅ 2026-11-16 |
| bridge/platform.dart（TTS/分享/选图/下载） | entry/src/main/ets/platform/{Tts,Share,ImagePick,PlatformBridge,Dlog,HttpTransport,WsTransport}.ets（@ohos 能力；下载 APK 不移植） | 4 | ✅ 2026-11-16 |
| bridge/dlog.dart（文件日志） | entry/src/main/ets/platform/Dlog.ets（hilog 封装；core 不 import @kit，实现只在 platform） | 2/4 | ✅ 骨架 2026-11-15 |
| bridge/credentials.dart / device.dart | ets/core/Credentials.ts + platform/PlatformBridge.ets（PrefsStore 持久化 / timeZoneId） | 1 / 2 | ✅ 2026-11-15 |

> **WS 帧口径（实测抓包对齐）**：响应帧字段是 `kind`、请求帧才是 `type`；requestId 在 data 里
>（应答 `{kind,data:{requestId,…}}`，安卓顶层/data 双兜底同款）；连接代数 attempt 防迟到
> catch 覆盖新连接状态（微任务时序实证）；READY 掉线才退避重连，hello 成功归零 index。

> ⚠️ **core 落位（2026-11-15 定案）**：core 物理放在 `entry/src/main/ets/core/`（entry 模块内），
> 不是工程根 `harmony/core/` —— ArkTS 禁跨模块相对 import（Error00309001 实证），
> 与姊妹仓 dsh-companion-harmony 同款结构（90+ core .ts 全在模块内，已过真机+AGC）。
| ui/connect_page.dart | pages/ConnectView.ets（历史主机/DSH1 导入/手动配对；删主机清凭据） | 2 | ✅ 2026-11-15 |
| ui/chat_state.dart + chat_history_actions.dart | ets/core/ChatStore.ts（node 18 用例） | 2 | ✅ 2026-11-15 |
| ui/mobile_workspace.dart | ets/core/ChatStore.ts ensureMobileWorkspace | 2 | ✅ 2026-11-15 |
| ui/chat_page.dart + chat_message_items/list | pages/ChatView.ets + components/MessageList.ets（气泡/流式/错误条 + **MdView 富渲染接入**） | 2/3 | ✅ 2026-11-16 |
| ui/composer.dart + composer_bar/panels/widgets | components/Composer.ets（发送键三态/命令补全/@ 引用/图片 chip/权限 chip=PermissionSheet.ets）+ ComposerPanels.ets | 4 | ✅ 2026-11-16 |
| ui/sessions_drawer.dart + session_groups.dart | components/SessionsDrawer.ets（分组列表/新建/高亮/设置入口） | 2 | ◐ 2026-11-16（搜索/删除/推挤动画延后） |
| ui/brand_mark.dart（品牌标） | ChatView 空态文字占位（自绘 path 延后阶段 5） | 2 | ◐ 2026-11-16 |
| ui/md_view 系（Markdown 全家福） | components/md/MdView.ets（块级循环+行内混排 Span）+ core/{MdParser,MdInline}.ts（node 22 用例） | 3 | ✅ 2026-11-16 |
| **公式渲染（行内/块级）** | core/LatexLite.ts + components/md/MdLatex.ets（自研子集，首版就上不降级——用户拍板） | 3 | ✅ 2026-11-16 |
| ui/md_code_block.dart | components/md/MdCodeBlock.ets + core/SimpleHighlight.ts（Atom One Light 配色；高亮仅 str/num/comment/kw 四类简化） | 3 | ✅ 2026-11-16 |
| ui/md_table.dart | components/md/MdTable.ets（复制；下载/展开延后阶段 4） | 3 | ✅ 2026-11-16 |
| ui/process_group.dart（工具折叠组） | components/ToolBlock.ets（摘要行/逐条 ✓✗/详情 prettyArgs+bash 代码块） | 3 | ✅ 2026-11-16 |
| ui/message_actions.dart | components/MessageActions.ets（复制/喜欢/朗读/分享/重新生成）+ platform/{Tts,Share}.ets | 4 | ✅ 2026-11-16 |
**阶段 3 已记偏差（2026-11-16）**：①代码高亮四类 token（kw/str/num/comment）+ 五语言关键词表，非 Atom One 全量 scope；②流式渲染无闪烁光标（安卓 GptMarkdown isStreaming 有）；③表格下载/展开按钮延后阶段 4；④任务列表勾选框用 Unicode ☑/☐ 字符非自绘 Checkbox；⑤HTML 内联块纯文本化不渲染。

| HITL（question/approval 卡） | core/HitlStore.ts（挂起表/摘卡/三动作）+ components/HitlPanel.ets（审批卡/提问卡/自定义回答） | 4 | ✅ 2026-11-16 |
| 投影面板（轨迹/团队/待办/统计/模型） | core/Projections.ts chatStatsOf + components/{ProjectionSheets,ModelSheet}.ets（bindSheet 五面板） | 4 | ✅ 2026-11-16（子会话下钻延后） |
| 7 个 MethodChannel | platform/（i18n 时区/Core Speech TTS/系统分享/photoViewPicker/startAbility/bundleManager 版本；下载 APK 不移植） | 4 | ✅ 2026-11-16 |
| 检查更新（下载 APK 直装） | **改口径**：ReleaseCheck.fetchLatestRelease 查新版 + SettingsView 提示跳 Gitee Release 页（鸿蒙不能自安装，下载/安装/进度轮询不移植） | 4 | ✅ 2026-11-16 |
| settings_page.dart（六分区设置页） | pages/SettingsView.ets（连接只读/外观三档/发送模式/关于+检查更新/断开连接） | 4 | ✅ 2026-11-16（字号缩放/诊断日志开关延后阶段 5） |

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

- `ArkUI getter 崩进程` —— **@Builder / ForEach 生成器里 `private get c(): DsColors`
  取值是 undefined**，`this.c().x` 不会自动兜底，直接 `TypeError: Cannot read property
  'labelPrimary' of undefined`，ArkUI 把它当未捕获 JS 异常 → AMS `exit_msg:TypeError`
  **整进程被杀死**（不是红屏，是 App 静默消失）。鸿蒙侧一律用普通方法 `private c()`，
  调用写 `this.c().labelPrimary`；`get` 访问器只允许出现在非 UI 的 core 纯逻辑里。
- `@Prop 无 @Watch 不重渲染` —— ArkUI **只对 build 期间读到的 @State/@Prop 建立依赖**。
  把 store 挂在 `store: ChatStore | null = null`（普通成员）上，再在 build 里
  `ForEach(this.store.messages)` / `if (this.isEmpty())` 直读，数据变化**不会**让节点重新
  求值 —— 真机现象：`version` 已涨到 73、`store.messages.length=2`，界面仍停在初始空态；
  改成 List 后子项恒为 0。修法：把 store 派生值在 `setNotify()` 回调里抄进 `@State`
  （`emptyView`/`titleView`/`msgs`/`sessionsView`/`connectedView`…），`@Prop version`
  必须配 `@Watch('syncVersion')`，并在 `aboutToAppear()` 补一次首帧快照。
- `hilog 抓 JS 崩溃栈` —— App 静默退出（`pidof` 为空、hilog 无 crash 关键字）时：
  `hdc shell "hilog -G 16M"` 先把 app 缓冲放到 16M（64M 会报 `Invalid buffer size`，
  上限就是 16M）→ `hilog -r` 清 → 复现 → `hdc shell "hilog -x | grep -iE
  'JsError|Stacktrace|TypeError'"`。能拿到 `FIX THIS APPLICATION ERROR: @Component 'X'[id]
  has error in update func: ...` + 精确到 `.ets:行:列` 的栈 + AMS 的
  `exit_msg/reason`。缓冲区不放大时崩溃日志常被后续日志冲掉。
- `hilog 读不到应用日志` —— 域 `0xD5C0`（platform/Dlog.ets）的 info/warn 在真机 hilog 里
  按 pid 或 `-T Dsh` 过滤都取不到（未落盘或被系统过滤）。**真机排障不要指望 hilog**，
  走协议探针（mock bridge 抓帧 / REST 直查 bridge）。
- `node 内置 WebSocket 不带 header` —— Node 22+ 的全局 `WebSocket` 构造项不认
  `headers`，探针要打 `Authorization` 头必须显式 require `ws` 包
  （`/home/wangke/.dsh/profiles/web/node_modules/ws/index.js`），否则握手虽然 OPEN，
  服务端按未鉴权处理、帧全被丢弃（表现为 messag 帧回 INTERNAL_ERROR）。
- `uitest inputText 是追加` —— `hdc shell uitest uiInput inputText x y "文本"` 往已有内容
  后面追加，不清空。重复导入 DSH1 会双拼成 2 倍长度 → 报「配置文本无法识别」。要么
  先清数据重装，要么发 DEL 清空。
- `设备上无 sed -i` —— 鸿蒙设备 shell 的 `sed -i` 报 `sed: no temp file`。改设备文件
  （如 preferences）要 `hdc file send` 传新文件再 `hdc shell cp` 覆盖。
- `bindContentCover 与 bindSheet 同节点失效` —— 同一节点同时挂 `bindSheet` +
  `bindContentCover` 时，后者（bindContentCover）点了不弹。真机现象：ChatView 的 ⋮
  溢出菜单 `menuOpen=true` 但界面毫无变化（`uitest` 树里也没有）。修法：改成 Stack 内联
  叠加 —— `if (this.menuOpen) { 遮罩 Column().onClick(关闭) ; this.overflowMenu() }`，
  同会话抽屉的写法；弹层本身用 `Blank()` 挤到底部或 `justifyContent` 定位。
- `getRouter().back() 退应用` —— 本工程页面切换是 `Index.ets` 里 `@State route` 的条件
  渲染（boot/connect/chat/settings），**没有 Router 栈**。`this.getUIContext().getRouter().back()`
  在这种结构下会把整个应用退到桌面（真机现象：点设置页「‹」后露出别的 App）。返回一律
  传回调：`onBack: () => { this.route = 'chat'; }`。
- `私有方法只定义没调用` —— ArkTS 编译器**不报未使用私有方法**。`ModelSheet.load()` 无
  `aboutToAppear` 调用 → 面板永远停在「加载中…」；`Composer.ensureCommands()` 无调用点 →
  输入 `/` 永远没有补全候选。新写组件的 `load()/ensureXxx()` 必须确认有挂载点。
- `子组件普通成员收数组` —— `HitlPanel` 的 `questions: PendingQuestion[]` / `approvals:
  PendingApproval[]` 写成普通成员时，组件只在**首次创建**时取一次值；父层 `@State` 换新
  数组不会重建子组件（真机现象：提交提问卡后卡片不消失、审批卡根本不出现）。接收父层
  数组一律 `@Prop`（`@Prop questions` / `@Prop approvals`）。
- `键盘遮输入框` —— 不设置避让模式时默认 OFFSET：键盘弹起整页上移，底部输入框连带被
  推出屏幕（真机现象：键盘弹出后 ＋/权限/↑ 全看不见）。修法：`EntryAbility.onWindowStageCreate`
  的 `loadContent` 回调里 `windowStage.getMainWindowSync().getUIContext()
  .setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)`（`import { window, KeyboardAvoidMode }
  from '@kit.ArkUI'`）；RESIZE 压缩页面高度，`Column(height 100%)` 随之收缩、List 的
  `layoutWeight` 吃多余空间，composer 停在键盘上沿。必须在 loadContent 之后取 UIContext。
- `连接历史不落盘` —— `ConnectView.enterWith()` 只写 `dsh.credentials`、不写 `dsh.hosts`，
  于是会话抽屉/连接页的历史主机永远是空、每次打开都要重输连接码。按安卓
  `connect_page.dart:55` 口径补：`host.id = stableId(baseUrl);
  this.persistHosts(upsertHost(this.hosts, host));`。
- `权限显示英文档位` —— 投影 `values.permissions.currentValue` 是 `workspace-write` /
  `danger-full-access` 这类 ASCII 名，直接上屏就是英文。必须过
  `core/Permissions.ts` 的 `permissionLabelOf(value)`（仅可查看/工作区读写/完全权限/
  自动审查；未识别原样返回，不杜撰档位）。
- `会话列表待回答标记靠 REST` —— bridge 的 `sessions` 列表只对**挂起审批**下发
  `pendingInteraction:'approval'`（`listSessions` 里 `hasPendingApproval()` 判断），
  **挂起提问不下发这个字段**；而且 WS 连上后不会补推其它会话的 HITL 帧（实测
  hello 后 0 条事件、逐个 subscribe 也不补推）。所以「待回答」标记只能：
  ① 当前连接实时收到的挂起项走 `HitlStore.pendingQuestions/pendingApprovals`；
  ② 其它会话靠 REST `GET /api/v1/chat/sessions/{sid}/questions`（`{items:[{callId,
  state,viaBridge,questions:[…]}]}`，`viaBridge:true` = agent 正阻塞）与
  `/approvals` 逐会话探测，结果写进 `ChatStore.pendingMarks`（Map）再抄成
  `@State marksView: string[]`（Map 内部变更不触发 ArkUI 重渲染）。抽屉打开时
  探测 40+ 会话 = 80+ 个 REST 请求，实测约 25–30s 出结果（41/41 成功）。
- `GatewayApi 忘注入 HTTP transport` —— `new GatewayApi(gateway, null)` 会让
  **所有 REST 功能**（附件/图片交接/根列表/文件全文/挂起项探测）报
  `NO_TRANSPORT`；两条连接路径必须都传 `new HttpTransportImpl()`：
  `ConnectView.enterWith()`（原有）与 `Index.autoConnect()`（真机发现漏传，
  自动连接后 @ 文件补全、图片、文件卡全坏）。
- `命令卡被 reloadHistory 冲掉` —— 本地注入的命令卡是 `role='command'`、`seq=-1`，
  不在服务端历史里；`reloadHistory()` 里 `self.messages = page.items` 整体替换会
  把它冲掉（`runCommandIn` 成功链恰好会重拉 history）。修法：替换前先收集
  `m.role === 'command' && m.seq < 0` 的卡片，再 `[...page.items, ...localCards]`
  （安卓 `chat_history_actions.dart:36-40` 同口径）。
- `TTS 必须先 setListener` —— `@kit.CoreSpeechKit` 的 `textToSpeech` 引擎，`speak()`
  之前必须先 `setListener(SpeakListener)`，否则 `onStart/onComplete/onStop/onError`
  一个都收不到（表现：能出声但工具条图标不切、异常静默）。另外
  `CreateEngineParams.online` 的语义是 **0=在线、1=离线**（不是布尔开关），
  在线音色更自然，取 0。引擎是进程级单例，Ability `onDestroy` 里 `shutdown()`
  释放，否则长期占音频焦点导致后续朗读报忙。
- `分享要先 ShareKit` —— 只发 Want `ohos.want.action.sendData` + `text/plain`
  在部分机型/版本不会弹出系统分享面板（静默失败或直接报错）。首选
  `@kit.ShareKit` 的 `systemShare`：`new SharedData({utd: UniformDataType.PLAIN_TEXT,
  content})` → `new ShareController(data).show(context, {selectionMode:
  SelectionMode.SINGLE, previewMode: SharePreviewMode.DEFAULT})`；ShareKit 不可用
  时再退回 Want 隐式拉起。
- `@ 面板/命令面板不刷新` —— `components/ComposerPanels.ets` 里 `CommandPanel.commands` 与
  `AtFilePanel.entries/loading/failed/dirPath` 原写成**普通成员**：这类字段只在组件首次
  创建时赋值一次，父层 `@State` 换新数组/新布尔不会重建子组件，表现就是 `@` 面板永远停在
  「正在加载目录…」（entries 早已到、loading 却不翻）。全部改 `@Prop` 即好。
  同源坑还有 `HitlPanel.questions/approvals`（见上）。
- `@ 下钻整面板报错` —— `components/Composer.ets` 的 `loadAtEntries()` 原用裸
  `Promise.all(jobs)` 并发拉所有授权根：下钻到只在某一个根里存在的目录（如
  `workspace/.dhs-diff`）时，另外两个根 `GET /roots/{id}/entries?path=…` 返回 404，
  整批 reject → 面板显示「目录加载失败，点按重试」。修法：每个 `listEntriesRest` 各自
  `.catch((e: Error): GatewayEntry[] => new Array<GatewayEntry>())` 容错；同时统计
  `okRoots`（`lists[i].length > 0 || dir.length === 0`），只有 `okRoots === 0 && dir.length > 0`
  才算真失败。注意空根（`default-workspace`）返回 200 + 空数组，别误判成失败。
- `新建会话没目录选项` —— 安卓空态有「工作目录」chip（`app/lib/ui/chat_page.dart` 的
  `_Greeting`），默认「手机会话」，可换成授权根下任意目录，走
  `session-create{rootId,cwd}`（`gateway_api.dart:52 createSessionAt`），会话落「未分组」。
  鸿蒙版补法：`core/SessionLocation.ts` 放纯逻辑（`SessionLocation`/`recentLocations`/
  `locationSubtitle`/`parentPath`/`locationChipLabel`），`components/SessionLocationSheet.ets`
  是面板（默认项 + 最近使用 + 授权根浏览），`ChatStore.pendingLocation` 存待定目录，
  `MobileWorkspace.prepareSessionFor` 里优先走 `api.createSessionAt(rootId, cwd)` 且
  失败**显式报错不静默回退**（回退等于建到用户没选的地方）；`ChatView` 空态渲染 chip，
  快照到 `@State pendingLocView` 才有观察。
- `目录浏览显示空根` —— 授权根列表里第一个常是空的 `default-workspace`
  （`GET /roots` 顺序即此，`/entries` 返回 200 + `entries:[]`），而安卓走 file-list 的
  「首个授权根」语义可以隐式跳空根。REST 必须显式给 `rootId`，因此浏览时要在**根层**
  `dirs.length === 0` 就自动换下一个根（下钻层不跳），并允许点标题手动切根。
- `发送键白底看不见` —— 禁用态底色若用 `inputFill`（浅色主题=纯白），白底 + 浅灰箭头在
  浅色界面上几乎不可见（用户反馈）。改用 token `sendDisabledBg`（亮 `#EBEEF2` / 暗
  `c800`）+ `sendDisabledFg`（亮 `c500` / 暗 `c400`）；可用态走实心 `brand` + `onBrand`
  白箭头、字号 20 加粗。
- `纯文本模型发图气泡` —— bridge 收到图片后，会把 `user/message` 的 content 写成
  **两个 text 块**（原文 + 一段给模型看的说明「🖼️ 图片 1「x.png」（当前模型看不到图，
  已存到 .dsh-images/<hex>.png…）」+ 独立一行 `[Image: source: /abs/<hex>.png]`），
  **没有 `type:'image'` 块**。所以：①`ContentParts.from()` 拿不到 images；②那段说明会
  原样进气泡（真机现象：气泡里出现整段提示和 64 位 hex 路径）。修法两半 ——
  `core/Content.ts` 的 `stripBridgeImageNote(text)` 逐行滤掉以 `🖼` 开头和以
  `[Image: source:` 开头的行（**不能整段正则贪婪匹配**，会连用户原文一起吃掉）；
  `core/HistoryPage.ts` 装配用户消息时把清洗结果写 `text`、被清洗的原文留
  `rawText` 字段；`components/MessageList.ets` 的用户气泡与助手气泡都用
  `handoffRefOf(rawText !== '' ? rawText : text)` 找交接图渲染缩略图（安卓
  `chat_message_items.dart:176` 同口径）。
- `覆盖式抽屉漏边` —— 官方是**推挤式**（`docs/design-tokens.md` §4.2、`app/lib/design/tokens.dart:329`
  `drawerWidth = 288.0` / `:336` `drawerPageShift = drawerWidth`）：抽屉滑入时聊天页整体右移
  一个抽屉宽度，右缘与抽屉右缘对齐停到屏外（官方截图仍露输入框一条）。用
  `Column(){ this.chatScaffold() }.translate({ x: this.drawerOpen ? '80%' : '0%' })
  .animation({ duration: 240, curve: Curve.EaseOut })`——**用百分比不用像素**，免依赖
  screenW；`SessionsDrawer` 宽度同步改 `.width('80%')`。
- `切权限不刷投影` —— `permission` 帧只改服务端投影（`values.permissions.currentValue`），
  **不产生 chat 事件**，所以客户端不会自动重渲染。`setPermissionIn` 成功后必须显式
  `store.reloadHistory()`（同 `runCommandIn` 的收尾），否则 chip 永远停在旧档位。
- `bindContentCover 不含安全区` —— `bindContentCover` 打开的全屏模态从屏幕物理顶起算，
  不包含系统状态栏安全区（真机现象：`MdDocViewer` 顶栏标题压在状态栏下、返回键 `‹`
  只剩 16px 高）。修法：`pages/MdDocViewer.ets` 的 `aboutToAppear()` 里
  `window.getLastWindow(getContext(this)).then((win) => { const avoid =
  win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
  this.topInset = px2vp(avoid.topRect.height); })`，根 `Column` 加
  `.padding({ top: this.topInset })`。
- `image-handoff 缺 sessionId` —— bridge 的 `attachmentsAndImage()`（`lib/index.js:10731-10735`）
  强制校验 `if (!name || !sessionId) throw new ApiError(400, "BODY_INVALID", "name and
  sessionId query parameters are required.")`。`core/GatewayApi.ts` 的
  `fetchImageHandoff(name)` 只拼 name → **恒 400**，图片永远「加载失败」。修法：签名加
  `sessionId: string`，path 拼 `'&sessionId=' + GatewayApi.encodePath(sessionId)`；
  `core/ImageFetcher.ts` 里把 `const sid: string = sessionId ?? ''` 提到分支外，
  `api.fetchImageHandoff(ref.handoffName, sid)`（`fetchAttachment` 本来就传了，交接图漏了）。
  安卓 `app/lib/bridge/gateway_api.dart:140` 同款漏传，属两端共有的潜在缺陷。
- `createImageSource 要 ArrayBuffer` —— `image.createImageSource(buf)` 的重载是
  `(buf: ArrayBuffer)`；传 `Uint8Array` 类型不符，运行时返回 `undefined`，紧接着
  `src.createPixelMap()` 抛 `TypeError: Cannot read property 'createPixelMap' of
  undefined` 直接崩进程（真机：一进含图会话就闪退）。修法：`const raw: ArrayBuffer =
  bytes.buffer as ArrayBuffer; const src: image.ImageSource | undefined =
  image.createImageSource(raw);` 再判 `undefined` 走「图片解码失败」分支。
- `TTS 建引擎要探测参数` —— 真机实测同一 SDK 版本下建引擎参数容错极差：
  `{language:'zh-CN', person:0, online:0}` 报 `{"code":1002300005,"message":"create
  engine error!"}`；再补 `extraParams: {style:'interaction-broadcast', locate:'CN',
  name:'zff'}` 报 `{"code":202,"message":"this is not systemCap!"}`（`extraParams` 里
  有未声明 key 会整体校验失败）。修法：`platform/Tts.ets` 加 `probeParams()` 候选序列
  `[{zh-CN,0,online:1}, {zh-CN,1,online:1}, {zh-CN,0,online:0}, {zh-CN,1,online:0},
  {en-US,0,online:0}]`，`ensureEngine` 里逐个 `await createEngine(params)`，首个成功
  即缓存。排障手法：把 `JSON.stringify(err)` 拼进 `flash()` 提示再用 dumpLayout 读回，
  一轮拿到准确错误码（定位后记得改回固定文案）。
  **不产生 chat 事件**，所以客户端不会自动重渲染。`setPermissionIn` 成功后必须显式
  `store.reloadHistory()`（同 `runCommandIn` 的收尾），否则 chip 永远停在旧档位。


- `切界面风格不生效` —— `SettingsView` 的 `themeChip` 只写 `AppStorage.setOrCreate('dshThemeMode', mode)`
  + `PrefsStore.putString('dsh.themeMode', mode)`，但全工程没有任何地方监听这个键：
  `Index` 的 `applyTheme` 只在 `bindDarkMode()` 的 mediaquery `on('change')` 回调里被调，
  所以点「深色」chip 只会让 chip 自己变色，整页配色不动。修法：`pages/Index.ets` 加
  `@StorageProp('dshThemeMode') @Watch('onThemeModeChange') themeMode: string = 'system';`
  + 私有字段 `sysDark: boolean`（mediaquery 最近一次结果），`onThemeModeChange()` 里
  `this.applyTheme(this.sysDark)`；`bindDarkMode()` 每次回调都先存 `this.sysDark`；
  `aboutToAppear()` 里异步读回偏好：`PrefsStore.getString('dsh.themeMode').then(...)`
  再 `AppStorage.setOrCreate` + `applyTheme`。**坑**：`PrefsStore.getString` 返
  `Promise<string | null>`，直接 `?? 'system'` 会是 `string | Promise<string>`，
  ArkTS 报 `10505001 Declaration or statement expected` 类错（实际信息是
  `Type '"system" | Promise<string>' is not assignable to type 'string'`），必须进 then。
  真机验证：设置页点「深色」→ 整页转深色；重启后保持。
- `应用更新走市场` —— 鸿蒙应用只能由华为应用市场分发，系统不允许应用自更新；照搬安卓
  `core/ReleaseCheck.ts` 的 Gitee→GitHub Release 检查既拿不到鸿蒙包也不合规。用户
  2026-11-16 要求改口径：`pages/SettingsView.ets` 的 `checkUpdate` 改调
  `@kit.AppGalleryKit` 的 `updateManager.checkAppUpdate(ctx)`（`updateAvailable === 1`
  即 `UpdateAvailableCode.LATER_VERSION_EXIST`），有新版时点「检查更新」调
  `updateManager.showUpdateDialog(ctx)` 由系统弹官方更新对话框。ctx 取
  `this.getUIContext().getHostContext() as common.UIAbilityContext`。错误码
  1009400001 SA 连接失败 / 1009400002 请求异常 / 1009400003 网络 / 1009400004 不在前台 /
  1009400005 未同意隐私协议 / 1009400006 限频 / 1009400007 其它，映射在
  `core/AppUpdate.ts` 的 `updateErrorMessage()`（纯函数，node 直测）。`ReleaseCheck.ts`
  保留给安卓侧与历史测试，鸿蒙入口不再引用（`projections-release.test.ts` 已移除相关用例）。
  真机验证：点「检查更新」→「已是最新版本」（本机为调试签名、未上架，市场仍回 0）。
- `会话列表时间优先` —— 用户 2026-11-16 口径：抽屉列表**先按时间、再按工作区**排，
  超过 2 天的会话收进可折叠「更早」。安卓 `app/lib/ui/session_groups.dart` 已同口径
  （a91c1d9：`groupSessionsByTime` 今天/昨天/更早 + 桶内工作区聚簇），两端一致。
  实现：`core/SessionGroups.ts` 纯函数 —— `dayBucketOf(updatedAt, nowMs)` 按**本地日历天**
  分桶（用 `new Date(y,m,d).getTime()` 比零点，避免 23:59/00:01 跨天误判；`updatedAt<=0`
  归更早）、`groupSessionsByTime(sessions, nowMs)` 产出 今天/昨天/更早 三组、组内先按
  `updatedAt` 倒序再用 `workspaceLabelOf` 把同工作区聚成连续小节（`SessionRow.sectionLabel`
  首行非空、后续空串，抽屉据此只显示一次小节名）、`visibleRowsOf(group, earlierOpen)`
  处理收起态；`COLLAPSE_AFTER_DAYS = 2`、`GROUP_KEY_EARLIER = 'earlier'`。
  `components/SessionsDrawer.ets` 用 `@State groupsView: SessionGroup[]`
  （`syncVersion()` 里 `groupSessionsByTime(this.sessionsView, Date.now())`）+ `@State earlierOpen`
  （点分组标题切换），`ForEach(this.groupsView)` → `ForEach(this.rowsOf(g))`。
  真机验证：抽屉显示「今天 / workspace / 未分组 / 手机会话」多层小节，滚到底「更早 28 条 · 展开」，
  点一下变「28 条 · 收起」并展开。

**阶段 4 已记偏差（2026-11-16）**：①@s 文件补全多根下钻/删除确认照搬；②设置页「字号跟随系统」开关与 Slider 鸿蒙版延后阶段 5（fontScale 真机定）；③诊断日志开关不移植（Dlog.ets hilog 直写不落文件）；④子会话历史页（subagent_history_page）与 subagentHistory REST 已有，入口延后阶段 5；⑤会话目录选择（session_location_sheet）延后阶段 5；⑥表格下载/展开、推挤抽屉动画、自绘品牌标延后。
