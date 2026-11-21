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
| `design/tokens.dart` | DsPalette / DsColors / DsTypography —— 全部样式值唯一出口（§4.4 设置页、§4.6 FAB/滚动动效 token）；DsSpacing/DsMotion 体量大拆 `design/design_tokens_layout.dart`（part of tokens.dart，引用方只 import tokens.dart） | ✅ |
| `design/app_settings.dart` | 本地偏好 `AppSettings`（界面风格三档 / 字号缩放 / 跟随系统 / 繁忙发送模式 / **工作步骤展示四档 `WorkStepsDetail` / 收起时机 `CollapseTiming` / 收起后显示的回复 `FoldedReplies` / 显示代码工作视图 `codeWorkView`——2026-11-16 官方通用设置批次，枚举持久化存官方 token 字符串（`jsonName`，如 `next-input`），未知名回默认；`WorkStepsDetailPolicy` 派生 policy（stepGrouping/liveProcessDetail/settledReasoningPreview/foldCompletedTurns，不持久化——2026-11-17 工具调用展示批次）** / 诊断日志）+ `AppFontScaler`（与系统字号相乘的 TextScaler）；凭据分库 | ✅ 单测覆盖 |
| `bridge/models.dart` | DshSession（含 `cwd` WirePath 相对路径 = 会话目录；**可选 `agentPreset` 记桥端当前 Agent 预设 id——openapi §ChatSession.agentPreset，空白会话可 PUT 切换、首条消息后锁定**）/ DshWorkspace / MessageDelta / MessageCommitted（**`hasReplyContent` 标记 assistant 消息是否真有正文——桥 e08b6b5，内核工具执行前先提交只含 tool-call 块的无正文消息；老桥缺省 true 兼容**）（openapi §ChatSession/§ChatWorkspace，asyncapi §ChatMessageDelta/§ChatMessageCommitted）；目录选择模型 `SessionLocation`{rootId?,cwd,label} / `DshFileEntry` / `DshDirectoryPage`（2026-11-15 新建会话可选目录）；历史装配四件套拆 `history_page.dart`，经 export 继续暴露 | ✅ 单测覆盖 |
| `bridge/history_page.dart` | 从 models.dart 拆出（宪法 §7 控行数）：`SessionEvent`（内核历史事件透传）/ `DeliverableFile`（文件卡）/ `ChatMessage`（含 `images`/`files` 引用）/ `HistoryPage`（`rawEvents` 归一化 + `projections` 透传投影 + `hasMore` 真值；fromEvents 含 `turn/end` 失败解析；deliverables 文件卡**暂存挂轮尾**——`pendingFileCards` + `flushFileCards()`，flush 点 = user/message、turn/end、事件流末尾，2026-11-14 落位修复）；**`truncated`/`bytes`/`historyFormatVersion`（history 字节预算，2026-11-19）** | ✅ 单测覆盖 |
| `bridge/content.dart` | content 部件模型（从 models.dart 拆出，控行数）：`ContentParts`（text/reasoning + `images` 图片引用解析）/ `ContentImageRef` / `PromptPart` / `handoffImageNameOf`（`[Image: source: …]` 交接占位提取）/ `parseAtMentionDraft`（@ 文件引用草稿解析——光标前最近 `@片段`，含替换区间与 @ 边界判定，m03878） | ✅ 单测覆盖 |
| `bridge/projections.dart` | 纯 Dart 投影解析：`trajectoryOf()` 客户端按 data.turn 分组原始事件（轨迹 Sheet）；`todoItems()` / `agentTeamProjectionOf()` 读服务端 `projections.values.*`（团队 / TODO）；全部容忍投影缺席 | ✅ 单测覆盖 |
| `bridge/tool_call.dart` | ToolCallInfo + 工具措辞表 `toolPhrases` + 摘要 `toolSummary` + `RawToolCall` / `extractToolCalls`（从 models.dart 拆出，控行数）；**`ToolCallInfo.meta` 存 `tool/result` 的 `data.meta`（桥原样透传）——改动卡据此拿 edit/write 的真实 oldText/newText，见 §4.17** | ✅ 单测覆盖 |
| `bridge/gateway.dart` | WS `/ws/mobile`：子协议 `dsh-mobile-v1`、hello.protocol=3、requestId（**data 内回显**）、退避重连 1→2→4→8→16s、心跳 25s（连接面本体；业务封装拆 `gateway_api.dart`，事件模型拆 `gateway_events.dart`，均 re-export，消费方只 import 本文件）；`chat.deliverables.presented` 实时帧转 `SessionEventReceived('deliverables/presented')` 触发防抖重拉（2026-11-14）；**`chat.turn.start`/`chat.turn.end` 帧转 `TurnStartedEvent`/`TurnEndedEvent`（reason.kind 宽容解析，2026-11-17）**；**2026-11-19 协议对齐：解析 `hello.capabilities`（`List<String> capabilities` + `hasCapability()`）与 `hello.port`；`onDone`/`onError` 读 WS close code 走 `_onDown(code, reason)`——4001 收口 `AUTH_FAILED` 不再重连、1009 提示帧超限、其余按退避接力（重连失败只在 NO_TOKEN/PROTOCOL 收口，别把 CONNECT_FAIL 当终态），挂起表抽到 `gateway_pending.dart`；**2026-11-20 真机：`_downHandled` 闸门让同一次掉线只收口一次（否则 failAll 唤醒的调用方立刻重发 → 又进 `_onDown`，打成微任务环）；心跳静默只记日志不判死（判死权在服务端）；逐帧 `gw <- kind=`/`gw event` 打点删掉——流式期每帧同步写盘会把 UI 线程写死（真机 ANR）**；**2026-11-20 加入 `dshrb-v1` 可选子协议（`_subprotocols()` 统一定义清单，`dsh-mobile-v1` 位置无关）+ `kernel-endpoints`/`kernel-call-result` 两帧分发（按 `callId` 结算）+ hello 时作废旧目录 + `_onDown` 一并 `failAll` 内核在飞调用；新增 `sendRawFrame()`/`kernelCallRegistry` 两个公开桥接给 `gateway_kernel.dart` 用** | ✅ 装机验证 |
| `bridge/gateway_events.dart` | 从 gateway.dart 拆出（宪法 §7 控行数）：`GatewayState` / `GatewayEvent` sealed（Delta/Committed/**TurnStarted/TurnEnded**/TurnFailed/Resync/SessionEventReceived/ToolCall/ToolResult）/ `RequestException`；**`LinkClosedEvent{code, reason}`（revoked=4001 / frameTooLarge=1009），2026-11-19** | ✅ |
| `bridge/gateway_api.dart` | 从 gateway.dart 拆出：`extension GatewayApi on GatewayClient`——workspaces/sessions/**session-create（workspaceId 预建）与 `createSessionAt({rootId,cwd})`（自选目录预建，失败显式报错勿静默回退）**/directory-create/**`listDirectory()`（file-list 帧目录浏览 → DshDirectoryPage）**/REST 建改工作区/history（`beforeSeq` 翻页 + `hasMore` 真值）/attachments 与 image-handoff 取图/sendText(mode+contentParts)/cancelTurn/permission/models/commands/**command-execute**/select-model/**`agentPresets()` 与 `selectAgentPreset(sessionId, presetId)`（Agent 预设清单与空白会话切换——2026-11-16 通用设置批次，409=AGENT_PRESET_LOCKED）**；**2026-11-19 协议对齐：`fetchImageHandoff(name, sessionId)` 补 sessionId（bridge 强制两参，缺一 400 BODY_INVALID）；新增 `sessionStats()` / `contextUsage()`（`session-stats`/`context-usage` 帧，键缺失回 null）；`history()` 解析 `truncated`/`bytes`/`historyFormatVersion`；路径拼装抽 `imageHandoffPath()` 纯函数供单测** | ✅ 单测覆盖 |
| `bridge/gateway_http.dart` | REST 字节下载 `gatewayHttpBytes()`（GET + Bearer + 30s 超时，附件/交接图共用） | ✅ |
| `bridge/gateway_pending.dart` | 挂起请求表（从 gateway.dart 拆出，控行数）：`PendingRequest`（type + completer + isCompleted） / `PendingRegistry`（add / take(requestId) / failOfType(requestType) —— error 帧不带 requestId 时按请求类型兜底 / failAll —— 掉线时统一拒绝） + `PendingRegistry.fail()` 先挂 `catchError` 再 completeError，防「无人 await」冒未捕获异步异常（2026-11-19 协议对齐） | ✅ 单测覆盖 |
| `bridge/gateway_liveness.dart` | 连接活性判据（2026-11-19 协议对齐新建，从 gateway.dart 拆出）：`kLivenessSilentLimit`=45s + `Liveness.seenAt(now)` / `isStaleAt(now)` / `silentFor(now)` / `reset()`；判据是**最近一次收到帧**（坏帧也算活着）而不是「最近一次状态迁移」；**2026-11-20 真机改为纯诊断**：静默只写日志、不再触发 `_onDown`——客户端抢先判死会误杀活连接（每 ~50s 一次无谓重连，收尾把主线程拖住 → ANR），判死交回服务端心跳 | ✅ 单测覆盖 |
| `bridge/gateway_kernel.dart` | **通用内核调用面（`dshrb-v1` 子协议，2026-11-20 接入，issue #26 阶段 5）**：`KernelEndpoint`（`{endpoint, scope, summary, stream, wires}`，工厂宽容未知字段——元素形状未冻结）/ `KernelCallResult`（`.ok(value)` / `.failed(code, message)`，`value` 形状由端点定、不保证）/ `KernelCallRegistry`（**按 `callId` 配对**的在飞表，与按 `requestId` 配对的 `PendingRegistry` 分开；取消后晚到的结果帧按协议静默丢弃；`failAll` 先挂 `catchError` 再 `completeError`）+ `extension GatewayKernel on GatewayClient`（`kernelEndpoints` = 目录 / `kernelCallsEnabled` = 能力位 `kernel-call-v1` / `kernelEndpoint()` / `kernelCall(endpoint, args, callId, timeout 35s)` / `kernelCancel()`）；目录是**唯一**端点真相（不硬编码端点表），空表 = 能力不可用；重试必须复用同一个 `callId` 才命中桥侧 24h 幂等表 | ✅ 单测覆盖 |
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
| `bridge/dlog.dart` | 文件日志 `/data/data/<pkg>/files/dsh.log`（vivo 过滤 flutter 日志，只能落文件）；`enabled` 开关 + `read()` 供设置页诊断日志区；2026-11-20 加 `dedupeWindow`=2s 同句抑制（下一条不同消息前先落「上一条重复 N 次」）与 `maxBytes`=2 MiB 尾部保留（对齐行首），判据抽成纯函数 `shouldSuppress()`/`trimOffset()`；**2026-11-20 真机：裁剪阈值改 `maxBytes×1.25`（2.5 MiB）才整份重写**——按行触发会退化成「每写一行读+写 2 MiB」，流式期直接 ANR；同时删掉三处逐帧打点 | ✅ 单测 |
| `ui/chat_page.dart` | 聊天主页：顶栏（会话名 + 新对话加号接 `newChat` + ⋯ 溢出菜单） / 空态问候（**工作目录 chip：`pendingLocation?.label` 或「手机会话（默认）」，onTap 弹 `session_location_sheet`——2026-11-15**） / 设置页入口；消息列表拆到 `chat_list.dart`、消息项拆到 `chat_message_items.dart`（均为独立库，宪法 §7 控行数）；**主页 PopScope 退出 APP 二次确认——首次返回提示「再按一次退出 DSH」，2s 内再按 SystemNavigator.pop 真退出（第五轮勘误，替代上一版错装在设置页的双击退出）** | ✅ 装机验证 |
| `ui/chat_message_items.dart` | 独立库（2026-11-20 task-6 从 chat_page.dart 的 part 拆出，类名去下划线 `MessageItem`/`StreamingItem`/`DeliverablesCard`）：消息项（双击复制整条；用户气泡内嵌历史图片 `DsChatImage`；助手消息 image-handoff 占位转图；**process 组按 `workStepsDetail` 渲染：verbose 档平铺逐条 `DsToolRow`；其余档 `DsProcessGroup` + 上层推导 turnRunning/forceOpen/`reasoningHint`（同轮最近 assistant reasoning，2026-11-17）与 `answerable`（HitlState.sessionQuestions 按 callId 匹配，2026-11-17）；展开态提升到 `GroupExpandState`（chat_expand_state.dart）**；**deliverables/presented → `DeliverablesCard` 文件卡：.md 点开全屏渲染（MdViewerPage），其他类型系统打开（openFile），失败回退分享——m03452 改进，第四轮反馈 6**）；**role=='command' 命令卡（斜杠命令本地回执：命令行 + ✓/✗ 结果，m03878）** / 流式项（思考行迁 `chat_thinking.dart`，2026-11-20 task-7） / 消息操作条（重新生成接线） | ✅ 装机验证 |
| `ui/chat_rows.dart` | 会话页行模型（2026-11-20 task-6 整页移植自 dsh-go 的 chat_rows.dart，纯逻辑不依赖 widget）：`sealed class ChatRow`（key/stable/index/cacheable）→ UserRow / AssistantRow / ProcessRow（key=`g`+首个 callId）/ ErrorRow / FilesRow / CommandRow / TurnEndRow（轮尾「已完成，用时 N 秒」）/ HistoryMoreRow / HistoryTruncatedRow / StreamingProcessRow / StreamingTextRow / MaxTokensRow / LinkErrorRow；`deriveRows(ChatRowsInput)` 按 visibleMessagesOf 过滤后逐条派生，轮内有过程组才插轮尾行，流式与截断提示排最后；`ChatRowsInput.signature` 是派生输入指纹（消息条数 + 末条 seq + 身份哈希 + 各开关），供上层判断要不要重算；`didPrependHistory(previous, next)` 判「这次派生是不是前插了更早的历史」（消息变多且最老非负 seq 变小），列表据此清行缓存而不动锚点；**`ChangeCardRow`（key `ch<anchorSeq>`）与 `ArtifactCardRow`（key `ar<anchorSeq>`）——已完成轮在 TurnEndRow 之后各插一张卡，正在跑的最后一轮不出卡（2026-11-21 task-12）** | ✅ 单测覆盖 |
| `ui/chat_header_status.dart` | 顶栏状态机（2026-11-20 task-6，纯逻辑）：`ChatStatusTone{idle,busy,warn,error,ok}` + `chatHeaderStatus({connection, streaming, waitingApproval, waitingAnswer, hostLabel})`——未连接 idle「未连接」/ 连接中 busy「连接中」/ 掉线 authFailed·closed error「已断开」/ 就绪时等待审批 warn「等待审批」·等待回答 warn「等待回答」·生成中 busy「生成中」·否则 ok 显示主机名；**颜色只是辅助，状态一律带文字** | ✅ 单测覆盖 |
| `ui/chat_shell.dart` | 会话页外壳（2026-11-20 task-6，结构移植自 dsh-go 的 `_ChatLayout`）：`CustomMultiChildLayout` 四槽（header / body / composer / veil）；**输入条先量高度 → 正文区伸到输入条上沿以下 `chatListOverlap` → 底部渐隐带（`_Veil`，实心托底 + 往上羽化 `chatVeilFeather`）盖住交界**；顶栏自己吃掉顶部安全区（body 用 `MediaQuery.removePadding(removeTop:true)`）；composer 槽 SafeArea(bottom: chatComposerBottomPad) + `LayoutBuilder` 按实际页宽取 `floatingColumnWidth`（§4.16；抽屉缩窄页面时跟着收） | ✅ analyze |
| `ui/chat_top_bar.dart` | 会话页顶栏（2026-11-20 task-6，结构移植自 dsh-go 的 chat_header.dart，不复刻玻璃自绘）：标题行（菜单 + 会话名 + 新对话加号 + 溢出菜单插槽）+ **状态行（状态点 + 一句人话）**；`ChatStatusDot` busy 时按 `DsMotion.statusPulse` 呼吸；颜色取 `DsColors.chatStatusOk/chatStatusWarn`（dsh-go 语义色）；**2026-11-20 宽窗适配**：标题行与状态行各包 `Center + ConstrainedBox(floatingColumnWidth(LayoutBuilder 页宽))`，平板上与输入条同一列（≡ 对齐输入条左缘、⊕/⋮ 对齐右缘），窄窗自然退化为整屏（§4.15/§4.16） | ✅ analyze |
| `ui/chat_list.dart` | 会话列表（2026-11-20 task-6 整页移植自 dsh-go 的 chat_list.dart）：**居中锚定的两段滚动**——`CustomScrollView(center: _centerKey, anchor:)` 把列表拆成 before 段（打开时已有的历史，反向生长）与 center 段（本次会话新内容，正向生长）；**不变量：before 段 delegate 下标 i → 行数组 rows[split-1-i]，前插 n 条更早历史时行数组头部多 n、split 同样多 n → 老行 delegate 下标不变 → 可见内容不跳位**（探针实测 test/chat_list_geometry_test.dart，Flutter 原生语义下无需手写锚点校正）；分界 `_split` 取最后一条 stable 行；**行间距统一在 `chat_row_gap.dart` 算，行框统一垫上（行内组件不再自带顶距）；正文列宽在 `LayoutBuilder` 里按这一块实际拿到的页宽算 `readableColumnWidth(constraints.maxWidth)`（§4.16：≤720 用满、更宽按 0.9 缩放；抽屉缩窄页面时跟着收）**；行级 widget 缓存 `_built`（行对象 identical、间距与列宽都没变才复用，前插时清空）；贴底跟随判据在 `scroll_follow.dart`（wantsBottom 粘性意图 + 80ms 解冻 + 140ms 渐显）；**slivers = 顶部 `chatListTopGap` 呼吸空间 → before 段 → center 段 → 尾部 `SliverToBoxAdapter(chatListOverlap + chatVeilFeather)`**（尾部 spacer 与 anchor 同值，滚到底时最后一条消息停在渐隐带之上）；`toggleTurn(state, turn)` 轮尾整轮过程组一起开合 | ✅ analyze |
| `ui/chat_row_gap.dart` | 会话列表行间距规则（2026-11-20 task-6，独立库）：`chatRowGapBefore(row, previous)` 算出这一行上方该留的空——换轮 `chatGapNewTurn` 24、同轮 `chatGapSameTurn` 8、相邻过程行 `chatGapProcess` 0、文件卡 / 改动卡 / 生成卡 `chatGapCard` 12、轮尾脚注 `chatGapFootnote` 4；**间距只在这里给一次，行内组件不再自带顶距**（结构参照 dsh-go chat_list.dart 的 `_gapBefore`） | ✅ 单测覆盖 |
| `ui/window_class.dart` | 窗口尺寸类 + 可读列宽（2026-11-20 task-9 宽窗适配 / 2026-11-21 task-11 全 App 可读列，docs/design-tokens.md §4.15/§4.16）：`enum DsWindowClass { compact, medium, expanded }` + `static of(Size)`（**高 < `windowCompactHeight` 480 一律紧凑**——手机横屏 412 高因此不进入分栏）+ `sidebarWidth`（288 / 320）/ `pageInsetFor(窗口宽)`（页面让路距离 = 抽屉宽；紧凑窗推走、宽窗缩窄）；列宽收敛成两条纯函数：`readableColumnWidth(可用宽)`（≤`readableBaseWidth` 720 用满，更宽 `min(可用宽, 可用宽 × readableScale 0.9)`，**没有第二道上限**）与 `floatingColumnWidth(可用宽)`（可读列两侧各窄 `chatFloatInset`，没有富余时铺满，供顶栏/输入条）；`modalSheetConstraints(context)` 覆盖 M3 bottom sheet 默认的 `maxWidth: 640`；顶层 `windowClassOf(context)` 读 `MediaQuery.sizeOf`。**三种窗口一律抽屉式**（真机反馈 2026-11-20：平板横屏也不要常驻侧栏，只要别把会话页推出屏外）。只做判断不做布局：顶栏限宽、抽屉宽度、推挤距离、HITL 卡宽、二级页正文列、模态 sheet 各自按它取参数 | ✅ 单测覆盖 |
| `ui/chat_row_view.dart` | 行渲染层（2026-11-20 task-6 独立库）：`chatRowView(row, {state, colors, onToggleTurn})` 把一行画成一个控件——消息类行走 `MessageItem`、轮尾行走 `TurnProcessRow`、流式行走流式过程组/正文、提示行走提示组件；**依赖可变状态的行（过程组展开态、轮尾聚合态）包 `ListenableBuilder` 自更新，不必让整张列表缓存失效**；`RowFadeIn` 新行入场淡入（token `rowFadeIn`）；**`ChangeCardRow` → `ChangeCard`、`ArtifactCardRow` → `ArtifactCard`（§4.17）** | ✅ analyze |
| `ui/turn_changes.dart` | 本轮改动 / 生成文件推导（纯逻辑，2026-11-21 task-12，§4.17）：`turnChangesOf(messages, turn)` 只认成功（非 failed）的 edit/write，优先工具结果 `meta.diffs` 的 {path, oldText, newText}，退回参数 `file_path/old_string/new_string/content`；同一文件多次编辑合并计数、逐次留 `EditHunk`；`write` 的 `meta.operation=create`（或 oldText 为空）记 created；缓存 key 带 messages 实例地址（同轮不串味）、上限 200；`turnArtifactsOf(messages, turn)` 取 write 新建文件 + 回复里的 markdown 图片/文件链接（相对路径按本轮最后的 bash `meta.cwd` 拼绝对，没有 cwd 不猜）；`ArtifactKind`/`artifactKindOf` 按扩展名盖类型与「图片 · PNG」说明 | ✅ 单测覆盖 |
| `ui/chat_change_card.dart` | 「改动了 N 个文件」卡（2026-11-21 task-12，对照 dsh-go change_card.dart）：标题 + 多文件时合计 `+N/−M`；最多列 3 行（文件名 + 弱化目录 + 增删数），底栏「查看改动」+「还有 N 个文件」→ `ChatDiffPage`；复用 bgLayer1/bubbleRadius/borderL2 与 DsTypography | ✅ analyze |
| `ui/chat_diff_page.dart` | 「本轮改动」逐文件 diff 页（2026-11-21 task-12，对照 dsh-go diff_page.dart）：顶栏返回 / 标题 / 合计 / 复制路径；横向文件 chips 切换；正文绝对路径 + `+N −M 修改 K 次`，每个 hunk 标「第 i 次修改」并画红绿行（diffAdd/diffRemove/mdCodeBlockText，等宽字体） | ✅ analyze |
| `ui/chat_artifact_card.dart` | 「生成了 N 个文件」卡（2026-11-21 task-12，对照 dsh-go artifact_card.dart）：最多列 4 行，超出收进「全部 N 个文件 ⌄」；行内 40×40 缩略图（图片走网关取字节 `Image.memory`，失败退回类型图标）+ 文件名 + 「图片 · PNG」说明；⋯ 打开复制路径 / 分享 | ✅ analyze |
| `ui/chat_thinking.dart` | 思考行（2026-11-20 task-7，形态移植自 dsh-go 的 thinking_pill.dart + stream_row.dart，颜色仍用本仓 brand，图形自绘不搬 orb 引擎）：`ThinkingRow(text, colors, {streaming, answerStarted, showPreview})` —— 图形列 24（呼吸光点环 `ThinkingOrb`，思考中）/ 静止原子图标 `ThinkAtom` + 8 间距 + 文字列；**思考中 = 「思考中」扫光标签（`thinkingSweep`/`thinkingSweepPeriod`/`thinkingSweepLead`，ShaderMask 横向扫）+ 三行恒高实时窗口（`thinkingTickerRows` 3，写满一行匀速上滑一行，块高不变，列表不跳）**；正文开始后收成一行首行预览；轮结束自动收起（`streaming` 由真转假时复位）；点行展开全文（Markdown，次级排版）+ 展开区 1px 竖线走图形列中线、正文缩进 32 | ✅ analyze |
| `ui/chat_thinking_glyph.dart` | 思考行图形件（2026-11-20 task-7，独立库）：`ThinkAtom`（静止原子图标：两道交错椭圆轨道 + 中心点，自绘 path，未复用官方素材）+ `ThinkingOrb`（思考中呼吸光点环：22 个点绕圆周，半径按双波 sin 扰动、近点更亮，按 `thinkingBreath` 循环；系统关动画时静止） | ✅ analyze |
| `ui/work_steps.dart` | 收起后显示的回复纯函数（2026-11-16 官方通用设置批次）：`turnsOf`（轮 = 每条 user 到下一条 user 前）/ `lastTurnOf` / `turnIsRunning`（轮内未 committed seq<0 或流式收尾中）/ `finalReplyIndexOf`（最后一条「有可见正文且不带工具调用」的 assistant 消息）/ `visibleMessagesOf(messages, FoldedReplies, streaming)`——all 或轮运行中全可见，final 且轮完成只保留最终回答（process 组交给 A/B 收起逻辑；无合格 assistant 消息则整轮全显示不猜） | ✅ 单测覆盖 |
| `ui/chat_image.dart` | 历史图片组件 `DsChatImage`：attachment / image-handoff 双通道自动下载（`gatewayImageFetcher(gateway, sessionId)` 注入，attachments 接口必填 sessionId query，随会话切换刷新）+ 进程内字节缓存 + 失败占位可点重试（真机反馈 2026-11-04 第 1 项） | ✅ 装机验证 |
| `ui/scroll_follow.dart` | 滚动跟随纯函数：`shouldAutoFollow` / `shouldShowFab` / `computeAtBottom` / `freezeSnapshot` / `isUserScrollGesture`（只认 dragDetails），对照 companion 三处滚动实现 | ✅ 单测覆盖 |
| `ui/chat_state.dart` | ChangeNotifier：会话列表 / 打开会话（**openSession 清流式缓冲 streaming/streamText/streamReasoning 并先渲染清空态——2026-11-15 切会话深度思考串台修复**）/ 发送（纯文本与带图；新会话**分流：`pendingLocation` 已选目录 → `createSessionAt(rootId,cwd)` 建会话即定死目录；未选 → `ensureMobileWorkspace` 预建到「手机会话」工作区——2026-11-15 可选工作目录**；`setPendingLocation()` + `notifyUi()`）/ 斜杠命令 `runCommand()`（command-execute；**回执注入本地命令卡 role=='command' 并在 reloadHistory 后保留——m03878**）/ `cancelTurn()` / `regenerateAt()` / `retryLast()` / 历史翻页 `loadOlder()`（beforeSeq + seq 去重；方法体抽 `chat_history_actions.dart` 控行数）/ 流式累积 / 推送分发（含 HITL 问答/审批事件转发到 `HitlState`；**assistant committed 只在 hasReplyContent 时清正文流式缓冲（`clearStreamText`）——工具执行前的无正文提交不再整段清流/收起（桥 e08b6b5）；「回答结束后」收起时机改挂 `TurnEndedEvent`（reason∉{aborted,interrupted,error} 才收，chat_state_events.dart）；`maxTokensNotice` 截断提示位（turn.end reason=max-tokens 置位 / turn.start、send() 复位）；`dropPersistedToolRows()` reloadHistory 后按 callId 摘除已持久化流式工具行防双份；`isPersistedToolCall()` 迟到的 tool/call 帧不再往缓冲重复建行（防抖重拉让持久组刷新）**；send() 入口按「下次有新消息时」时机 `collapseOnNewInput()`）/ HITL 动作 `answerQuestion()`/`cancelQuestion()`/`decideApproval()`；分组 getter 委托 `session_groups.dart`；`newChat()` 清 pendingLocation（不沿用上次选择） | ✅ 装机验证 |
| `ui/streaming_tools.dart` | 流式工具行状态机（2026-11-17 实时工具事件批次，对齐安卓语义与官方 Web 五态）：`StreamingToolBuffer`（`_rows` 按 callId 存行 + `_indexToCallId` index→callId 映射；`_rowFor` 真实 callId 首现时删除 `'idx<index>'` 旧键并把占位行迁到 callId 键（不产生重复行）、只带 index 的续包经映射找回同行）+ `handleDelta`（拼 argumentsDelta）/ `handleEnd`（arguments 定稿 settled）/ `handleCall`（转 running）/ `handleResult`（done/failed/stopped/cancelled，errorCode=='interrupted' 与 'ASK_CANCELLED' 不算失败）/ `infos`（preparing=未 settled/running/done，缺名兜底「工具调用」）/ `processMessage`（role=='process' 合成过程组，seq=-2）/ `dropPersisted`（**reloadHistory 后按 callId 摘除已持久化行并清 index 映射——防「流式行+持久组」双份，2026-11-17**）/ `clear` | ✅ 单测覆盖 |
| `ui/chat_state_events.dart` | `part of chat_state.dart`（2026-11-17 实时工具事件批次拆出，控行数）：`_onGatewayEvent` 全事件分派——Delta 显式四路（text→streamText / reasoning→streamReasoning / tool-call→`_toolBuffer.handleDelta` / tool-call-end→`handleEnd`；**未知 kind 忽略，不得当文本渲染（老客户端契约）**）/ ToolCallEvent→handleCall / ToolResultEvent→handleResult（**均已挂 `isPersistedToolCall` 守卫：callId 已被持久过程组承载时不再往缓冲建行，改防抖重拉——迟到帧防「持久组+流式组」双份，2026-11-17**）/ CommittedEvent assistant→**hasReplyContent 时只清正文缓冲（clearStreamText，工具行继续跑）+ 重拉；不再停流/收起（内核工具执行前先提交无正文消息）**、其余→防抖重拉 / **TurnStarted→streaming=true+复位截断提示 / TurnEnded→停流+清流+（reason∉{aborted,interrupted,error}）收起 + max-tokens 置 `maxTokensNotice` + 重拉（2026-11-17）** / TurnFailed→清流+lastError+复位提示 / Resync→重拉 / SessionEventReceived→防抖重拉 / HITL 四类→hitl；**2026-11-20：delta 不再逐条写诊断日志（流式期同步写盘会拖死 UI 线程）** | ✅ analyze |
| `ui/ask_present.dart` | 提问（ask_user_question）展示纯函数（2026-11-17 从 tool_present.dart 拆出，控行数）：`AskAnswerEntry`/`AskResult`/`askResultOf`（宽容解析）/ `askQuestions`（multi_select 兼容驼峰、重复 id 或缺字段→null）/ `askSummary`（运行中「等待回答」/ errorCode=='ASK_CANCELLED'→「已取消」/ 待续「已继续工作，仍可回答」/ 已关闭「已结束」/ 已答「N/M 已回答」） | ✅ 单测覆盖 |
| `ui/hitl_state.dart` | HITL 挂起表 `HitlState`（全连接 pendingQuestions/pendingApprovals 按 callId/approvalId 去重 + 会话过滤 getter + answer/cancel/decide 动作；从 chat_state.dart 拆出控行数） | ✅ 单测覆盖 |
| `ui/chat_expand_state.dart` | 工作步骤展开态宿主（2026-11-16 通用设置批次，2026-11-17 扩展）：`processGroupKeyOf`（组内首个 callId，缺省回 `'seq<seq>'`，跨 reload 稳定）+ `mixin GroupExpandState on ChangeNotifier`（`expandedGroups` 手动展开集 + verbose 模式手动收起例外集，两集互不污染；`toggleProcessGroup(key, open:)` 以视觉态为准 + `isForceOpenDismissed`（运行中轮 forceOpen 被用户收起后的豁免表——2026-11-17）/ `isGroupExpanded`；**收起时机：`collapseOnAssistantCommitted`（回答结束后）/ `collapseOnNewInput`（下次有新消息时）；verbose 档永不自动收起**） | ✅ analyze |
| `ui/question_card.dart` | `HitlPanel`：提问卡（每题 FilterChip 单/多选 + 自定义回答输入 + 提交键，提交走 question-answer）与**审批卡官方语义（2026-11-17）：顶部 strip 状态条（小圆点 + 「等待审批」），决定提交后按钮全禁用（answered 态，本地态挂起等待 resolved 摘表）；full-access 越权标题「工具 {toolName} 请求越权执行」，standard 保持「DSH 请求使用 {toolName}」；reason 代码等宽字体；只有「拒绝」「允许一次」两键（协议 decideApproval 只收 allow bool，官方亦无「始终允许」）**；**整面板限高屏高 ×0.5（`hitlPanelMaxFraction`）内部上下滚动——2026-11-15 用户反馈内容过多时提交按钮被推出屏幕** | ✅ 单测覆盖 |
| `ui/session_groups.dart` | 会话抽屉分组纯函数 `groupSessionsByWorkspace()`：顶层按工作区分（「手机会话」置顶、其余用 workspace title、无工作区「未分组」），组内按今天/昨天/更早；单工作区单日期退化为纯日期（真机反馈第 7 项） | ✅ 单测覆盖 |
| `ui/chat_history_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`reloadChatHistory(state)` / `loadOlderMessages(state)` / `oldestSeqOf(state)`——chat_state 薄转发保 UI 调用点 | ✅ 单测覆盖 |
| `ui/chat_hitl_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`submitChatAnswer` / `skipChatQuestion` / `decideChatApproval(state,…)`——HITL 动作落 lastError 后 notifyUi；chat_state 薄转发保 UI 调用点 | ✅ analyze |
| `ui/session_location_sheet.dart` | 新建会话目录选择 sheet（2026-11-15 可选工作目录）：默认项「手机会话（默认）」+ 已选高亮（「点此恢复默认」）+ 「最近使用」按历史会话 (rootId,cwd) 去重（cwdAbsolute 副标题）+ 浏览页（面包屑 + 只列目录 + 加载更多 + 「在此目录新建会话」回传 `SessionLocation`）；`DirectoryLister` 注入点供测试 | ✅ 单测覆盖 |
| `ui/mobile_workspace.dart` | 「手机会话」工作区准备 `ensureMobileWorkspace()`：title 含「手机」的既有工作区 → 建目录 `.dsh-mobile`（directory-create，409 幂等）→ REST 登记工作区 → PATCH 改名「手机会话」；失败回 null 不阻断发送（真机反馈第 7 项） | ✅ |
| `ui/stats_sheet.dart` | 会话统计 Sheet：`chatStatsOf()` 由已加载消息本地计算（消息/工具/思考/错误数），零网络请求；对照 companion ChatStatsSheet；**服务端半边（2026-11-19）：`serverStatGroups()` 把 `session-stats` 帧的三个容器拍平为标量行（不译键名不猜单位），Sheet 内 fire-and-forget `loadServerStats()` + AnimatedBuilder；拿不到时给「桥未提供 session-stats」提示，本地七项统计不变** | ✅ 单测覆盖 |
| `ui/projection_sheets.dart` | 三个零请求面板：运行轨迹（rawEvents 本地分组、点节点展开原始 JSON；**轮次+节点渲染体抽公共 `TrajectoryBody`，轨迹面板与代码工作视图共用——2026-11-16**）/ 智能团队（projections.values.agentTeam，含三枚普通消息话术 chips，**子会话行可点进详情页，第四轮反馈 3**）/ 待办任务（projections.values.todos）；投影缺席显示空态而非隐藏入口 |
| `ui/work_view_sheet.dart` | 代码工作视图底部抽屉（2026-11-16 官方「显示代码工作视图」）：聊天页 ⋯ 菜单入口（`codeWorkView` 开启才出现）→ 三段——①运行轨迹（复用 `TrajectoryBody`）②本轮代码差异（`codeDiffsOfTurn` 取当前轮 edit/write 参数渲染 +/- 行色，超 400 行折叠「… 其余 N 行」）③Agent 预设（REST 清单 name/description/默认标记/当前打勾；空白会话可切，非 blank 置灰提示「首条消息后锁定」，409 显示「已锁定，仅空白会话可切换」） | ✅ analyze |
| `ui/code_diff.dart` | 本轮代码差异纯函数（2026-11-16）：`codeDiffOfCall(name, rawArguments)`（edit→`file_path/old_string/new_string` 生成 -old/+new 行、write→`file_path/content` 全 + 行，公共前后缀标 ctx；坏 JSON/缺 file_path 回 null 不抛；兼容 `tools.` 前缀工具名）+ `codeDiffsOfTurn(messages)`（最后一轮 process 组逐调用按序产出 `CodeDiff{path,kind,lines}`）；**`diffLinesOf(oldText, newText)` 公开给改动卡/diff 页：行级 LCS（中间的公共行也标 ctx；先裁公共前后缀，表超 40 万格退回前后缀裁剪）——2026-11-21 task-12** | ✅ 单测覆盖 |
| `ui/subagent_history_page.dart` | 子会话（团队成员）只读历史页：REST 窄口 `subagentHistory()`（GET /chat/sessions/{leadId}/subagents/{id}/messages，openapi.yaml:992-1050）+ beforeSeq 翻页 + 轻量只读消息渲染；协议明确成员会话不可写，无输入条（第四轮反馈 3） | ✅ 单测覆盖 |
| `ui/settings_page.dart` | 设置页主文件：Scaffold + 分区骨架（`settings_sections.dart` / `settings_widgets.dart` / `settings_update.dart` 是同库 `part`，共享私有成员，宪法 §7 控行数）；普通返回即退出（二次确认挪到主页——第五轮勘误：用户要的是退出 APP 二次确认，不是设置页） | ✅ 单测覆盖 |
| `ui/settings_sections.dart` | 设置页分区：连接与设备信息（hello 只读）/ 界面风格三档 / **通用（官方原文四行：工作步骤展示四档 / 工作步骤收起时机 / 收起后显示的回复——verbose 档整行隐藏 / 显示代码工作视图开关——2026-11-16）** / 字号缩放与跟随系统 / 繁忙发送模式 / 诊断日志 / 关于（含检查更新行）/ 断开连接；不摆无授权的服务端开关 | ✅ 单测覆盖 |
| `ui/settings_update.dart` | `part of settings_page.dart`：`_UpdateCheckRow` 检查新版本（1.5s 静默检查有新版才提示；手动检查三态：发现新版本→点按下载 / 已是最新 / 两站都连不上；下载轮询进度百分比 + STATUS_SUCCESSFUL 后 installApk 自动拉起安装，第二轮反馈 C；`Timer` 必须 dispose 取消，测试断言无 pending timer；本机版本运行时经 `DshPlatform.appVersion()` 读取（没读到则跳过比较，不拿 0.0.0 误报）） | ✅ 单测覆盖 |
| `ui/settings_widgets.dart` | 设置页通用组件：`_Section` / `_InfoRow` / `_ActionRow` / `_SwitchRow` / `_SegmentedRow`（**可选 `description` 描述行——官方通用设置每行带说明文字，2026-11-16**）/ `_ScopeChip` / `_WarningBanner` | ✅ 单测覆盖 |
| `ui/composer.dart` | 输入条：白浮层圆角容器 + 输入框 + 权限档位 chip + **多图附件 chip（最多 6 张、可横滑、逐张删；每张 8MiB 上限）** 与发送（纯图也亮发送键；2026-11-21 工单 2）+ **「/」斜杠命令面板**（`parseSlashDraft` 检测草稿 → commands 帧清单前缀过滤 → 浮层建议（**可滚动 + 键盘上下高亮、回车选中——m03878**）→ 点选回填；发送优先走 `onCommand`；**拉取失败不落缓存、下次输入自动重试——m04149**）+ **「@」引用面板**（`parseAtMentionDraft` 草稿检测 → gatewayListRoots+gatewayListEntries **多根逐根拉取合并**（空根不挡非空根——m04149）→ 目录按草稿里的 `/` 下钻一层、文件回填 `@path`；**「对话」分组列出 `ChatState.sessions`，选中插 `@[标题](dsh-session:<id>)`——2026-11-21 工单 3/4**）+ 发送键三态 + **加图与文件夹圆钮常驻（未连接才置灰；不再跟发送键三态联动——2026-11-21 工单 5，此前运行中空输入会整排消失）** + 底部免责提示（**流式思考期间隐藏，无思考时显示——m03759 反馈**；命令面板组件拆 `composer_widgets.dart`）+ **选图不再按文件名扩展名猜类型：用原生回传的真实 mediaType（缺失时读缓存字节魔数兜底）+ 内核 4 种白名单核对，失败原因显式弹提示（华为 HEIC 修复）** | ✅ 装机验证 |
| `ui/composer_widgets.dart` | `part of composer.dart`：基础件 `_Chip`（胶囊 chip）/ `_RoundIconButton`（圆形按钮）+ `pickComposerImage`（读选图缓存字节→base64；mediaType 由调用方按魔数/原生回传传入，不再按扩展名判——华为 HEIC 修复，m03878 拆入） | ✅ |
| `ui/composer_panels.dart` | `part of composer.dart`：`_CommandPanel`（斜杠命令建议浮层，可滚动+高亮——m03878）/ `_AtFilePanel`（@ 文件引用浮层，目录/文件图标区分，可滚动+高亮——m03878；**失败态错误行+点按重试——m04149**）+ `fetchAtEntries`（**多根逐根拉取合并**，空根不挡非空根——m04149）+ `insertAtMention`（**「选择项目中的内容」圆钮：光标处插 `@` 走与手敲同一 `_atDraft` 状态路径唤起面板——2026-11-16**）+ `fileMentionText` / `sessionMentionText`（**与内核 `formatFileMention` / `renderSessionMention` 同形的 mention 文本，纯函数**）；`_AtSessionPanel` 已拆到 `ui/composer_at_sessions.dart`（2026-11-21 守 §7 行数） | ✅ |
| `ui/composer_at_sessions.dart` | `part of composer.dart`：@ 面板的「对话」分组 `_AtSessionPanel`（`ChatState.sessions` 最多 6 条、去掉当前会话，选中插 `@[标题](dsh-session:<id>)`；面板整体高度由 composer 的外层限高容器统一滚动，这里只平铺——2026-11-21 工单 3） | ✅ |
| `ui/composer_bar.dart` | `part of composer.dart`：`_ComposerBar`（输入容器：输入框+权限 chip+**多图 chip 横排（`SingleChildScrollView` 横滑、右对齐、逐个删）**+加图/**「选择项目中的内容」文件夹圆钮（Tooltip，与加图钮同禁用条件）——2026-11-16**/发送圆钮；**两个圆钮常驻不再随 stop 隐藏——2026-11-21 工单 5**）/ `_PermissionSheet`（权限档位底部弹层）/ `confirmFullPermission`（完全权限二次确认） | ✅ |
| `ui/composer_permission.dart` | `part of composer.dart`：权限档位的交互（`_ComposerPermission` 扩展挂 `_pickPermission`：拉 `permission-options` → 底部弹层选档 → 需要时二次确认 → `setPermission`）——2026-11-21 从 composer.dart 拆出守 §7 单文件 ≤500 行 | ✅ |
| `ui/todo_dock.dart` | 输入条上方的任务条（**移植 dsh-go 的 dock/todo_bar（ArkTS 无关的 Flutter 参考实现），2026-11-21 工单 6**）：`TodoDockSummary.of(todos, running:)` 纯逻辑（空→null；`done/total`；当前项取首个进行中否则首个未完成；全完成「全部完成」/运行中「正在：…」/否则「下一步：…」）+ `TodoDockBar`（摘要行 + 2px 进度线 + chevron，点一下卡内展开清单，最高 168vp 内滚）；数据走既有 `todoItems(state.projections)`，无清单不占位 | ✅ 单测覆盖 |
| `ui/connect_page.dart` | 连接页三级路径：历史主机点击直连（DshHosts，有 token 才显示、失败显式报错）+ DSH1 配置文本导入（decodeDsh1，有 token 直连/无 token 填表）+ 手动配对（bridge 地址 + 配对码）；成功都 upsert 主机记录；**历史主机卡片删除按钮 + AlertDialog 二次确认 + 直连失败「删除这条失效记录」入口（DshHosts.remove，命中当前凭证顺手 DshCredentials.clear）** | ✅ 装机验证 |
| `ui/md_view.dart` | GptMarkdown 定制：官方 token 全量映射、任务列表预处理、codeBuilder/tableBuilder 接线、**链接可点外跳浏览器（url_launcher onLinkTap，第四轮反馈 5）**；2026-11-20 加 `normalizeTables()` —— 表格紧贴段落时补空行（引擎只在空行后认 GFM 表格，围栏代码块整段跳过），companion PITFALLS「表格贴上一行」 | ✅ 装机验证 + 单测 |
| `ui/md_viewer.dart` | 全屏 Markdown 文档查看页 `MdViewerPage`：.md 文件卡点开 → `gatewayResolvePath` + `gatewayReadFileBytes` 取字节 → utf8 → `DsMarkdownView` 滚动渲染；顶栏文件名 + 体积，失败给重试（文件卡 m03452 改进） | ✅ 单测覆盖 |
| `ui/image_viewer.dart` | 全屏图片查看器 `openImageViewer()`：黑底 InteractiveViewer 双指缩放/拖移、单击关闭、双击 1x/2.5x 变焦；聊天图片（chat_image.dart）点按进入，字节走进程内缓存零请求（第四轮反馈 1） | ✅ 装机验证 |
| `ui/md_code_block.dart` | 自绘代码块：Atom One Light（ValTheme 自定义）+ banner「语言名 / 复制」 | ✅ 装机验证 |
| `ui/md_table.dart` | 自绘表格：banner「表格 + 复制/下载/展开」+ 官方 #fafafa 底 + #dcdcdc 线 | ✅ 装机验证 |
| `ui/message_actions.dart` | 助手消息操作条：复制 / 喜欢 / 朗读（系统 TTS）/ 分享（系统分享面板，**尾部附「—— 发送于 yyyy-MM-dd HH:mm」，第四轮反馈 7**）+ 右侧重新生成接线；平台不支持时明确提示（点踩按真机反馈 2026-11-04 移除） | ✅ 装机验证 |
| `ui/process_group.dart` | 工具调用折叠组（2026-11-17 官方 Web 工具调用展示批次）：聚合标题 `processGroupTitle`（tool_present.dart 官方词表：进行中「正在…/准备…」+ live detail 键值（或 reasoning 兜底）· 后缀；完成按 kind 计数排序取前三类「并/，」连接、超三类加「等」，distinct callId 去重）；单条工具行 `DsToolRow` 五态（kind 图标 + `toolTitle`（tool_titles.dart 官方分派）+ 2px 圆点分隔 + 摘要 summarizeArgs（generic 工具带原工具名前缀 `工具调用 · <name>`）+ edit/write diff 后缀 `+N -M`（**仅展开或 hover 显色**）+ 行尾退出徽标 `parseExitStatus`（4px 红点+「退出码 N / 信号 X / 未正常退出」，官方 terminalFailed 口径——**exit 0 与无标记不出徽标**）；失败无 exit 标记才换 resultText 首行红字；**run-state（正在准备调用/运行中/失败/已停止）只进 `Semantics` 文案，行上不渲染文字（官方 visuallyHidden 口径，2026-11-17）**）；**`workStepsDetail` 四档 policy（`WorkStepsDetailPolicy` 扩展：stepGrouping/liveProcessDetail/settledReasoningPreview/foldCompletedTurns）——concise 只渲染折叠行 / standard 不渲染详情 / detailed 完成轮 history / verbose 平铺逐条 DsToolRow（chat_message_items.dart 处理）**；展开态提升 `GroupExpandState`（key=首个 callId），运行中轮 forceOpen 默认展开（用户收起过豁免 `isForceOpenDismissed`）；详情特化拆 `process_detail.dart` | ✅ 单测覆盖 |
| `ui/process_detail.dart` | `part of process_group.dart`（2026-11-17 工具调用展示批次拆出，控行数）：工具详情特化（官方逆向）——edit/write → 行级差异块 `_DiffBlock`（复用 code_diff.dart，默认 9 行 + 「… 其余 N 行」展开，diff 行色 token）+ 失败结果保留；commands → BASH 代码块（command 字段）+ 结果正文；read → 结果正文 8 行开窗 + 顶部「显示 8 / N 行」（官方 read.window）+ 展开；code（run_code）→ code 字段代码块 + 结果；webSearch/webFetch → 结果正文，完成且无结果 →「未找到结果」；questions → 逐问卡（问题文本主色 + selected/custom 答案行，无答案「未回答」）或 verdict（「已继续工作，仍可回答」/「已结束」）+ 问题列表（HITL 面板常驻消息列表上方为已知偏差）；其余 → 官方 ioCard（输入/输出两段 [label|content]、每段最高 150px 内滚、0.5px 分隔线、mdCodeBlockBg 底）；耗时行保留，完成且无结果 →「无结果」 | ✅ analyze |
| `ui/tool_present.dart` | 官方 Web 工具调用展示纯函数（2026-11-17 批次，zh 词表逐字对齐）：`activityKind` 15 类（read/readImage/write/search/edit/commands/code/webSearch/webFetch/subagents/plan/questions/tools/thinking，剥 `tools.` 前缀）；`toolIcon`（行标题 `toolTitle` 迁 `tool_titles.dart` 官方三段分派，2026-11-17 task-5）；`summarizeArgs` 按 kind 键序（search queries 数组 join）；`liveDetailText` 22 键序截 160 + `reasoningDetailOf`；`processGroupTitle`（进行中/准备中/完成聚合标题）；ask 特化 `askResultOf`/`askQuestions`（重复 id 或缺字段 → null）/`askSummary`（等待中 / 已继续；仍可回答 / 已关闭 / N/M 已回答，解析失败回原摘要） | ✅ 单测覆盖 |
| `ui/tool_titles.dart` | 工具行标题官方分派（2026-11-17 task-5 对齐 dsh-client-ui-tool 0.2.2-rc.1）：`classifyTool` 六变体（bash/read/search/write/edit/code，pwsh→bash、read_image/web_fetch→read、grep/glob/web_search→search、apply_patch→edit、run_code→code）+ `TOOL_TITLE_KEYS` 精确名 zh 表（含 grep=搜索文件内容/glob=查找文件/web_search=网页搜索/web_fetch=网页获取/todo_write=更新任务清单/ask_user_question=提问/lsp=查询代码符号）→ `toolTitle`；`bareToolName` 剥 `tools.` 前缀；`isGenericTool`（generic 工具摘要带原工具名前缀）。偏差：官方 lsp 按结果 kind 二段分派，App 侧折叠行拿不到结果结构，统一「查询代码符号」 | ✅ 单测覆盖 |
| `ui/reasoning_text.dart` | 思考行纯函数（2026-11-17 task-5，官方 client.js 8126-8150 逐字移植）：`firstLineOf` / `latestCompletedParagraphFirstLine`（空行分段取最后已完成段首行，未收尾段不产出）/ `reasoningTextOf`（剥 `<signature>` 包裹）/ `reasoningHidden`（剥签后全空白→整块不渲染）/ `reasoningSummaryOf`（running 取最后已完成段、否则首行，`**` 全剥） | ✅ 单测覆盖 |
| `ui/turn_process_row.dart` | 轮尾行（2026-11-17 task-5 对齐官方 TurnProcessNodeView）：`formatRunDuration`（zh「N小时N分N秒」）/ `TurnEndInfo`+`turnEndInfoOf`（轮内过程组聚合 startedAt/finishedAt 最小最大差→「已完成，用时 …」；轮内 error 卡→「处理失败」；无过程组→null 不渲染；展开态按组 key 聚合）/ `TurnProcessRow`（行高 33、0.5px 底线、label-tertiary hover 升 secondary、标题左 chevron 右 14px 旋转）。偏差：轮计时用轮内过程组首尾近似；aborted/interrupted 与 error 在 App 侧仅 error 卡可判定 | ✅ 单测覆盖 |
| `design/design_tokens_layout.dart` | `part of tokens.dart`（2026-11-17 tokens.dart 超 500 行拆出）：DsSpacing / DsMotion 全量；task-5 新增 turnRowHeight=33/turnRowPadBottom=8/thinkRowHeight=24/sepDot=2/sepGap=8/exitBadgeDot=4/exitBadgeGap=5/exitBadgeGapLeft=8/diffStatGap=10/ioCardGap=4/ioSectionMaxHeight=150/ioColumnGap=14/ioSectionPadV=12/ioSectionPadH=16 + `DsMotion.processTitleMinimum=150ms` | ✅ analyze |
| `ui/model_sheet.dart` | 模型选择面板：models 帧拉分组清单，**按供应商分组可折叠（默认只展开当前供应商，折叠组若含当前选中模型显示一行提示）**→ select-model 帧确认切换 → 重拉 history；routable=false / failures 有值时显式提示（真机反馈第 4 项） | ✅ 单测覆盖 |
| `ui/sessions_drawer.dart` | 侧边会话抽屉：胶囊搜索框 + 分组列表（组名来自 `session_groups.dart`：工作区置顶分组）+ 纯文字条目 + 底部栏（**整行可点开设置** + 设置圆钮 + 「设置」文字 + 设备名 + 连接状态点：绿=桥正常/红=未连接（GatewayState.ready 判别）+ `connectionLabel` 地址，真机反馈第三轮 3 + 第五轮） ；**2026-11-20 接内核会话内容搜索**：搜索框 onChanged 同时喂 `SessionSearchController`（300ms 防抖 + 请求序号防旧结果回闪），桥不提供 `dshrb-v1` 或内核无 `session/search` 时整节不出现、退回原按标题本地过滤（降级）；正文命中另起一节（`session_search_section.dart`）；条目行拆到 `sessions_drawer_item.dart` 并支持第二行片段（宪法 §7 控行数）；**2026-11-20 宽窗适配**：新增 `width` 参数（手机 288 / 平板 320，由 `window_class.dart` 给）；三种窗口都是抽屉式，让路距离由 `DsWindowClass.pageInsetFor` 给（紧凑窗推走、宽窗缩窄） | ✅ 装机验证 |
| `ui/sessions_drawer_item.dart` | 抽屉里的一行会话（从 sessions_drawer.dart 拆出）：单行条目 + 可选第二行注脚（正文命中片段，`drawerItemSubtitleGap` = 2）；行尾角标复用既有位置（待回答/待审批/正文/已归档）；`onTap == null` 表示不可点（会话已不在列表里，点开只会拉回空历史） | ✅ 单测覆盖 |
| `ui/session_search.dart` | **会话内容搜索编排（内核 `session/search`，2026-11-20）**：`SessionSearchController extends ChangeNotifier`（防抖 300ms / 请求序号只认最后一批 / `supported` = 能力位 `kernel-call-v1` + 目录含该端点）+ `SessionSearchHit` + `parseSessionSearchHits()`（宽容解析 `{items:[{sessionId,snippet}],hasMore}`，坏条目跳过、片段压成一行）+ `sessionSearchArgs(endpoint, query)`（**键名以目录 `wires` 为准**，内核 strict codec 既拒缺键也拒多键）；空结果 ≠ 失败（部署侧可能 `openAt "never"` 关了索引） | ✅ 单测覆盖 |
| `ui/session_search_section.dart` | 抽屉「对话内容」一节的渲染件（从 sessions_drawer.dart 拆出）：标题行 + 三种结局（搜索中… / 搜索不可用：<原因> / 没有匹配）+ 命中行（同会话多处命中只出一条，已归档的留行不可点） | ✅ |
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
| `chat_cards_test.dart` | 两张新卡与 diff 页的渲染 + 行派生接线（2026-11-21 task-12，§4.17）：改动卡标题/逐文件行/合计+"查看改动"、超 3 个出「还有 N 个文件」、生成文件卡标题/类型说明/「全部 N 个文件」展开、查看改动页 chips 与「修改 N 次 行号未知」、一轮里 write+edit 同时存在时 ChangeCardRow 在 ArtifactCardRow 之前 | ✅ widget 覆盖 |
| `turn_changes_test.dart` | 本轮改动/生成文件推导（2026-11-21 task-12，§4.17）：edit meta.diffs 的 +/− 计数与 hunk、同文件两次编辑合并、无 meta 退回 arguments、write create 全文计新增、failed 不计、无写操作回 null、同输入复用缓存实例、`diffLinesOf` 公共前后缀 ctx、write create 进生成列表而 update 不进、markdown 链接按 bash cwd 拼绝对、无 cwd 不猜、`artifactKindOf` 扩展名映射 | ✅ 单测覆盖 |
| `tool_present_test.dart` | 官方工具调用展示纯函数（2026-11-17 批次）：`activityKind` 全词表 / `toolTitle` 特例 / `summarizeArgs` kind 键序与坏 JSON 兜底 / `liveDetailText`（运行中调用键值、queries 首项、160 字截断）/ `processGroupTitle`（空组兜底、进行中 + liveDetail、准备中、两类「并」去「已」、三类逗号、超三类加「等」、按计数排序）/ `askSummary`（等待中、已继续；仍可回答、已关闭、1/2 已回答 skipped 不计、解析失败兜底）/ `askQuestions`（重复 id/缺字段/空列表 → null）/ `askResultOf` |
| `todo_dock_test.dart` | 任务条摘要（2026-11-21 工单 6，§4.18）：空清单返回 null、计数/进度、运行中「正在：…」、未运行「下一步：…」、无进行中项取首个未完成、全完成「全部完成」且 current 为 null | ✅ 单测覆盖 |
| `mention_text_test.dart` | mention 文本格式（2026-11-21 工单 3/4，§4.18）：文件 `@path`/目录补 `/`/含空白加引号/引号转义；会话 `@[标题](dsh-session:id)`、`]` 转全角、空标题回退 id | ✅ 单测覆盖 |
| `composer_multi_image_test.dart` | 输入条多图与按钮常驻（2026-11-21 工单 2/5，§4.18）：连选两张都保留、删第一张不影响第二张；运行中空输入时「+」与文件夹按钮仍在屏内；未连接时按钮在但不可点 | ✅ widget 覆盖 |
| `reasoning_text_test.dart` | 思考行官方口径纯函数（2026-11-17 官方 Web 对齐批次）：`firstLineOf` 不 trim / `latestCompletedParagraphFirstLine` 按空行分段取最后完成段 / `reasoningTextOf` signature 三路（非 `<` 原样、未写完前缀空串、非 `<signature>` 开头原样、闭合标签后剪除）/ `reasoningHidden` / `reasoningSummaryOf` 去 `**` |
| `window_class_test.dart` | 窗口尺寸类（2026-11-20 task-9）：断点边界（599/600、839/840）、矮窗一律紧凑（915×412 手机横屏、479/480 高、1000×400 分屏）、各档 `sidebarWidth`（288/320）、`pageInsetFor`（让路距离 = 抽屉宽，手机 360 剩 72 / 平板横屏 1181 剩 861；窗口比抽屉还窄时不让出超过窗口）、`readableColumnWidth`（≤720 用满 / 738→720 / 861→774.9 / 1181→1062.9 / 1600→1440 / 2000 继续长、单调不减且 ≤ 可用宽、infinity 透传）、`floatingColumnWidth`（手机铺满、738→692、1181→1034.9）、模态 sheet 实测不再被 M3 的 640 卡住 | ✅ 单测覆盖 |
| `hitl_width_test.dart` | HITL 卡片宽度（2026-11-20 task-10，§4.16）：实测渲染宽度——手机 360dp 铺满、平板横屏 1181dp 收在 1062.9（0.9 缩放）、竖屏 738dp 收在 720（卡片与正文同列，宽窗不单独收窄；断言量 `SingleChildScrollView`，限宽是布局行为不是 getter 数值） | ✅ 单测覆盖 |
| `chat_thinking_test.dart` | 思考行行为（2026-11-20 task-7）：`thinkingTickerText`（掐尾空行/剥 `**`/压连续空行/长文本只留尾部 2000 字）；思考中标签写「思考中」、正文开始后收成一行首行摘要、点行展开全文再点收回、轮结束手动展开的全文自动收回、`<signature>` 剥空后整块不渲染 | ✅ 单测覆盖 |
| `gateway_kernel_test.dart` | 通用内核调用面纯逻辑（2026-11-20）：`parseKernelEndpoints` 正常解析 / 坏条目跳过 / 未知字段忽略与非列表回空 / `parseKernelCallResult` 三态（成功带 value、失败带 error{code,message}、缺详情兜底 `KERNEL_FAILED`）/ `KernelCallRegistry` settle 取走并只结算一次、未知与空 callId 静默丢弃、`failAll` 全部失败并清表且不重复结算已完成的 / `groupKernelEndpointsByScope` 保序分组 / `describeKernelCatalog` 空表说明原因 | ✅ 单测覆盖 |
| `session_search_test.dart` | 会话内容搜索纯逻辑（2026-11-20）：`parseSessionSearchHits` 正常解析与片段压成一行 / 坏条目跳过 / 片段缺席或非字符串给空串 / 形状不认识回空表；`sessionSearchArgs` 按目录 `wires` 拼参数（`[request]` 包一层、`[query]` 直放、目录缺席退已知形状、形状不认识塞第一个键） | ✅ 单测覆盖 |
| `turn_process_row_test.dart` | 轮尾行官方口径（2026-11-17）：`formatRunDuration`（毫秒/秒/分秒/整小时带 0 分 0 秒）/ `turnEndInfoOf` 锚为 assistant 消息、失败取轮内 error 卡、时长取过程组首尾且下限 1000ms、`canCollapse` 需有过程组 / 标签「已完成 / 已完成，用时 X / 处理失败」 |
| `streaming_tools_test.dart` | 流式工具行状态机（2026-11-17 实时工具事件批次）：首包缺 callId 按 index 占位、`callId` 到达后迁移（不产生重复行）/ 续包按 index 找回已迁移行 / delta 增量拼 arguments / end 定稿 / call 转 running / result 终态（interrupted 与 ASK_CANCELLED 不算失败）/ 缺名兜底「工具调用」/ 进程组合成 |
| `chat_actions_test.dart` | `chatStatsOf()` 本地统计、`Composer` 发送键三态、`ChatState.regenerateAt/retryLast` 重发用户消息 |
| `composer_image_name_test.dart` | 输入条待发送图片 chip 长文件名回归（2026-11-17 真机反馈）：mock `dsh/platform` 通道 + 真实临时 PNG 走完整选图链路，断言 ①无 RenderFlex 溢出（旧实现溢出 1252px）②chip 宽 ≤ `composerImageChipMaxWidth`(128) ③发送键仍在屏内可点 ④点 chip 删除标记可清图 |
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
| `ets/pages/SubagentHistoryPage.ets` | 子代理历史页（对照安卓 subagent_history_page.dart）：REST subagentHistory 拉取 + 「加载更早消息」beforeSeq 翻页；轻量行（过程短语/错误/文件卡/用户气泡/助手 Markdown）；标题取 label，空则「子会话 <id 前 8 位>」；只读无输入条 |
| `ets/pages/ChangeDiffPage.ets` | 本轮改动查看页（对照安卓 chat_diff_page.dart）：顶栏返回/「本轮改动」/N 文件 +A −R/复制全部、横向文件 chip、每 hunk「第 N 次修改」+ 红绿行、TYPE_SYSTEM 安全区 topInset、返回走 onBack 回调（getRouter().back() 会退应用） |
| `ets/pages/ChatView.ets` | 对话页：顶栏（⋮ 溢出菜单五项 + 代码工作视图入口（仅 dshCodeWorkView='1'）/标题/连接点/新建）+ HitlPanel 提问审批卡 + 消息列表 + 输入条 + 会话抽屉 + 六面板 bindSheet（统计/轨迹/团队/任务/模型/代码工作视图）+ 设置页入口；每次 changed 把 workSteps 展开集合版本写 AppStorage('dshExpandedVersion')（ProcessGroup @Watch 回读，LazyForEach 同 key 不重建的替代链路） |
| `ets/components/MessageList.ets` | 消息列表：用户气泡（Column 图上文下、右对齐、86.4% 宽 + 收图 ImageTile；原 Row 布局会与正文争宽把文字挤出屏外，2026-11-17 修）/ 助手 MdView 富渲染 + 消息操作条 MessageActions；命令卡/文件卡/错误条已迁 MessageCards；列表尾插 StreamingBlock（流式正文与思考），其后是 max-tokens 截断提示；assistant 项后插轮尾行 TurnProcessRow（turnTailOf 非 null 时，2026-11-17 task-6）；渲染前过 core/WorkSteps.visibleMessagesOf（dshFoldedReplies='final' 时完成轮只留最后一条正文助手消息，dshDark 同款 @StorageProp 链路）；过程组按展示档分派——verbose（core/ToolDetails.STEP_GROUPING_NONE）平铺逐条 ToolBlock（answerable 回调传挂起询问查询），其余档 ProcessGroup；ThinkBlock 传 settledReasoningPreview=policyOf(dshWorkStepsDetail)；**列表头 `truncated` 提示行「会话过长，更早的部分未显示」（2026-11-19）** |
| `ets/components/Composer.ets` | 输入条：发送键三态（send/stop/disabled）+ 命令补全/@ 文件补全（ComposerPanels）+ 图片 chip（PhotoPick 魔数校验 8MiB）+ 📁 选择项目中的内容（合成空 @ 草稿复用 AtFilePanel，原位插入 '@文件名 '）+ 权限 chip（PermissionSheet bindSheet）+ 免责声明 |
| `ets/components/SessionsDrawer.ets` | 会话抽屉：主机标识 + 新对话钮 + 搜索框（标题本地过滤 + DrawerSearch 正文命中）+ 工作区分组列表（未分组垫底）+ 当前会话高亮 + 待回答/待审批标记；删除阶段 4 |
| `ets/components/md/MdView.ets` | Markdown 主组件：块级循环（h/p/quote/code/table/ul/ol/hr/latex）+ 行内混排（Span 样式/链接外跳/内嵌 MdLatexView）；任务项 ☑/☐，引用左竖条 |
| `ets/components/md/MdCodeBlock.ets` | 代码块：banner 语言名+复制（pasteboard）+ 1px 分隔线 + 横滚 + SimpleHighlight 四类着色 |
| `ets/components/md/MdTable.ets` | 表格：banner「表格」+复制（\t 连接）+ 表头 w500 + cellAlign l/c/r + cellMinWidth 100 |
| `ets/components/md/MdLatex.ets` | 轻量 LaTeX 渲染：frac/sqrt/sup/sub/sym 分派（横线分子分母/√ 上边框/70% 字号偏移）；嵌套 smallArg 拍平 |
| `ets/components/ArrayDataSource.ets` | `IDataSource` 的数组实现（MessageList/SessionsDrawer 的 LazyForEach 数据源）：totalCount/getData + 监听注册注销，reset(items) 广播 onDataReloaded（不做逐项 diff —— ChatStore.messages 每次 changed() 都是新数组） |
| `ets/components/ToolBlock.ets` | 工具折叠组：摘要行（⚒ 短语）+ 展开逐条（✓/✗ 措辞/耗时）+ 单条 detail（bash 走 MdCodeBlock，其余 prettyArgs） |
| `ets/components/ToolBlockDetail.ets` | 工具行展开详情（2026-11-17 task-6 从 ToolBlock 切出控行数，官方 ToolRow 详情口径）：detailModeOf 七路分派 diff/command/read/search/web/ask/io——diff→DiffBlock（9 行+expandRestLabelOf「… 其余 N 行」行内展开）；command→命令正文 MdCodeBlock+结果；read→8 行窗口+readWindowLabelOf「显示 X / Y 行」；search→searchSummaryOf 摘要行+ioCard 正文（grep「N 处匹配 · M 个文件」/glob「N 个路径」/空「无结果」）；web→ioCard 或「未找到结果」；ask→answered 逐问卡（问题 brand+答案列表/未回答灰）；io→统一 ioCard（Scroll maxHeight 150/monospace/0.5px 边/radius4/输入·输出·错误标签） |
| `ets/components/ProcessGroup.ets` | 官方 web 式过程组（对齐 dsh-client-ui-chat ProcessGroupHeader，2026-11-17 task-6 重写）：组头=[icon+chevron 在左]+150ms 稳定标题（useStableLiveProcessTitle：live 标题至少驻留 150ms 才 commit，防闪烁；closed 即时）——label 进行中「正在…/准备调用工具」词表+liveDetailOf detail 附加、完成组 processGroupTitle（done 词 combineDoneWords）；icon=closed?kindIcon(topKindOf(calls)):kindIcon(最新 running kind)；总耗时归轮尾行不再显示；四档 detail 模式收口 ChatWorkSteps（concise 只留组头不可展开 / standard 展开仅工具行 / detailed 现状+最新一轮 deferCollapse / verbose 平铺不走本组件），恒展开 isGroupForceOpen（组后同轮有 user 或轮未结束），展开集合 key=组内首个 callId（无 callId 'seq<seq>'），组件经 AppStorage('dshExpandedVersion') @Watch 回读 store.workSteps；answerable 回调查 store.pendingQuestions |
| `ets/components/ThinkBlock.ets` | 思考行（官方 ReasoningRow 口径，2026-11-17 task-6 重写）：🧭+标题「思考」（400）+2×2px 圆点（label-caption）+摘要（reasoningSummaryOf：流式取最后已完成段首行/否则首行，「**」全剥，caption nowrap）+chevron；收起且摘要非空且（流式||settledReasoningPreview）显示；reasoningHidden（剥 signature 后全空白）整块不渲染；展开正文 reasoningText 剥 <signature>；流式默认展开「思考中」、结束自动收起、手动展开不强制折叠 |
| `ets/components/TurnProcessRow.ets` | 轮尾行（官方 TurnProcessNodeView 口径，2026-11-17 task-6 新建）：turnTailOf 取轮尾信息——label=turnTailLabel（「已完成」/「已完成，用时 1小时2分3秒」durationPartsOf（formatRunDuration：h>0→小时、total>=60→分、恒有秒，数字 monospace）/轮内 error 卡→「处理失败」）；样式行高 33+底部 0.5px 边+labelTertiary+标题左 chevron 右 14（open 旋转）；canCollapse=hasContent 时整行可点 → workSteps.setExpanded(groupKeys,open) 整轮组开关；canCollapse=false 仅显示 |
| `ets/components/ToolBlock.ets` | 工具行（官方 dsh-client-ui-tool ToolRow 口径，2026-11-17 task-6 重写控行数）：行=[kind 图标]+toolTitle（toolTitleOf 三段分派）+2×2px 分隔点+摘要（ask→askSummaryOf 六态/search 完成→searchSummaryOf/web 完成→webSummaryOf/失败→resultText 首行红/其余 toolSummaryOf）+suffix（exit 徽标「退出码 N/信号 X」或 diffStat「+N -M」；settledWithCue 失败收起态不显示）+chevron 14；状态词（准备中/运行中/已停止/已取消/失败）只进 a11y；expandable=非 preparing 且（ask/ioInput/结果/可 diff）；行内展开 @State detail（关详情即销毁详情卡、重开复位行内展开），standard 档 allowDetail=false 禁展开；详情抽 ToolBlockDetail |
| `ets/components/HitlPanel.ets` | 提问/审批卡：审批（顶部状态条 圆点+「等待审批」，risk=full-access 标题「工具 X 请求越权执行」else「DSH 请求使用 X」，reason monospace，决定提交后按钮禁用 opacity 0.5——协议只有「允许一次」无「始终允许」，警示底 拒绝/允许一次）先、提问（选项 chips 单选清旧 + 自定义输入 canSubmit）后；限高 0.5 屏 |
| `ets/components/StreamingBlock.ets` | 流式块（对照安卓 `_StreamingItem`，2026-11-17 补）：思考增量 → ThinkBlock(streaming=true)；正文增量 → MdView(streaming=true)；两者都空时给「正在思考…」占位行。数据源 ChatStore.streamText/streamReasoning（ChatEvents delta 累积），父级 MessageList 经 syncVersion 抄成 @State 再传入（ArkUI 只对 build 读到的 @State 建依赖） |
| `ets/components/MessageCards.ets` | 三种小卡片（2026-11-17 从 MessageList.ets 抽出以守 500 行上限）：CommandCard（命令卡，首行 monospace + ✓/✗）/ DeliverableCard（交付文件卡，.md 经 onOpenDoc 回调打开站内查看器）/ ErrorBar（turn 失败红字轻背景） |
| `ets/components/ImageTile.ets` | 收图渲染四态（加载/像素/错误重试/全屏）：createImageSource→PixelMap→Image 260 Cover，点按 bindContentCover 全屏 |
| `ets/components/MessageActions.ets` | 消息操作条：复制（pasteboard 回弹）/喜欢/朗读（Tts）/分享（Share）/⟳ 重新生成 |
| `ets/components/ModelSheet.ets` | 调整模型 bindSheet：分组折叠（默认展开当前）+ pending 提示 + reasoning chips + 确认（st.selectModel） |
| `ets/components/ProjectionSheets.ets` | 会话统计/运行轨迹两 sheet（智能团队/任务已切出到 ProjectionTeamSheets，控行数）；TrajectorySheet 支持 showHeader=false 内嵌复用（代码工作视图①段）；**StatsSheet 服务端半边（2026-11-19）：`@Prop @Watch version` 驱动重绘 + `serverStatRows()` 渲染 session-stats 标量行（Repeat，键 group/label），本地七项统计保留** |
| `ets/components/ProjectionTeamSheets.ets` | 智能团队/任务两 sheet（从 ProjectionSheets 切出）：团队三指挥 chip + 成员/任务/子代理行；任务状态圆点与删除线；官方 todo.title=「任务」（2026-11-17 task-6） |
| `ets/components/PermissionSheet.ets` | 会话权限档位 sheet（从 Composer 拆出）：aboutToAppear 拉清单 + pick/apply + danger 二次确认 |
| `ets/components/ComposerBanners.ets` | 输入条两条横幅（从 Composer 切出，控行数）：ErrorBanner（错误「点按查看」）与 HintBanner（提示可带 danger 色 + 关闭钮） |
| `ets/components/ComposerPanels.ets` | 输入面板：命令补全（缓存切会话失效/前缀过滤）与 @ 文件补全（多根合并 label/ 前缀 + 目录下钻 + 失败重试） |
| `ets/ui/theme.ets` | design-tokens.md 的鸿蒙翻译：DsPalette/DsColors（dark 构造语义别名，含代码差异四色 diffAddBg/Fg、diffDelBg/Fg）/DsTypography/DsSpacing；改样式先改 token 文档再改这里 |
| `ets/platform/WsTransport.ets` | @ohos.web.websocket 实现 WebSocketTransport：header 小写键 + protocol 单值，connectTimeoutMs settled 防竞态；**close 回调读 `CloseResult.code`/`reason` 透给 onDown（2026-11-19）** |
| `ets/platform/HttpTransport.ets` | @ohos.net.http 实现 HttpTransport：响应头键小写收敛；PATCH 枚举缺失走字符串透传（真机待验） |
| `ets/platform/PlatformBridge.ets` | ArkTimers（setTimeout/clearTimeout）+ timeZoneId（Intl→UTC 兜底）+ PrefsStore（preferences 单例，getString/putString/removeKey） |
| `ets/platform/Dlog.ets` | hilog 封装（DOMAIN 0xD5C0，info/warn/error）——core 层禁 import @kit，日志实现只在 platform |
| `ets/platform/PhotoPick.ets` | 系统图库选图（photoAccessHelper PhotoViewPicker）→ 临时文件读字节 + 魔数嗅探 mediaType |
| `ets/platform/Tts.ets` | CoreSpeechKit 朗读（zh-CN，speak/stopSpeak，音量语速走 extraParams） |
| `ets/platform/Share.ets` | 系统分享面板（Want ohos.want.action.sendData text/plain） |
| `ets/core/Breakpoints.ts` | 窗口断点纯逻辑（R007 一多）：`breakpointOf` 归一 sm/md/lg + 抽屉尺寸（drawerWidth 288/352/400、drawerFraction 0.8/0.4/0.32）+ 正文列宽 `readableColumnWidth(实测宽)`（≤720 用满、更宽 ×0.9，无第二道上限）与 `floatingColumnWidth`（顶栏/输入条，列有富余时两侧各收 14；不再有 contentMaxWidth/sheetMaxWidth 硬上限）；放 core 以便 node 直测 |
| `ets/core/ChatStore.ts` | 会话状态机（chat_state.dart 全语义）：send 乐观上屏+手机工作区预建（ensureMobileWorkspace）、流式收束、防抖重拉 800ms、loadOlder 翻页去重、isCurrent 空态防串台；send() 里 collapseOnSend（next-input 时机）；workSteps:ChatWorkSteps 随会话 reset；事件分派 onEventIn 与流式工具行粘合拆到 ChatEvents/ChatStreamTools（onEvent/reattachLiveRows 转发）；streamTools:StreamToolState 容器；selectAgentPreset/loadAgentPresets 转发；**`serverStats`/`historyTruncated` 两字段（resetSessionView 一并清零，2026-11-19）** |
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
| `ets/core/Transport.ts` | 传输抽象：HttpRequest/HttpResponse/HttpTransport、WebSocketTransport.open→EventSocketHandle、TimerBridge；WS/请求/心跳/退避常量（协议时序唯一出处）；**`onDown(reason, code?)` 增加可选 close code（2026-11-19）** |
| `ets/core/GatewayEvents.ts` | GatewayState 枚举 + 扁平 GatewayEvent（十种事件 type 分派）+ RequestException（稳定错误码）+ eventFromFrame（十一支事件帧映射纯函数）；**`GatewayEventType.LINK_CLOSED` + `linkCode`/`linkReason` 字段（2026-11-19）** |
| `ets/core/Questions.ts` | HITL 模型：UserQuestion/UserQuestionOption/PendingQuestion/PendingApproval/QuestionAnswerItem（custom 空省略，与安卓 questions.dart 对齐） |
| `ets/core/GatewayClient.ts` | WS 状态机：connect/hello 8s/心跳 25s/退避重连（1→30s，attempt+downAttempt 双代数防迟到/重复回调）、重连链 relay（reconnecting）、事件派发（映射在 GatewayEvents.eventFromFrame）、dispose；帧收发本体在 GatewayRequests；**2026-11-19 协议对齐：`capabilities`/`listenerPort` 从 `hello` 存档 + `hasCapability()`/`getCapabilities()`/`getListenerPort()`；`onDown(attempt, reason, code)` 读 WS close code——4001 置 `AUTH_FAILED` 且不排退避、1009 照常接力，code∉{1000,1005,0} 时 emit `LINK_CLOSED`** |
| `ets/core/GatewayApi.ts` | WS 端点 19 个 + REST 委托层（15 个同名方法转发给 GatewayRest；历史实现已搬到 GatewayRest，含 agentPresets/selectAgentPreset）；**`history()` 解析 truncated/bytes/historyFormatVersion；新增 `sessionStats()`/`contextUsage()`（2026-11-19）** |
| `ets/core/GatewayRest.ts` | REST 实现（从 GatewayApi 拆出）：restHeaders/restJson/encodePath + pairing exchange/workspace 建改/roots 浏览/entries/path 解析/attachment/image-handoff/subagentHistory/countPending 两跳 + agentPresets（GET /chat/agent-presets）/selectAgentPreset（PUT /chat/sessions/{sid}/agent-preset，409→AGENT_PRESET_LOCKED） |
| `ets/core/GatewayRequests.ts` | 帧收发（从 GatewayClient 拆出）：requestWithTimeoutOn 请求-回显结算 + requestOn 默认 30s + subscribeOn 发出即成功 + onFrameOn 帧分派（kind=hello/event/error/ping/pong/resync 双兜底 requestId）|
| `ets/core/ToolCall.ts` | 工具调用合并模型 + 措辞表（bash/read_image…/mcp__ 直译/run_code 内嵌扫描）+ toolSummary 九键 + toolResultText（text 拼接/图片占位）|
| `ets/core/HistoryPage.ts` | 历史装配器 fromEvents：user/assistant 正文、连续 tool/call+result 合并过程组（callId 去重/就地升级）、组内 reasoning 聚合（groupReasoning，进行中组无 running 工具时组标题取尾段）、文件卡轮尾挂载、turn/end 错误卡、注入内容过滤（source.kind）+ mergeOlderMessages 翻页去重；**`truncated`/`bytes`/`historyFormatVersion` 三字段（history 字节预算截断标记，fromEvents 尾部可选参数向后兼容，2026-11-19）** |
| `ets/core/ToolPresent.ts` | 工具呈现纯逻辑上半（对齐官方 dsh-client-ui-chat/dsh-client-ui-tool，node 直测；2026-11-17 task-6 删旧 toolTitle 三段改 ToolTitles）：activityKind 归类（剥 tools. 前缀→14 kind，空→thinking）+ 三词表（正在/准备/done）+ KIND_ICONS + kindIcon + topKindOf（组 kind 计数降序、并列按首现、空→thinking）+ firstLineOf/truncateDetail/stripStars/reasoningTailOf + isCallRunning/isCallPreparing/hasRunningCall + liveDetailOf（LIVE_TOOL_DETAIL_KEYS 22 键序首个命中，数组取首项，截 160）+ processGroupTitle/doneGroupTitle/combineDoneWords（官方 joinTwo：2 类「并」+「已」去重、≥3 类「，」、>3 类「等」、空组「已完成分析」）+ SUMMARY_KEYS_BY_KIND/toolSummaryOf（键序摘要） |
| `ets/core/ToolTitles.ts` | 工具标题三段分派（2026-11-17 task-6 新建，对齐官方 TOOL_VARIANTS/TOOL_TITLE_KEYS/组件覆盖）：stripToolPrefix→classifyTool（TOOL_VARIANTS 17 键变体归类：bash/pwsh→bash、read/read_image/web_fetch→read、web_search/grep/glob→search、edit/apply_patch→edit、run_code→code、cordis_package/runtime_inspect→read、cordis_run/stop/undefine→others）→ toolTitleOf 三段优先级=组件级覆盖（grep 搜索文件内容/glob 查找文件/web_search 网页搜索/web_fetch 网页获取）> TOOL_TITLE_ZH 49 键逐字 > VARIANT_TITLE_ZH 7 变体词 > 「工具调用」兜底 |
| `ets/core/ToolDetails.ts` | 工具呈现纯逻辑下半（详情分派/询问状态机/展示档位 policy；2026-11-17 task-6 扩 search/web 摘要）：DETAIL_DIFF_MAX_LINES=9/DETAIL_READ_WINDOW=8/DETAIL_INPUT_MAX_CHARS=200 + detailModeOf（edit/write→diff，commands→command，read→read，search（grep/glob）→search，web_search/web_fetch→web，questions→ask，else io）+ readLinesOf + ioInputOf（run_code 取 code 正文，JSON.stringify 2 空格截 200，坏 JSON 首行兜底）+ ioOutputOf（空→「无结果」）+ searchSummaryOf（grep「N 处匹配 · M 个文件」（file=结果行首「:」前缀去重）/glob「N 个路径」/空「无结果」）+ webSummaryOf（结果首行/「未找到结果」）+ readWindowLabelOf「显示 X / Y 行」+ expandRestLabelOf「… 其余 N 行」+ askSummaryOf 六态（等待回答/已继续工作，仍可回答/已结束/{n}/{total} 已回答/未回答/已取消）+ answerEntries/askQuestions（坏 JSON/重复 id/缺 question→null）+ isAnswered + WorkStepsPolicy 四档（policyOf：concise/standard/detailed/verbose → foldCompletedTurns/stepGrouping collapsed|history|none/liveProcessDetail/settledReasoningPreview）+ isGroupForceOpen（组后同轮 user→true，终回复/error→false，尾随轮状态） |
| `ets/core/ReasoningText.ts` | 思考行纯文本逻辑（2026-11-17 task-6 新建，官方 reasoningText 逐字）：reasoningText（< 前缀判断——'<signature>' 未闭合→空串/非 signature 开头原样/闭合后跳换行返回剩余）+ reasoningFirstLine（首个 \n 前截取不 trim）+ reasoningParagraphPreview（分隔=空白行序列，每段首个换行前行 trim 非空记候选，返回最后候选）+ reasoningSummaryOf（内部 reasoningText+「**」全剥）+ reasoningHidden（text!==rawText 且 trim 空→整块不渲染） |
| `ets/core/TurnTail.ts` | 轮尾行纯逻辑（2026-11-17 task-6 新建，对齐官方 TurnProcessNodeView/formatRunDuration）：TurnTailInfo（closed/failed/durationMs/hasContent/groupKeys）+ turnTailOf(messages,index,isTurnRunning)（锚=assistant，轮=上 user 后至下 user 前；非闭合轮→null；failed=轮内 error 卡；时长=轮内过程组 startedAt 最小→finishedAt 最大、span>0→max(1000,span)；groupKeys=轮内组 key）+ durationPartsOf（官方 formatRunDuration：total=floor 秒、h>0→N 小时、total>=60→N 分、恒 N 秒）+ turnTailLabel（处理失败/已完成/「已完成，用时 …」） |
| `ets/core/Projections.ts` | 轨迹分组 trajectoryOf（按 turn/seq、未知轮垫底）+ 服务端投影（todoItems/agentTeamProjectionOf，宽容零抛）+ chatStatsOf 七键统计 + prettyJson |
| `ets/core/ReleaseCheck.ts` | 新版检测：fetchLatestRelease（Gitee api/v5 → GitHub api.github.com 落链，8s 超时）+ releaseFromJson 双前缀资产 + versionParts 三段 + isNewerVersion |
| `ets/core/Hosts.ts` | 主机记录 DshHost + FNV-1a 幂等 id（BigInt 64 位）+ DSH1 宽容解码（前缀任意位置/双字母表/补 =/截 {...} 重试）+ upsert/remove/parse/encode 纯函数 |
| `ets/core/ModelsView.ts` | models 应答收敛（SessionModels/groups/failures/current）+ parseSelectModelReply + reasoningEffortLabel |
| `ets/core/Permissions.ts` | permission-options 收敛（PermissionCatalog/Option）+ 本地中文标签（label/descriptionLabel/needsConfirm/isDerived）+ permissionLabelOf |
| `ets/core/MobileWorkspace.ts` | 手机工作区约定：ensureMobileWorkspace（缓存→标题匹配→.dsh-mobile 建目录→REST 登记→改名，全失败回 null 不阻断）+ prepareSessionFor + oldestSeqOf |
| `ets/core/ChatActions.ts` | 会话动作集（store 参数纯函数）：runCommandIn 命令卡（✓/✗ 就地改写）/regenerateAtIn 重生成/cancelTurnIn 停止/setPermissionIn（NO_SESSION 拒） |
| `ets/core/ChatHitl.ts` | HITL 动作集（从 ChatStore 拆出，store 参数纯函数）：refreshPendingMarksIn 抽屉角标两跳计数/pendingMarkOfIn/answerQuestionIn/cancelQuestionIn/decideApprovalIn |
| `ets/core/ChatHistory.ts` | 历史装载与翻页（从 ChatStore 拆出，store 参数纯函数）：reloadHistoryIn 重拉（本地命令卡灌回尾部）+ loadOlderIn 向上翻页（beforeSeq=最小 seq、合并去重、跨会话结果丢弃）；**historyTruncated 置位（reload 覆盖、loadOlder 只置不清，2026-11-19）** |
| `ets/core/ChatStreamTools.ts` | 流式工具行↔store 粘合（从 ChatStore 拆出，store 参数纯函数）：bumpStreamToolsIn 版本广播/clearStreamToolsIn 清流+去合成卡/dropSyntheticGroupsIn 回收 seq=-1 占位组/afterLiveRowsIn 每帧并入+通知/syncLiveRowsIntoMessagesIn live 行并入运行中轮（callId 命中 mergeLiveRow 就地升级、未命中追加、无组追加合成卡）/reattachLiveRowsIn reload 后重挂 |
| `ets/core/ChatStats.ts` | 会话统计服务端半边（2026-11-19 协议对齐新建）：`ServerStatRow{group,label,value}` + `serverStatRows(stats)`——只拍平 sessionStats/tokenUsage/contextPressure 三个容器的**标量叶子**（int/double/bool→是·否/str），Map/List/null 跳过、空分组消失，不翻译键名不猜单位（与安卓 `ui/stats_sheet.dart` 的 serverStatGroups 同口径）+ `loadServerStatsIn(store)` 拉 `session-stats` 帧（切会话即丢弃，失败置 null 静默） |
| `ets/core/LinkLiveness.ts` | 连接活性判据（2026-11-19 协议对齐新建，从 GatewayClient 拆出）：`lastInboundAt` 哨兵 `NO_INBOUND_YET`（-1，不用 0——真机 `Date.now()` 与假钟会撞）+ `seen(now)` / `isStale(now)`（静默 > `LINK_LIVENESS_MS`=45s 即半死）/ `silentFor(now)` / `reset()`；判据是「最近一次收到帧」而不是「最近一次状态迁移」 |
| `ets/core/ChatEvents.ts` | Gateway 事件分派（从 ChatStore 拆出，store 参数纯函数）：onEventIn——DELTA 显式分派 text/reasoning/tool-call/tool-call-end（未知 kind 只抬流式态不渲染，防新协议帧 JSON 漏进气泡）/TOOL_CALL/TOOL_RESULT 进 StreamToolState、COMMITTED assistant 清流+reload+collapseTurnOnCompletion（user 走防抖）、TURN_FAILED 清流+lastError、RESYNC/SESSION_EVENT 防抖重拉、其余 hitl.onEvent 兜底；**LINK_CLOSED 分支（4001→lastError 提示重新配对 / 1009→帧超限，2026-11-19）** |
| `ets/core/ChatResync.ts` | 重连对账（从 ChatStore 拆出，store 参数纯函数）：syncStreamingWithServerIn——READY 后用会话列表 running 订正本地流式态，服务端说没在跑就无条件清 streaming/两缓冲/流式工具行并重拉历史（不能只在 streaming=true 时清，残留文本同样钉住轮尾占位），并记 serverIdleSession 挡该回合迟到增量；bridge 不补发断线事件，这是唯一收口途径 |
| `ets/core/StreamTools.ts` | 流式工具行状态机（bridge 四帧→行；对齐安卓 streaming_tools.dart _rowFor）：StreamToolState 容器（rows+indexToCallId 映射；缺 callId 首包落 'idx<index>' 占位行、真实 callId 首现就地改键迁移收编+记映射、续包按 index 找回）applyDelta/applyEnd/applyCall/applyResult + 纯函数 exitBadgeOf（结果文本尾 [exit code: N]/[killed by signal: X]）/statusFromErrorCode（interrupted→stopped/ASK_CANCELLED→cancelled/未知降级失败）/rankOf（终态>有结果>running>preparing）/mergeLiveRow（rank 守卫防降级）+ TOOL_STATUS_* 三常量 |
| `ets/core/WorkSteps.ts` | 通用设置①②③纯逻辑：WorkStepsDetail/CollapseTiming/FoldedReplies 解析（未知回退 detailed/completion/all）+ 四偏好键常量（dsh.workStepsDetail 等）+ turnsOf 轮分组（user 起轮）+ visibleMessagesOf 折叠回复（final 档完成轮只留最后一条正文助手消息；运行中轮全可见；user/process/error/files/command 卡全保留）+ processGroupKey（首个 callId，无 callId 'seq<seq>'）+ lastTurnGroupKeys（completion 自动收起用） |
| `ets/core/CodeDiff.ts` | 本轮代码差异纯逻辑：fileDiffOfCall 从 edit（file_path/old_string/new_string→−old/＋new）/write（file_path/content→全＋）工具调用提取 FileDiff（行 type add/del/ctx，ctx 暂未产出保留档位）+ codeDiffsOfTurn 同 path 聚合保序 + codeDiffsOfLastTurn + diffStatOf（+N -M，工具行 suffix 用，2026-11-17 task-6） |
| `ets/core/AgentPresets.ts` | Agent 预设模型：AgentPreset(id/name/description/trust/isDefault/available) fromJson 全宽容（姊妹仓 0.2.x 无 trust 字段实证→默认 system 兜底）+ listFrom + toJson（round-trip，description null 省键） |
| `ets/core/ChatWorkSteps.ts` | 工作步骤运行时状态（从 ChatStore 拆出）：detail/timing 偏好应用（concise/standard/verbose 收 expanded，verbose 靠 isExpanded 默认 true）+ expandedGroups Set（key=callId）+ snapshotExpanded 自增版本（AppStorage 'dshExpandedVersion' 桥）+ isExpanded/toggle（concise 拒）+ setExpanded(keys,open) 批量开关（轮尾行整轮组开合用，2026-11-17 task-6）+ collapseTurnOnCompletion（轮 committed 后收起；detailed=history 档 deferCollapse 只收倒数轮、最新一轮保持展开）+ collapseOnSend（detailed 收当前全部；concise/standard 仅 next-input 时机收，时机门内聚在本类）+ Agent 预设缓存（currentAgentPreset/cachedAgentPresets）+ selectAgentPresetIn（PUT 成功回填+loadSessions，NO_SESSION 拒） |
| `ets/core/SessionGroups.ts` | 会话抽屉分组纯函数：groupSessionsByTime 先按时间分桶（今天/昨天/更早，超 2 天折叠）、桶内按工作区聚合（同区只显示一次小节标题），visibleRowsOf 处理「更早」展开态；dayBucketOf 按本地日历天分桶 |
| `ets/core/AppUpdate.ts` | 检查更新（华为应用市场口径）：UpdateCheckResult 结果对象 + updateErrorMessage SDK 错误码（1009400001~7/401）中文映射 + NOT_SUPPORTED_MESSAGE；平台调用在 SettingsView（updateManager.checkAppUpdate / showUpdateDialog） |
| `ets/core/AtMention.ts` | @ 文件引用面板纯逻辑（从 Composer 抽出）：AtEntry 条目模型 + mergeAtEntries 多根合并（label/ 前缀、query 名字前缀过滤不区分大小写、逐根容错 okRoots 计数）+ inSubDirectory 全失败判定 + loadMergedAtEntries（逐根拉取合并，@ 补全与「选择项目中的内容」共用）；Composer 只做拉取与状态搬运 |
| `ets/core/SessionLocation.ts` | 新建会话工作目录纯逻辑（对照安卓 session_location_sheet.dart）：SessionLocation(rootId,cwd,label)+key 契约串、locationLabel（''=根目录）、recentLocations（历史会话 (rootId,cwd) 去重保序、跳过无根会话）、locationSubtitle（优先 cwdAbsolute 退回 rootId）、parentPath 逐级上退、locationChipLabel 空态 chip 文案 |
| `ets/core/ChatHeaderStatus.ts` | 顶栏第二行状态纯逻辑（对照安卓 chat_header_status.dart）：`ChatHeaderStatus{tone,label}` + `chatHeaderStatus(state,streaming,waitingApproval,waitingAnswer,hostLabel)`；优先级 IDLE 未连接 > CONNECTING 连接中 > CLOSED/AUTH_FAILED 已断开 > 等待审批 > 等待回答 > 生成中 > 主机名（空则「已连接」） |
| `ets/core/TurnChanges.ts` | 本轮改动/生成文件纯逻辑（对照安卓 turn_changes.dart）：EditHunk/FileChange/TurnChanges + turnChangesOf（只收 isProcess&&!failed 的 edit/write，meta.diffs 优先、退回工具参数，同文件合并留 hunk 序号）+ ArtifactFile/artifactKindOf/artifactKindLabel + turnArtifactsOf（write 非 update + 正文 markdown 引用，cwd 拼相对路径去重）+ markdownRefs/resolveRef/decodeArgs |
| `ets/core/ThinkingState.ts` | 思考行新形态纯逻辑（对照安卓 chat_thinking.dart）：ThinkingRowState{active,summary,ticker,hidden} + thinkingRowStateOf(streaming 且正文未开始才活跃) + thinkingTickerText（剥 signature/折叠空行/尾部 2000 字）+ thinkingLiveLines（最后 3 个非空行）；TICKER_ROWS=3、TICKER_TAIL=2000 |
| `ets/core/TurnCards.ts` | 两张卡的挂载判据：TurnCards{changes,artifacts} + turnCardsOf(messages,index,isTurnRunning)——只挂闭合轮最后一条 assistant（后向扫到 user 前仍有 assistant 即 null），两卡都空返回 null |
| `ets/core/TodoDock.ts` | 任务条纯逻辑（对照安卓 todo_dock.dart）：TodoDockSummary.of(todos,running) 预算 total/done/current/fraction/headline（全部完成/正在：X/下一步：Y）+ todoGlyph 状态字形；空 todo 返回 null（不占位） |
| `ets/core/KernelCall.ts` | dshrb-v1 内核调用面模型：KernelEndpoint.fromJson/accepts + parseKernelEndpoints（顶层 endpoints，容错坏条目）+ KernelCallResult.fromFrame/object/frames/message + KernelPending + KernelCallRegistry（add 同 id 拒/take 只结算一次/failAll）；KERNEL_CALL_TIMEOUT_MS=35000、KERNEL_SESSION_SEARCH='session/search' |
| `ets/core/KernelPlane.ts` | 连接级内核状态（拆出以守住 GatewayClient 500 行）：KernelPlane{catalog,registry,seq}；hello 清目录、重连 failAll |
| `ets/core/GatewayKernel.ts` | 内核面收发纯函数（收 GatewayClient，同 GatewayRequests 范式）：kernelEndpointOf/kernelSearchSupportedOn/settleKernelCallOn/kernelCallOn（自铸 callId）/kernelCallWithIdOn（幂等重试）/kernelCancelOn/searchSessionsOn（端点缺失 NOT_SUPPORTED） |
| `ets/core/SessionSearch.ts` | 会话正文搜索纯逻辑：SessionSearchHit + tidySnippet（空白折叠 trim）+ parseSessionSearchHits（读 value.items[].sessionId/snippet，坏形状跳过，limit）+ sessionSearchHasMore + sessionSearchArgs（wires 含 request→{request:{query}}、含 query→{query}、否则首个 wire） |
| `ets/components/SessionLocationSheet.ets` | 工作目录选择面板：默认「手机会话」项 + 最近使用列表 + 授权根逐级浏览（空根自动跳到下一个有子目录的根、多根可点标题切换、面包屑「用此目录」）；选中写 store.pendingLocation，首条消息走 session-create{rootId,cwd} |
| `ets/components/SettingsGeneralSection.ets` | 设置页「通用」四行（从 SettingsView 切出，控行数，官方 Web 文案逐字对齐）：工作步骤展示四 chip（concise/standard/detailed/verbose）+ 收起时机（completion/next-input）+ 折叠回复（all/final，verbose 档隐藏该行）+ 显示代码工作视图开关；偏好键带点官方 token，AppStorage 无点驼峰（dshWorkStepsDetail 等），写 PrefsStore |
| `ets/components/SettingsDisconnectSection.ets` | 设置页「断开连接」分区（从 SettingsView 切出控行数）：红描边按钮 + 系统 AlertDialog 二次确认（自绘遮罩在 Scroll 内定位不可靠，真机点按无反应）→ onDisconnect 回连接页；不持状态、不碰 store |
| `ets/components/CodeWorkSheet.ets` | 代码工作视图 sheet（官方 developerTools）：三段 chip 切换 —— ①运行轨迹（官方描述 + TrajectorySheet showHeader=false 内嵌）②本轮代码差异（core/CodeDiff 本地提取最后一轮 edit/write，+/- 行着色 theme.diffAdd*/diffDel*，卡底 bgLayer1）③Agent 预设（GET /chat/agent-presets 列表 + 当前项打勾；非 blank 会话整列表置灰「首条消息后锁定」，点选走 PUT，409 AGENT_PRESET_LOCKED 行内提示「已锁定，仅空白会话可切换」） |
| `ets/components/ChatTopBar.ets` | 会话页两行顶栏（对照安卓 chat_top_bar.dart）：44 操作行（☰/标题 16 Medium 单行/＋/⋮）+ 20 状态行（左缩进 56、6px 圆点 + caption）；statusColor 映射 chatStatusOk/Warn/danger/brand/labelTertiary；限宽 floatingColumnWidth |
| `ets/components/ChangeCard.ets` | 本轮改动卡（对照安卓 chat_change_card.dart）：@Prop files+onOpen(index)；标题「改动了 N 个文件」、最多 3 行（文件名/弱化目录/+N −N）、脚注「查看改动」/「还有 N 个文件」；bgLayer1+圆角 16+borderL2 |
| `ets/components/ArtifactCard.ets` | 本轮生成文件卡（对照安卓 chat_artifact_card.dart）：40×40 类型字形占位（真实缩略图待补）、默认 4 行可展开「全部 N 个文件」、行尾 ⋯ 菜单（复制路径/分享）、行点击复制路径 |
| `ets/components/ChatOverflowMenu.ets` | 溢出菜单（从 ChatView 拆出）：会话统计/运行轨迹/代码工作视图（dshCodeWorkView='1' 时）/智能团队/任务/调整模型，回调转发父层 |
| `ets/components/ImageViewer.ets` | 全屏图片查看器（对照安卓 image_viewer.dart）：黑底 + 双指缩放（1–8x）/放大后拖移/双击 1x↔2.5x/单击原尺寸关闭/右上 ✕；TYPE_SYSTEM 安全区；复用 ImageTile 已解码的 PixelMap 零额外请求 |
| `ets/components/TurnCards.ets` | 两张卡的接线壳：@Prop @Watch version 重算 core/TurnCards，挂 ChangeCard/ArtifactCard，自带 bindContentCover 打开 ChangeDiffPage |
| `ets/components/TodoDock.ets` | 任务条（对照安卓 todo_dock.dart）：composer 上方左右 12 上 16；40 高行 + 2px 进度 + 展开 maxHeight 168 内滚；空 todo 不占位 |
| `ets/components/UserBubble.ets` | 用户气泡（从 MessageList 抽出击 500 行上限）：右对齐、外层左 32、最大宽 86.4%、16/24 正文、padding 16/12；收图 ImageTile |
| `ets/components/ComposerActions.ets` | 输入条右侧动作区（从 Composer 切出控行数）：＋ 选图/📁 选择项目内容/权限 chip/发送或停止；禁用态仍可点但 onClick 判 sendEnabled（避免 .enabled(false) 的 0.4 透明度压对比度） |
| `ets/components/ImageChips.ets` | 多图待发 chip 横排：文件名超 16 字截断、✕ 20×20 热区逐张删 |
| `ets/components/PermissionChip.ets` | 会话权限 chip：🛡+中文档位+⌄，maxWidth 200，accessibilityText「会话权限：…」 |
| `ets/components/DrawerSearch.ets` | 抽屉正文搜索（对照安卓 session_search.dart）：@Link query + @Prop @Watch version；300ms 防抖调 dshrb-v1 `session/search`，parseSessionSearchHits(limit 20)，三种空态；目录晚到自动补发；不支持时静默降级为标题过滤 |
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
| `harmony/test/cases/tool-detail.test.ts` | 工具详情（2026-11-17 task-6 扩）：formatDuration 四档+bashCommandOf/参数截断/prettyArguments/readLinesOf/ioInputOf run_code 正文/搜索摘要 searchSummaryOf（grep 匹配·文件数/glob 路径数/空→无结果）/webSummaryOf 首行·未找到结果/readWindowLabelOf/expandRestLabelOf/askSummaryOf 六态（含已取消） |
| `harmony/test/cases/work-steps.test.ts` | 工作步骤 9 用例：三偏好解析回退/turnsOf 轮分组/visibleMessagesOf all 原样与 final 过滤（运行中轮三路全可见、无候选整轮保留、process/files 卡保留）/processGroupKey callId 与 seq 兜底/lastTurnGroupKeys |
| `harmony/test/cases/code-diff.test.ts` | 代码差异 6 用例：edit −old/＋new 行序/write 全 ＋ 行与空内容/非目标工具与坏参数→null/tools.edit+tools.write 前缀识别/同 path 聚合保序/codeDiffsOfLastTurn 只取最后一轮 |
| `harmony/test/cases/tool-present.test.ts` | 工具呈现（2026-11-17 task-6 更新）：activityKind 全表/kindIcon 兜底/topKindOf 计数降序并列首现/toolTitleOf 三段分派（见 tool-titles.test）/词表截断（truncateDetail 160+…、reasoningTail 去 **）+liveDetailOf 键序与 queries 首项/processGroupTitle 进行中（preparing/detail 附加/liveProcessDetail=false/ask）/完成组组合（2 类「并」含「已」去重、≥3 类「，」、4 类「等」、空组已完成分析、count 降序并列首现）/toolSummaryOf 键序与兜底/detailModeOf 分派（grep/glob→search、web_search/web_fetch→web）/ioInputOf（run_code code 正文/JSON 截 200/坏 JSON）/ioOutputOf（空→无结果）/askSummaryOf 六态/answerEntries/askQuestions/policyOf 四档/isGroupForceOpen 六路/五态口径与 AK 常量锚定 |
| `harmony/test/cases/tool-titles.test.ts` | 工具标题三段分派 5 用例（2026-11-17 task-6 新建）：stripToolPrefix/classifyTool 17 键变体全表（cordis_define 缺席→others）/toolTitleOf 优先级（组件覆盖>49 键表>变体词>兜底）/自有标题抽样（pwsh 运行命令/todo_write 更新任务清单/apply_patch 应用补丁/wait_agent 等待子智能体）/未知与空名兜底 |
| `harmony/test/cases/reasoning-text.test.ts` | 思考行文本 6 用例（2026-11-17 task-6 新建）：reasoningText signature 三路（未闭合空串/非 sig 原样/闭合剥包裹）/firstLine 不 trim/paragraphPreview 空白行分段取最后已完成段（末段单行回落上一段）/「**」全剥/reasoningHidden |
| `harmony/test/cases/turn-tail.test.ts` | 轮尾行 7 用例（2026-11-17 task-6 新建）：turnTailOf 非 assistant/流式中→null/闭合轮 hasContent·durationMs 1s 下限·groupKeys/缺一端·同毫秒→null 时长/轮内 error 卡→failed/列表尾轮空闲视为闭合/durationPartsOf（小时分秒 floor、整小时也带 0 分 0 秒）/turnTailLabel 三态 |
| `harmony/test/cases/stream-tools.test.ts` | 流式工具行 11 用例（2026-11-17 实时工具事件批次，对齐安卓 streaming_tools.dart）：applyDelta 建 preparing 行/缺名占位「工具调用」/真实 callId 到达后迁移收编（仅 1 行、旧 idx 键消失）/只带 index 的续包命中已迁移行/applyEnd 定稿/applyCall 转 running/applyResult 终态（failed/stopped/cancelled）/exitBadgeOf（exit code / killed by signal）/statusFromErrorCode（interrupted→stopped、ASK_CANCELLED→cancelled、未知→失败）/rankOf 降级守卫/mergeLiveRow |
| `harmony/test/cases/agent-presets.test.ts` | Agent 预设 5 用例：全字段解析/缺键回默认（0.2.x 无 trust 实证）/null 全默认/toJson round-trip（description null 省键）/listFrom |
| `harmony/test/cases/stream-render.test.ts` | 流式渲染接线回归 7 用例（2026-11-17 真机「流式思考不显示」）：源码契约钉死 StreamingBlock 的 reasoning/text/showPreview 为 @Prop、ThinkBlock 的 text 为 @Prop 且展开正文走 `MdView(reasoningText(this.text))`、MdView 的 text 为 @Prop+@Watch 且回调重 parseMarkdown、MessageList 把流式缓冲抄进 @State 再下传/streamingVisible 覆盖残留增量；行为侧覆盖 send() 即建空实例（streaming=true 且两缓冲为空）→ reasoning 增量逐帧累积、跨会话不串台、turn.end 清空缓冲 |
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

- 消费对象：`dsh-remote-bridge`（协议基线 v2.10.0，2026-11-19 起对齐到 v2.12.1 的
  `session-stats` / `context-usage` 帧、`hello.capabilities` 能力位、`history` 字节预算截断标记、
  WS close code 语义），协议 `dsh-mobile-v1`，hello.protocol=3。
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
  `session-stats` / `context-usage`（桥读内核 `session/projections` 的
  `sessionStats`/`tokenUsage`/`contextPressure`，**键缺失回 null 不是缺字段**，老桥回
  `UNKNOWN_TYPE` 由调用方静默降级——2026-11-19 协议对齐）；
  推送：`event(chat.message.delta|chat.message.committed|chat.turn.failed)`、
  `connection-resync-required`、`question-requested`。
- 能力位（`hello.data.capabilities`，判特性**不判版本**）：本仓只读取不驱动布局，
  存档在 `GatewayClient.capabilities` / `ChatStore` 侧 `hasCapability()` 供后续按位降级；
  `hello.data.port` 一并存档（隧道专用数据端口排查用）。
- REST：`GET /api/v1/attachments/{id}?sessionId=` 与
  `GET /api/v1/image-handoff?name=&sessionId=`（取图，真机反馈第 1/8 项；
  **image-handoff 两个 query 都必填**，缺一 bridge 回 400 `BODY_INVALID` —— 姊妹仓踩过、
  安卓侧 2026-11-19 才补上 sessionId）、
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
8. **WS close code 是有语义的**（`/ws/mobile` 服务端主动关连接）：`4001` = 鉴权失败/设备已被吊销
   （**不能重连**，重连必被同样打回，症状是无脑重连刷屏）、`1009` = 单帧超 1 MiB、`1000/1005` =
   正常关。只把 onDone 当「掉线」处理会把这三种情形混成一个。客户端按 4001 收口
   `AUTH_FAILED` 并提示重新配对，1009 提示「请求内容超过 1 MiB」。
9. **`history` 会被桥按字节预算裁剪**：真裁剪时响应体追加 `truncated:true` 与 `bytes`
   （未裁剪时这两个字段**不出现**，不是 `false`/`0`），单条事件里被截的字符串标
   `bridgeTruncated`。不处理的下场是把「更早历史没取到」误当成「历史就这么长」。
10. **能力位只增不撤、命名 `<能力>-v<主版本>`**：`hello` 每连接推一次且每次现算
   （插件/隧道状态变了就会变），所以不能在连接建立时缓存成全局常量后永不刷新，
   也不能拿 `bridgeVersion` 字符串比较来猜特性（版本号是给人看的，特性看能力位）。
