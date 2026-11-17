# STRUCTURE — dsh-Chat

> 宪法 §8 要求：lib/ 下文件增删与结构变更，**同提交**更新本表。

## docs/（平铺）

| 文件 | 用途 |
|---|---|
| `design-tokens.md` | 设计基准（官方 Web token + App 实测像素），token 单一事实来源 |
| `STRUCTURE.md` | 本文件 |
| `feedback-2026-11-04-report.md` | 真机反馈 8 条调查报告（模板） |
| `huawei-heic-upload-report.md` | 华为手机 HEIC 图片无法上传调查报告（根因 / 内核 4 种白名单一手证据 / 魔数嗅探+转码修法 / 验证边界 / 外部来源索引） |
| `connect-host-remove-report.md` | 连接页历史主机无删除功能调查报告（记录库缺单条删除 / 卡片删除按钮+二次确认 / 失效记录入口 / 凭证清理 / 验证边界与回归项） |

## app/lib/

| 文件 | 用途 | 状态 |
|---|---|---|
| `main.dart` | 入口：DshLog 初始化、主题装配（三档 / 字号缩放由 `AppSettings` 驱动）、**中文本地化（flutter_localizations + locale zh，TextField 长按菜单中文，第二轮反馈 D）**、自动连接（凭证持久化）、路由（连接页 ⇄ 聊天页 ⇄ 设置页） | ✅ 装机验证 |
| `design/tokens.dart` | DsPalette / DsColors / DsTypography / DsSpacing / DsMotion —— 全部样式值唯一出口（§4.4 设置页、§4.6 FAB/滚动动效 token） | ✅ |
| `design/app_settings.dart` | 本地偏好 `AppSettings`（界面风格三档 / 字号缩放 / 跟随系统 / 繁忙发送模式 / **工作步骤展示四档 `WorkStepsDetail` / 收起时机 `CollapseTiming` / 收起后显示的回复 `FoldedReplies` / 显示代码工作视图 `codeWorkView`——2026-11-16 官方通用设置批次，枚举持久化存官方 token 字符串（`jsonName`，如 `next-input`），未知名回默认；`WorkStepsDetailPolicy` 派生 policy（stepGrouping/liveProcessDetail/settledReasoningPreview/foldCompletedTurns，不持久化——2026-11-17 工具调用展示批次）** / 诊断日志）+ `AppFontScaler`（与系统字号相乘的 TextScaler）；凭据分库 | ✅ 单测覆盖 |
| `bridge/models.dart` | DshSession（含 `cwd` WirePath 相对路径 = 会话目录；**可选 `agentPreset` 记桥端当前 Agent 预设 id——openapi §ChatSession.agentPreset，空白会话可 PUT 切换、首条消息后锁定**）/ DshWorkspace / MessageDelta / MessageCommitted（**`hasReplyContent` 标记 assistant 消息是否真有正文——桥 e08b6b5，内核工具执行前先提交只含 tool-call 块的无正文消息；老桥缺省 true 兼容**）（openapi §ChatSession/§ChatWorkspace，asyncapi §ChatMessageDelta/§ChatMessageCommitted）；目录选择模型 `SessionLocation`{rootId?,cwd,label} / `DshFileEntry` / `DshDirectoryPage`（2026-11-15 新建会话可选目录）；历史装配四件套拆 `history_page.dart`，经 export 继续暴露 | ✅ 单测覆盖 |
| `bridge/history_page.dart` | 从 models.dart 拆出（宪法 §7 控行数）：`SessionEvent`（内核历史事件透传）/ `DeliverableFile`（文件卡）/ `ChatMessage`（含 `images`/`files` 引用）/ `HistoryPage`（`rawEvents` 归一化 + `projections` 透传投影 + `hasMore` 真值；fromEvents 含 `turn/end` 失败解析；deliverables 文件卡**暂存挂轮尾**——`pendingFileCards` + `flushFileCards()`，flush 点 = user/message、turn/end、事件流末尾，2026-11-14 落位修复） | ✅ 单测覆盖 |
| `bridge/content.dart` | content 部件模型（从 models.dart 拆出，控行数）：`ContentParts`（text/reasoning + `images` 图片引用解析）/ `ContentImageRef` / `PromptPart` / `handoffImageNameOf`（`[Image: source: …]` 交接占位提取）/ `parseAtMentionDraft`（@ 文件引用草稿解析——光标前最近 `@片段`，含替换区间与 @ 边界判定，m03878） | ✅ 单测覆盖 |
| `bridge/projections.dart` | 纯 Dart 投影解析：`trajectoryOf()` 客户端按 data.turn 分组原始事件（轨迹 Sheet）；`todoItems()` / `agentTeamProjectionOf()` 读服务端 `projections.values.*`（团队 / TODO）；全部容忍投影缺席 | ✅ 单测覆盖 |
| `bridge/tool_call.dart` | ToolCallInfo + 工具措辞表 `toolPhrases` + 摘要 `toolSummary` + `RawToolCall` / `extractToolCalls`（从 models.dart 拆出，控行数） | ✅ 单测覆盖 |
| `bridge/gateway.dart` | WS `/ws/mobile`：子协议 `dsh-mobile-v1`、hello.protocol=3、requestId（**data 内回显**）、退避重连 1→2→4→8→16s、心跳 25s（连接面本体；业务封装拆 `gateway_api.dart`，事件模型拆 `gateway_events.dart`，均 re-export，消费方只 import 本文件）；`chat.deliverables.presented` 实时帧转 `SessionEventReceived('deliverables/presented')` 触发防抖重拉（2026-11-14）；**`chat.turn.start`/`chat.turn.end` 帧转 `TurnStartedEvent`/`TurnEndedEvent`（reason.kind 宽容解析，2026-11-17）** | ✅ 装机验证 |
| `bridge/gateway_events.dart` | 从 gateway.dart 拆出（宪法 §7 控行数）：`GatewayState` / `GatewayEvent` sealed（Delta/Committed/**TurnStarted/TurnEnded**/TurnFailed/Resync/SessionEventReceived/ToolCall/ToolResult）/ `RequestException` | ✅ |
| `bridge/gateway_api.dart` | 从 gateway.dart 拆出：`extension GatewayApi on GatewayClient`——workspaces/sessions/**session-create（workspaceId 预建）与 `createSessionAt({rootId,cwd})`（自选目录预建，失败显式报错勿静默回退）**/directory-create/**`listDirectory()`（file-list 帧目录浏览 → DshDirectoryPage）**/REST 建改工作区/history（`beforeSeq` 翻页 + `hasMore` 真值）/attachments 与 image-handoff 取图/sendText(mode+contentParts)/cancelTurn/permission/models/commands/**command-execute**/select-model/**`agentPresets()` 与 `selectAgentPreset(sessionId, presetId)`（Agent 预设清单与空白会话切换——2026-11-16 通用设置批次，409=AGENT_PRESET_LOCKED）** | ✅ 单测覆盖 |
| `bridge/gateway_http.dart` | REST 字节下载 `gatewayHttpBytes()`（GET + Bearer + 30s 超时，附件/交接图共用） | ✅ |
| `bridge/gateway_rest.dart` | REST JSON 顶层函数：`gatewayCreateWorkspace()`（POST /chat/workspaces，path=根内相对路径）/ `gatewayRenameWorkspace()`（PATCH，落「手机会话」组名）/ **`gatewayResolvePath()`（GET /roots/resolve 解析 deliverables 绝对路径 → ResolvedFile{rootId,path,size,contentType}）+ `gatewayReadFileBytes()`（GET /roots/{rootId}/content 取文件字节，m03452 文件卡打开用）** + **`gatewayListRoots()`（GET /roots 授权根清单 → GatewayRoot）/ `gatewayListEntries()`（GET /roots/{rootId}/entries 目录懒分页 → GatewayEntry，目录优先排序——m03878 @ 文件补全用）** + **`gatewayAgentPresets()`（GET /chat/agent-presets → GatewayAgentPreset{id,name,description,trust,isDefault,available}）/ `gatewaySelectAgentPreset()`（PUT /chat/sessions/{sid}/agent-preset，200 回显 `agentPreset`、409=锁定——2026-11-16 通用设置批次，代码工作视图用）** | ✅ |
| `bridge/questions.dart` | HITL 模型：`UserQuestion`/`UserQuestionOption`/`PendingQuestion`（userQuestions/requested 收敛，callId 去重键）/ `PendingApproval`（approval.requested）/ `QuestionAnswerItem`（question-answer 载荷，custom 空省略） | ✅ 单测覆盖 |
| `bridge/credentials.dart` | shared_preferences 持久化 `{baseUrl, token}`，实现「一次配对，此后自动连接」 | ✅ |
| `bridge/hosts.dart` | 主机记录库 `DshHosts`（shared_preferences 单键 `dsh.hosts` JSON 数组，FNV-1a 幂等 id；`load/upsert/remove/clear`，remove 按 baseUrl 优先+非空 id 兜底、删空写 `[]`）+ DSH1 配置文本宽容解码 `decodeDsh1`（companion ConnectionShare 口径：前缀任意位置/双字母表/补填充/失败返回 null） | ✅ 单测覆盖 |
| `bridge/permissions.dart` | 权限档位目录 `PermissionCatalog`/`PermissionOption`（permission-options 应答收敛 + value→中文标签映射 + `parsePermissionCatalog`），档位以服务端清单为准不硬编码 | ✅ 单测覆盖 |
| `bridge/models_view.dart` | 会话模型视图 `SessionModels`/`ModelProviderGroup`/`ModelView`/`ModelSelection`（models 应答收敛 + `parseSelectModelReply` 按 `data.type` 判别 sent + `reasoningEffortLabel`），effort 枚举以服务端 efforts 为准 | ✅ 单测覆盖 |
| `bridge/device.dart` | MethodChannel `dsh/device#ianaZone` → IANA 时区（clientTimeZone 必需 `Area/Location`） | ✅ |
| `bridge/platform.dart` | MethodChannel `dsh/platform`：系统 TTS 朗读（speak/stopSpeak）+ 系统分享（share）+ 系统选图器（pickImage→缓存路径 **+ 真实 mediaType；失败回 {error: 中文原因} 不再静默 null，华为 HEIC 修复**）+ **系统打开文件（openFile：字节写缓存目录 FileProvider + ACTION_VIEW，m03452 文件卡用）**+ **系统下载器下载 APK（downloadApk 返回任务 id + downloadStatus 轮询进度 + installApk 拉起安装，第二轮反馈 C）**+ **appVersion（读 gradle versionName/longVersionCode，Flutter 工具链从 pubspec version 自动注入，成功缓存、失败回 null 降级；2026-11-15 发版号漂移修复）**，零第三方依赖；Android MainActivity 实现，iOS 留桩走「暂不可用」提示 | ✅ |
| `bridge/image_media_type.dart` | 图片真实类型纯 Dart 判据（华为 HEIC 修复）：`supportedImageMediaTypes`（内核内联 prompt 只收 4 种，源自 dsh-attachment-local `imageLimits.mediaTypes`）/ `isSupportedImageMediaType` / `mediaTypeExtension` / `sniffImageMediaType`（字节魔数嗅探，与 bridge `image-handoff.ts` 的 `sniffMediaType` 同表：PNG/JPEG/GIF/WEBP/BMP/HEIC/AVIF）；供 composer 兜底核对原生回传，平台无关 | ✅ 单测覆盖 |
| `bridge/release_check.dart` | 新版本检测：`fetchLatestRelease({http.Client? client})` 先 Gitee 后 GitHub 拉 releases/latest（8s 超时各一次），`ReleaseInfo` 挑 APK 资产（**小写前缀 `dsh-chat-` / `dshchat-` 两种历史命名都放行，2026-11-15：sync-gitee-release.sh 产物 dshchat-* 之前被过滤导致远端 v1.0.14 识别不到**），`isNewerVersion` 语义化三段比较（真机反馈第 9 项） | ✅ 单测覆盖 |
| `bridge/dlog.dart` | 文件日志 `/data/data/<pkg>/files/dsh.log`（vivo 过滤 flutter 日志，只能落文件）；`enabled` 开关 + `read()` 供设置页诊断日志区 | ✅ |
| `ui/chat_page.dart` | 聊天主页：顶栏（会话名 + 新对话加号接 `newChat` + ⋯ 溢出菜单） / 空态问候（**工作目录 chip：`pendingLocation?.label` 或「手机会话（默认）」，onTap 弹 `session_location_sheet`——2026-11-15**） / 设置页入口；消息列表与消息项拆成同库 `part`（宪法 §7 控行数）；**主页 PopScope 退出 APP 二次确认——首次返回提示「再按一次退出 DSH」，2s 内再按 SystemNavigator.pop 真退出（第五轮勘误，替代上一版错装在设置页的双击退出）** | ✅ 装机验证 |
| `ui/chat_message_list.dart` | `part of chat_page.dart`：消息列表 + 跳转最新 FAB + **收起后显示的回复过滤（`visibleMessagesOf(work_steps.dart)`：foldedReplies=final 且轮已完成时只保留最终回答，files/error/command 卡恒可见、流式与运行中轮不过滤；index 保持原 messages 下标——regenerateAt 依赖原索引，2026-11-16）** + **流式过程组 `_StreamingProcessGroup`（streamingProcess 非空时插在流式正文前，2026-11-17）** + **`_MaxTokensNotice` 截断提示行（`maxTokensNotice` 置位时渲染，官方文案逐字 + settingsWarnBg 浅 warn 底，2026-11-17）** + 滚动冻结 / 贴底跟随（`wantsBottom` 粘性意图、80ms 解冻、140ms 渐显）；判据在 `scroll_follow.dart` | ✅ 单测覆盖 |
| `ui/chat_message_items.dart` | `part of chat_page.dart`：消息项（双击复制整条；用户气泡内嵌历史图片 `DsChatImage`；助手消息 image-handoff 占位转图；**process 组按 `workStepsDetail` 渲染：verbose 档平铺逐条 `DsToolRow`；其余档 `DsProcessGroup` + 上层推导 turnRunning/forceOpen/`reasoningHint`（同轮最近 assistant reasoning，2026-11-17）与 `answerable`（HitlState.sessionQuestions 按 callId 匹配，2026-11-17）；展开态提升到 `GroupExpandState`（chat_expand_state.dart）**；**deliverables/presented → `_DeliverablesCard` 文件卡：.md 点开全屏渲染（MdViewerPage），其他类型系统打开（openFile），失败回退分享——m03452 改进，第四轮反馈 6**）；**role=='command' 命令卡（斜杠命令本地回执：命令行 + ✓/✗ 结果，m03878）** / 流式项（思考块迁 `chat_message_blocks.dart`，2026-11-17） / 消息操作条（重新生成接线） | ✅ 装机验证 |
| `ui/work_steps.dart` | 收起后显示的回复纯函数（2026-11-16 官方通用设置批次）：`turnsOf`（轮 = 每条 user 到下一条 user 前）/ `lastTurnOf` / `turnIsRunning`（轮内未 committed seq<0 或流式收尾中）/ `finalReplyIndexOf`（最后一条「有可见正文且不带工具调用」的 assistant 消息）/ `visibleMessagesOf(messages, FoldedReplies, streaming)`——all 或轮运行中全可见，final 且轮完成只保留最终回答（process 组交给 A/B 收起逻辑；无合格 assistant 消息则整轮全显示不猜） | ✅ 单测覆盖 |
| `ui/chat_image.dart` | 历史图片组件 `DsChatImage`：attachment / image-handoff 双通道自动下载（`gatewayImageFetcher(gateway, sessionId)` 注入，attachments 接口必填 sessionId query，随会话切换刷新）+ 进程内字节缓存 + 失败占位可点重试（真机反馈 2026-11-04 第 1 项） | ✅ 装机验证 |
| `ui/scroll_follow.dart` | 滚动跟随纯函数：`shouldAutoFollow` / `shouldShowFab` / `computeAtBottom` / `freezeSnapshot` / `isUserScrollGesture`（只认 dragDetails），对照 companion 三处滚动实现 | ✅ 单测覆盖 |
| `ui/chat_state.dart` | ChangeNotifier：会话列表 / 打开会话（**openSession 清流式缓冲 streaming/streamText/streamReasoning 并先渲染清空态——2026-11-15 切会话深度思考串台修复**）/ 发送（纯文本与带图；新会话**分流：`pendingLocation` 已选目录 → `createSessionAt(rootId,cwd)` 建会话即定死目录；未选 → `ensureMobileWorkspace` 预建到「手机会话」工作区——2026-11-15 可选工作目录**；`setPendingLocation()` + `notifyUi()`）/ 斜杠命令 `runCommand()`（command-execute；**回执注入本地命令卡 role=='command' 并在 reloadHistory 后保留——m03878**）/ `cancelTurn()` / `regenerateAt()` / `retryLast()` / 历史翻页 `loadOlder()`（beforeSeq + seq 去重；方法体抽 `chat_history_actions.dart` 控行数）/ 流式累积 / 推送分发（含 HITL 问答/审批事件转发到 `HitlState`；**assistant committed 只在 hasReplyContent 时清正文流式缓冲（`clearStreamText`）——工具执行前的无正文提交不再整段清流/收起（桥 e08b6b5）；「回答结束后」收起时机改挂 `TurnEndedEvent`（reason∉{aborted,interrupted,error} 才收，chat_state_events.dart）；`maxTokensNotice` 截断提示位（turn.end reason=max-tokens 置位 / turn.start、send() 复位）；`dropPersistedToolRows()` reloadHistory 后按 callId 摘除已持久化流式工具行防双份；`isPersistedToolCall()` 迟到的 tool/call 帧不再往缓冲重复建行（防抖重拉让持久组刷新）**；send() 入口按「下次有新消息时」时机 `collapseOnNewInput()`）/ HITL 动作 `answerQuestion()`/`cancelQuestion()`/`decideApproval()`；分组 getter 委托 `session_groups.dart`；`newChat()` 清 pendingLocation（不沿用上次选择） | ✅ 装机验证 |
| `ui/streaming_tools.dart` | 流式工具行状态机（2026-11-17 实时工具事件批次，对齐安卓语义与官方 Web 五态）：`StreamingToolBuffer`（`_rows` 按 callId 存行 + `_indexToCallId` index→callId 映射；`_rowFor` 真实 callId 首现时删除 `'idx<index>'` 旧键并把占位行迁到 callId 键（不产生重复行）、只带 index 的续包经映射找回同行）+ `handleDelta`（拼 argumentsDelta）/ `handleEnd`（arguments 定稿 settled）/ `handleCall`（转 running）/ `handleResult`（done/failed/stopped/cancelled，errorCode=='interrupted' 与 'ASK_CANCELLED' 不算失败）/ `infos`（preparing=未 settled/running/done，缺名兜底「工具调用」）/ `processMessage`（role=='process' 合成过程组，seq=-2）/ `dropPersisted`（**reloadHistory 后按 callId 摘除已持久化行并清 index 映射——防「流式行+持久组」双份，2026-11-17**）/ `clear` | ✅ 单测覆盖 |
| `ui/chat_state_events.dart` | `part of chat_state.dart`（2026-11-17 实时工具事件批次拆出，控行数）：`_onGatewayEvent` 全事件分派——Delta 显式四路（text→streamText / reasoning→streamReasoning / tool-call→`_toolBuffer.handleDelta` / tool-call-end→`handleEnd`；**未知 kind 忽略，不得当文本渲染（老客户端契约）**）/ ToolCallEvent→handleCall / ToolResultEvent→handleResult（**均已挂 `isPersistedToolCall` 守卫：callId 已被持久过程组承载时不再往缓冲建行，改防抖重拉——迟到帧防「持久组+流式组」双份，2026-11-17**）/ CommittedEvent assistant→**hasReplyContent 时只清正文缓冲（clearStreamText，工具行继续跑）+ 重拉；不再停流/收起（内核工具执行前先提交无正文消息）**、其余→防抖重拉 / **TurnStarted→streaming=true+复位截断提示 / TurnEnded→停流+清流+（reason∉{aborted,interrupted,error}）收起 + max-tokens 置 `maxTokensNotice` + 重拉（2026-11-17）** / TurnFailed→清流+lastError+复位提示 / Resync→重拉 / SessionEventReceived→防抖重拉 / HITL 四类→hitl | ✅ analyze |
| `ui/ask_present.dart` | 提问（ask_user_question）展示纯函数（2026-11-17 从 tool_present.dart 拆出，控行数）：`AskAnswerEntry`/`AskResult`/`askResultOf`（宽容解析）/ `askQuestions`（multi_select 兼容驼峰、重复 id 或缺字段→null）/ `askSummary`（运行中「等待中」/ errorCode=='ASK_CANCELLED'→「已取消」/ 待续「已继续；仍可回答」/ 已关闭「已关闭」/ 已答「N/M 已回答」） | ✅ 单测覆盖 |
| `ui/hitl_state.dart` | HITL 挂起表 `HitlState`（全连接 pendingQuestions/pendingApprovals 按 callId/approvalId 去重 + 会话过滤 getter + answer/cancel/decide 动作；从 chat_state.dart 拆出控行数） | ✅ 单测覆盖 |
| `ui/chat_expand_state.dart` | 工作步骤展开态宿主（2026-11-16 通用设置批次，2026-11-17 扩展）：`processGroupKeyOf`（组内首个 callId，缺省回 `'seq<seq>'`，跨 reload 稳定）+ `mixin GroupExpandState on ChangeNotifier`（`expandedGroups` 手动展开集 + verbose 模式手动收起例外集，两集互不污染；`toggleProcessGroup(key, open:)` 以视觉态为准 + `isForceOpenDismissed`（运行中轮 forceOpen 被用户收起后的豁免表——2026-11-17）/ `isGroupExpanded`；**收起时机：`collapseOnAssistantCommitted`（回答结束后）/ `collapseOnNewInput`（下次有新消息时）；verbose 档永不自动收起**） | ✅ analyze |
| `ui/question_card.dart` | `HitlPanel`：提问卡（每题 FilterChip 单/多选 + 自定义回答输入 + 提交键，提交走 question-answer）与**审批卡官方语义（2026-11-17）：顶部 strip 状态条（小圆点 + 「等待审批」），决定提交后按钮全禁用（answered 态，本地态挂起等待 resolved 摘表）；full-access 越权标题「工具 {toolName} 请求越权执行」，standard 保持「DSH 请求使用 {toolName}」；reason 代码等宽字体；只有「拒绝」「允许一次」两键（协议 decideApproval 只收 allow bool，官方亦无「始终允许」）**；**整面板限高屏高 ×0.5（`hitlPanelMaxFraction`）内部上下滚动——2026-11-15 用户反馈内容过多时提交按钮被推出屏幕** | ✅ 单测覆盖 |
| `ui/session_groups.dart` | 会话抽屉分组纯函数 `groupSessionsByWorkspace()`：顶层按工作区分（「手机会话」置顶、其余用 workspace title、无工作区「未分组」），组内按今天/昨天/更早；单工作区单日期退化为纯日期（真机反馈第 7 项） | ✅ 单测覆盖 |
| `ui/chat_history_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`reloadChatHistory(state)` / `loadOlderMessages(state)` / `oldestSeqOf(state)`——chat_state 薄转发保 UI 调用点 | ✅ 单测覆盖 |
| `ui/chat_hitl_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`submitChatAnswer` / `skipChatQuestion` / `decideChatApproval(state,…)`——HITL 动作落 lastError 后 notifyUi；chat_state 薄转发保 UI 调用点 | ✅ analyze |
| `ui/session_location_sheet.dart` | 新建会话目录选择 sheet（2026-11-15 可选工作目录）：默认项「手机会话（默认）」+ 已选高亮（「点此恢复默认」）+ 「最近使用」按历史会话 (rootId,cwd) 去重（cwdAbsolute 副标题）+ 浏览页（面包屑 + 只列目录 + 加载更多 + 「在此目录新建会话」回传 `SessionLocation`）；`DirectoryLister` 注入点供测试 | ✅ 单测覆盖 |
| `ui/mobile_workspace.dart` | 「手机会话」工作区准备 `ensureMobileWorkspace()`：title 含「手机」的既有工作区 → 建目录 `.dsh-mobile`（directory-create，409 幂等）→ REST 登记工作区 → PATCH 改名「手机会话」；失败回 null 不阻断发送（真机反馈第 7 项） | ✅ |
| `ui/stats_sheet.dart` | 会话统计 Sheet：`chatStatsOf()` 由已加载消息本地计算（消息/工具/思考/错误数），零网络请求；对照 companion ChatStatsSheet | ✅ 单测覆盖 |
| `ui/projection_sheets.dart` | 三个零请求面板：运行轨迹（rawEvents 本地分组、点节点展开原始 JSON；**轮次+节点渲染体抽公共 `TrajectoryBody`，轨迹面板与代码工作视图共用——2026-11-16**）/ 智能团队（projections.values.agentTeam，含三枚普通消息话术 chips，**子会话行可点进详情页，第四轮反馈 3**）/ 待办任务（projections.values.todos）；投影缺席显示空态而非隐藏入口 |
| `ui/work_view_sheet.dart` | 代码工作视图底部抽屉（2026-11-16 官方「显示代码工作视图」）：聊天页 ⋯ 菜单入口（`codeWorkView` 开启才出现）→ 三段——①运行轨迹（复用 `TrajectoryBody`）②本轮代码差异（`codeDiffsOfTurn` 取当前轮 edit/write 参数渲染 +/- 行色，超 400 行折叠「… 其余 N 行」）③Agent 预设（REST 清单 name/description/默认标记/当前打勾；空白会话可切，非 blank 置灰提示「首条消息后锁定」，409 显示「已锁定，仅空白会话可切换」） | ✅ analyze |
| `ui/code_diff.dart` | 本轮代码差异纯函数（2026-11-16）：`codeDiffOfCall(name, rawArguments)`（edit→`file_path/old_string/new_string` 生成 -old/+new 行、write→`file_path/content` 全 + 行，公共前后缀标 ctx；坏 JSON/缺 file_path 回 null 不抛；兼容 `tools.` 前缀工具名）+ `codeDiffsOfTurn(messages)`（最后一轮 process 组逐调用按序产出 `CodeDiff{path,kind,lines}`） | ✅ 单测覆盖 |
| `ui/subagent_history_page.dart` | 子会话（团队成员）只读历史页：REST 窄口 `subagentHistory()`（GET /chat/sessions/{leadId}/subagents/{id}/messages，openapi.yaml:992-1050）+ beforeSeq 翻页 + 轻量只读消息渲染；协议明确成员会话不可写，无输入条（第四轮反馈 3） | ✅ 单测覆盖 |
| `ui/settings_page.dart` | 设置页主文件：Scaffold + 分区骨架（`settings_sections.dart` / `settings_widgets.dart` / `settings_update.dart` 是同库 `part`，共享私有成员，宪法 §7 控行数）；普通返回即退出（二次确认挪到主页——第五轮勘误：用户要的是退出 APP 二次确认，不是设置页） | ✅ 单测覆盖 |
| `ui/settings_sections.dart` | 设置页分区：连接与设备信息（hello 只读）/ 界面风格三档 / **通用（官方原文四行：工作步骤展示四档 / 工作步骤收起时机 / 收起后显示的回复——verbose 档整行隐藏 / 显示代码工作视图开关——2026-11-16）** / 字号缩放与跟随系统 / 繁忙发送模式 / 诊断日志 / 关于（含检查更新行）/ 断开连接；不摆无授权的服务端开关 | ✅ 单测覆盖 |
| `ui/settings_update.dart` | `part of settings_page.dart`：`_UpdateCheckRow` 检查新版本（1.5s 静默检查有新版才提示；手动检查三态：发现新版本→点按下载 / 已是最新 / 两站都连不上；下载轮询进度百分比 + STATUS_SUCCESSFUL 后 installApk 自动拉起安装，第二轮反馈 C；`Timer` 必须 dispose 取消，测试断言无 pending timer；本机版本运行时经 `DshPlatform.appVersion()` 读取（没读到则跳过比较，不拿 0.0.0 误报）） | ✅ 单测覆盖 |
| `ui/settings_widgets.dart` | 设置页通用组件：`_Section` / `_InfoRow` / `_ActionRow` / `_SwitchRow` / `_SegmentedRow`（**可选 `description` 描述行——官方通用设置每行带说明文字，2026-11-16**）/ `_ScopeChip` / `_WarningBanner` | ✅ 单测覆盖 |
| `ui/composer.dart` | 输入条：白浮层圆角容器 + 输入框 + 权限档位 chip + 图片附件 chip 与发送（8MiB 上限；单发图片也亮发送键）+ **「/」斜杠命令面板**（`parseSlashDraft` 检测草稿 → commands 帧清单前缀过滤 → 浮层建议（**可滚动 + 键盘上下高亮、回车选中——m03878**）→ 点选回填；发送优先走 `onCommand`；**拉取失败不落缓存、下次输入自动重试——m04149**）+ **「@」文件引用面板**（`parseAtMentionDraft` 草稿检测 → gatewayListRoots+gatewayListEntries **多根逐根拉取合并**（空根不挡非空根——m04149）→ 目录点选继续进子目录、文件回填 `@label/path `——m03878）+ 发送键三态 + **加图按钮常驻（先打字也能加图，第二轮反馈 D）** + 底部免责提示（**流式思考期间隐藏，无思考时显示——m03759 反馈**；命令面板组件拆 `composer_widgets.dart`）+ **选图不再按文件名扩展名猜类型：用原生回传的真实 mediaType（缺失时读缓存字节魔数兜底）+ 内核 4 种白名单核对，失败原因显式弹提示（华为 HEIC 修复）** | ✅ 装机验证 |
| `ui/composer_widgets.dart` | `part of composer.dart`：基础件 `_Chip`（胶囊 chip）/ `_RoundIconButton`（圆形按钮）+ `pickComposerImage`（读选图缓存字节→base64；mediaType 由调用方按魔数/原生回传传入，不再按扩展名判——华为 HEIC 修复，m03878 拆入） | ✅ |
| `ui/composer_panels.dart` | `part of composer.dart`：`_CommandPanel`（斜杠命令建议浮层，可滚动+高亮——m03878）/ `_AtFilePanel`（@ 文件引用浮层，目录/文件图标区分，可滚动+高亮——m03878；**失败态错误行+点按重试——m04149**）+ `fetchAtEntries`（**多根逐根拉取合并**，空根不挡非空根——m04149）+ `insertAtMention`（**「选择项目中的内容」圆钮：光标处插 `@` 走与手敲同一 `_atDraft` 状态路径唤起面板——2026-11-16**） | ✅ |
| `ui/composer_bar.dart` | `part of composer.dart`：`_ComposerBar`（输入容器：输入框+权限 chip+图片 chip+加图/**「选择项目中的内容」文件夹圆钮（Tooltip，禁用条件与加图钮一致）——2026-11-16**/发送圆钮）/ `_PermissionSheet`（权限档位底部弹层）/ `confirmFullPermission`（完全权限二次确认） | ✅ |
| `ui/connect_page.dart` | 连接页三级路径：历史主机点击直连（DshHosts，有 token 才显示、失败显式报错）+ DSH1 配置文本导入（decodeDsh1，有 token 直连/无 token 填表）+ 手动配对（bridge 地址 + 配对码）；成功都 upsert 主机记录；**历史主机卡片删除按钮 + AlertDialog 二次确认 + 直连失败「删除这条失效记录」入口（DshHosts.remove，命中当前凭证顺手 DshCredentials.clear）** | ✅ 装机验证 |
| `ui/md_view.dart` | GptMarkdown 定制：官方 token 全量映射、任务列表预处理、codeBuilder/tableBuilder 接线、**链接可点外跳浏览器（url_launcher onLinkTap，第四轮反馈 5）** | ✅ 装机验证 |
| `ui/md_viewer.dart` | 全屏 Markdown 文档查看页 `MdViewerPage`：.md 文件卡点开 → `gatewayResolvePath` + `gatewayReadFileBytes` 取字节 → utf8 → `DsMarkdownView` 滚动渲染；顶栏文件名 + 体积，失败给重试（文件卡 m03452 改进） | ✅ 单测覆盖 |
| `ui/image_viewer.dart` | 全屏图片查看器 `openImageViewer()`：黑底 InteractiveViewer 双指缩放/拖移、单击关闭、双击 1x/2.5x 变焦；聊天图片（chat_image.dart）点按进入，字节走进程内缓存零请求（第四轮反馈 1） | ✅ 装机验证 |
| `ui/md_code_block.dart` | 自绘代码块：Atom One Light（ValTheme 自定义）+ banner「语言名 / 复制」 | ✅ 装机验证 |
| `ui/md_table.dart` | 自绘表格：banner「表格 + 复制/下载/展开」+ 官方 #fafafa 底 + #dcdcdc 线 | ✅ 装机验证 |
| `ui/message_actions.dart` | 助手消息操作条：复制 / 喜欢 / 朗读（系统 TTS）/ 分享（系统分享面板，**尾部附「—— 发送于 yyyy-MM-dd HH:mm」，第四轮反馈 7**）+ 右侧重新生成接线；平台不支持时明确提示（点踩按真机反馈 2026-11-04 移除） | ✅ 装机验证 |
| `ui/process_group.dart` | 工具调用折叠组（2026-11-17 官方 Web 工具调用展示批次）：聚合标题 `processGroupTitle`（tool_present.dart 官方词表：进行中「正在…/准备…」+ live detail 键值（或 reasoning 兜底）· 后缀；完成按 kind 计数排序取前三类「并/，」连接、超三类加「等」，distinct callId 去重）；单条工具行 `DsToolRow` 五态（kind 图标 + `toolTitle` + 摘要 summarizeArgs + 「运行中/失败」状态字 + edit/write diff 后缀 `+N -M`；失败摘要换 resultText 首行红字）；**`workStepsDetail` 四档 policy（`WorkStepsDetailPolicy` 扩展：stepGrouping/liveProcessDetail/settledReasoningPreview/foldCompletedTurns）——concise 只渲染折叠行 / standard 不渲染详情 / detailed 完成轮 history / verbose 平铺逐条 DsToolRow（chat_message_items.dart 处理）**；展开态提升 `GroupExpandState`（key=首个 callId），运行中轮 forceOpen 默认展开（用户收起过豁免 `isForceOpenDismissed`）；详情特化拆 `process_detail.dart` | ✅ 单测覆盖 |
| `ui/process_detail.dart` | `part of process_group.dart`（2026-11-17 工具调用展示批次拆出，控行数）：工具详情特化（官方逆向）——edit/write → 行级差异块 `_DiffBlock`（复用 code_diff.dart，默认 9 行 + 「… 其余 N 行」展开，diff 行色 token）+ 失败结果保留；commands → BASH 代码块（command 字段）+ 结果正文；read → 结果正文 8 行开窗 + 顶部「显示 N 行中的 8 行」+ 展开；code（run_code）→ code 字段代码块 + 结果；webSearch/webFetch → 结果正文，完成且无结果 →「未找到结果」；questions → 逐问卡（问题文本主色 + selected/custom 答案行，无答案「未回答」）或 verdict（「已继续；仍可回答」/「已关闭」）+ 问题列表（HITL 面板常驻消息列表上方为已知偏差）；其余 IN/OUT；耗时行保留，完成且无结果 →「无结果」 | ✅ analyze |
| `ui/tool_present.dart` | 官方 Web 工具调用展示纯函数（2026-11-17 批次，zh 词表逐字对齐）：`activityKind` 15 类（read/readImage/write/search/edit/commands/code/webSearch/webFetch/subagents/plan/questions/tools/thinking，剥 `tools.` 前缀）；`toolTitle`（pwsh/grep/glob 精确名优先）；`toolIcon`；`summarizeArgs` 按 kind 键序（search queries 数组 join）；`liveDetailText` 22 键序截 160 + `reasoningDetailOf`；`processGroupTitle`（进行中/准备中/完成聚合标题）；ask 特化 `askResultOf`/`askQuestions`（重复 id 或缺字段 → null）/`askSummary`（等待中 / 已继续；仍可回答 / 已关闭 / N/M 已回答，解析失败回原摘要） | ✅ 单测覆盖 |
| `ui/chat_message_blocks.dart` | `part of chat_page.dart`（2026-11-17 从 chat_message_items.dart 拆出，控行数）：`_ThinkBlock` 思考流块——流式默认展开「深度思考中…」（m03759），历史折叠「已深度思考」；**折叠态一行正文预览（`settledReasoningPreview` 消费，concise 档只留标题——2026-11-17）** | ✅ analyze |
| `ui/model_sheet.dart` | 模型选择面板：models 帧拉分组清单，**按供应商分组可折叠（默认只展开当前供应商，折叠组若含当前选中模型显示一行提示）**→ select-model 帧确认切换 → 重拉 history；routable=false / failures 有值时显式提示（真机反馈第 4 项） | ✅ 单测覆盖 |
| `ui/sessions_drawer.dart` | 侧边会话抽屉：胶囊搜索框 + 分组列表（组名来自 `session_groups.dart`：工作区置顶分组）+ 纯文字条目 + 底部栏（**整行可点开设置** + 设置圆钮 + 「设置」文字 + 设备名 + 连接状态点：绿=桥正常/红=未连接（GatewayState.ready 判别）+ `connectionLabel` 地址，真机反馈第三轮 3 + 第五轮） | ✅ 装机验证 |
| `ui/chat_message_list.dart` | `part of chat_page.dart`：消息列表 + 跳转最新 FAB + **列表头「加载更早消息」按钮（`historyHasMore` 控制，翻页中转圈；翻页 prepend 后经 `historyPageJustLoaded` 跳过一次贴底跟随，保住阅读位置，第二轮反馈 A）** + **整表 `SelectionArea` 包裹（长按可选字复制，第二轮反馈 E）** + 滚动冻结 / 贴底跟随；判据在 `scroll_follow.dart` | ✅ 单测覆盖 |
| `ui/brand_mark.dart` | 空态品牌标记 DsBrandMark（`_WhalePainter` 原创 Path 绘制：圆身 + 双瓣尾鳍 + 月牙腹部 + 眼睛），不引用官方素材 | ✅ 装机验证 |

## 平台侧（框架通道与清单）

| 文件 | 用途 |
|---|---|
| `app/android/app/src/main/kotlin/.../MainActivity.kt` | MethodChannel `dsh/device#ianaZone`（Android IANA 时区）+ `dsh/platform`（系统 TTS speak/stopSpeak + 系统分享 share + **系统选图器 pickImage：ACTION_GET_CONTENT + FLAG_GRANT_READ_URI_PERMISSION → 读字节 → `ImagePickHelper.prepare` 按魔数定真实类型 / 把 HEIC 等转码成 JPEG/PNG → 安全缓存名 → 回 {path, name, mediaType}，失败回 {error} 不静默（华为 HEIC 修复）** + **DownloadManager：downloadApk 返回任务 id / downloadStatus 查询进度 / installApk 经 getUriForDownloadedFile 拉起安装器（FLAG_GRANT_READ_URI_PERMISSION），第二轮反馈 C**，TextToSpeech 惰性初始化、onDestroy shutdown） |
| `app/android/app/src/main/kotlin/.../ImagePickHelper.kt` | 选图字节处理（华为 HEIC 修复，从 MainActivity 拆出控行数）：`sniffMediaType`（与 bridge `image-handoff.ts` 同魔数表）/ `supportedMediaTypes`（内核 4 种）/ `prepare`（内核不收的格式走 `BitmapFactory` 解码 → JPEG/PNG 重编码，带 alpha 编 PNG，8MiB 上限，超大图仅降采样防 OOM）/ `cacheFileName`（不拼 DISPLAY_NAME）/ `displayName`（净化 + 真实扩展名）；对齐 dsh-companion `ImageTranscoder.kt` | |
| `app/android/app/src/main/AndroidManifest.xml` | `INTERNET` 权限 + `REQUEST_INSTALL_PACKAGES`（应用内更新拉起安装器，第三轮反馈 2）+ `usesCleartextTraffic`（bridge 走 ws:// 明文）+ queries 包可见性（PROCESS_TEXT + apk mime 的 ACTION_VIEW） |
| `app/ios/Runner/AppDelegate.swift` | 同款 `dsh/device#ianaZone` 通道（iOS `TimeZone.current.identifier`） |
| `app/ios/Runner/Info.plist` | 显示名 DSH Chat + ATS 放行明文 + 本地网络用途说明 |

## app/test/

| 文件 | 覆盖 |
|---|---|
| `app_settings_test.dart` | `normalizeFontScale`（NaN/Inf/越界夹取）、`AppFontScaler` 与系统字号相乘、`AppSettings` 默认值与 `effectiveFontScale`、**通用设置四项 round-trip（官方 token 字符串存读、未知名回默认、setX notify）——2026-11-16** |
| `settings_page_test.dart` | 设置页渲染：界面风格三档 / 繁忙发送模式两档 / 字号滑块与跟随系统 / 诊断日志开关均真实生效、**通用分区渲染与四行接线（verbose 隐藏「收起后显示的回复」）——2026-11-16** |
| `work_steps_test.dart` | `turnsOf` 轮分组 / `turnIsRunning` / `finalReplyIndexOf` / `visibleMessagesOf`（final 只保留最终回答、运行中全可见、无合格消息不猜） |
| `code_diff_test.dart` | `codeDiffOfCall` edit/write 参数解析与 +/-/ctx 行序、`tools.` 前缀、坏输入 null；`codeDiffsOfTurn` 只取最后一轮 |
| `tool_present_test.dart` | 官方工具调用展示纯函数（2026-11-17 批次）：`activityKind` 全词表 / `toolTitle` 特例 / `summarizeArgs` kind 键序与坏 JSON 兜底 / `liveDetailText`（运行中调用键值、queries 首项、160 字截断）/ `processGroupTitle`（空组兜底、进行中 + liveDetail、准备中、两类「并」去「已」、三类逗号、超三类加「等」、按计数排序）/ `askSummary`（等待中、已继续；仍可回答、已关闭、1/2 已回答 skipped 不计、解析失败兜底）/ `askQuestions`（重复 id/缺字段/空列表 → null）/ `askResultOf` |
| `streaming_tools_test.dart` | 流式工具行状态机（2026-11-17 实时工具事件批次）：首包缺 callId 按 index 占位、`callId` 到达后迁移（不产生重复行）/ 续包按 index 找回已迁移行 / delta 增量拼 arguments / end 定稿 / call 转 running / result 终态（interrupted 与 ASK_CANCELLED 不算失败）/ 缺名兜底「工具调用」/ 进程组合成 |
| `chat_actions_test.dart` | `chatStatsOf()` 本地统计、`Composer` 发送键三态、`ChatState.regenerateAt/retryLast` 重发用户消息 |
| `image_media_type_test.dart` | 图片类型纯函数：`sniffImageMediaType` 魔数表（PNG/JPEG/GIF/WEBP/BMP/HEIC(hei/hev/mif)/AVIF + 短数组截断）/ `isSupportedImageMediaType` 内核 4 种白名单 / `mediaTypeExtension` 映射（华为 HEIC 修复） |
| `scroll_follow_test.dart` | `shouldAutoFollow` 粘性意图自锁回归、`shouldShowFab` / `computeAtBottom` / `freezeSnapshot` 空表 / `isUserScrollGesture` 程序滚动不算手势 |
| `projections_test.dart` | `trajectoryOf()` 按 turn 分组 / 组内 seq 排序 / 丢弃过程细节 / 未知轮次垫底；`todoItems()` 只认 `{content,status}`；`agentTeamProjectionOf()` 缺省回退与空壳 null；`HistoryPage` 保留原始事件与投影 |
| `hosts_test.dart` | `DshHost` stableId 幂等 / round-trip（token 缺省不发键）；`decodeDsh1` 宽容解码（前缀前说明文字/换行/结尾标点/大小写不敏感）与垃圾输入一律 null；**`DshHosts.remove` 存储层：删存在→true/落盘同步、删不存在→false、按非空 id 兜底匹配、删空写 `[]`** |
| `permissions_test.dart` | 权限档位：`PermissionOption`/`PermissionCatalog` 解析与中文标签（未知回退）、`custom` 过滤、round-trip；`SessionModels`/`parseSelectModelReply`（sent 按 `data.type` 判别）/`reasoningEffortLabel` |
| `models_test.dart` | 协议模型 round-trip、`data.message.content` 提取、注入上下文过滤（`source.kind != user`）、displayTitle 兜底、工具调用措辞表（含 read_image 等中文名）/ 摘要 / `toolResultText` / 过程组合并去重与耗时（result 正文进 `ToolCallInfo.resultText`）/ `turn/end` 失败 → `role=error` |
| `models_agent_preset_test.dart` | `DshSession.agentPreset` round-trip（带/缺/显式 null 字段——2026-11-16，从 models_test 迁出防超行） |
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

## harmony/（鸿蒙版，ArkUI 原生重写）

> 安卓版全功能的鸿蒙移植，工程根 `harmony/`，阶段与规程见 `harmony/docs/{PORT-MAP,RELEASE,STATUS}.md`；
> 静态审查报告见 `harmony/docs/REVIEW-20261116.md`（设计令牌/无障碍/一多/上架四类问题清单与排期）。
> ets 源码按 `ets/` 内相对路径登记（`scripts/ci/docs-check.sh` 第 1b 条机检）。

### 工程配置

| 文件 | 用途 |
|---|---|
| `harmony/build-profile.json5` | 工程级：compatibleSdkVersion 5.1.0(18)、signingConfigs 留空（签名走 hap-sign-tool，见 RELEASE.md） |
| `harmony/oh-package.json5` / `harmony/package.json` | 工程元信息（1.0.0 起独立版本线）+ node ESM 标记 |
| `harmony/hvigorfile.ts` / `harmony/hvigor/hvigor-config.json5` | hvigor 构建入口（appTasks，modelVersion 5.0.0） |
| `harmony/AppScope/app.json5` | bundleName `com.dsh.dshchat`（与安卓 applicationId 对齐）、versionCode 1000000 / versionName 1.0.0、分层图标 |
| `harmony/AppScope/resources/**` | 应用名 DSH Chat（base/en_US）+ 1024 分层图标（前景/背景/启动图，自安卓自绘图标放大，矢量精绘待真机阶段） |

### entry/src/main

| 文件 | 用途 |
|---|---|
| `harmony/entry/src/main/module.json5` | entry 模块清单：EntryAbility + 仅 INTERNET 权限（剪贴板受限权限教训见 PORT-MAP） |
| `harmony/entry/build-profile.json5`、`hvigorfile.ts`、`oh-package.json5`、`obfuscation-rules.txt` | 模块级构建配置（混淆暂不启用） |
| `harmony/entry/src/main/resources/**` | 文案/颜色资源（base + dark 深色档 + en_US 预留）+ 模块侧分层图标 + main_pages |

### ets 源码（阶段推进时逐行补）

> core 层物理在 entry 模块内（ArkTS 禁跨模块相对 import，Error00309001 实证）；
> 纯逻辑 .ts 全部 node 直测，不 import 任何 `@kit`/ets/UI。

| 文件 | 用途 |
|---|---|
| `ets/entryability/EntryAbility.ets` | 唯一 Ability：loadContent + 深浅色显式跟随系统（COLOR_MODE_NOT_SET，后台切色不丢） |
| `ets/pages/Index.ets` | 根路由 boot（自动连接）→ connect（连接页）→ chat（对话页）；深浅色 mediaquery 监听写 AppStorage('dshDark')；通用四偏好（workStepsDetail/collapseTiming/foldedReplies/codeWorkView）异步装载写 AppStorage 无点驼峰键；ChatStore 单例随连接存活 |
| `ets/pages/ConnectView.ets` | 连接页三级路径：历史主机直连（失败记失效记录可删）/ DSH1 文本导入 / 手动地址+配对码（pairViaRest）；删除当前主机顺带清凭据 |
| `ets/pages/SettingsView.ets` | 设置页七分区：连接只读（状态/设备/scopes/HTTP 警告）/外观（跟随系统/浅色/深色）/通用（SettingsGeneralSection：工作步骤展示四档/收起时机/折叠回复/代码工作视图开关）/发送（queue|steer）/关于（版本+检查更新跳 Gitee）/断开连接（清凭据回连接页） |
| `ets/pages/MdDocViewer.ets` | .md 全屏查看页：resolvePath/readFileBytes → MdView；标题+大小 caption/失败重试 |
| `ets/pages/ChatView.ets` | 对话页：顶栏（⋮ 溢出菜单五项 + 代码工作视图入口（仅 dshCodeWorkView='1'）/标题/连接点/新建）+ HitlPanel 提问审批卡 + 消息列表 + 输入条 + 会话抽屉 + 六面板 bindSheet（统计/轨迹/团队/待办/模型/代码工作视图）+ 设置页入口；每次 changed 把 workSteps 展开集合版本写 AppStorage('dshExpandedVersion')（ProcessGroup @Watch 回读，LazyForEach 同 key 不重建的替代链路） |
| `ets/components/MessageList.ets` | 消息列表：用户气泡（86.4% 宽 + 收图 ImageTile）/ 助手 MdView 富渲染 + 命令卡 + 文件卡（.md 全屏 MdDocViewer）+ 消息操作条 MessageActions / 错误条；渲染前过 core/WorkSteps.visibleMessagesOf（dshFoldedReplies='final' 时完成轮只留最后一条正文助手消息，dshDark 同款 @StorageProp 链路）；过程组按展示档分派——verbose（core/ToolDetails.STEP_GROUPING_NONE）平铺逐条 ToolBlock（answerable 回调传挂起询问查询），其余档 ProcessGroup；ThinkBlock 传 settledReasoningPreview=policyOf(dshWorkStepsDetail) |
| `ets/components/Composer.ets` | 输入条：发送键三态（send/stop/disabled）+ 命令补全/@ 文件补全（ComposerPanels）+ 图片 chip（PhotoPick 魔数校验 8MiB）+ 📁 选择项目中的内容（合成空 @ 草稿复用 AtFilePanel，原位插入 '@文件名 '）+ 权限 chip（PermissionSheet bindSheet）+ 免责声明 |
| `ets/components/SessionsDrawer.ets` | 会话抽屉（阶段 2）：主机标识 + 新对话钮 + 工作区分组列表（未分组垫底）+ 当前会话高亮；搜索/删除阶段 4 |
| `ets/components/md/MdView.ets` | Markdown 主组件：块级循环（h/p/quote/code/table/ul/ol/hr/latex）+ 行内混排（Span 样式/链接外跳/内嵌 MdLatexView）；任务项 ☑/☐，引用左竖条 |
| `ets/components/md/MdCodeBlock.ets` | 代码块：banner 语言名+复制（pasteboard）+ 1px 分隔线 + 横滚 + SimpleHighlight 四类着色 |
| `ets/components/md/MdTable.ets` | 表格：banner「表格」+复制（\t 连接）+ 表头 w500 + cellAlign l/c/r + cellMinWidth 100 |
| `ets/components/md/MdLatex.ets` | 轻量 LaTeX 渲染：frac/sqrt/sup/sub/sym 分派（横线分子分母/√ 上边框/70% 字号偏移）；嵌套 smallArg 拍平 |
| `ets/components/ArrayDataSource.ets` | `IDataSource` 的数组实现（MessageList/SessionsDrawer 的 LazyForEach 数据源）：totalCount/getData + 监听注册注销，reset(items) 广播 onDataReloaded（不做逐项 diff —— ChatStore.messages 每次 changed() 都是新数组） |
| `ets/components/ToolBlock.ets` | 工具折叠组：摘要行（⚒ 短语）+ 展开逐条（✓/✗ 措辞/耗时）+ 单条 detail（bash 走 MdCodeBlock，其余 prettyArgs） |
| `ets/components/ProcessGroup.ets` | 官方 web 式过程组（对齐 dsh-client-ui-chat processTitle）：组头 🔧+官方组标题（进行中「正在…/准备…」词表+liveProcessDetail detail 附加，无 running 工具取组内 reasoning 尾段；完成组 done 词 counts 降序取前 3 类组合——2 类「并」/≥3 类「，」/>3 类「等」/空组「已完成分析」）+ 总耗时 → 展开后 ToolBlock 逐行；四档 detail 模式收口 ChatWorkSteps（concise 只留组头不可展开 / standard 展开仅工具行 / detailed 现状+最新一轮 deferCollapse / verbose 平铺不走本组件），恒展开 isGroupForceOpen（组后同轮有 user 或轮未结束），展开集合 key=组内首个 callId（无 callId 'seq<seq>'），组件经 AppStorage('dshExpandedVersion') @Watch 回读 store.workSteps；answerable 回调查 store.pendingQuestions |
| `ets/components/ThinkBlock.ets` | 深度思考可折叠小块（从 MessageList 切出）：🧭 + 「深度思考中…/已深度思考」+ ⌃⌄；流式默认展开、流式结束自动收起、用户手动展开后不再强制折叠；展开走 MdView small；收起且 showPreview（policyOf(dshWorkStepsDetail).settledReasoningPreview，concise 档 false）时显示 reasoning 首行预览（reasoningPreviewOf，caption 弱化） |
| `ets/components/ToolBlock.ets` | 工具行五态与展开详情（官方 dsh-client-ui-tool ToolRow/AskQuestionRow 口径，从 ProcessGroup 拆出控行数）：行=[kind 图标]+toolTitle+summary 同行+状态字+箭头——running（resultText===null 且 !failed→「运行中」caption）/error（failed→「失败」红，summary 换 resultText 首行红）/ok（无状态字）；standard 档不展开；展开详情分派 detailModeOf——edit/write→DiffBlock（fileDiffOfCall，9 行+「… 其余 N 行 +A -D」行内展开）/commands→命令正文 MdCodeBlock+结果/read→8 行窗口+「显示 X 行中的 Y 行」/ask→ask_user_question 特化（answered 逐问卡（问题 brand+答案列表/未回答灰），否则 verdict+问题列表）/其余 IN/OUT（run_code 只显示 code 正文，JSON 美化截 200，web 空结果「未找到结果」）；ask 行摘要走 askSummaryOf 五态（等待中/已继续；仍可回答/已关闭/n,m 已回答），answerable 由父层传查询回调 |
| `ets/components/HitlPanel.ets` | 提问/审批卡：审批（顶部状态条 圆点+「等待审批」，risk=full-access 标题「工具 X 请求越权执行」else「DSH 请求使用 X」，reason monospace，决定提交后按钮禁用 opacity 0.5——协议只有「允许一次」无「始终允许」，警示底 拒绝/允许一次）先、提问（选项 chips 单选清旧 + 自定义输入 canSubmit）后；限高 0.5 屏 |
| `ets/components/ImageTile.ets` | 收图渲染四态（加载/像素/错误重试/全屏）：createImageSource→PixelMap→Image 260 Cover，点按 bindContentCover 全屏 |
| `ets/components/MessageActions.ets` | 消息操作条：复制（pasteboard 回弹）/喜欢/朗读（Tts）/分享（Share）/⟳ 重新生成 |
| `ets/components/ModelSheet.ets` | 调整模型 bindSheet：分组折叠（默认展开当前）+ pending 提示 + reasoning chips + 确认（st.selectModel） |
| `ets/components/ProjectionSheets.ets` | 会话统计/运行轨迹两 sheet（智能团队/待办已切出到 ProjectionTeamSheets，控行数）；TrajectorySheet 支持 showHeader=false 内嵌复用（代码工作视图①段） |
| `ets/components/ProjectionTeamSheets.ets` | 智能团队/待办任务两 sheet（从 ProjectionSheets 切出）：团队三指挥 chip + 成员/任务/子代理行；待办状态圆点与删除线 |
| `ets/components/PermissionSheet.ets` | 会话权限档位 sheet（从 Composer 拆出）：aboutToAppear 拉清单 + pick/apply + danger 二次确认 |
| `ets/components/ComposerBanners.ets` | 输入条两条横幅（从 Composer 切出，控行数）：ErrorBanner（错误「点按查看」）与 HintBanner（提示可带 danger 色 + 关闭钮） |
| `ets/components/ComposerPanels.ets` | 输入面板：命令补全（缓存切会话失效/前缀过滤）与 @ 文件补全（多根合并 label/ 前缀 + 目录下钻 + 失败重试） |
| `ets/ui/theme.ets` | design-tokens.md 的鸿蒙翻译：DsPalette/DsColors（dark 构造语义别名，含代码差异四色 diffAddBg/Fg、diffDelBg/Fg）/DsTypography/DsSpacing；改样式先改 token 文档再改这里 |
| `ets/platform/WsTransport.ets` | @ohos.web.websocket 实现 WebSocketTransport：header 小写键 + protocol 单值，connectTimeoutMs settled 防竞态 |
| `ets/platform/HttpTransport.ets` | @ohos.net.http 实现 HttpTransport：响应头键小写收敛；PATCH 枚举缺失走字符串透传（真机待验） |
| `ets/platform/PlatformBridge.ets` | ArkTimers（setTimeout/clearTimeout）+ timeZoneId（Intl→UTC 兜底）+ PrefsStore（preferences 单例，getString/putString/removeKey） |
| `ets/platform/Dlog.ets` | hilog 封装（DOMAIN 0xD5C0，info/warn/error）——core 层禁 import @kit，日志实现只在 platform |
| `ets/platform/PhotoPick.ets` | 系统图库选图（photoAccessHelper PhotoViewPicker）→ 临时文件读字节 + 魔数嗅探 mediaType |
| `ets/platform/Tts.ets` | CoreSpeechKit 朗读（zh-CN，speak/stopSpeak，音量语速走 extraParams） |
| `ets/platform/Share.ets` | 系统分享面板（Want ohos.want.action.sendData text/plain） |
| `ets/core/Breakpoints.ts` | 窗口断点纯逻辑（R007 一多）：`breakpointOf` 归一 sm/md/lg + 三档尺寸查询（contentMaxWidth 0/720/840、drawerWidth 288/352/400、sheetMaxWidth 0/640/720、drawerFraction 0.8/0.4/0.32）；放 core 以便 node 直测 |
| `ets/core/ChatStore.ts` | 会话状态机（chat_state.dart 全语义）：send 乐观上屏+手机工作区预建（ensureMobileWorkspace）、流式收束、防抖重拉 800ms、loadOlder 翻页去重、isCurrent 空态防串台；send() 里 collapseOnSend（next-input 时机）；workSteps:ChatWorkSteps 随会话 reset；事件分派 onEventIn 与流式工具行粘合拆到 ChatEvents/ChatStreamTools（onEvent/reattachLiveRows 转发）；streamTools:StreamToolState 容器；selectAgentPreset/loadAgentPresets 转发 |
| `ets/core/MdParser.ts` | Markdown 块级解析（围栏/#/hr/引用/列表+任务项/表格/块公式/段落）：行扫描产 MdBlock；parseMarkdown 入口 |
| `ets/core/MdInline.ts` | 行内解析：code/bold/italic/strike/link/裸 URL 最早匹配优先；snake_case 不误判 |
| `ets/core/LatexLite.ts` | 轻量 LaTeX 解析：递归下降 \frac/\sqrt/^/_/\text + SYMBOLS ~90 项；splitLatex 切 $..$/$$..$$ 段 |
| `ets/core/SimpleHighlight.ts` | 轻量代码高亮：PY/JS/GO/SQL/BASH 关键词表 + 字符串/数字/注释四类 token；语言未知纯文本 |
| `ets/core/JsonAccess.ts` | JSON 宽容守卫（入站侧）：缺键/null/类型不符→null 或默认，绝不抛异常；strOr/numOr/boolOr 便捷默认版 |
| `ets/core/Wire.ts` | WireBuilder 出站编码（null 一律省略键，encodeDefaults=false 语义，姊妹仓同源） |
| `ets/core/Models.ts` | 协议帧模型 8 类：DshSession（含可空 agentPreset）/DshWorkspace/MessageDelta/MessageCommitted/SessionLocation/DshFileEntry/DshDirectoryPage/SessionWaitResult（缺键全默认值） |
| `ets/core/Content.ts` | 消息内容部件：ContentParts 拼接规则、图片引用、交接占位正则、PromptPart（ArkTS 扁平类 + type 分派）、SlashCommand/别名过滤、斜杠/@ 草稿解析 |
| `ets/core/Credentials.ts` | 凭据数据形状（键 'dsh.credentials'，baseUrl+token）；持久化留 entry 层（preferences） |
| `ets/core/ImageMediaType.ts` | 图片白名单 4 种 + 魔数嗅探（PNG/JPEG/GIF/WEBP/BMP/AVIF/HEIC）+ 扩展名映射 |
| `ets/core/Transport.ts` | 传输抽象：HttpRequest/HttpResponse/HttpTransport、WebSocketTransport.open→EventSocketHandle、TimerBridge；WS/请求/心跳/退避常量（协议时序唯一出处） |
| `ets/core/GatewayEvents.ts` | GatewayState 枚举 + 扁平 GatewayEvent（十种事件 type 分派）+ RequestException（稳定错误码）+ eventFromFrame（十一支事件帧映射纯函数） |
| `ets/core/Questions.ts` | HITL 模型：UserQuestion/UserQuestionOption/PendingQuestion/PendingApproval/QuestionAnswerItem（custom 空省略，与安卓 questions.dart 对齐） |
| `ets/core/GatewayClient.ts` | WS 状态机：connect/hello 8s/心跳 25s/退避重连（1→30s，attempt+downAttempt 双代数防迟到/重复回调）、重连链 relay（reconnecting）、事件派发（映射在 GatewayEvents.eventFromFrame）、dispose；帧收发本体在 GatewayRequests |
| `ets/core/GatewayApi.ts` | WS 端点 19 个 + REST 委托层（15 个同名方法转发给 GatewayRest；历史实现已搬到 GatewayRest，含 agentPresets/selectAgentPreset）|
| `ets/core/GatewayRest.ts` | REST 实现（从 GatewayApi 拆出）：restHeaders/restJson/encodePath + pairing exchange/workspace 建改/roots 浏览/entries/path 解析/attachment/image-handoff/subagentHistory/countPending 两跳 + agentPresets（GET /chat/agent-presets）/selectAgentPreset（PUT /chat/sessions/{sid}/agent-preset，409→AGENT_PRESET_LOCKED） |
| `ets/core/GatewayRequests.ts` | 帧收发（从 GatewayClient 拆出）：requestWithTimeoutOn 请求-回显结算 + requestOn 默认 30s + subscribeOn 发出即成功 + onFrameOn 帧分派（kind=hello/event/error/ping/pong/resync 双兜底 requestId）|
| `ets/core/ToolCall.ts` | 工具调用合并模型 + 措辞表（bash/read_image…/mcp__ 直译/run_code 内嵌扫描）+ toolSummary 九键 + toolResultText（text 拼接/图片占位）|
| `ets/core/HistoryPage.ts` | 历史装配器 fromEvents：user/assistant 正文、连续 tool/call+result 合并过程组（callId 去重/就地升级）、组内 reasoning 聚合（groupReasoning，进行中组无 running 工具时组标题取尾段）、文件卡轮尾挂载、turn/end 错误卡、注入内容过滤（source.kind）+ mergeOlderMessages 翻页去重 |
| `ets/core/ToolPresent.ts` | 工具呈现纯逻辑上半（对齐官方 dsh-client-ui-chat processTitle + dsh-client-ui-tool，node 直测）：activityKind 归类（剥 tools. 前缀→14 kind，空→thinking）+ 四词表（正在/准备/done/标题）+ KIND_ICONS + kindIcon/toolTitle（pwsh/grep/glob 精确特例）+ firstLineOf/truncateDetail/stripStars/reasoningTailOf/reasoningPreviewOf + isCallRunning/isCallPreparing/hasRunningCall + liveDetailOf（LIVE_TOOL_DETAIL_KEYS 22 键序首个命中，数组取首项，截 160）+ processGroupTitle/doneGroupTitle/combineDoneWords（官方 joinTwo：2 类「并」+「已」去重、≥3 类「，」、>3 类「等」、空组「已完成分析」）+ SUMMARY_KEYS_BY_KIND/toolSummaryOf（键序摘要） |
| `ets/core/ToolDetails.ts` | 工具呈现纯逻辑下半（详情分派/询问状态机/展示档位 policy）：DETAIL_DIFF_MAX_LINES=9/DETAIL_READ_WINDOW=8/DETAIL_INPUT_MAX_CHARS=200 + detailModeOf（edit/write→diff，commands→command，read→read，questions→ask，else io）+ readLinesOf + ioInputOf（run_code 取 code 正文，JSON.stringify 2 空格截 200，坏 JSON 首行兜底）+ ioOutputOf（web 空结果「未找到结果」else「无结果」）+ askSummaryOf 五态（等待中/已继续；仍可回答/已关闭/n,m 已回答/解析失败兜底原摘要）+ answerEntries/askQuestions（坏 JSON/重复 id/缺 question→null）+ isAnswered + WorkStepsPolicy 四档（policyOf：concise/standard/detailed/verbose → foldCompletedTurns/stepGrouping collapsed|history|none/liveProcessDetail/settledReasoningPreview）+ isGroupForceOpen（组后同轮 user→true，终回复/error→false，尾随轮状态） |
| `ets/core/Projections.ts` | 轨迹分组 trajectoryOf（按 turn/seq、未知轮垫底）+ 服务端投影（todoItems/agentTeamProjectionOf，宽容零抛）+ chatStatsOf 七键统计 + prettyJson |
| `ets/core/ReleaseCheck.ts` | 新版检测：fetchLatestRelease（Gitee api/v5 → GitHub api.github.com 落链，8s 超时）+ releaseFromJson 双前缀资产 + versionParts 三段 + isNewerVersion |
| `ets/core/Hosts.ts` | 主机记录 DshHost + FNV-1a 幂等 id（BigInt 64 位）+ DSH1 宽容解码（前缀任意位置/双字母表/补 =/截 {...} 重试）+ upsert/remove/parse/encode 纯函数 |
| `ets/core/ModelsView.ts` | models 应答收敛（SessionModels/groups/failures/current）+ parseSelectModelReply + reasoningEffortLabel |
| `ets/core/Permissions.ts` | permission-options 收敛（PermissionCatalog/Option）+ 本地中文标签（label/descriptionLabel/needsConfirm/isDerived）+ permissionLabelOf |
| `ets/core/MobileWorkspace.ts` | 手机工作区约定：ensureMobileWorkspace（缓存→标题匹配→.dsh-mobile 建目录→REST 登记→改名，全失败回 null 不阻断）+ prepareSessionFor + oldestSeqOf |
| `ets/core/ChatActions.ts` | 会话动作集（store 参数纯函数）：runCommandIn 命令卡（✓/✗ 就地改写）/regenerateAtIn 重生成/cancelTurnIn 停止/setPermissionIn（NO_SESSION 拒） |
| `ets/core/ChatHitl.ts` | HITL 动作集（从 ChatStore 拆出，store 参数纯函数）：refreshPendingMarksIn 抽屉角标两跳计数/pendingMarkOfIn/answerQuestionIn/cancelQuestionIn/decideApprovalIn |
| `ets/core/ChatHistory.ts` | 历史装载与翻页（从 ChatStore 拆出，store 参数纯函数）：reloadHistoryIn 重拉（本地命令卡灌回尾部）+ loadOlderIn 向上翻页（beforeSeq=最小 seq、合并去重、跨会话结果丢弃）|
| `ets/core/ChatStreamTools.ts` | 流式工具行↔store 粘合（从 ChatStore 拆出，store 参数纯函数）：bumpStreamToolsIn 版本广播/clearStreamToolsIn 清流+去合成卡/dropSyntheticGroupsIn 回收 seq=-1 占位组/afterLiveRowsIn 每帧并入+通知/syncLiveRowsIntoMessagesIn live 行并入运行中轮（callId 命中 mergeLiveRow 就地升级、未命中追加、无组追加合成卡）/reattachLiveRowsIn reload 后重挂 |
| `ets/core/ChatEvents.ts` | Gateway 事件分派（从 ChatStore 拆出，store 参数纯函数）：onEventIn——DELTA 显式分派 text/reasoning/tool-call/tool-call-end（未知 kind 只抬流式态不渲染，防新协议帧 JSON 漏进气泡）/TOOL_CALL/TOOL_RESULT 进 StreamToolState、COMMITTED assistant 清流+reload+collapseTurnOnCompletion（user 走防抖）、TURN_FAILED 清流+lastError、RESYNC/SESSION_EVENT 防抖重拉、其余 hitl.onEvent 兜底 |
| `ets/core/StreamTools.ts` | 流式工具行状态机（bridge 四帧→行；对齐安卓 streaming_tools.dart _rowFor）：StreamToolState 容器（rows+indexToCallId 映射；缺 callId 首包落 'idx<index>' 占位行、真实 callId 首现就地改键迁移收编+记映射、续包按 index 找回）applyDelta/applyEnd/applyCall/applyResult + 纯函数 exitBadgeOf（结果文本尾 [exit code: N]/[killed by signal: X]）/statusFromErrorCode（interrupted→stopped/ASK_CANCELLED→cancelled/未知降级失败）/rankOf（终态>有结果>running>preparing）/mergeLiveRow（rank 守卫防降级）+ TOOL_STATUS_* 三常量 |
| `ets/core/WorkSteps.ts` | 通用设置①②③纯逻辑：WorkStepsDetail/CollapseTiming/FoldedReplies 解析（未知回退 detailed/completion/all）+ 四偏好键常量（dsh.workStepsDetail 等）+ turnsOf 轮分组（user 起轮）+ visibleMessagesOf 折叠回复（final 档完成轮只留最后一条正文助手消息；运行中轮全可见；user/process/error/files/command 卡全保留）+ processGroupKey（首个 callId，无 callId 'seq<seq>'）+ lastTurnGroupKeys（completion 自动收起用） |
| `ets/core/CodeDiff.ts` | 本轮代码差异纯逻辑：fileDiffOfCall 从 edit（file_path/old_string/new_string→−old/＋new）/write（file_path/content→全＋）工具调用提取 FileDiff（行 type add/del/ctx，ctx 暂未产出保留档位）+ codeDiffsOfTurn 同 path 聚合保序 + codeDiffsOfLastTurn |
| `ets/core/AgentPresets.ts` | Agent 预设模型：AgentPreset(id/name/description/trust/isDefault/available) fromJson 全宽容（姊妹仓 0.2.x 无 trust 字段实证→默认 system 兜底）+ listFrom + toJson（round-trip，description null 省键） |
| `ets/core/ChatWorkSteps.ts` | 工作步骤运行时状态（从 ChatStore 拆出）：detail/timing 偏好应用（concise/standard/verbose 收 expanded，verbose 靠 isExpanded 默认 true）+ expandedGroups Set（key=callId）+ snapshotExpanded 自增版本（AppStorage 'dshExpandedVersion' 桥）+ isExpanded/toggle（concise 拒）+ collapseTurnOnCompletion（轮 committed 后收起；detailed=history 档 deferCollapse 只收倒数轮、最新一轮保持展开）+ collapseOnSend（detailed 收当前全部；concise/standard 仅 next-input 时机收，时机门内聚在本类）+ Agent 预设缓存（currentAgentPreset/cachedAgentPresets）+ selectAgentPresetIn（PUT 成功回填+loadSessions，NO_SESSION 拒） |
| `ets/core/SessionGroups.ts` | 会话抽屉分组纯函数：groupSessionsByTime 先按时间分桶（今天/昨天/更早，超 2 天折叠）、桶内按工作区聚合（同区只显示一次小节标题），visibleRowsOf 处理「更早」展开态；dayBucketOf 按本地日历天分桶 |
| `ets/core/AppUpdate.ts` | 检查更新（华为应用市场口径）：UpdateCheckResult 结果对象 + updateErrorMessage SDK 错误码（1009400001~7/401）中文映射 + NOT_SUPPORTED_MESSAGE；平台调用在 SettingsView（updateManager.checkAppUpdate / showUpdateDialog） |
| `ets/core/AtMention.ts` | @ 文件引用面板纯逻辑（从 Composer 抽出）：AtEntry 条目模型 + mergeAtEntries 多根合并（label/ 前缀、query 名字前缀过滤不区分大小写、逐根容错 okRoots 计数）+ inSubDirectory 全失败判定 + loadMergedAtEntries（逐根拉取合并，@ 补全与「选择项目中的内容」共用）；Composer 只做拉取与状态搬运 |
| `ets/core/SessionLocation.ts` | 新建会话工作目录纯逻辑（对照安卓 session_location_sheet.dart）：SessionLocation(rootId,cwd,label)+key 契约串、locationLabel（''=根目录）、recentLocations（历史会话 (rootId,cwd) 去重保序、跳过无根会话）、locationSubtitle（优先 cwdAbsolute 退回 rootId）、parentPath 逐级上退、locationChipLabel 空态 chip 文案 |
| `ets/components/SessionLocationSheet.ets` | 工作目录选择面板：默认「手机会话」项 + 最近使用列表 + 授权根逐级浏览（空根自动跳到下一个有子目录的根、多根可点标题切换、面包屑「用此目录」）；选中写 store.pendingLocation，首条消息走 session-create{rootId,cwd} |
| `ets/components/SettingsGeneralSection.ets` | 设置页「通用」四行（从 SettingsView 切出，控行数，官方 Web 文案逐字对齐）：工作步骤展示四 chip（concise/standard/detailed/verbose）+ 收起时机（completion/next-input）+ 折叠回复（all/final，verbose 档隐藏该行）+ 显示代码工作视图开关；偏好键带点官方 token，AppStorage 无点驼峰（dshWorkStepsDetail 等），写 PrefsStore |
| `ets/components/CodeWorkSheet.ets` | 代码工作视图 sheet（官方 developerTools）：三段 chip 切换 —— ①运行轨迹（官方描述 + TrajectorySheet showHeader=false 内嵌）②本轮代码差异（core/CodeDiff 本地提取最后一轮 edit/write，+/- 行着色 theme.diffAdd*/diffDel*，卡底 bgLayer1）③Agent 预设（GET /chat/agent-presets 列表 + 当前项打勾；非 blank 会话整列表置灰「首条消息后锁定」，点选走 PUT，409 AGENT_PRESET_LOCKED 行内提示「已锁定，仅空白会话可切换」） |
| `ets/core/ChatLabels.ts` | 展示文案纯函数：sessionTitleOf/deviceLabelOf/connectionLabelOf/stateLabelOf（安卓 chat_labels 口径） |
| `ets/core/HitlStore.ts` | HITL 挂起表：pendingQuestions/approvals Map + session 过滤 + onEvent 四分支（返回是否变化）+ answer/cancel/decide（api 参数，成功即本地摘卡） |
| `ets/core/ImageRef.ts` | 收图引用：DsImageRef（attachmentId/handoffName 二选一 + cacheKey）+ imageRefsOf/handoffRefOf（交接占位正则复用 Content） |
| `ets/core/ImageFetcher.ts` | 图片字节拉取：进程内 Map 缓存不淘汰 + EMPTY 校验（attachment 带 sessionId/handoff 直拉） |
| `ets/core/Files.ts` | 文件树模型：GatewayRoot/GatewayEntry（非 file/directory 回 null，sortList 目录优先）/ResolvedFile |

### harmony/test/（node 单测，与 ets/core 同款模式）

| 文件 | 覆盖 |
|---|---|
| `harmony/test/cases/version-contract.test.ts` | AppScope versionName/Code 与 entry/oh-package 版本一致性机检（防 AGC 拒收同 versionCode 重复包） |
| `harmony/test/cases/json-access.test.ts` | JsonAccess 宽容守卫矩阵（坏形状不抛） |
| `harmony/test/cases/models.test.ts` | 8 类帧模型缺键默认值 + round-trip |
| `harmony/test/cases/content.test.ts` | ContentParts 拼接/图片引用/交接正则/PromptPart 编码键省略/命令过滤/@草稿 |
| `harmony/test/cases/credentials.test.ts` | 凭据 encode/decode/坏 JSON 清空 |
| `harmony/test/cases/image-media-type.test.ts` | 魔数嗅探全表 + 白名单 + 扩展名映射 |
| `harmony/test/cases/gateway-client.test.ts` | WS 状态机 15 用例：NO_TOKEN/组帧/PROTOCOL/hello 超时/退避序列/请求配对/超时/心跳/事件分发/resync/dispose/迟到回调防护 |
| `harmony/test/cases/questions.test.ts` | HITL 模型宽容解析 + custom 空省略 + JSON 往返 |
| `harmony/test/cases/gateway-api.test.ts` | WS 端点 15 用例：帧形状（键名对齐安卓）/requestId 配对/错误映射（BAD_REPLY/PERMISSION/QUESTION_REJECTED/APPROVAL_REJECTED）/history 装配/subagentHistory REST |
| `harmony/test/cases/history-page.test.ts` | 装配器 11 用例：分组语义（安卓 models_test 同款）/措辞表/文件卡轮尾/错误卡/hasMore/projections |
| `harmony/test/cases/hosts-models-permissions.test.ts` | 12 用例：FNV 幂等/DSH1 宽容解码/主机列表操作/SessionModels 收敛/select-model 判别/权限标签 |
| `harmony/test/cases/projections-release.test.ts` | 7 用例：轨迹分组排序/todo 变体丢弃/团队投影空壳 null/发布资产双前缀/版本比较（更新检查已改走华为应用市场，ReleaseCheck 的 Gitee/GitHub 通道在鸿蒙版停用） |
| `harmony/test/cases/md-parser.test.ts` | Markdown 四件套 22 用例：块级/行内/LaTeX/高亮 + splitLatex/任务项/表格对齐 |
| `harmony/test/cases/gateway-rest.test.ts` | REST 用例：URL 拼装/头/HTTP_40x/BAD_REPLY/空 body/encode/NO_TRANSPORT + fetchQuestions 解析与 403 + agentPresets items 解析与 selectAgentPreset（PUT body/409→AGENT_PRESET_LOCKED/200 缺字段→BAD_REPLY） |
| `harmony/test/cases/chat-store.test.ts` | 会话状态容器核心：oldestSeqOf/loadSessions/openSession/newChat/send 成功与失败/delta 累积/committed 三态（含 hasReplyContent 中途 commit）/turn.start·turn.end（max-tokens 提示、aborted 不收起）/committed user 与 sessionEvent 防抖/turnFailed/resync/loadOlder 翻页去重/cancelTurn/READY 回调/deviceLabel |
| `harmony/test/cases/chat-store-actions.test.ts` | 会话交互动作：ensureMobileWorkspace 三条（命中复用/新建改名/缓存短路）/sendWithImage/runCommand ✓✗ 两卡/HITL answer·decide 摘卡/setPermission/refreshPendingMarks/openSession REST 兜底（空 callId 丢弃、403 静默、保留 WS rpcId）/refreshPendingQuestions |
| `harmony/test/cases/hitl-store.test.ts` | HITL 表 10 用例：mergeQuestions upsert/空 callId/保留旧 rpcId/采纳新 rpcId/跨会话隔离 + 两个 sessionIds 派生 + 摘卡收缩 + onEvent 四类消费 |
| `harmony/test/cases/session-groups.test.ts` | 会话抽屉分组 10 用例：今天/昨天/更早分桶、空桶、时间倒序、同刻工作区升序、工作区聚合、未分组兜底、折叠可见性、常量 |
| `harmony/test/cases/session-location.test.ts` | 工作目录 7 用例：locationLabel/最近使用去重保序（跳过无根会话）/locationSubtitle 三级回退/parentPath/locationChipLabel |
| `harmony/test/cases/app-update.test.ts` | 检查更新 6 用例：UpdateCheckResult 三态 + updateErrorMessage 错误码 (1009400001~7/401/NOT_IN_MARKET) 中文映射 |
| `harmony/test/cases/tool-detail.test.ts` | 工具详情 9 用例：formatDuration 四档（ms/s/mXs）+负值+null、bashCommandOf 认 bash/tools.bash、参数缺command/坏JSON/空串、prettyArguments 逐行+超200字截断 |
| `harmony/test/cases/work-steps.test.ts` | 工作步骤 9 用例：三偏好解析回退/turnsOf 轮分组/visibleMessagesOf all 原样与 final 过滤（运行中轮三路全可见、无候选整轮保留、process/files 卡保留）/processGroupKey callId 与 seq 兜底/lastTurnGroupKeys |
| `harmony/test/cases/code-diff.test.ts` | 代码差异 6 用例：edit −old/＋new 行序/write 全 ＋ 行与空内容/非目标工具与坏参数→null/tools.edit+tools.write 前缀识别/同 path 聚合保序/codeDiffsOfLastTurn 只取最后一轮 |
| `harmony/test/cases/tool-present.test.ts` | 工具呈现 24 用例：activityKind 全表/kindIcon 兜底/toolTitle 特例/词表截断（truncateDetail 160+…、reasoningTail 去 **）+liveDetailOf 键序与 queries 首项/processGroupTitle 进行中（preparing/detail 附加/liveProcessDetail=false/ask）/完成组组合（2 类「并」含「已」去重、≥3 类「，」、4 类「等」、空组已完成分析、count 降序并列首现）/toolSummaryOf 键序与兜底/detailModeOf 分派/ioInputOf（run_code code 正文/JSON 截 200/坏 JSON）/ioOutputOf（web 未找到结果）/askSummaryOf 五态（answerable/已关闭/计数/坏 JSON 兜底/null resultText）+answerEntries/askQuestions（multi_select 兜底/重复 id/缺字段）/answerEntries 非对象跳过/isAnswered/policyOf 四档/isGroupForceOpen 六路/五态口径与 AK 常量锚定 |
| `harmony/test/cases/stream-tools.test.ts` | 流式工具行 11 用例（2026-11-17 实时工具事件批次，对齐安卓 streaming_tools.dart）：applyDelta 建 preparing 行/缺名占位「工具调用」/真实 callId 到达后迁移收编（仅 1 行、旧 idx 键消失）/只带 index 的续包命中已迁移行/applyEnd 定稿/applyCall 转 running/applyResult 终态（failed/stopped/cancelled）/exitBadgeOf（exit code / killed by signal）/statusFromErrorCode（interrupted→stopped、ASK_CANCELLED→cancelled、未知→失败）/rankOf 降级守卫/mergeLiveRow |
| `harmony/test/cases/agent-presets.test.ts` | Agent 预设 5 用例：全字段解析/缺键回默认（0.2.x 无 trust 实证）/null 全默认/toJson round-trip（description null 省键）/listFrom |
| `harmony/test/helpers/fake-ws.ts` | FakeTimers（手动 advance）/FakeSocket（服务端扮演 + lastRequestId）/FakeHttp（队列式应答） |
| `harmony/test/helpers/chat-ctx.ts` | ChatStore 测试公共基建：drain/respond/respondHistory/userItem·assistantItem 桩/ReadyCtx/makeReady/openSession1 + createdClients 收口（after dispose，随各测试文件根上下文注册） |
| `harmony/test/package.json` / `tsconfig.json` | node:test + tsx 跑 `cases/*.test.ts`，strict TS |

### harmony/scripts/

| 文件 | 用途 |
|---|---|
| `harmony/scripts/package.sh` | 双闸门打包：node 单测 + hvigorw assembleHap（未签名）→ dist/ + SHA256SUMS |
| `harmony/scripts/toolchain-env.sh` | 工具链环境（ROOT 可用 `DSH_HARMONY_TOOLCHAIN_ROOT` 覆盖，缺省共享 _toolchain） |
| `harmony/scripts/install-harmony-toolchain.sh` | 工具链国内源部署脚本（可重放，分钟级） |

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
  `GET /api/v1/chat/agent-presets` 与 `PUT /api/v1/chat/sessions/{sid}/agent-preset`
  （Agent 预设清单与空白会话切换；409=AGENT_PRESET_LOCKED 非空白锁定——2026-11-16 通用设置批次，代码工作视图用）、
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
