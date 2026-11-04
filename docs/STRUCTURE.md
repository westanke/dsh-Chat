# STRUCTURE — dsh-Chat

> 宪法 §8 要求：lib/ 下文件增删与结构变更，**同提交**更新本表。

## docs/（平铺）

| 文件 | 用途 |
|---|---|
| `design-tokens.md` | 设计基准（官方 Web token + App 实测像素），token 单一事实来源 |
| `STRUCTURE.md` | 本文件 |

## app/lib/

| 文件 | 用途 | 状态 |
|---|---|---|
| `main.dart` | 入口：DshLog 初始化、主题装配（三档 / 字号缩放由 `AppSettings` 驱动）、**中文本地化（flutter_localizations + locale zh，TextField 长按菜单中文，第二轮反馈 D）**、自动连接（凭证持久化）、路由（连接页 ⇄ 聊天页 ⇄ 设置页） | ✅ 装机验证 |
| `design/tokens.dart` | DsPalette / DsColors / DsTypography / DsSpacing / DsMotion —— 全部样式值唯一出口（§4.4 设置页、§4.6 FAB/滚动动效 token） | ✅ |
| `design/app_settings.dart` | 本地偏好 `AppSettings`（界面风格三档 / 字号缩放 / 跟随系统 / 繁忙发送模式 / 诊断日志）+ `AppFontScaler`（与系统字号相乘的 TextScaler）；枚举按 name 持久化，凭据分库 | ✅ 单测覆盖 |
| `bridge/models.dart` | SessionEvent / ChatMessage（含 `images` 图片引用）/ DshSession / DshWorkspace / MessageDelta / MessageCommitted / HistoryPage（含 `turn/end` 失败解析；`rawEvents` 归一化原始事件 + `projections` 透传首屏投影 + `hasMore` 真值）；re-export `tool_call.dart` / `content.dart` | ✅ 单测覆盖 |
| `bridge/content.dart` | content 部件模型（从 models.dart 拆出，控行数）：`ContentParts`（text/reasoning + `images` 图片引用解析）/ `ContentImageRef` / `PromptPart` / `handoffImageNameOf`（`[Image: source: …]` 交接占位提取） | ✅ 单测覆盖 |
| `bridge/projections.dart` | 纯 Dart 投影解析：`trajectoryOf()` 客户端按 data.turn 分组原始事件（轨迹 Sheet）；`todoItems()` / `agentTeamProjectionOf()` 读服务端 `projections.values.*`（团队 / TODO）；全部容忍投影缺席 | ✅ 单测覆盖 |
| `bridge/tool_call.dart` | ToolCallInfo + 工具措辞表 `toolPhrases` + 摘要 `toolSummary` + `RawToolCall` / `extractToolCalls`（从 models.dart 拆出，控行数） | ✅ 单测覆盖 |
| `bridge/gateway.dart` | WS `/ws/mobile`：子协议 `dsh-mobile-v1`、hello.protocol=3、requestId（**data 内回显**）、退避重连 1→2→4→8→16s、心跳 25s（连接面本体；业务封装拆 `gateway_api.dart`，事件模型拆 `gateway_events.dart`，均 re-export，消费方只 import 本文件） | ✅ 装机验证 |
| `bridge/gateway_events.dart` | 从 gateway.dart 拆出（宪法 §7 控行数）：`GatewayState` / `GatewayEvent` sealed（Delta/Committed/TurnFailed/Resync/SessionEventReceived）/ `RequestException` | ✅ |
| `bridge/gateway_api.dart` | 从 gateway.dart 拆出：`extension GatewayApi on GatewayClient`——workspaces/sessions/**session-create（workspaceId 预建会话）**/directory-create/REST 建改工作区/history（`beforeSeq` 翻页 + `hasMore` 真值）/attachments 与 image-handoff 取图/sendText(mode+contentParts)/cancelTurn/permission/models/commands/**command-execute**/select-model | ✅ 单测覆盖 |
| `bridge/gateway_http.dart` | REST 字节下载 `gatewayHttpBytes()`（GET + Bearer + 30s 超时，附件/交接图共用） | ✅ |
| `bridge/gateway_rest.dart` | REST JSON 顶层函数：`gatewayCreateWorkspace()`（POST /chat/workspaces，path=根内相对路径）/ `gatewayRenameWorkspace()`（PATCH，落「手机会话」组名） | ✅ |
| `bridge/questions.dart` | HITL 模型：`UserQuestion`/`UserQuestionOption`/`PendingQuestion`（userQuestions/requested 收敛，callId 去重键）/ `PendingApproval`（approval.requested）/ `QuestionAnswerItem`（question-answer 载荷，custom 空省略） | ✅ 单测覆盖 |
| `bridge/credentials.dart` | shared_preferences 持久化 `{baseUrl, token}`，实现「一次配对，此后自动连接」 | ✅ |
| `bridge/hosts.dart` | 主机记录库 `DshHosts`（shared_preferences 单键 `dsh.hosts` JSON 数组，FNV-1a 幂等 id）+ DSH1 配置文本宽容解码 `decodeDsh1`（companion ConnectionShare 口径：前缀任意位置/双字母表/补填充/失败返回 null） | ✅ 单测覆盖 |
| `bridge/permissions.dart` | 权限档位目录 `PermissionCatalog`/`PermissionOption`（permission-options 应答收敛 + value→中文标签映射 + `parsePermissionCatalog`），档位以服务端清单为准不硬编码 | ✅ 单测覆盖 |
| `bridge/models_view.dart` | 会话模型视图 `SessionModels`/`ModelProviderGroup`/`ModelView`/`ModelSelection`（models 应答收敛 + `parseSelectModelReply` 按 `data.type` 判别 sent + `reasoningEffortLabel`），effort 枚举以服务端 efforts 为准 | ✅ 单测覆盖 |
| `bridge/device.dart` | MethodChannel `dsh/device#ianaZone` → IANA 时区（clientTimeZone 必需 `Area/Location`） | ✅ |
| `bridge/platform.dart` | MethodChannel `dsh/platform`：系统 TTS 朗读（speak/stopSpeak）+ 系统分享（share）+ 系统选图器（pickImage→缓存路径）+ **系统下载器下载 APK（downloadApk 返回任务 id + downloadStatus 轮询进度 + installApk 拉起安装，第二轮反馈 C）**，零第三方依赖；Android MainActivity 实现，iOS 留桩走「暂不可用」提示 | ✅ |
| `bridge/release_check.dart` | 新版本检测：`fetchLatestRelease()` 先 Gitee 后 GitHub 拉 releases/latest（8s 超时各一次），`ReleaseInfo` 挑 `dsh-Chat-*.apk` 资产，`isNewerVersion` 语义化三段比较（真机反馈第 9 项） | ✅ 单测覆盖 |
| `bridge/dlog.dart` | 文件日志 `/data/data/<pkg>/files/dsh.log`（vivo 过滤 flutter 日志，只能落文件）；`enabled` 开关 + `read()` 供设置页诊断日志区 | ✅ |
| `ui/chat_page.dart` | 聊天主页：顶栏（会话名 + 新对话加号接 `newChat` + ⋯ 溢出菜单） / 空态问候 / 设置页入口；消息列表与消息项拆成同库 `part`（宪法 §7 控行数） | ✅ 装机验证 |
| `ui/chat_message_list.dart` | `part of chat_page.dart`：消息列表 + 跳转最新 FAB + 滚动冻结 / 贴底跟随（`wantsBottom` 粘性意图、80ms 解冻、140ms 渐显）；判据在 `scroll_follow.dart` | ✅ 单测覆盖 |
| `ui/chat_message_items.dart` | `part of chat_page.dart`：消息项（双击复制整条；用户气泡内嵌历史图片 `DsChatImage`；助手消息 image-handoff 占位转图）/ 流式项 / 思考块折叠 / 消息操作条（重新生成接线） | ✅ 装机验证 |
| `ui/chat_image.dart` | 历史图片组件 `DsChatImage`：attachment / image-handoff 双通道自动下载（`gatewayImageFetcher(gateway, sessionId)` 注入，attachments 接口必填 sessionId query，随会话切换刷新）+ 进程内字节缓存 + 失败占位可点重试（真机反馈 2026-11-04 第 1 项） | ✅ 装机验证 |
| `ui/scroll_follow.dart` | 滚动跟随纯函数：`shouldAutoFollow` / `shouldShowFab` / `computeAtBottom` / `freezeSnapshot` / `isUserScrollGesture`（只认 dragDetails），对照 companion 三处滚动实现 | ✅ 单测覆盖 |
| `ui/chat_state.dart` | ChangeNotifier：会话列表 / 打开会话 / 发送（纯文本与带图；新会话先经 `ensureMobileWorkspace` 预建到「手机会话」工作区）/ 斜杠命令 `runCommand()`（command-execute）/ `cancelTurn()` / `regenerateAt()` / `retryLast()` / 历史翻页 `loadOlder()`（beforeSeq + seq 去重）/ 流式累积 / 推送分发（含 HITL 问答/审批事件转发到 `HitlState`）/ HITL 动作 `answerQuestion()`/`cancelQuestion()`/`decideApproval()`；分组 getter 委托 `session_groups.dart` | ✅ 装机验证 |
| `ui/hitl_state.dart` | HITL 挂起表 `HitlState`（全连接 pendingQuestions/pendingApprovals 按 callId/approvalId 去重 + 会话过滤 getter + answer/cancel/decide 动作；从 chat_state.dart 拆出控行数） | ✅ 单测覆盖 |
| `ui/question_card.dart` | `HitlPanel`：提问卡（每题 FilterChip 单/多选 + 自定义回答输入 + 提交键，提交走 question-answer）与审批卡（允许一次 / 拒绝，approval-response） | ✅ 单测覆盖 |
| `ui/session_groups.dart` | 会话抽屉分组纯函数 `groupSessionsByWorkspace()`：顶层按工作区分（「手机会话」置顶、其余用 workspace title、无工作区「未分组」），组内按今天/昨天/更早；单工作区单日期退化为纯日期（真机反馈第 7 项） | ✅ 单测覆盖 |
| `ui/mobile_workspace.dart` | 「手机会话」工作区准备 `ensureMobileWorkspace()`：title 含「手机」的既有工作区 → 建目录 `.dsh-mobile`（directory-create，409 幂等）→ REST 登记工作区 → PATCH 改名「手机会话」；失败回 null 不阻断发送（真机反馈第 7 项） | ✅ |
| `ui/stats_sheet.dart` | 会话统计 Sheet：`chatStatsOf()` 由已加载消息本地计算（消息/工具/思考/错误数），零网络请求；对照 companion ChatStatsSheet | ✅ 单测覆盖 |
| `ui/projection_sheets.dart` | 三个零请求面板：运行轨迹（rawEvents 本地分组、点节点展开原始 JSON）/ 智能团队（projections.values.agentTeam，含三枚普通消息话术 chips）/ 待办任务（projections.values.todos）；投影缺席显示空态而非隐藏入口 | ✅ 单测覆盖 |
| `ui/settings_page.dart` | 设置页主文件：Scaffold + 分区骨架（`settings_sections.dart` / `settings_widgets.dart` / `settings_update.dart` 是同库 `part`，共享私有成员，宪法 §7 控行数） | ✅ 单测覆盖 |
| `ui/settings_sections.dart` | 设置页分区：连接与设备信息（hello 只读）/ 界面风格三档 / 字号缩放与跟随系统 / 繁忙发送模式 / 诊断日志 / 关于（含检查更新行）/ 断开连接；不摆无授权的服务端开关 | ✅ 单测覆盖 |
| `ui/settings_update.dart` | `part of settings_page.dart`：`_UpdateCheckRow` 检查新版本（1.5s 静默检查有新版才提示；手动检查三态：发现新版本→点按下载 / 已是最新 / 两站都连不上；下载轮询进度百分比 + STATUS_SUCCESSFUL 后 installApk 自动拉起安装，第二轮反馈 C；`Timer` 必须 dispose 取消，测试断言无 pending timer） | ✅ 单测覆盖 |
| `ui/settings_widgets.dart` | 设置页通用组件：`_Section` / `_InfoRow` / `_ActionRow` / `_SwitchRow` / `_SegmentedRow` / `_ScopeChip` / `_WarningBanner` | ✅ 单测覆盖 |
| `ui/composer.dart` | 输入条：白浮层圆角容器 + 输入框 + 权限档位 chip + 图片附件 chip 与发送（8MiB 上限；单发图片也亮发送键）+ **「/」斜杠命令面板**（`parseSlashDraft` 检测草稿 → commands 帧清单前缀过滤 → 浮层建议 → 点选回填；发送优先走 `onCommand`）+ 发送键三态 + **加图按钮常驻（先打字也能加图，第二轮反馈 D）** + 底部免责提示（命令面板组件拆 `composer_widgets.dart`） | ✅ 装机验证 |
| `ui/composer_widgets.dart` | `part of composer.dart`：`_Chip` / `_RoundIconButton` / `_CommandPanel`（斜杠命令建议浮层，最多 6 条） | ✅ |
| `ui/connect_page.dart` | 连接页三级路径：历史主机点击直连（DshHosts，有 token 才显示、失败显式报错）+ DSH1 配置文本导入（decodeDsh1，有 token 直连/无 token 填表）+ 手动配对（bridge 地址 + 配对码）；成功都 upsert 主机记录 | ✅ 装机验证 |
| `ui/md_view.dart` | GptMarkdown 定制：官方 token 全量映射、任务列表预处理、codeBuilder/tableBuilder 接线 | ✅ 装机验证 |
| `ui/md_code_block.dart` | 自绘代码块：Atom One Light（ValTheme 自定义）+ banner「语言名 / 复制」 | ✅ 装机验证 |
| `ui/md_table.dart` | 自绘表格：banner「表格 + 复制/下载/展开」+ 官方 #fafafa 底 + #dcdcdc 线 | ✅ 装机验证 |
| `ui/message_actions.dart` | 助手消息操作条：复制 / 喜欢 / 朗读（系统 TTS）/ 分享（系统分享面板）+ 右侧重新生成接线；平台不支持时明确提示（点踩按真机反馈 2026-11-04 移除） | ✅ 装机验证 |
| `ui/process_group.dart` | 工具调用折叠组：折叠一行「执行了命令，读取了图片…」，点开展开逐条明细，再点单条看完整详情（bash 命令按 BASH 代码块 `DsCodeBlock` 语法高亮展示、其余工具纯文本参数 / 输出 / 耗时 / 错误，真机反馈第 6 项） | ✅ 装机验证 |
| `ui/model_sheet.dart` | 模型选择面板：models 帧拉分组清单，**按供应商分组可折叠（默认只展开当前供应商，折叠组若含当前选中模型显示一行提示）**→ select-model 帧确认切换 → 重拉 history；routable=false / failures 有值时显式提示（真机反馈第 4 项） | ✅ 单测覆盖 |
| `ui/sessions_drawer.dart` | 侧边会话抽屉：胶囊搜索框 + 分组列表（组名来自 `session_groups.dart`：工作区置顶分组）+ 纯文字条目 + 底部栏（设置圆钮 + 设备名 + 绿点连接指示 + `connectionLabel` 地址，真机反馈第三轮 3） | ✅ 装机验证 |
| `ui/chat_message_list.dart` | `part of chat_page.dart`：消息列表 + 跳转最新 FAB + **列表头「加载更早消息」按钮（`historyHasMore` 控制，翻页中转圈；翻页 prepend 后经 `historyPageJustLoaded` 跳过一次贴底跟随，保住阅读位置，第二轮反馈 A）** + **整表 `SelectionArea` 包裹（长按可选字复制，第二轮反馈 E）** + 滚动冻结 / 贴底跟随；判据在 `scroll_follow.dart` | ✅ 单测覆盖 |
| `ui/brand_mark.dart` | 空态品牌标记 DsBrandMark（`_WhalePainter` 原创 Path 绘制：圆身 + 双瓣尾鳍 + 月牙腹部 + 眼睛），不引用官方素材 | ✅ 装机验证 |

## 平台侧（框架通道与清单）

| 文件 | 用途 |
|---|---|
| `app/android/app/src/main/kotlin/.../MainActivity.kt` | MethodChannel `dsh/device#ianaZone`（Android IANA 时区）+ `dsh/platform`（系统 TTS speak/stopSpeak + 系统分享 share + 系统选图器 pickImage→缓存复制 + **DownloadManager：downloadApk 返回任务 id / downloadStatus 查询进度 / installApk 经 getUriForDownloadedFile 拉起安装器（FLAG_GRANT_READ_URI_PERMISSION），第二轮反馈 C**，TextToSpeech 惰性初始化、onDestroy shutdown） |
| `app/android/app/src/main/AndroidManifest.xml` | `INTERNET` 权限 + `REQUEST_INSTALL_PACKAGES`（应用内更新拉起安装器，第三轮反馈 2）+ `usesCleartextTraffic`（bridge 走 ws:// 明文）+ queries 包可见性（PROCESS_TEXT + apk mime 的 ACTION_VIEW） |
| `app/ios/Runner/AppDelegate.swift` | 同款 `dsh/device#ianaZone` 通道（iOS `TimeZone.current.identifier`） |
| `app/ios/Runner/Info.plist` | 显示名 DSH Chat + ATS 放行明文 + 本地网络用途说明 |

## app/test/

| 文件 | 覆盖 |
|---|---|
| `app_settings_test.dart` | `normalizeFontScale`（NaN/Inf/越界夹取）、`AppFontScaler` 与系统字号相乘、`AppSettings` 默认值与 `effectiveFontScale` |
| `settings_page_test.dart` | 设置页渲染：界面风格三档 / 繁忙发送模式两档 / 字号滑块与跟随系统 / 诊断日志开关均真实生效 |
| `chat_actions_test.dart` | `chatStatsOf()` 本地统计、`Composer` 发送键三态、`ChatState.regenerateAt/retryLast` 重发用户消息 |
| `scroll_follow_test.dart` | `shouldAutoFollow` 粘性意图自锁回归、`shouldShowFab` / `computeAtBottom` / `freezeSnapshot` 空表 / `isUserScrollGesture` 程序滚动不算手势 |
| `projections_test.dart` | `trajectoryOf()` 按 turn 分组 / 组内 seq 排序 / 丢弃过程细节 / 未知轮次垫底；`todoItems()` 只认 `{content,status}`；`agentTeamProjectionOf()` 缺省回退与空壳 null；`HistoryPage` 保留原始事件与投影 |
| `hosts_test.dart` | `DshHost` stableId 幂等 / round-trip（token 缺省不发键）；`decodeDsh1` 宽容解码（前缀前说明文字/换行/结尾标点/大小写不敏感）与垃圾输入一律 null |
| `permissions_test.dart` | 权限档位：`PermissionOption`/`PermissionCatalog` 解析与中文标签（未知回退）、`custom` 过滤、round-trip；`SessionModels`/`parseSelectModelReply`（sent 按 `data.type` 判别）/`reasoningEffortLabel` |
| `models_test.dart` | 协议模型 round-trip、`data.message.content` 提取、注入上下文过滤（`source.kind != user`）、displayTitle 兜底、工具调用措辞表（含 read_image 等中文名）/ 摘要 / `toolResultText` / 过程组合并去重与耗时（result 正文进 `ToolCallInfo.resultText`）/ `turn/end` 失败 → `role=error` |
| `md_view_test.dart` | MD 全家福 / 超长表格**不溢出**（360dp 宽，断言 `takeException() == null`） |
| `widget_test.dart` | 冷启动进连接页 |
| `brand_mark_test.dart` | 空态品牌标记尺寸 = token |
| `render_mark_test.dart` | 离屏导出品牌标记 PNG（`ref/mark-preview.png`） |
| `render_md_test.dart` | 离屏导出 MD 全家福 PNG（`ref/md-preview.png`） |

## app/tool/

| 文件 | 用途 |
|---|---|
| `tool/verify_groups.dart` | 宿主侧校验脚本：读 `ref/hist-demo.json` 跑 `HistoryPage.fromEvents`，打印用户/过程组/助手三段结构 |
| `tool/verify_err.dart` | 宿主侧校验脚本：读 `ref/hist-err.json`，确认 `turn/end` 失败被解析成 `role=error` 消息 |

## bridge 协议引用

- 消费对象：`dsh-remote-bridge` v2.10.0，协议 `dsh-mobile-v1`，hello.protocol=3。
- 事实来源：`/media/wangke/OFFICE/workspace/dsh-remote-bridge/docs/api/`（openapi/asyncapi）
  + `docs/project/API.md` §客户端→服务端帧。
- 用到的帧：`ping/subscribe/unsubscribe/message/workspaces/sessions/history/hello`
  （`message.mode` 由本地偏好取 `queue` 或 `steer`，对照 companion 的繁忙发送策略；
  `history` 首屏应答的可选 `projections.values.{todos,agentTeam,subagentCatalog,permissions}` 供
  团队 / TODO 面板与权限 chip 只读展示，轨迹面板则由 `events` 客户端本地分组）；
  `session-cancel`（停止当前回合，应答 `session-cancelled` 会回显 requestId，可 await）；
  `permission-options`（权限档位清单）与 `permission`（切档位，内部走 `/permission` 斜杠命令）；
  `models`（会话模型分组清单，sessionId 必需）与 `select-model`
  （切模型，应答 kind=`sent` 须按 `data.type=='select-model'` 判别）；
  `commands` / `command-execute`（斜杠命令清单与执行，真机反馈第 3 项）；
  `session-create`（带 workspaceId 预建会话，真机反馈第 7 项）与 `directory-create`（建 `.dsh-mobile` 目录，409 幂等）；
  推送：`event(chat.message.delta|chat.message.committed|chat.turn.failed)`、
  `connection-resync-required`、`question-requested`。
- REST：`GET /api/v1/attachments/{id}` 与 `GET /api/v1/image-handoff`（取图，真机反馈第 1/8 项）、
  `POST /api/v1/chat/workspaces` 与 `PATCH /api/v1/chat/workspaces/{id}`（工作区登记/改名，真机反馈第 7 项）、
  Gitee/GitHub `releases/latest`（版本检测，真机反馈第 9 项）。

### 踩过的协议坑（勿重犯）

1. **requestId 在 `data` 里，不在帧顶层** —— `ws-protocol.ts:611` 的 `withRequestIdEcho`
   返回 `{...frame, data:{...record, requestId}}`。只读 `frame['requestId']` 会导致
   所有 `request()` 永不 resolve（30s 超时），但消息本身已送达。
2. **`subscribed` 帧不回显 requestId**（在 `REQUEST_ID_ECHO_EXCLUDED_KINDS` 排除表里）→
   `subscribe` 必须 fire-and-forget，不能 await。
3. **空态会收到别的会话的推送**（bridge「连接即重放」活跃会话）→ 必须用
   `sessionId != null && (sid == sessionId || sid == pendingSessionId)` 过滤，否则串台。
4. **`clientTimeZone` 必须是 IANA `Area/Location`**（正则要求带 `/`），Dart 的
   `timeZoneName` 在 Android 返回 `CST` → 走 MethodChannel 取 `TimeZone.getDefault().id`。
5. **`user/message` 带 `data.source.kind`**（`user` / `runtime-context` / `skill-catalog` /
   `time-context`），注入上下文也记成 user/message → 只显示 `kind == 'user'`。
6. **`assistant/message` 的 content 在 `data.message.content`**，`user/message` 在
    `data.content`。
7. **`history` 首屏应答的 `projections` 是可选字段**：内核没给基线时整个字段缺席
    （不是空对象），且只在首屏带、翻页不带（`API.md:165,766`）。`GatewayClient.history()`
    原样透传，UI 必须容忍 null/缺席，不能把「读不到投影」当成「没有这个功能」
    （v2.2.44 真机踩过，会做出永不渲染的入口）。
