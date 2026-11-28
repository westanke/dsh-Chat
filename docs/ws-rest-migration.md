# WS / REST 迁移审计（dsh-Chat 客户端 × dsh-remote-bridge）

只读审计，未改任何代码、未提交。

**基线**：`dsh-Chat` HEAD `c956fa3`；`dsh-remote-bridge` HEAD `dd771a1`。
审计期间两仓都有**并发未提交改动**（§0.3）。表中「工作树」= 只在未提交改动里存在，**不在 HEAD、不在协议文档**。
行号按 2026-11-28 21:5x–22:0x 抓取；较稳的锚点是函数名、帧名与 REST 路径字面量。

## 0. 口径

### 0.1 客户端真正发 REST 的只有 14 处

`grep -rn "/api/v1" app/lib app/ohos app/android app/ios`（排除注释与地址归一化代码）后，实际发请求的：

| # | 文件:行 | 函数 | REST |
|---|---|---|---|
| 1 | `app/lib/bridge/gateway_rest.dart:23` | `gatewayCreateWorkspace` | POST /chat/workspaces |
| 2 | `app/lib/bridge/gateway_rest.dart:46` | `gatewayRenameWorkspace` | PATCH /chat/workspaces/{id} |
| 3 | `app/lib/bridge/gateway_rest.dart:129` | `gatewaySendMessage` | POST /chat/sessions/{id}/messages |
| 4 | `app/lib/bridge/gateway_rest.dart:158` | `gatewayResolvePath` | GET /roots/resolve |
| 5 | `app/lib/bridge/gateway_rest.dart:219` | `gatewayListRoots` | GET /roots |
| 6 | `app/lib/bridge/gateway_rest.dart:265` | `gatewayListEntries` | GET /roots/{id}/entries |
| 7 | `app/lib/bridge/gateway_rest.dart:335` | `gatewayReadFileBytes` | GET /roots/{id}/content |
| 8 | `app/lib/bridge/gateway_rest.dart:348` | `gatewayAgentPresets` | GET /chat/agent-presets |
| 9 | `app/lib/bridge/gateway_rest.dart:424` | `gatewaySelectAgentPreset` | PUT /chat/sessions/{id}/agent-preset |
| 10 | `app/lib/bridge/gateway_api.dart:296` | `fetchAttachment` | GET /attachments/{id}?sessionId= |
| 11 | `app/lib/bridge/gateway_api.dart:312` | `fetchQuestions`（仅回落） | GET /chat/sessions/{id}/questions |
| 12 | `app/lib/bridge/gateway_api.dart:459` | `subagentHistory` | GET …/subagents/{id}/messages |
| 13 | `app/lib/bridge/gateway_api.dart:342` | `fetchImageHandoff` | GET /image-handoff |
| 14 | `app/lib/bridge/endpoint_select.dart:146` | `_probeOne` | GET /healthz |

**没有**代码的能力面：`/settings/*`（只有 `ui/settings_page.dart:4`、`ui/settings_sections.dart:74` 的说明文案）、
`/trash*`、分块上传（`/uploads`、`/chunks`、`/complete`）、`/chat/schedules`（`gateway_schedule.dart` 全帧）、
`/jobs`（`jobs.dart` 全帧）、`PUT /roots/{id}/content`、`PATCH,DELETE /roots/{id}/entries`。

### 0.2 能力位不等于「帧可用」

`dsh-remote-bridge/src/host/capabilities.ts:22-35`：能力位是「服务端能做什么」的对外声明，加位必须能在 OpenAPI 路径或 AsyncAPI 事件里
指出依据；只有 `session-pin-v1` 这类注释里只写帧、没有任何 REST 路径的位（`capabilities.ts:70`）才代表帧。
因此 `workspace-manage-v1`、`subagent-history-v1`、`file-write-v1`/`file-trash-v1`（`capabilities.ts:59-60,75,82`）
**只证明 REST 在**，不能证明同名帧在。客户端拿这些位去 gate 帧时，只支持 REST 的桥会先回 `UNKNOWN_TYPE` 再回落
（工作树里 `gateway_api.dart:683` 用 `agent-presets-v1`、`:771` 用 `workspace-list-v1` 就是这种写法）。

### 0.3 并发未提交改动（读结论时务必知道）

- 客户端工作树：`M bridge/{gateway,gateway_api,gateway_events,history_page,projections}.dart`、`M ui/chat_state.dart`、
  新增 `?? bridge/mobile_frames.dart`。已把 `agentPresets`/`selectAgentPreset`/`createWorkspace` 改为
  「WS 优先 + REST 回落」（`gateway_api.dart:682,710,763`），并用会话 `cwdAbsolute` 反推授权根绝对路径（`mobile_frames.dart:164-190`）。
- 桥工作树：`M ws-protocol.ts, ws-sessions.ts, ws-files.ts, ws-team.ts, ws-handler.ts, file-service.ts, error-codes.ts, index.ts`，
  新增 `?? tests/ws-file-frames.spec.ts`。**已经把 4 组 REST-only 能力补成帧**（尚未提交、未跑测试、协议文档未同步）：

  | 帧 | handler | 状态 |
  |---|---|---|
  | `workspace-update` / `workspace-deleted` | `ws-sessions.ts:263-281`，载荷 `{workspaceId,name}`，`chat.write` | 工作树已实现 |
  | `workspace-delete` / `workspace-deleted` | `ws-sessions.ts:283-298`，载荷 `{workspaceId}`，`chat.write` | 工作树已实现 |
  | `subagent-history` | `ws-team.ts:106-124`，载荷 `{leadSessionId,subagentId,beforeSeq?,maxMessages?}`，`chat.read`，授权复用 REST 那条 | 工作树已实现 |
  | `file-write` / `file-written` | `ws-files.ts:213-263`，`files.write`，20 MiB 上限 | 工作树已实现 |
  | `file-rename` / `file-renamed` | `ws-files.ts:265-276` | 工作树已实现 |
  | `file-delete` / `file-deleted` | `ws-files.ts:278-290` | 工作树已实现 |
  | `trash-list` / `trash-restore` | `ws-files.ts:292-345` | 工作树已实现 |

  未同步项：`docs/api/asyncapi.yaml` 里 **0 处**提到这些帧名（`grep -c` 结果为 0），`CHANGELOG-DEV.md` 也未记。
  这些帧**没有独立的帧可用性位**：`file-write-v1`/`file-trash-v1`（`capabilities.ts:59-60`）、`subagent-history-v1`（`:75`）、`workspace-manage-v1`（`:82`）都在，但每个位的注释依据都是 REST 路径，只支持 REST 的桥也会宣告它们（见 §0.2、§2.4）。

## 1. 全量清单

「现有 WS 帧」列：「已有」= HEAD 里就有；「工作树」= 只在未提交改动里；「无」= 协议与服务端都没有。
编号 R* 在 §2/§3 复用。

| # | 能力 | 客户端调用点（文件:行 · 函数） | REST | 现有 WS 帧 | 建议 | 阻塞点 | P |
|---|---|---|---|---|---|---|---|
| R1 | 会话历史首屏/翻页 | `bridge/gateway_api.dart:416 history` | GET /chat/sessions/{id}/messages（`openapi.yaml:1020`，deprecated） | 已有 `history`（`ws-basic.ts:87`，帧 `ws-protocol.ts:437`） | 已迁完 | 无 | P2 |
| R2 | 子会话（团队成员）历史 | `bridge/gateway_api.dart:459 subagentHistory`；`ui/subagent_history_page.dart:57,93` | GET …/subagents/{subagentId}/messages（`openapi.yaml:1075-1148`） | 工作树 `subagent-history`（`ws-team.ts:106-124`）；HEAD 无（`subagents` 只回目录，`ws-team.ts:10,49`） | **桥发布后直接换**；参数一对一映射，应答还多了 `projections/bytes/truncated/historyFormatVersion` | 未提交、协议文档未同步（`asyncapi.yaml` 无此帧）；客户端要加能力探测或最低桥版本判断 | P1 |
| R3 | Agent 预设清单 | `bridge/gateway_api.dart:682 agentPresets`；UI `ui/work_view_sheet.dart:73`、`ui/chat_setup_state.dart:90` | GET /chat/agent-presets（`openapi.yaml:461-474`，deprecated） | 已有 `agent-presets`（`ws-presets.ts:45`，回 `data.presets`） | **直接换 WS**（工作树已 WS 优先） | 帧处理里没有显式 scope（REST 要 `chat.read`）；老桥无帧 → 靠 `UNKNOWN_TYPE` 回落 | P0 |
| R4 | 切换 Agent 预设 | `bridge/gateway_api.dart:710 selectAgentPreset`；UI `ui/chat_setup.dart:79`、`ui/work_view_sheet.dart:97` | PUT /chat/sessions/{id}/agent-preset（`openapi.yaml:1466`，deprecated） | 已有 `session-agent-preset`（`ws-presets.ts:67`）、`select-agent-preset`（`:85`） | **直接换 WS**（工作树已 WS 优先） | 载荷键是 `agentPresetId`（REST 是 `agentPreset`）；409 `AGENT_PRESET_LOCKED` 变 error 帧 code，`work_view_sheet.dart:107` 的文案映射要保留 | P0 |
| R5 | 工作区清单 | `bridge/gateway_api.dart:51 workspaceListing` | GET /chat/workspaces（`openapi.yaml:382-400`，deprecated） | 已有 `workspaces`（`ws-basic.ts:74`，带 `pinnedSessionIds`） | 已迁完 | 无 | P2 |
| R6 | 工作区创建 | `bridge/gateway_api.dart:763 createWorkspace`（工作树）→ `gateway_rest.dart:23`；UI `ui/mobile_workspace.dart:59` | POST /chat/workspaces（`openapi.yaml:401-424`） | 已有 `workspace-create`（`ws-sessions.ts:219-246`） | **部分可换**：帧只收宿主绝对路径，客户端用同根会话 `cwdAbsolute` 反推（`mobile_frames.dart:164-190`） | 新设备/该根下还没有会话时推不出绝对路径 → 必回落 REST；帧不收 `rootId`+`WirePath`（`ws-sessions.ts:221-230`）；REST 侧明确「绝对路径不收不发」（`openapi.yaml:401`） | P1 |
| R7 | 工作区改名 | `bridge/gateway_rest.dart:46 gatewayRenameWorkspace`；UI `ui/mobile_workspace.dart:65` | PATCH /chat/workspaces/{id}（`openapi.yaml:426-444`，body `{title}`） | 工作树 `workspace-update`（`ws-sessions.ts:263-281`，回 `workspace-updated`） | **桥发布后直接换** | 字段名跨传输不一致：帧用 `name`、REST 用 `title`；未提交；`API.md:74` 仍列永久例外 | P1 |
| R8 | 工作区删除 | 无调用点 | DELETE /chat/workspaces/{id}（`openapi.yaml:446-455`） | 工作树 `workspace-delete`（`ws-sessions.ts:283-298`） | 暂不迁（客户端没有删除入口）；要做时帧已就绪 | 未提交；只注销登记、不动磁盘（与 REST 同义） | P2 |
| R9 | 全局模型目录 | `bridge/gateway_api.dart:582 defaultModelCatalog` | GET /settings/models（`openapi.yaml:592`） | 已有 `default-model`（`ws-settings.ts:46`，需 `settings.read`） | 已迁完，REST 仅回落 | 老桥 settings 未注入时 `NOT_IMPLEMENTED` + REST 指引（`ws-models.ts:33-41`） | P2 |
| R10 | 会话可用模型 | `bridge/gateway_api.dart:573 sessionModels` | GET models（`openapi.yaml:1403`，deprecated） | 已有 `models`（`ws-models.ts:50`） | 已迁完 | 帧必须带 sessionId，缺了回 `MISSING_PARAMS` 并指向 REST（`ws-models.ts:50-54`） | P2 |
| R11 | 选模型 | `bridge/gateway_api.dart:604 selectModel` | PUT /chat/sessions/{id}/model（`openapi.yaml:1439`） | 已有 `select-model` | 已迁完 | 无 | P2 |
| R12 | provider 只读 | 无调用点（`ui/settings_page.dart:4`、`ui/settings_sections.dart:74` 只有文案） | GET /settings/providers（`openapi.yaml:505-540`） | 已有 `providers`（`ws-settings.ts:59`，需 `settings.read`） | 无客户端需求；做设置页时直接换 WS | 设备默认 scope 不含 `settings.write`（`settings_page.dart:4-8`） | P2 |
| R13 | provider 增删改/发现 | 无调用点 | POST /settings/providers、PATCH/DELETE /settings/providers/{id}（`openapi.yaml:505,663`）、POST …/discover（`:702`） | 无 | **保持 REST**（无需求，写入需 `settings.write`） | `API.md:75` 已列永久例外；无帧 | P2 |
| R14 | settings 命名空间读 | 无调用点 | GET /settings/namespaces（`openapi.yaml:601-627`） | 无 | 保持 REST；做通用设置页时需桥补帧 | 无帧；内核 `settings` 命名空间被钉死（`kernel-allowlist.ts` 的 `KERNEL_DENIED_NAMESPACES`），`kernel-call` 也绕不过 | P2 |
| R15 | settings 命名空间写 | 无调用点 | PATCH /settings/namespaces/{ns}（`openapi.yaml:628-662`） | 无 | 保持 REST（需 `settings.write`） | 同上 + 设备默认无 `settings.write` | P2 |
| R16 | 插件清单 | `bridge/plugin_center.dart:264 listPlugins`（`kernel-call` → `pluginManager/listBundles`，`:243`） | GET /settings/plugins（`openapi.yaml:542-557`） | 已有 `plugin-catalog`（映射 `src/host/bridge/kernel-allowlist.ts:186`）+ 通用 `kernel-call` | 已迁完；可选把 `kernel-call` 换成 `plugin-catalog` 帧 | `kernel-call` 面未启用时回 `NOT_IMPLEMENTED`（`ws-kernel-frames.ts:34-37,70-77`）；`plugin-catalog` 应答是 `{ok,value}` 信封，需解包 | P2 |
| R17 | 插件开关 | `bridge/plugin_center.dart:310 setPluginEnabled`（`pluginManager/setBundleEnabled`） | PATCH /settings/plugins（`openapi.yaml:558-591`，`{name,loaded}`） | 已有 `plugin-settings`（`src/host/bridge/kernel-allowlist.ts:216`，`{name,enabled}`） | 已迁完（同上可选换帧） | REST 用 `loaded`、帧用 `enabled`；`restartRequired` 语义要保留 | P2 |
| R18 | 授权根清单 | `bridge/gateway_rest.dart:219 gatewayListRoots`；UI `ui/composer.dart:301` | GET /roots（`openapi.yaml:135-150`） | 无（`file-list` 只列内容、不列根） | **保持 REST** | `API.md:71` 永久例外（根绝对路径刻意不下发） | P2 |
| R19 | 目录列举 | `bridge/gateway_rest.dart:265 gatewayListEntries`；UI `ui/composer_panels.dart:188`；另 `bridge/gateway_api.dart:255 listDirectory`（WS）已被 `ui/session_location_sheet.dart:283` 使用 | GET /roots/{id}/entries（`openapi.yaml:177-242`） | 已有 `file-list`（`ws-files.ts:117-160`） | **可换 WS，但桥先修 `rootId`+相对 path** | 实现把非空 `path` 当**绝对路径**（`ws-files.ts:137-149`），与 `:123` 注释「相对或绝对均可」矛盾；相对 path 会被拼到桥进程 cwd 上再判是否在任一授权根内（**未核实**运行期 cwd）：cwd 恰在某根内就会列到别处、否则 403/404；无测试覆盖（`tests/mobile-gateway-ws.spec.ts:1044-1072` 只测 `path=''` 与绝对路径；新增的 `tests/ws-file-frames.spec.ts` 也没测 `file-list`） | P0 |
| R20 | 文件字节读取 | `bridge/gateway_rest.dart:335 gatewayReadFileBytes`；UI `ui/file_open.dart:52,90`、`ui/chat_artifact_card.dart:260`、`ui/md_viewer.dart:57` | GET /roots/{id}/content（`openapi.yaml:243-286`） | 已有 `file-download-open/read/cancel`（`ws-file-transfer.ts:273+`）但只认 `sessionId` + 会话根内相对路径（`:295-317`） | **保持 REST**；要迁需把帧扩成 `rootId`+path 或绝对路径 | 帧的授权模型是「会话根」，客户端手里是绝对路径或产物路径；512 KiB 分块 + base64 有明显开销 | P1 |
| R21 | 路径解析 | `bridge/gateway_rest.dart:158 gatewayResolvePath`；UI `ui/file_open.dart:50,88`、`ui/md_viewer.dart:53`、`ui/chat_artifact_card.dart:259` | GET /roots/resolve（`openapi.yaml:151-176`） | 已有 `file-resolve`（`ws-file-transfer.ts:229-269`），同样只认会话根相对路径 | **保持 REST**；或随 R20 一起扩帧 | 同 R20；`file-resolve` 只 stat 不传字节，语义倒是够用 | P1 |
| R22 | 回收站列表/恢复 | 无调用点 | GET /trash（`openapi.yaml:287-301`）、POST /trash/{id}/restore（`:302-313`） | 工作树 `trash-list`/`trash-restore`（`ws-files.ts:292-345`） | 暂不迁（无入口）；做「删除恢复」时直接可用 | 未提交、协议文档未同步 | P2 |
| R23 | 附件字节读取 | `bridge/gateway_api.dart:296 fetchAttachment`；UI `ui/chat_image.dart:196` | GET /attachments/{id}?sessionId=（`openapi.yaml:348-381`） | 无（`attachment` 帧是**上传**，`ws-basic.ts:128`） | **保持 REST** | 二进制 + 内核要确认会话事件引用（`gateway_api.dart:293-295`）；`API.md:72` 永久例外 | P2 |
| R24 | image-handoff 字节 | `bridge/gateway_api.dart:342 fetchImageHandoff`；UI `ui/chat_image.dart:200` | GET /image-handoff?name=&sessionId=（`openapi.yaml:314-344`） | 无 | **保持 REST** | 二进制 + 一次性命名的交接产物；`API.md:68` 永久例外 | P2 |
| R25 | 附件分块上传 | 无调用点（客户端只发 base64 内联图） | POST uploads / PUT chunks/{index} / POST complete / GET,DELETE uploadId（`openapi.yaml:1509,1567,1606,1645`；`BFF-REST-CONTRACT.md:47-87`） | 已有 `file-upload-open/chunk/finish/cancel/status`（`ws-protocol.ts:760-805`） | 现有内联路径不动；**将来新增上传一律走 WS** | 帧上限 1 MiB（`ws-protocol.ts:91`）→ 客户端须按 256 KiB 分片（`ws-protocol.ts:116-121`）；`receiptId` 只能用于 message 的 `file` 部件（`asyncapi.yaml:1141`） | P2 |
| R26 | 单条附件上传（base64） | 无调用点 | POST /chat/sessions/{id}/attachments（`openapi.yaml:1149-1200`） | 已有 `attachment`（`ws-basic.ts:128`） | 新代码用帧，不要新增 REST 调用 | 单帧 1 MiB 上限；大图仍走 R27 | P2 |
| R27 | 大消息（内联图/长文） | `bridge/gateway_rest.dart:129 gatewaySendMessage`；UI `ui/chat_state.dart:689` | POST /chat/sessions/{id}/messages（`openapi.yaml:1057-1110`） | 已有 `message`，但默认帧上限 1 MiB（`ws-protocol.ts:91`） | **保持 REST** | 2.5–9 MB 内联图超帧限；REST body 上限 12 MB（`gateway_rest.dart:112`）；非图大文件可改「分块上传 + `file` 部件」；内核是否接受用 receipt 引用图片**未核实** | P1 |
| R28 | 订阅与推送 | `bridge/gateway.dart:826 subscribe`（`subscriptionFrames` :51-64）；`ui/chat_state.dart:719` | 无 | 已有 `subscribe`/`event`（`ws-handler.ts:880`；`ws-pushes.ts:75`：80 ms 去抖、整份快照载荷、`queue-item-updated`/`goal-updated`） | 已迁完 | 空 sessionId 集合 = 全部已授权会话（推送面靠逐会话授权过滤，`ws-pushes.ts` 头注释） | P2 |
| R29 | 定时任务 | `bridge/gateway_schedule.dart:227,241,254,265,273,284,302,317` | /chat/schedules 四条（`openapi.yaml:1673+`），未调用 | 已有 `schedule-*`（含 create/edit/view/run/delete-inactive；能力位 `capabilities.ts:122`） | 已迁完，无 REST | 帧内 scope 已补 `chat.read`/`chat.write`（桥提交 `87ac903`） | P2 |
| R30 | 后台任务 | `bridge/jobs.dart:333,378,392` | /chat/sessions/{id}/jobs 三条（`openapi.yaml:924,950,983`），未调用 | 已有 `job-list`/`job-output`/`job-kill`（`ws-protocol.ts:608-622`） | 已迁完，无 REST | 推送无回放，`onState=ready` 时须整体 refresh（`jobs.dart:411`） | P2 |
| R31 | 地址探活 | `bridge/endpoint_select.dart:146` | GET /healthz（`openapi.yaml:12-30`） | 无（连接前探活，本来就没有会话） | **保持 REST** | `API.md:70` 永久例外；连 WS 也能探活，但多地址并发要先选地址 | P2 |
| R32 | 待回答问题 | `bridge/gateway_api.dart:312 fetchQuestions` | GET /chat/sessions/{id}/questions（`openapi.yaml:1244`，deprecated） | 已有 `questions`（`ws-hitl.ts:92`） | 已 WS 优先，REST 只在 `UNKNOWN_TYPE`/`NOT_IMPLEMENTED` 回落 | 老桥无帧时保留；`asyncapi.yaml:1132` 说 REST 要等客户端迁完才删 | P2 |
| R33 | 会话写操作族 | `bridge/gateway_api.dart:138,150,160,525,589,595,604,624,644,658`（rename/archive/fork/wait/commands/select-model/answer/cancel-approval） | openapi 的 deprecated 段（`:806-1498`） | 已有 `session-rename`/`session-archive`/`fork`/`session-wait`/`commands`/`command-execute`/`select-model`/`question-answer`/`approval-response` | 已迁完，REST 未调用 | 无 | P2 |
| R34 | 会话清单 | `bridge/gateway_api.dart:128 sessions` | GET /chat/sessions（`openapi.yaml:742`，deprecated） | 已有 `sessions`（`ws-basic.ts:81`） | 已迁完 | 帧只认 `archived===true`，没有「全部」 | P2 |
| R35 | 文件写/改名/删除 | 无调用点 | PUT /roots/{id}/content、PATCH,DELETE /roots/{id}/entries（`openapi.yaml:177-286`） | 工作树 `file-write`/`file-rename`/`file-delete`（`ws-files.ts:213-290`） | 暂不迁（客户端没有编辑/删除文件入口）；将来要做直接用帧 | 未提交；`file-write` 单帧 20 MiB（`DEFAULT_FILE_WRITE_MAX_BYTES`）、base64 入参 | P2 |

## 2. 桥侧补帧清单

### 2.1 已被并发改动补上（等评审/提交/发布，客户端别重复做）

| 能力 | 依据行号 | 客户端现状 |
|---|---|---|
| 子会话历史 | `ws-team.ts:106-124`（授权复用 `chat.subagentHistory`，scope `chat.read`，回帧含 `leadSessionId`/`subagentId` + 整份 `events/hasMore/projections/bytes/truncated/historyFormatVersion`） | `gateway_api.dart:459` 仍走 REST，可直接换 |
| 工作区改名 | `ws-sessions.ts:263-281`（`{workspaceId,name}` → `workspace-updated{workspace}`） | `gateway_rest.dart:46` 仍走 REST |
| 工作区删除 | `ws-sessions.ts:283-298`（`{workspaceId}` → `workspace-deleted{workspaceId}`） | 无调用点 |
| 文件写/改名/删除 | `ws-files.ts:213-290`（`files.write`；`file-write` 支持 `expectedSha256` 前置校验、`createParents`） | 无调用点 |
| 回收站 | `ws-files.ts:292-345`（`trash-list` 分页、`trash-restore`） | 无调用点 |

**但下面三件事没跟着做，落地前不要当「帧已可用」对外说**：

1. `docs/api/asyncapi.yaml` 里没有这 8 个帧（`grep -c "subagent-history\|workspace-update\|trash-list\|file-write"` = 0），
   协议文档与实现脱节；AGENTS 类纪律要求帧进协议文件。
2. 没有**帧级**能力位。这几族能力位（`capabilities.ts:59-60,75,81-82`）早就存在，但注释依据写的是 REST 路径，只支持 REST 的桥同样会宣告它们；客户端仍只能「先发帧、撞 `UNKNOWN_TYPE` 再回落」（`ws-handler.ts:951`），在只有 REST 的桥上多一次往返 + 一条 `DshLog.w`。
3. 没有跑测试。新增 `tests/ws-file-frames.spec.ts` 只覆盖 file-write/rename/delete/trash（`grep` 无 `file-list`），
   `file-list` 的相对路径问题仍在（§2.2 第 1 条）。

### 2.2 仍然缺（客户端有活跃调用，是真正剩下的活）

1. **`file-list` 支持 `rootId` + 根内相对路径**（修实现，不是新帧）
   `ws-files.ts:123` 注释说「相对或绝对均可」，实现 `:137-149` 对非空 `path` 一律 `resolvePath()` + `matchAuthorizedRootResolved()`，
   即按宿主绝对路径解析；`rootId` 只在 `path===''` 时生效（`:151-155`）。相对 path 会被拼到桥进程 cwd 上再判是否落在任一授权根内（**未核实**运行期 cwd）：cwd 恰在某根内就会列到别处，否则 403/404。
   文件头 `:19-25` 又声称「只接受授权根内相对路径」，与新补的 `file-write`/`directory-create` 语义一致 —— **`file-list` 是唯一不一致的那个**。
   客户端：`gateway_api.dart:255 listDirectory`（已被 `ui/session_location_sheet.dart:283` 使用，**可能已经半坏**）、`gateway_rest.dart:265`（`ui/composer_panels.dart:188` 的 @ 补全仍走它）。

2. **`workspace-create` 接受 `rootId` + 相对路径**
   `ws-sessions.ts:221-230` 只接受绝对路径；REST 的 body 正是 `{rootId,path}`（`openapi.yaml:401-424`）。
   现状靠客户端从 `session.cwdAbsolute - session.cwd` 反推根（`mobile_frames.dart:164-190`，桥在 `chat/sessions.ts:109-121` 下发 `cwdAbsolute`），
   只在「该根下已有会话」时成立；新设备首启（`mobile_workspace.dart` 第一次建会话）仍回落 REST。
   补法：载荷允许 `{rootId, path}`，有 `rootId` 时按根内相对路径解析（与 `directory-create`、新 `file-write` 一致）。

3. **`file-download-open` / `file-resolve` 支持 `rootId` + path（或绝对路径）**
   `ws-file-transfer.ts:229-269`（file-resolve）、`:295-317`（resolveSessionTarget）都强制 `sessionId` 并从会话取根；
   客户端的产物/交付卡场景手里是绝对路径（`gateway_rest.dart:158`），且路径可能属于**另一个**授权根，无法先知道 sessionId。
   客户端：`ui/file_open.dart:50,52,88,90`、`ui/chat_artifact_card.dart:259,260`、`ui/md_viewer.dart:53,57`。
   补完才可能删 `GET /roots/resolve` 与 `GET /roots/{rootId}/content` 两条 REST。

### 2.3 不建议补（保持 REST）

- `attachment-read`（`GET /attachments/{id}`）与 `image-handoff`：二进制 + 1 MiB 帧 + 会话引用校验，`API.md:68,72` 已列永久例外。
- `settings/providers` 写、`settings/namespaces` 读/写：`API.md:75` 永久例外；写入要 `settings.write`（设备默认没有，`settings_page.dart:4-8`）；
  内核 `settings` 命名空间被 `src/host/bridge/kernel-allowlist.ts` 的 `KERNEL_DENIED_NAMESPACES` 钉死，`kernel-call` 也绕不过。
- `GET /roots`（根清单）：帧里没有「有哪些授权根」这个概念，且根绝对路径刻意不下发（`API.md:71`）。
- `GET /healthz`：连接前探活，`API.md:70`。

### 2.4 协议层缺口（比补帧更要紧）

**帧可用性没有独立信号。** `hello.capabilities` 只有按 OpenAPI 依据声明的能力位（`capabilities.ts:22-35`），
客户端无法区分「这台桥有 `workspaces` 帧」与「只有 REST」。建议二选一：
给帧加独立位（如 `ws-workspace-create-v1`，并在 `capabilities.ts` 里注明依据是 AsyncAPI 帧），或在 `hello` 里单列 `frames` 数组。
在补之前，客户端不要拿 REST 位当帧位用（现在工作树 `gateway_api.dart:683,771` 就是这种写法）。

## 3. 客户端可直接替换清单

### 3.1 今天就能删（帧在 HEAD 里就有）

1. **R3 `agent-presets`**：`gateway_rest.dart:348` → `gateway_api.dart:682`（工作树已 WS 优先）。
   帧 `ws-presets.ts:45`，应答 `data.presets`；REST 是 `items`。调用点 `ui/work_view_sheet.dart:73`、`ui/chat_setup_state.dart:90`。
2. **R4 `select-agent-preset`**：`gateway_rest.dart:424` → `gateway_api.dart:710`（工作树已 WS 优先）。
   帧 `ws-presets.ts:67`（`session-agent-preset`）/`:85`（`select-agent-preset`）。两处差异：载荷键 `agentPresetId`；失败从 HTTP 409 变 error 帧 code。
   调用点 `ui/chat_setup.dart:79`、`ui/work_view_sheet.dart:97`；错误文案在 `work_view_sheet.dart:107`。
3. **R32 `questions`**：`gateway_api.dart:312` 已经是 WS 优先、REST 仅在 `UNKNOWN_TYPE`/`NOT_IMPLEMENTED` 回落；
   等最低支持桥版本抬到含 `questions` 帧的版本后即可删兜底（依据 `asyncapi.yaml:1132`：REST 与帧同一实现，客户端迁完才删）。

### 3.2 桥把工作树那批帧发布后就能换

4. **R2 `subagentHistory`**：`gateway_api.dart:459` → 帧 `subagent-history`。参数一对一（`leadSessionId`/`subagentId`/`beforeSeq`/`maxMessages`）；
   应答比 REST 多 `projections/bytes/truncated/historyFormatVersion`，现有 `HistoryPage.fromEvents` 只传 `events/hasMore` 也能无损忽略。
5. **R7 工作区改名**：`gateway_rest.dart:46` → `workspace-update`，注意 body 键 `title` → 帧键 `name`。
6. **R22 回收站**：无 UI，等要做时用 `trash-list`/`trash-restore`。
7. **R35 文件写/改名/删除**：无调用点，将来直接用帧，别加 REST。

### 3.3 先修桥再用

8. **R19 目录列举**：`gateway_rest.dart:265` → `gateway_api.dart:255 listDirectory`。前置是 §2.2 第 1 条。
   注意 `ui/session_location_sheet.dart:283` 已在用这个帧，**先核实它是不是已经踩 403**，再决定是否扩大使用。
9. **R20/R21 文件字节与路径解析**：等 `file-download-*`/`file-resolve` 支持 `rootId`（§2.2 第 3 条）。

### 3.4 已经全是 WS、无需动作（防止再有人加 REST 分支）

- 会话读：`sessions`/`history`（`gateway_api.dart:128,416`）；会话写：`session-rename`/`session-archive`/`fork`/`session-wait`/`session-cancel`/`session-pin`（`:138,150,160,525`）；
  `commands`/`command-execute`（`:589,595`）；`models`/`select-model`/`default-model`（`:573,604,582`）；`permission-options`/`permission`（`:551,557`）；
  `questions`/`question-answer`/`question-cancel`/`approval-response`（`:312,624,644,658`）；`session-stats`/`context-usage`（`:349,353`）；
  `goal*`/`session-queues`/`queue-update`（`:359,367,376,392,401,410,171,179`）；`workspaces`（`:51`）；`file-list`/`directory-create`（`:255,271`）。
- schedule 全族（`gateway_schedule.dart:227-317`）、jobs 全族（`jobs.dart:333-395`）、插件管理（`plugin_center.dart:264-310` 走 `kernel-call`）。
- 推送（`gateway.dart:826`、`subscriptionFrames` :51-64）。

## 4. 保持 REST（不建议迁）

| REST | 理由 | 依据 |
|---|---|---|
| R18 GET /roots | 根清单在帧里没有对应概念；根绝对路径刻意不下发 | `API.md:71`；`ws-files.ts` 只列内容 |
| R20 GET /roots/{id}/content、R21 /roots/resolve | 帧的授权模型是会话根，客户端手里是绝对路径/产物路径，且可能跨根 | `ws-file-transfer.ts:295-317` |
| R23 GET /attachments/{id}、R24 /image-handoff | 二进制 + 会话引用校验 + 一次性命名；收益低于成本 | `API.md:68,72` |
| R27 POST …/messages（大消息） | 内联图 2.5–9 MB 超 1 MiB 帧限；REST body 12 MB | `ws-protocol.ts:91`；`gateway_rest.dart:112` |
| R13/R14/R15 `/settings/*` | 无客户端需求；写入需 `settings.write`（设备默认没有） | `API.md:75`；`settings_page.dart:4-8` |
| R22 `/trash*` | 客户端无入口（帧已补，将来用帧） | `API.md:71` |
| R31 GET /healthz | 连接前的多地址探活，本来没有会话可订阅 | `API.md:70`；`endpoint_select.dart:129-160` |

## 5. 未核实 / 风险

- **未核实**：`file-list` 传根内相对 path 时运行期到底是 403 还是「碰巧列到桥进程 cwd 所在的根」——取决于 `dsh web` 的启动 cwd；
  代码（`ws-files.ts:137-149`）与注释（`:123`）矛盾，测试未覆盖。这会让 `session_location_sheet.dart:283` 进子目录时行为不可预测。
- **未核实**：工作树新补的 8 个帧我没跑测试（`tests/ws-file-frames.spec.ts` 未执行），也未见协议文档登记；
  按代码读，`workspace-update` 用 `name` 而不是 REST 的 `title`，`subagent-history` 复用 `chat.subagentHistory` 授权，语义看起来对齐。
- **未核实**：内核是否接受用 `file` 部件（receiptId）引用**图片**；`asyncapi.yaml:1141` 只说「大附件先上传拿回执再引用」，没区分图片。
  若接受，R27 的大图 REST 有可能改成「分块上传 + message 帧」，但需要桥/内核两侧确认。
- **未核实**：`rootAbsolutePathOf`（`mobile_frames.dart:164-190`）在 Windows 盘符根、符号链接根、`cwd` 为绝对路径时的推导；
  推错会得到 403 再回落 REST，不会写坏数据，但会多一次往返。
- **风险**：`ws-presets.ts` 的 `agent-presets`/`select-agent-preset` **没有显式 scope 检查**，而 REST 对应面要 `chat.read`。
  迁移完成后等于降低「预设清单」的读取门槛；建议桥侧补 `requireScope('chat.read')` 并写进协议文档。
- **风险**：工作树里客户端用 REST 能力位 gate 帧（`gateway_api.dart:683,771`）。桥若只实现 REST 不实现帧，客户端会稳定先失败一次；
  且 `workspace-list-v1` 的语义是「GET/POST /chat/workspaces」（`capabilities.ts:82` 附近），与 `workspace-create` 帧不是一回事。
- **行号漂移**：两个仓都在并发改动（§0.3），本文件的 `:行号` 只保证抓取时刻；函数名、帧名、REST 路径是稳定锚点。

## 6. 一句话结论

14 处 REST 按可迁移性分四档：

- **3 处今天就能换**：agent-presets（`gateway_api.dart:682`）、select-agent-preset（`:710`）、questions 的 REST 兜底（`:312`）——帧在 HEAD 里就有。
- **2 处等桥发布工作树那批帧**：子会话历史（`:459`）、工作区改名（`gateway_rest.dart:46`）。
- **3 处要先修桥**：目录列举（`gateway_rest.dart:265` / `gateway_api.dart:255`，差 `file-list` 的 `rootId`+相对路径）、
  文件路径解析（`gateway_rest.dart:158`）与文件字节（`:335`，差 `file-resolve`/`file-download-*` 支持 `rootId`）。
- **1 处部分可换 + 5 处保持 REST**：工作区创建（`gateway_rest.dart:23`）靠 `cwdAbsolute` 反推根，新设备首个会话仍要 REST；
  roots 列表（`:219`）、附件字节（`gateway_api.dart:296`）、image-handoff（`:342`）、大消息（`gateway_rest.dart:129`）、healthz（`endpoint_select.dart:146`）
  按 `docs/project/API.md:64-75` 的永久例外保留。
- 回收站与文件写/改名/删除：帧已就绪（`ws-files.ts:213-345`），客户端**没有调用点**，将来直接用帧。

比补帧更该先解决的是**帧可用性没有独立能力位**：现在客户端只能靠「发一帧撞 `UNKNOWN_TYPE` 再回落」探测，
而 `workspace-manage-v1`/`subagent-history-v1`/`file-write-v1` 这些位的注释依据都是 REST 路径（`capabilities.ts:59-60,75,82`）。
