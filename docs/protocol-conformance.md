# 协议一致性报告（对照 dsh-remote-bridge 2.12.1 / issue #26）

> 日期：2026-11-20　范围：`app/`（Flutter）+ `harmony/`（ArkTS）
> 基准：`dsh-remote-bridge` **2.12.1** 已发版契约 + main 上 issue #26 的阶段 5/6/7/8 改动
> 事实来源：`docs/api/openapi.yaml`(2551 行)、`docs/api/asyncapi.yaml`(1159)、
> `docs/project/API.md`(1078)、`src/host/ws-protocol.ts`、`src/host/capabilities.ts`、
> `src/host/ws-handler.ts`、`src/host/ws-goals.ts`

## 1. 结论摘要

| 项 | 状态 |
|---|---|
| 握手（子协议 / `X-DSH-Device-*` / hello.protocol=3 / requestId 在 `data` 内） | ✅ 原本正确，本轮补了能力位与端口存档 |
| 帧词表（服务端 84 / 客户端 83） | ✅ 客户端**发出的**帧全部在词表内；**未消费**的帧见 §4（有理由，不是遗漏） |
| 能力位（`hello.capabilities`） | ✅ 本轮新增解析 + `hasCapability()`（此前两端零处理） |
| WS close code 语义（4001 / 1009 / 1000） | ✅ 本轮新增（此前一律当普通掉线） |
| `history` 字节预算（`truncated` / `bytes` / `historyFormatVersion`） | ✅ 本轮新增（此前不读，截断被当成「历史就这么长」） |
| `session-stats` / `context-usage` 帧 | ✅ 本轮接入（统计面板服务端半边） |
| `image-handoff` 的 `sessionId` query | ✅ 本轮修复（安卓侧此前漏传 → 一直 400） |
| `subscribe` / `unsubscribe` 语义 | ✅ 核对为「累积白名单 / 清空过滤」，本仓做法正确，未改 |
| 能力位缺位时的降级 | ✅ 老桥回 `UNKNOWN_TYPE` 时静默降级，不报错弹窗 |
| kernel-call / 插件 / 排程 / 语音 / 文件上传下载 | ⏸ 未消费，见 §4 |

## 2. 逐条核对（客户端行为 ↔ 桥侧契约）

### 2.1 握手与连接

| 契约 | 本仓行为 |
|---|---|
| 子协议清单 `dsh-mobile-v1, dsh-auth.<token>`（或 `dsh-pair.<code>`），服务端挑第一个认识的 | `gateway.dart` 固定首位 `dsh-mobile-v1`，位置无关语义成立 |
| `X-DSH-Device-ID` 必填、`X-DSH-Device-Name` 为 Base64(UTF-8) | 两端均已带，name 走 base64 |
| `hello` 每连接推一次、能力位每次现算 | 本轮在 `_onFrame`/`onFrame` 里解析并存档，不做「连上时缓存成常量」 |
| close `4001` = 鉴权失败/设备吊销，**不可重连** | 4001 → `AUTH_FAILED` + 提示「设备已被吊销，请重新配对」，且**不排退避**（此前会无限重连） |
| close `1009` = 单帧超 1 MiB | 提示「请求内容超过 1 MiB，连接已重置」，仍按退避重连 |
| 连接上限 32 / 超限 HTTP 429 + Retry-After | 429 仍落到「连接失败」，退避重连兜住（未做专项提示，记 §5 遗留） |
| 服务端 30s ping、缺 2 个 pong 断 | 客户端 25s 主动 ping 保持不变 |

### 2.2 帧面

- 本仓发出的帧（22 条）：`ping, subscribe, message, workspaces, sessions, history,
  attachment, file-list, directory-create, models, commands, command-execute,
  select-model, permission-options, permission, question-answer, question-cancel,
  approval-response, session-create, session-cancel, session-wait`（+ 本轮
  `session-stats`、`context-usage`）。
- 全部命中 `ClientFrameType`（`ws-protocol.ts`）；**没有**发送阶段 8 已删除的
  `search / defaults / set-default / queue-update / directories`（发送即 `UNKNOWN_TYPE`）。
- `unsubscribe` 的语义核实：`handleUnsubscribe`（`ws-handler.ts:869`）**清空整张过滤表**、
  回到「接收所有已授权会话」，**不接收 `sessionId`**、不退订单个会话。
  因此「打开会话就 `subscribe`、从不上报 `unsubscribe`」是**正确**做法
  （`subscribe` 是累积白名单，`handleSubscribe` `ws-handler.ts:846`）；本仓未改。
- 应答关联：三个来源都沿用「`data.requestId` 优先」——`error` 帧、`sent` 帧、
  其余普通应答（`withRequestIdEcho`）。`subscribed` 在排除表里，故 `subscribe` 不 await。
- `select-model` / `session-agent-preset` 的应答 kind 是共享的 `sent`，必须按
  `data.type` 判别 —— 两端早已如此。

### 2.3 历史与流式

| 契约 | 本仓行为 |
|---|---|
| `history` 带 `beforeSeq` / `maxMessages` / `maxBytes`（默认 4 MiB） | 用 `beforeSeq` + `maxMessages=200`；**不传 `maxBytes`**（留给服务端默认，见 §5） |
| 真裁剪时响应体追加 `truncated:true` + `bytes`；未裁剪时**字段缺席**（不是 false/0） | 本轮解析三者并在列表头显示「会话过长，更早的部分未显示」；缺席即 `false`/`null` |
| 单条事件超长标 `bridgeTruncated` | 未处理（渲染层无需求，见 §5） |
| `historyFormatVersion` 恒在（当前 1） | 本轮存档（只声明不校验，符合桥侧「本轮只声明」） |
| `chat.message.delta` 不再带 `seq`（位置在 `index`） | 已按 `index`/`turn`/`step` 处理，不依赖 delta 的 seq |
| delta 的未知 `kind` 必须忽略、不得当文本渲染 | 两端 DAWT 分支只有 text/reasoning/tool-call/tool-call-end，其余丢弃 |
| `hasReplyContent` 决定「可清流/收起」 | 两端已按该字段判断（`models.dart:240-266` / `Models.ts:216-227`） |
| `chat.turn.end.reason.kind` = ok/error/max-tokens/aborted，未知忽略 | 已实现，`max-tokens` 不当失败 |
| `chat.tool.result.error.code` 未知值降级失败；exit code 从结果文本尾解析 | `StreamTools.ts` / `streaming_tools.dart` 已实现 |

### 2.4 REST

| 契约 | 本仓行为 |
|---|---|
| `GET /api/v1/image-handoff?name=&sessionId=` **两参必填**，缺一 400 `BODY_INVALID` | **本轮修复**：安卓 `fetchImageHandoff` 此前只传 `name`（鸿蒙早已带）；路径拼装抽成纯函数 `imageHandoffPath()` 并加回归用例 |
| `GET /api/v1/attachments/{id}?sessionId=` | 已带 `sessionId` |
| 分块上传六端点（chunkSize=1 MiB、票据 1h、缺块 409） | 未接入（当前附件走单帧 `attachment`，见 §5） |
| `/chat/schedules`、`/chat/speech/*` | 未接入（本仓无排程/语音入口，见 §4） |
| 子会话 `GET .../subagents/{id}/messages`（2 MiB / 单条 512 KiB 预算、`hasMore`） | 已用窄口 REST，不调 `requireSession(subagentId)` |

## 3. 本轮改动清单

**Flutter（12 文件，2 新建）**

| 文件 | 改动 |
|---|---|
| `app/lib/bridge/gateway_pending.dart`（新） | 挂起表 `PendingRegistry`（`add/take/failOfType/failAll` + `catchError` 兜底） |
| `app/lib/bridge/gateway_liveness.dart`（新） | 活性判据 `Liveness`，阈值 `kLivenessSilentLimit`=45s |
| `app/lib/bridge/gateway.dart` | 能力位 + `port` 存档、`hasCapability()`；`_onDown(code,reason)` 读 close code；重连接力（不再把 CONNECT_FAIL 当终态）；心跳/发送前判半死 |
| `app/lib/bridge/gateway_events.dart` | `LinkClosedEvent{code,reason}`（`revoked`/`frameTooLarge`） |
| `app/lib/bridge/gateway_api.dart` | `image-handoff` 补 `sessionId`、`sessionStats()`/`contextUsage()`、`history()` 读截断三字段 |
| `app/lib/bridge/history_page.dart` | `truncated`/`bytes`/`historyFormatVersion` |
| `app/lib/ui/chat_state.dart` | `historyTruncated`、`serverStats`、`loadServerStats()`、鉴权失败文案 |
| `app/lib/ui/chat_state_events.dart` | 消费 `LinkClosedEvent` |
| `app/lib/ui/chat_history_actions.dart` | **过期应答丢弃**（companion #16）、**刷新保留已翻页内容**（#37）、rawEvents 同口径合并 |
| `app/lib/ui/chat_message_list.dart` | 截断提示行 |
| `app/lib/ui/chat_image.dart` | 取图带 `sessionId` |
| `app/lib/ui/stats_sheet.dart` | 服务端统计半边（`serverStatGroups()` 拍平标量，不臆造语义） |

**Harmony（13 文件，3 新建）**：`LinkLiveness.ts`（新）、`ChatStats.ts`（新）+
`Transport/WsTransport/GatewayEvents/GatewayClient/GatewayRequests/GatewayApi/GatewayRest/
HistoryPage/ChatStore/ChatHistory/ChatEvents/MessageList.ets/ProjectionSheets.ets` 同口径改动，
`ChatView.ets` 传 `version` 触达 Sheet 重绘。

**配套文档**：`docs/STRUCTURE.md`（新文件登记 + 协议章节 3 条新坑 + 版本基线）。

## 4. 协议已提供但本仓**刻意未消费**（不是遗漏）

| 面 | 帧/端点 | 不做的理由 |
|---|---|---|
| 内核调用面 | `kernel-call`、`kernel-endpoints` | 需先协商 `dshrb-v1` 子协议；App 侧无内核直调需求（宪法：只消费协议，不越权） |
| 插件/排程/语音 | `plugin-*`、`schedule-*`、`speech-*` 及 REST 对等面 | 手机端暂时没有对应 UI；接了就是「永不渲染的入口」 |
| 目标 / 后台任务 / 审批列表 | `goal*`、`jobs`、`GET .../approvals` | 与「手机端只做对话」定位不符；审批走实时 `approval.requested` 已够 |
| 文件上传/下载分块 | `file-upload-*`、`file-download-*`、`file-resolve` | 当前交付物走 `deliverables.presented` + REST 读字节；分块是 >4 MiB 大文件才需要 |
| 会话管理增强 | `session-archive`、`session-rename`、`fork`、`workspace-create` | 安卓侧走 REST 同名端点（`PATCH /chat/sessions/{id}` 等）；WS 帧未接 |
| 模型/命令选项 | `command-options`、`command-select` | 权限与模型分别有专用帧，够用 |
| 通用默认模型 | `default-model`、`save-default-model` | App 不做全局默认模型设置 |
| 主机会话统计 | `session-stats` 之外的 `context-usage` | 本轮都接了（面板里展示） |

> 判据：**接入一个帧的成本是「入口 + 空态 + 降级」三件套**，只看协议有就接，
> 会做出永不渲染的入口（本仓 STRUCTURE.md「踩过的协议坑」第 7 条同款教训）。

## 5. 遗留与观察

1. **真机联调**：2026-11-20 已在 vivo V2080A（Android 11，1080×2400）跑通
   会话抽屉 → 会话历史 → 工具行流式 → 服务端统计，结论见 §8；仍**未**验的只剩
   入站图片渲染（见 §8.4）与设备吊销文案（需另配 3198 测试桥，未动用户在用桥）。
2. **429 连接上限**没有专项提示，靠退避兜住（用户看到的是「重连中」）。
3. **不传 `maxBytes`**：手机端一页 200 条远小于 4 MiB 默认值，显式传反而可能让
   老桥（无 `history-byte-budget-v1`）报 `UNKNOWN_TYPE` 风险，故保持不传。
4. **`bridgeTruncated`（单条事件超长标记）**未渲染：当前 UI 只对整页截断做提示。
5. **companion 坑位审计**的 6 条命中已全部修完（见 §7）；报告里另记了 4 条
   「补充命中」（不在 51 锚点内），属观察项，未改。

## 6. 验证记录

```bash
# 文档契约（lib/ + harmony ets/ 逐文件登记、死链、旧仓名残留）
bash scripts/ci/docs-check.sh                      # ✅ 通过

# Flutter
flutter analyze                                    # ✅ No issues found!
flutter test                                       # ✅ 273 passed
# 新增用例：gateway_pending(5) / gateway_api_paths(2) / gateway_liveness(1) /
#          history_merge(4) / md_view 表格规整(4) / dlog 纯判据(2)

# Harmony（node:test + tsx，CI 无鸿蒙 SDK 也能跑）
cd harmony/test && npm test                        # ✅ 362 passed
# 新增用例：gateway-client(+5 能力位/close code) / history-page(+1 截断) /
#          chat-stats(2) / link-liveness(3) / chat-history-merge(3)
```

## 7. 修复的 companion 坑位（对应 `docs/companion-pitfall-audit.md`）

| 编号 | 坑 | 修法 | 回归用例 |
|---|---|---|---|
| #16 | 过期响应覆盖新上下文 | `reloadChatHistory` / `reloadHistoryIn` 在 await 回来先比 `sessionId`，变了整块丢弃 | `history_merge_test.dart`、`chat-history-merge.test.ts` |
| #37 | 刷新抹掉「加载更早」的成果 | `mergeRefreshedHistory` / `mergeRefreshedRawEvents`：保留新页首条 seq 之前的旧页，`hasMore` 延续旧结论 | 同上（4 + 3 例） |
| #46 | WS 半死：状态还写「已连接」，帧写进死连接等满超时 | `Liveness` / `LinkLiveness` 只做**诊断**（静默仅记日志）；判死权交回服务端心跳——真机实测「客户端抢先判死」会在活连接上误杀（见 §8.2） | `gateway_liveness_test.dart`、`link-liveness.test.ts`（3 例，断言「静默后照发帧、不重连」） |
| #28 | GFM 表格贴上一行（引擎只在空行后认表格） | `md_view.dart` 新增 `normalizeTables()` 补空行（围栏代码块跳过） | `md_view_test.dart`（4 例） |
| #22 | 诊断日志噪音（每帧同步写、无上限） | ①删掉三处**逐帧**打点（`gw <- kind=event` / `gw event chat.message.delta` / `ui delta …`）；②`dlog.dart` 加 2s 同句抑制 + 2 MiB 尾部保留且**裁剪阈值留 25% 余量**（否则每写一行都要整份读+整份写，见 §8.2） | `dlog_test.dart`（2 例） |
| #48 | 发版脚本把「列表首项」当最新 | `scripts/release.sh` 改在整页（per_page=100）里找本 tag | — |
| 协议 | close code / 能力位 / 历史截断 / image-handoff 缺 sessionId | 见 §2 | 见 §6 |

## 8. 真机实测（2026-11-20，vivo V2080A / Android 11 / 1080×2400）

### 8.1 通过项（截图逐条留证于会话记录）

| 项 | 结果 |
|---|---|
| 装机与配对 | 与 bridge 2.12.1（3090）自动重连成功，`manage/status` 里设备 `ca4c43a7` 心跳更新 |
| 会话抽屉 | 一次点击展开：今天/昨天分组、`workspace` 与 `手机会话` 分组标题、设置行（`Mobile device 192.168.1.126:3090` 绿点）全部渲染 |
| 会话历史 | 打开本会话即显示「加载更早消息」入口、折叠过程行、正文、`思考` 块、工具行，均为真数据 |
| 流式 | 手机端实时出现 `正在运行命令 · …`、`思考` 增量文本，轮末显示「已完成，用时 51分15秒」——`chat.message.delta`（text/reasoning/tool-call）、`chat.tool.call/result`、`chat.turn.end.reason.kind` 三路都通 |
| 服务端统计 | `⋮ → 会话统计` 出现**服务端统计**组：`turns 3 / steps 508 / llmMs 1965243 / toolMs 4046546 / ttftMs 750923 / ttftSteps 509 / decodeMs 1214320 / decodeTokens 263777`，即 `session-stats` 帧与 `serverStatGroups()` 端到端可用 |
| 无截断不误报 | 该会话 `/messages` 响应无 `truncated` 键，手机上**没有**出现「会话过长」提示行 ✅（有截断时才会有） |
| 长稳 | 修完日志问题后连续交互 10 分钟（开抽屉/开会话/开菜单/开统计/滑动/展开工具行），无 ANR、无掉线 |

### 8.2 真机暴露并已修的两个缺陷

1. **流式期间逐帧同步写日志 → 主线程卡死 → ANR**。现象：启动约 40–50 s、或流式
   期间任意一次点击，`Input dispatching timed out`，`dumpsys activity exit-info` 记
   `reason=6 (ANR)`；ANR 现场里进程 CPU 97%（`82% user + 14% kernel`），主线程栈停在
   `libflutter.so` + `nativePollOnce`。两个叠加原因：
   - 每来一帧就 `DshLog.w` 写盘一次（`gateway.dart` 的 `gw <- kind=…`、
     `gw event …`、`chat_state_events.dart` 的 `ui delta …`）——流式期每帧三条同步写；
   - 我上一轮给 `dlog.dart` 加的「超 2 MiB 只留尾部」按行触发：剪完仍刚好越线，
     于是**每写一行都要 readAsStringSync 2 MiB + 整份重写**，成本 O(文件大小)×每行。
   修法：删掉三处逐帧打点（高频事件不记流水）；裁剪阈值改 `2 MiB × 1.25`，摊到
   每 ~512 KiB 才重写一次。修后同样的交互路径复测 10 分钟无 ANR。
   > 注：旧构建（11-17 那份 APK，不含本轮任何改动）在同一台机上也 ANR，说明
   > 「逐帧同步写盘」是**既有**设计问题，本轮只是让它从「偶发卡」变成「必卡」。
2. **客户端自己判「静默超时」把活连接打死**。上一轮 #46 修复引入 `Liveness`
   （45s 静默 → `_onDown`），真机上每 ~50 s 触发一次无谓重连（心跳 25 s ×2 正好跨过
   阈值），收尾路径把主线程拖住。桥本来就有服务端心跳（30 s 一次 ping、连缺 2 次
   pong 才 terminate），客户端再判一次纯属重复且危险。修法：静默只记日志，帧照发，
   Flutter/Harmony 两端同步改（Harmony 的 `refuseStaleLink()` → `notePeerSilence()`）。

### 8.3 真机测试的工具坑（供后来者省时间）

- vivo 对 `adb install` 有次数限流（`Too many pm install from shell`），`adb reboot`
  才清；安装对话框要**后台**跑 `adb install -r` 再点「继续安装」，前台跑会一直等。
- `uiautomator dump` 与设备端常驻代理（`com.wetest.uia2`，`app_process … -p 9008`）
  抢同一个 UiAutomation：被 dump 进程抢到后，代理只 dump 出系统窗口（app 窗口整块
  缺席），表现为「读界面树失败/只有状态栏」。`pkill -9 -f` 掉两者让代理重生即可。
- Flutter 语义树默认不给：`settings put secure accessibility_enabled 1` +
  `touch_exploration_enabled 1` 后重启 app 才有文本树；**测完要复原成 0**。
- 最稳的通道是「截图 + `input tap` 坐标」：不走无障碍、不会被 ANR 连带打死。

### 8.4 仍未验

- **入站图片渲染**（`ChatImage` + `/api/v1/image-handoff?name=&sessionId=`）：
  手机会话里没有含 image 内容块的会话可点，`imageHandoffPath()` 有单测覆盖两参，
  但「像素真的出来」还需一张真图会话。
- **设备吊销文案**（close 4001 → 「设备已被吊销，请重新配对」）：要在 3198 测试桥上
  吊销设备，涉及重新配对，未在用户在用桥上做破坏性操作。
