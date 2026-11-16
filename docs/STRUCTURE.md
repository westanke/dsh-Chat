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
| `design/app_settings.dart` | 本地偏好 `AppSettings`（界面风格三档 / 字号缩放 / 跟随系统 / 繁忙发送模式 / 诊断日志）+ `AppFontScaler`（与系统字号相乘的 TextScaler）；枚举按 name 持久化，凭据分库 | ✅ 单测覆盖 |
| `bridge/models.dart` | DshSession（含 `cwd` WirePath 相对路径 = 会话目录）/ DshWorkspace / MessageDelta / MessageCommitted（openapi §ChatSession/§ChatWorkspace，asyncapi §ChatMessageDelta/§ChatMessageCommitted）；目录选择模型 `SessionLocation`{rootId?,cwd,label} / `DshFileEntry` / `DshDirectoryPage`（2026-11-15 新建会话可选目录）；历史装配四件套拆 `history_page.dart`，经 export 继续暴露 | ✅ 单测覆盖 |
| `bridge/history_page.dart` | 从 models.dart 拆出（宪法 §7 控行数）：`SessionEvent`（内核历史事件透传）/ `DeliverableFile`（文件卡）/ `ChatMessage`（含 `images`/`files` 引用）/ `HistoryPage`（`rawEvents` 归一化 + `projections` 透传投影 + `hasMore` 真值；fromEvents 含 `turn/end` 失败解析；deliverables 文件卡**暂存挂轮尾**——`pendingFileCards` + `flushFileCards()`，flush 点 = user/message、turn/end、事件流末尾，2026-11-14 落位修复） | ✅ 单测覆盖 |
| `bridge/content.dart` | content 部件模型（从 models.dart 拆出，控行数）：`ContentParts`（text/reasoning + `images` 图片引用解析）/ `ContentImageRef` / `PromptPart` / `handoffImageNameOf`（`[Image: source: …]` 交接占位提取）/ `parseAtMentionDraft`（@ 文件引用草稿解析——光标前最近 `@片段`，含替换区间与 @ 边界判定，m03878） | ✅ 单测覆盖 |
| `bridge/projections.dart` | 纯 Dart 投影解析：`trajectoryOf()` 客户端按 data.turn 分组原始事件（轨迹 Sheet）；`todoItems()` / `agentTeamProjectionOf()` 读服务端 `projections.values.*`（团队 / TODO）；全部容忍投影缺席 | ✅ 单测覆盖 |
| `bridge/tool_call.dart` | ToolCallInfo + 工具措辞表 `toolPhrases` + 摘要 `toolSummary` + `RawToolCall` / `extractToolCalls`（从 models.dart 拆出，控行数） | ✅ 单测覆盖 |
| `bridge/gateway.dart` | WS `/ws/mobile`：子协议 `dsh-mobile-v1`、hello.protocol=3、requestId（**data 内回显**）、退避重连 1→2→4→8→16s、心跳 25s（连接面本体；业务封装拆 `gateway_api.dart`，事件模型拆 `gateway_events.dart`，均 re-export，消费方只 import 本文件）；`chat.deliverables.presented` 实时帧转 `SessionEventReceived('deliverables/presented')` 触发防抖重拉（2026-11-14） | ✅ 装机验证 |
| `bridge/gateway_events.dart` | 从 gateway.dart 拆出（宪法 §7 控行数）：`GatewayState` / `GatewayEvent` sealed（Delta/Committed/TurnFailed/Resync/SessionEventReceived）/ `RequestException` | ✅ |
| `bridge/gateway_api.dart` | 从 gateway.dart 拆出：`extension GatewayApi on GatewayClient`——workspaces/sessions/**session-create（workspaceId 预建）与 `createSessionAt({rootId,cwd})`（自选目录预建，失败显式报错勿静默回退）**/directory-create/**`listDirectory()`（file-list 帧目录浏览 → DshDirectoryPage）**/REST 建改工作区/history（`beforeSeq` 翻页 + `hasMore` 真值）/attachments 与 image-handoff 取图/sendText(mode+contentParts)/cancelTurn/permission/models/commands/**command-execute**/select-model | ✅ 单测覆盖 |
| `bridge/gateway_http.dart` | REST 字节下载 `gatewayHttpBytes()`（GET + Bearer + 30s 超时，附件/交接图共用） | ✅ |
| `bridge/gateway_rest.dart` | REST JSON 顶层函数：`gatewayCreateWorkspace()`（POST /chat/workspaces，path=根内相对路径）/ `gatewayRenameWorkspace()`（PATCH，落「手机会话」组名）/ **`gatewayResolvePath()`（GET /roots/resolve 解析 deliverables 绝对路径 → ResolvedFile{rootId,path,size,contentType}）+ `gatewayReadFileBytes()`（GET /roots/{rootId}/content 取文件字节，m03452 文件卡打开用）** + **`gatewayListRoots()`（GET /roots 授权根清单 → GatewayRoot）/ `gatewayListEntries()`（GET /roots/{rootId}/entries 目录懒分页 → GatewayEntry，目录优先排序——m03878 @ 文件补全用）** | ✅ |
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
| `ui/chat_message_list.dart` | `part of chat_page.dart`：消息列表 + 跳转最新 FAB + 滚动冻结 / 贴底跟随（`wantsBottom` 粘性意图、80ms 解冻、140ms 渐显）；判据在 `scroll_follow.dart` | ✅ 单测覆盖 |
| `ui/chat_message_items.dart` | `part of chat_page.dart`：消息项（双击复制整条；用户气泡内嵌历史图片 `DsChatImage`；助手消息 image-handoff 占位转图；**deliverables/presented → `_DeliverablesCard` 文件卡：.md 点开全屏渲染（MdViewerPage），其他类型系统打开（openFile），失败回退分享——m03452 改进，第四轮反馈 6**）；**role=='command' 命令卡（斜杠命令本地回执：命令行 + ✓/✗ 结果，m03878）** / 流式项 / 思考块（流式默认展开「深度思考中…」并随思考流滚动；历史消息折叠「已深度思考」——m03759 反馈） / 消息操作条（重新生成接线） | ✅ 装机验证 |
| `ui/chat_image.dart` | 历史图片组件 `DsChatImage`：attachment / image-handoff 双通道自动下载（`gatewayImageFetcher(gateway, sessionId)` 注入，attachments 接口必填 sessionId query，随会话切换刷新）+ 进程内字节缓存 + 失败占位可点重试（真机反馈 2026-11-04 第 1 项） | ✅ 装机验证 |
| `ui/scroll_follow.dart` | 滚动跟随纯函数：`shouldAutoFollow` / `shouldShowFab` / `computeAtBottom` / `freezeSnapshot` / `isUserScrollGesture`（只认 dragDetails），对照 companion 三处滚动实现 | ✅ 单测覆盖 |
| `ui/chat_state.dart` | ChangeNotifier：会话列表 / 打开会话（**openSession 清流式缓冲 streaming/streamText/streamReasoning 并先渲染清空态——2026-11-15 切会话深度思考串台修复**）/ 发送（纯文本与带图；新会话**分流：`pendingLocation` 已选目录 → `createSessionAt(rootId,cwd)` 建会话即定死目录；未选 → `ensureMobileWorkspace` 预建到「手机会话」工作区——2026-11-15 可选工作目录**；`setPendingLocation()` + `notifyUi()`）/ 斜杠命令 `runCommand()`（command-execute；**回执注入本地命令卡 role=='command' 并在 reloadHistory 后保留——m03878**）/ `cancelTurn()` / `regenerateAt()` / `retryLast()` / 历史翻页 `loadOlder()`（beforeSeq + seq 去重；方法体抽 `chat_history_actions.dart` 控行数）/ 流式累积 / 推送分发（含 HITL 问答/审批事件转发到 `HitlState`）/ HITL 动作 `answerQuestion()`/`cancelQuestion()`/`decideApproval()`；分组 getter 委托 `session_groups.dart`；`newChat()` 清 pendingLocation（不沿用上次选择） | ✅ 装机验证 |
| `ui/hitl_state.dart` | HITL 挂起表 `HitlState`（全连接 pendingQuestions/pendingApprovals 按 callId/approvalId 去重 + 会话过滤 getter + answer/cancel/decide 动作；从 chat_state.dart 拆出控行数） | ✅ 单测覆盖 |
| `ui/question_card.dart` | `HitlPanel`：提问卡（每题 FilterChip 单/多选 + 自定义回答输入 + 提交键，提交走 question-answer）与审批卡（允许一次 / 拒绝，approval-response）；**整面板限高屏高 ×0.5（`hitlPanelMaxFraction`）内部上下滚动——2026-11-15 用户反馈内容过多时提交按钮被推出屏幕** | ✅ 单测覆盖 |
| `ui/session_groups.dart` | 会话抽屉分组纯函数 `groupSessionsByWorkspace()`：顶层按工作区分（「手机会话」置顶、其余用 workspace title、无工作区「未分组」），组内按今天/昨天/更早；单工作区单日期退化为纯日期（真机反馈第 7 项） | ✅ 单测覆盖 |
| `ui/chat_history_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`reloadChatHistory(state)` / `loadOlderMessages(state)` / `oldestSeqOf(state)`——chat_state 薄转发保 UI 调用点 | ✅ 单测覆盖 |
| `ui/chat_hitl_actions.dart` | 从 chat_state.dart 拆出（宪法 §7 控行数）顶层函数：`submitChatAnswer` / `skipChatQuestion` / `decideChatApproval(state,…)`——HITL 动作落 lastError 后 notifyUi；chat_state 薄转发保 UI 调用点 | ✅ analyze |
| `ui/session_location_sheet.dart` | 新建会话目录选择 sheet（2026-11-15 可选工作目录）：默认项「手机会话（默认）」+ 已选高亮（「点此恢复默认」）+ 「最近使用」按历史会话 (rootId,cwd) 去重（cwdAbsolute 副标题）+ 浏览页（面包屑 + 只列目录 + 加载更多 + 「在此目录新建会话」回传 `SessionLocation`）；`DirectoryLister` 注入点供测试 | ✅ 单测覆盖 |
| `ui/mobile_workspace.dart` | 「手机会话」工作区准备 `ensureMobileWorkspace()`：title 含「手机」的既有工作区 → 建目录 `.dsh-mobile`（directory-create，409 幂等）→ REST 登记工作区 → PATCH 改名「手机会话」；失败回 null 不阻断发送（真机反馈第 7 项） | ✅ |
| `ui/stats_sheet.dart` | 会话统计 Sheet：`chatStatsOf()` 由已加载消息本地计算（消息/工具/思考/错误数），零网络请求；对照 companion ChatStatsSheet | ✅ 单测覆盖 |
| `ui/projection_sheets.dart` | 三个零请求面板：运行轨迹（rawEvents 本地分组、点节点展开原始 JSON）/ 智能团队（projections.values.agentTeam，含三枚普通消息话术 chips，**子会话行可点进详情页，第四轮反馈 3**）/ 待办任务（projections.values.todos）；投影缺席显示空态而非隐藏入口 | ✅ 单测覆盖 |
| `ui/subagent_history_page.dart` | 子会话（团队成员）只读历史页：REST 窄口 `subagentHistory()`（GET /chat/sessions/{leadId}/subagents/{id}/messages，openapi.yaml:992-1050）+ beforeSeq 翻页 + 轻量只读消息渲染；协议明确成员会话不可写，无输入条（第四轮反馈 3） | ✅ 单测覆盖 |
| `ui/settings_page.dart` | 设置页主文件：Scaffold + 分区骨架（`settings_sections.dart` / `settings_widgets.dart` / `settings_update.dart` 是同库 `part`，共享私有成员，宪法 §7 控行数）；普通返回即退出（二次确认挪到主页——第五轮勘误：用户要的是退出 APP 二次确认，不是设置页） | ✅ 单测覆盖 |
| `ui/settings_sections.dart` | 设置页分区：连接与设备信息（hello 只读）/ 界面风格三档 / 字号缩放与跟随系统 / 繁忙发送模式 / 诊断日志 / 关于（含检查更新行）/ 断开连接；不摆无授权的服务端开关 | ✅ 单测覆盖 |
| `ui/settings_update.dart` | `part of settings_page.dart`：`_UpdateCheckRow` 检查新版本（1.5s 静默检查有新版才提示；手动检查三态：发现新版本→点按下载 / 已是最新 / 两站都连不上；下载轮询进度百分比 + STATUS_SUCCESSFUL 后 installApk 自动拉起安装，第二轮反馈 C；`Timer` 必须 dispose 取消，测试断言无 pending timer；本机版本运行时经 `DshPlatform.appVersion()` 读取（没读到则跳过比较，不拿 0.0.0 误报）） | ✅ 单测覆盖 |
| `ui/settings_widgets.dart` | 设置页通用组件：`_Section` / `_InfoRow` / `_ActionRow` / `_SwitchRow` / `_SegmentedRow` / `_ScopeChip` / `_WarningBanner` | ✅ 单测覆盖 |
| `ui/composer.dart` | 输入条：白浮层圆角容器 + 输入框 + 权限档位 chip + 图片附件 chip 与发送（8MiB 上限；单发图片也亮发送键）+ **「/」斜杠命令面板**（`parseSlashDraft` 检测草稿 → commands 帧清单前缀过滤 → 浮层建议（**可滚动 + 键盘上下高亮、回车选中——m03878**）→ 点选回填；发送优先走 `onCommand`；**拉取失败不落缓存、下次输入自动重试——m04149**）+ **「@」文件引用面板**（`parseAtMentionDraft` 草稿检测 → gatewayListRoots+gatewayListEntries **多根逐根拉取合并**（空根不挡非空根——m04149）→ 目录点选继续进子目录、文件回填 `@label/path `——m03878）+ 发送键三态 + **加图按钮常驻（先打字也能加图，第二轮反馈 D）** + 底部免责提示（**流式思考期间隐藏，无思考时显示——m03759 反馈**；命令面板组件拆 `composer_widgets.dart`）+ **选图不再按文件名扩展名猜类型：用原生回传的真实 mediaType（缺失时读缓存字节魔数兜底）+ 内核 4 种白名单核对，失败原因显式弹提示（华为 HEIC 修复）** | ✅ 装机验证 |
| `ui/composer_widgets.dart` | `part of composer.dart`：基础件 `_Chip`（胶囊 chip）/ `_RoundIconButton`（圆形按钮）+ `pickComposerImage`（读选图缓存字节→base64；mediaType 由调用方按魔数/原生回传传入，不再按扩展名判——华为 HEIC 修复，m03878 拆入） | ✅ |
| `ui/composer_panels.dart` | `part of composer.dart`：`_CommandPanel`（斜杠命令建议浮层，可滚动+高亮——m03878）/ `_AtFilePanel`（@ 文件引用浮层，目录/文件图标区分，可滚动+高亮——m03878；**失败态错误行+点按重试——m04149**）+ `fetchAtEntries`（**多根逐根拉取合并**，空根不挡非空根——m04149） | ✅ |
| `ui/composer_bar.dart` | `part of composer.dart`：`_ComposerBar`（输入容器：输入框+权限 chip+图片 chip+加图/发送圆钮）/ `_PermissionSheet`（权限档位底部弹层）/ `confirmFullPermission`（完全权限二次确认） | ✅ |
| `ui/connect_page.dart` | 连接页三级路径：历史主机点击直连（DshHosts，有 token 才显示、失败显式报错）+ DSH1 配置文本导入（decodeDsh1，有 token 直连/无 token 填表）+ 手动配对（bridge 地址 + 配对码）；成功都 upsert 主机记录；**历史主机卡片删除按钮 + AlertDialog 二次确认 + 直连失败「删除这条失效记录」入口（DshHosts.remove，命中当前凭证顺手 DshCredentials.clear）** | ✅ 装机验证 |
| `ui/md_view.dart` | GptMarkdown 定制：官方 token 全量映射、任务列表预处理、codeBuilder/tableBuilder 接线、**链接可点外跳浏览器（url_launcher onLinkTap，第四轮反馈 5）** | ✅ 装机验证 |
| `ui/md_viewer.dart` | 全屏 Markdown 文档查看页 `MdViewerPage`：.md 文件卡点开 → `gatewayResolvePath` + `gatewayReadFileBytes` 取字节 → utf8 → `DsMarkdownView` 滚动渲染；顶栏文件名 + 体积，失败给重试（文件卡 m03452 改进） | ✅ 单测覆盖 |
| `ui/image_viewer.dart` | 全屏图片查看器 `openImageViewer()`：黑底 InteractiveViewer 双指缩放/拖移、单击关闭、双击 1x/2.5x 变焦；聊天图片（chat_image.dart）点按进入，字节走进程内缓存零请求（第四轮反馈 1） | ✅ 装机验证 |
| `ui/md_code_block.dart` | 自绘代码块：Atom One Light（ValTheme 自定义）+ banner「语言名 / 复制」 | ✅ 装机验证 |
| `ui/md_table.dart` | 自绘表格：banner「表格 + 复制/下载/展开」+ 官方 #fafafa 底 + #dcdcdc 线 | ✅ 装机验证 |
| `ui/message_actions.dart` | 助手消息操作条：复制 / 喜欢 / 朗读（系统 TTS）/ 分享（系统分享面板，**尾部附「—— 发送于 yyyy-MM-dd HH:mm」，第四轮反馈 7**）+ 右侧重新生成接线；平台不支持时明确提示（点踩按真机反馈 2026-11-04 移除） | ✅ 装机验证 |
| `ui/process_group.dart` | 工具调用折叠组：折叠一行「执行了命令，读取了图片…」，点开展开逐条明细，再点单条看完整详情（bash 命令按 BASH 代码块 `DsCodeBlock` 语法高亮展示、其余工具纯文本参数 / 输出 / 耗时 / 错误，真机反馈第 6 项） | ✅ 装机验证 |
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
| `app_settings_test.dart` | `normalizeFontScale`（NaN/Inf/越界夹取）、`AppFontScaler` 与系统字号相乘、`AppSettings` 默认值与 `effectiveFontScale` |
| `settings_page_test.dart` | 设置页渲染：界面风格三档 / 繁忙发送模式两档 / 字号滑块与跟随系统 / 诊断日志开关均真实生效 |
| `chat_actions_test.dart` | `chatStatsOf()` 本地统计、`Composer` 发送键三态、`ChatState.regenerateAt/retryLast` 重发用户消息 |
| `image_media_type_test.dart` | 图片类型纯函数：`sniffImageMediaType` 魔数表（PNG/JPEG/GIF/WEBP/BMP/HEIC(hei/hev/mif)/AVIF + 短数组截断）/ `isSupportedImageMediaType` 内核 4 种白名单 / `mediaTypeExtension` 映射（华为 HEIC 修复） |
| `scroll_follow_test.dart` | `shouldAutoFollow` 粘性意图自锁回归、`shouldShowFab` / `computeAtBottom` / `freezeSnapshot` 空表 / `isUserScrollGesture` 程序滚动不算手势 |
| `projections_test.dart` | `trajectoryOf()` 按 turn 分组 / 组内 seq 排序 / 丢弃过程细节 / 未知轮次垫底；`todoItems()` 只认 `{content,status}`；`agentTeamProjectionOf()` 缺省回退与空壳 null；`HistoryPage` 保留原始事件与投影 |
| `hosts_test.dart` | `DshHost` stableId 幂等 / round-trip（token 缺省不发键）；`decodeDsh1` 宽容解码（前缀前说明文字/换行/结尾标点/大小写不敏感）与垃圾输入一律 null；**`DshHosts.remove` 存储层：删存在→true/落盘同步、删不存在→false、按非空 id 兜底匹配、删空写 `[]`** |
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

## harmony/（鸿蒙版，ArkUI 原生重写）

> 安卓版全功能的鸿蒙移植，工程根 `harmony/`，阶段与规程见 `harmony/docs/{PORT-MAP,RELEASE,STATUS}.md`。
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
| `ets/pages/Index.ets` | 根路由 boot（自动连接）→ connect（连接页）→ chat（对话页）；深浅色 mediaquery 监听写 AppStorage('dshDark')；ChatStore 单例随连接存活 |
| `ets/pages/ConnectView.ets` | 连接页三级路径：历史主机直连（失败记失效记录可删）/ DSH1 文本导入 / 手动地址+配对码（pairViaRest）；删除当前主机顺带清凭据 |
| `ets/pages/SettingsView.ets` | 设置页六分区：连接只读（状态/设备/scopes/HTTP 警告）/外观（跟随系统/浅色/深色）/发送（queue|steer）/关于（版本+检查更新跳 Gitee）/断开连接（清凭据回连接页） |
| `ets/pages/MdDocViewer.ets` | .md 全屏查看页：resolvePath/readFileBytes → MdView；标题+大小 caption/失败重试 |
| `ets/pages/ChatView.ets` | 对话页：顶栏（⋮ 溢出菜单五项/标题/连接点/新建）+ HitlPanel 提问审批卡 + 消息列表 + 输入条 + 会话抽屉 + 五面板 bindSheet（统计/轨迹/团队/待办/模型）+ 设置页入口 |
| `ets/components/MessageList.ets` | 消息列表：用户气泡（86.4% 宽 + 收图 ImageTile）/ 助手 MdView 富渲染 + 工具折叠组 ToolBlock + 命令卡 + 文件卡（.md 全屏 MdDocViewer）+ 消息操作条 MessageActions / 错误条 |
| `ets/components/Composer.ets` | 输入条：发送键三态（send/stop/disabled）+ 命令补全/@ 文件补全（ComposerPanels）+ 图片 chip（PhotoPick 魔数校验 8MiB）+ 权限 chip（PermissionSheet bindSheet）+ 免责声明 |
| `ets/components/SessionsDrawer.ets` | 会话抽屉（阶段 2）：主机标识 + 新对话钮 + 工作区分组列表（未分组垫底）+ 当前会话高亮；搜索/删除阶段 4 |
| `ets/components/md/MdView.ets` | Markdown 主组件：块级循环（h/p/quote/code/table/ul/ol/hr/latex）+ 行内混排（Span 样式/链接外跳/内嵌 MdLatexView）；任务项 ☑/☐，引用左竖条 |
| `ets/components/md/MdCodeBlock.ets` | 代码块：banner 语言名+复制（pasteboard）+ 1px 分隔线 + 横滚 + SimpleHighlight 四类着色 |
| `ets/components/md/MdTable.ets` | 表格：banner「表格」+复制（\t 连接）+ 表头 w500 + cellAlign l/c/r + cellMinWidth 100 |
| `ets/components/md/MdLatex.ets` | 轻量 LaTeX 渲染：frac/sqrt/sup/sub/sym 分派（横线分子分母/√ 上边框/70% 字号偏移）；嵌套 smallArg 拍平 |
| `ets/components/ToolBlock.ets` | 工具折叠组：摘要行（⚒ 短语）+ 展开逐条（✓/✗ 措辞/耗时）+ 单条 detail（bash 走 MdCodeBlock，其余 prettyArgs） |
| `ets/components/HitlPanel.ets` | 提问/审批卡：审批（⚖ 警示底 拒绝/允许一次）先、提问（选项 chips 单选清旧 + 自定义输入 canSubmit）后；限高 0.5 屏 |
| `ets/components/ImageTile.ets` | 收图渲染四态（加载/像素/错误重试/全屏）：createImageSource→PixelMap→Image 260 Cover，点按 bindContentCover 全屏 |
| `ets/components/MessageActions.ets` | 消息操作条：复制（pasteboard 回弹）/喜欢/朗读（Tts）/分享（Share）/⟳ 重新生成 |
| `ets/components/ModelSheet.ets` | 调整模型 bindSheet：分组折叠（默认展开当前）+ pending 提示 + reasoning chips + 确认（st.selectModel） |
| `ets/components/ProjectionSheets.ets` | 会话统计/运行轨迹/智能团队/待办任务四 sheet（骨架内联；团队三指挥 chip） |
| `ets/components/PermissionSheet.ets` | 会话权限档位 sheet（从 Composer 拆出）：aboutToAppear 拉清单 + pick/apply + danger 二次确认 |
| `ets/components/ComposerPanels.ets` | 输入面板：命令补全（缓存切会话失效/前缀过滤）与 @ 文件补全（多根合并 label/ 前缀 + 目录下钻 + 失败重试） |
| `ets/ui/theme.ets` | design-tokens.md 的鸿蒙翻译：DsPalette/DsColors（dark 构造语义别名）/DsTypography/DsSpacing；改样式先改 token 文档再改这里 |
| `ets/platform/WsTransport.ets` | @ohos.web.websocket 实现 WebSocketTransport：header 小写键 + protocol 单值，connectTimeoutMs settled 防竞态 |
| `ets/platform/HttpTransport.ets` | @ohos.net.http 实现 HttpTransport：响应头键小写收敛；PATCH 枚举缺失走字符串透传（真机待验） |
| `ets/platform/PlatformBridge.ets` | ArkTimers（setTimeout/clearTimeout）+ timeZoneId（Intl→UTC 兜底）+ PrefsStore（preferences 单例，getString/putString/removeKey） |
| `ets/platform/Dlog.ets` | hilog 封装（DOMAIN 0xD5C0，info/warn/error）——core 层禁 import @kit，日志实现只在 platform |
| `ets/platform/PhotoPick.ets` | 系统图库选图（photoAccessHelper PhotoViewPicker）→ 临时文件读字节 + 魔数嗅探 mediaType |
| `ets/platform/Tts.ets` | CoreSpeechKit 朗读（zh-CN，speak/stopSpeak，音量语速走 extraParams） |
| `ets/platform/Share.ets` | 系统分享面板（Want ohos.want.action.sendData text/plain） |
| `ets/core/ChatStore.ts` | 会话状态机（chat_state.dart 全语义）：send 乐观上屏+手机工作区预建（ensureMobileWorkspace）、流式收束、committed assistant/user 分支、防抖重拉 800ms、loadOlder 翻页去重、isCurrent 空态防串台 |
| `ets/core/MdParser.ts` | Markdown 块级解析（围栏/#/hr/引用/列表+任务项/表格/块公式/段落）：行扫描产 MdBlock；parseMarkdown 入口 |
| `ets/core/MdInline.ts` | 行内解析：code/bold/italic/strike/link/裸 URL 最早匹配优先；snake_case 不误判 |
| `ets/core/LatexLite.ts` | 轻量 LaTeX 解析：递归下降 \frac/\sqrt/^/_/\text + SYMBOLS ~90 项；splitLatex 切 $..$/$$..$$ 段 |
| `ets/core/SimpleHighlight.ts` | 轻量代码高亮：PY/JS/GO/SQL/BASH 关键词表 + 字符串/数字/注释四类 token；语言未知纯文本 |
| `ets/core/JsonAccess.ts` | JSON 宽容守卫（入站侧）：缺键/null/类型不符→null 或默认，绝不抛异常；strOr/numOr/boolOr 便捷默认版 |
| `ets/core/Wire.ts` | WireBuilder 出站编码（null 一律省略键，encodeDefaults=false 语义，姊妹仓同源） |
| `ets/core/Models.ts` | 协议帧模型 8 类：DshSession/DshWorkspace/MessageDelta/MessageCommitted/SessionLocation/DshFileEntry/DshDirectoryPage/SessionWaitResult（缺键全默认值） |
| `ets/core/Content.ts` | 消息内容部件：ContentParts 拼接规则、图片引用、交接占位正则、PromptPart（ArkTS 扁平类 + type 分派）、SlashCommand/别名过滤、斜杠/@ 草稿解析 |
| `ets/core/Credentials.ts` | 凭据数据形状（键 'dsh.credentials'，baseUrl+token）；持久化留 entry 层（preferences） |
| `ets/core/ImageMediaType.ts` | 图片白名单 4 种 + 魔数嗅探（PNG/JPEG/GIF/WEBP/BMP/AVIF/HEIC）+ 扩展名映射 |
| `ets/core/Transport.ts` | 传输抽象：HttpRequest/HttpResponse/HttpTransport、WebSocketTransport.open→EventSocketHandle、TimerBridge；WS/请求/心跳/退避常量（协议时序唯一出处） |
| `ets/core/GatewayEvents.ts` | GatewayState 枚举 + 扁平 GatewayEvent（十种事件 type 分派）+ RequestException（稳定错误码）+ eventFromFrame（十一支事件帧映射纯函数） |
| `ets/core/Questions.ts` | HITL 模型：UserQuestion/UserQuestionOption/PendingQuestion/PendingApproval/QuestionAnswerItem（custom 空省略，与安卓 questions.dart 对齐） |
| `ets/core/GatewayClient.ts` | WS 状态机：connect/hello 8s/心跳 25s/退避重连（1→30s，attempt 代数防迟到回调）、requestWithTimeout 配对、事件派发（映射在 GatewayEvents.eventFromFrame）、subscribe、dispose |
| `ets/core/GatewayApi.ts` | WS 端点 19 个（含 history/subagentHistory）+ REST（pairing exchange/attachment/image-handoff）|
| `ets/core/ToolCall.ts` | 工具调用合并模型 + 措辞表（bash/read_image…/mcp__ 直译/run_code 内嵌扫描）+ toolSummary 九键 + toolResultText（text 拼接/图片占位）|
| `ets/core/HistoryPage.ts` | 历史装配器 fromEvents：user/assistant 正文、连续 tool/call+result 合并过程组（callId 去重/就地升级）、文件卡轮尾挂载、turn/end 错误卡、注入内容过滤（source.kind）+ mergeOlderMessages 翻页去重 |
| `ets/core/Projections.ts` | 轨迹分组 trajectoryOf（按 turn/seq、未知轮垫底）+ 服务端投影（todoItems/agentTeamProjectionOf，宽容零抛）+ chatStatsOf 七键统计 + prettyJson |
| `ets/core/ReleaseCheck.ts` | 新版检测：fetchLatestRelease（Gitee api/v5 → GitHub api.github.com 落链，8s 超时）+ releaseFromJson 双前缀资产 + versionParts 三段 + isNewerVersion |
| `ets/core/Hosts.ts` | 主机记录 DshHost + FNV-1a 幂等 id（BigInt 64 位）+ DSH1 宽容解码（前缀任意位置/双字母表/补 =/截 {...} 重试）+ upsert/remove/parse/encode 纯函数 |
| `ets/core/ModelsView.ts` | models 应答收敛（SessionModels/groups/failures/current）+ parseSelectModelReply + reasoningEffortLabel |
| `ets/core/Permissions.ts` | permission-options 收敛（PermissionCatalog/Option）+ 本地中文标签（label/descriptionLabel/needsConfirm/isDerived）+ permissionLabelOf |
| `ets/core/MobileWorkspace.ts` | 手机工作区约定：ensureMobileWorkspace（缓存→标题匹配→.dsh-mobile 建目录→REST 登记→改名，全失败回 null 不阻断）+ prepareSessionFor + oldestSeqOf |
| `ets/core/ChatActions.ts` | 会话动作集（store 参数纯函数）：runCommandIn 命令卡（✓/✗ 就地改写）/regenerateAtIn 重生成/cancelTurnIn 停止/setPermissionIn（NO_SESSION 拒） |
| `ets/core/SessionGroups.ts` | 会话抽屉分组纯函数：groupSessionsByTime 先按时间分桶（今天/昨天/更早，超 2 天折叠）、桶内按工作区聚合（同区只显示一次小节标题），visibleRowsOf 处理「更早」展开态；dayBucketOf 按本地日历天分桶 |
| `ets/core/AppUpdate.ts` | 检查更新（华为应用市场口径）：UpdateCheckResult 结果对象 + updateErrorMessage SDK 错误码（1009400001~7/401）中文映射 + NOT_SUPPORTED_MESSAGE；平台调用在 SettingsView（updateManager.checkAppUpdate / showUpdateDialog） |
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
| `harmony/test/cases/projections-release.test.ts` |
| `harmony/test/cases/md-parser.test.ts` | Markdown 四件套 22 用例：块级/行内/LaTeX/高亮 + splitLatex/任务项/表格对齐 |
 8 用例：轨迹分组排序/todo 变体丢弃/团队投影空壳 null/发布资产双前缀/版本比较 |
| `harmony/test/cases/gateway-rest.test.ts` | REST 8 用例：URL 拼装/头/HTTP_40x/BAD_REPLY/空 body/encode/NO_TRANSPORT |
| `harmony/test/helpers/fake-ws.ts` | FakeTimers（手动 advance）/FakeSocket（服务端扮演 + lastRequestId）/FakeHttp（队列式应答） |
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
