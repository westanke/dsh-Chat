# dsh-Chat × dsh-companion 坑位迁移对照审计报告

> **审计对象**：`dsh-Chat`（双客户端：`app/` Flutter + `harmony/` ArkTS）
> **基线**：HEAD `d15df30 chore(release): bump 1.0.18+19 并回填发版数据` ＋ 工作树未提交改动（审计起点 52 条，收尾 53 条已跟踪改动 + 9 个未跟踪新文件；审计期间一直有并发写者在改 `app/lib/bridge/*` 与 `harmony/.../core/*`，见 §5.4 / §5.5）
> **对照源**：`dsh-companion/docs/project/PITFALLS.md` 全文 1598 行、其 `AGENTS.md` §7「坑位索引」
> **审计时间**：2026-11-19 23:43–23:55（+08:00）
> **方式**：只读代码 + 离屏探针（1 个临时 dart 探针写在 `app/build/`，跑完即删）；**未修改 `app/` 与 `harmony/` 任何源码**；未使用 `/tmp`
> **判定口径**：命中 / 已避免 / 不适用 / 待真机验证（四选一，逐条带 file:line 证据）

---

## 1. 摘要

### 1.1 被检对象与版本

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `dsh-Chat` / `main` |
| HEAD | `d15df30`（`1.0.18+19`） |
| 工作树 | 审计起点 52 条、收尾 53 条已跟踪改动（`git status --porcelain \| wc -l`），另有 9 个未跟踪新文件；均为并发作者的在途改动，本报告只新增 `docs/companion-pitfall-audit.md` 一个文件 |
| Flutter 客户端 | `app/lib/` 共 **73** 个 `.dart`（`bridge/` 21、`ui/` 48、`design/` 若干；审计起点为 72/20/47，因并发作者新增而增长）+ `app/android` 下 2 个 Kotlin 文件 |
| 鸿蒙客户端 | `harmony/entry/src/main/ets/core/` **53** 个纯逻辑 `.ts`（审计起点 52，同上）+ `components/` + `pages/` + `platform/Dlog.ets` |
| 上游协议 | `dsh-remote-bridge`（WS `dsh-mobile-v1`，`hello.protocol=3`，REST `/api/v1`） |

### 1.2 统计

| 判定 | 条数 | 锚点编号 |
|---|---|---|
| **命中** | **6** | 16、22、28、37、46、48 |
| **已避免** | **34** | 1–3、5、7–15、18、21、24、27、29、30、32、33、35、36、38–40、42–45、47、49–51 |
| **不适用** | **10** | 4、17、19、20、23、25、26、31、34、41 |
| **待真机验证** | **1** | 6 |
| **合计** | **51** | 与 `PITFALLS.md` 的 `### 锚点` 数量一致 |

锚点口径核对：`grep -c '^### ' docs/project/PITFALLS.md` = **51**；companion `AGENTS.md` §7 索引同为 **51** 条，两者集合逐条比对**完全一致、差集为空**（用 python 做过集合比对）。本报告矩阵的 51 行与原文顺序一一对应。

另有 **4 条「补充命中」**不在 companion 的 51 个锚点内，但属于同一类坑在 dsh-Chat 的等价形态，列在 §5.1（其中 1 条是 companion「命令卡被 reloadHistory 冲掉」的安卓侧等价物，只是该条被记在 dsh-Chat 自己的 AGENTS §11 而非 companion PITFALLS）。

### 1.3 命中 Top（按严重度排序）

1. **#16 过期响应覆盖新上下文（高）** —— `app/lib/ui/chat_history_actions.dart:24-48` 与 `harmony/entry/src/main/ets/core/ChatHistory.ts:23-58` 的 reload 都只取 `sessionId` 却不在 await 之后复核，切会话后旧响应会把上一个会话的整页历史写进新会话。
2. **#46 WS 半死（高）** —— `app/lib/bridge/gateway.dart:414-430` 心跳只发 ping、不记 pong/最后入站时间，`_sendRaw` 在死 socket 上仍返回 `true`，请求靠 30s 超时收场，期间既不重连也不回落 REST；鸿蒙 `GatewayClient.ts` 同款。
3. **#37 刷新历史抹掉「加载更早」（高）** —— `chat_history_actions.dart:32` / `ChatHistory.ts:37` 用最后一页整体替换 `messages`，已 `loadOlder` 加载的更早页在任意一次刷新后消失。
4. **#28 表格贴上一行（中）** —— `app/lib/ui/md_view.dart:19-45` 无表格规整；gpt_markdown 1.4.0 的块解析器不认 `|` 开头行（离屏探针实测 `tables=0`），紧贴上一行的表格在安卓端退化为竖线纯文本，而鸿蒙 `MdParser.ts:384-388` 正确。
5. **#22 诊断日志噪音（中）** —— `app/lib/bridge/dlog.dart:31-33` 每帧同步 `writeAsStringSync`，无重复抑制、无轮转、无大小上限；流式回复期间每帧一次磁盘写。
6. **#48 发布脚本把列表首项当最新（中）** —— `scripts/release.sh:250-252` 用 `releases?per_page=1` 取 `d[0]` 判存在；该接口 **升序**返回（实测首项恒 `v1.0.0`），当前 v1.0.18 永远判「不存在」。

---

## 2. 逐条矩阵（51 条，顺序与 PITFALLS.md 原文一致）

> 证据列的行号均取自 §1.1 所述工作树快照；`app/lib/...` 为仓内相对路径。

| # | 坑位名 | 判定 | 证据(file:line) | 一句话说明 |
|---|---|---|---|---|
| 1 | Kotlin 注释里写 image 通配符会吞掉后面整个文件 | 已避免 | `app/android/app/src/main/kotlin/com/dsh/dshchat/MainActivity.kt:75`、`:83`；`ImagePickHelper.kt` 全文 | `image/*` 只出现于 `//` 行注释与字符串字面量，Kotlin 侧块注释内无 `/*` 序列，不存在嵌套注释提前闭合吞文件 |
| 2 | README 双站漂移 | 已避免 | `scripts/release.sh:104-117`、`:140-148` | 单 README 由发版脚本回填版本/测试数/SHA 并自检「README 里的 SHA-256 与产物不符」；Gitee 与 AtomGit 共用同一份 |
| 3 | Compose 状态与 SharedPreferences | 已避免 | `app/lib/design/app_settings.dart:180`、`:218`；`app/lib/ui/settings_page.dart:70` | 设置项统一走可监听 store，页面用 `ListenableBuilder` 重建；没有「开关直接读 prefs 不触发重组」 |
| 4 | WebView 与原生双实现 | 不适用 | `grep -rni webview app/lib harmony/…/core` 零命中 | 双端都是原生渲染（Flutter widget / ArkUI），不存在 WebView 兜底资产 |
| 5 | 图片附件元数据与字节读取 | 已避免 | `app/lib/bridge/gateway_api.dart:109-114`、`:142`；`app/lib/ui/chat_image.dart:199-200`；`harmony/entry/src/main/ets/core/ImageFetcher.ts:26-29` | 附件与交接图都走完整引用且带 `sessionId`（两渠道都已带），发送上限 8 MiB；本仓无 24 MiB 文件上传，故「分块上传」部分不适用。残留小差异：失败态未分 401/403/404，图片高度写死 140 |
| 6 | 熄屏断流与亮屏接回 | 待真机验证 | `grep -rn "WidgetsBindingObserver\|didChangeAppLifecycleState\|AppLifecycle" app/lib` 零命中；`app/lib/bridge/gateway.dart:414-420` | 无生命周期监听、也无主动省电逻辑，靠 25s 心跳 + 掉线重连兜底；vivo 灭屏是否冻结 socket、亮屏能否自愈必须装机验（§4 V1） |
| 7 | ask_user_question 三态 | 已避免 | `app/lib/ui/question_card.dart:40-41`；`app/lib/ui/hitl_state.dart:33-42` | open/continued 都渲染且「提交」可点，REST `mergeQuestions` 按 callId upsert 合流；continued 无专属提示条（文案缺口，非功能缺陷） |
| 8 | 交付物事件与路径嗅探 | 已避免 | `app/lib/bridge/history_page.dart:196-220`、`:359-379`；`harmony/entry/src/main/ets/core/HistoryPage.ts:197`、`:221-227` | `deliverables/presented` 按轮尾缓冲冲刷成文件卡（不按事件序内联，避免卡在过程组与收尾之间）；不做 bash 路径嗅探（无该功能） |
| 9 | bridge 版本基线 | 已避免 | `app/lib/bridge/gateway.dart:174`（`protocol == 3` 判定）；`AGENTS.md` §1（bridge ≥ 2.10.0） | 单一基线（协议 v3）＋ 能力位随 hello 下发；没有逐特性版本表，因为口径是「用能力位探测、不硬比版本」 |
| 10 | 端口 3090 归属 | 已避免 | `grep -rn 3090 app/lib harmony/entry` 代码零命中（仅 docs 提及）；`app/lib/ui/connect_page.dart` 由用户输入 baseUrl | 端口不硬编码，配对时手输地址，故不存在与 DSHA 的 3090 撞车 |
| 11 | Gradle wrapper 挂起 | 已避免 | `app/android/gradle/wrapper/gradle-wrapper.properties`（`distributionUrl=…mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`） | wrapper 走腾讯镜像，不会挂在 services.gradle.org |
| 12 | 并发写者与未提交改动 | 已避免 | `scripts/release.sh:11`、`:122`；`scripts/push-all.sh` 全文 | 无 `git add -A`，发版只点名 `README.md` / `artifacts/` |
| 13 | GitHub 443 阻断与镜像从站 | 已避免 | `AGENTS.md` §10；`.github/workflows/mirror-sync.yml` | GitHub 只作镜像从站（每 3h `push --mirror`），日常推 Gitee 主站 + AtomGit 备站 |
| 14 | AtomGit 账号名与 API 版本 | 已避免 | `scripts/release.sh:54`；`scripts/setup-remotes.sh:25` | 账号 `westanke163`、API `…/api/v5/`（实测 200），与 remote 一致 |
| 15 | 长文本正则与重复分组 | 已避免 | `app/lib/bridge/content.dart:245`；`app/lib/ui/md_view.dart:42`；`harmony/…/core/MdParser.ts:158`、`:210-212`；`Content.ts:365` | 全仓正则为行级锚定式，无含嵌套重复分组的表达式；Dart/ArkTS 引擎为非递归回溯，不存在 Java 那种 `StackOverflowError` |
| 16 | 过期响应覆盖新上下文 | **命中** | `app/lib/ui/chat_history_actions.dart:24`、`:27`、`:32-48`；`harmony/…/core/ChatHistory.ts:23-58` | reload 领了 `id` 但 await 后不复核，切会话后旧响应覆盖新会话的 messages/rawEvents/projections/hasMore |
| 17 | SelectionContainer 把子节点当兄弟排布 | 不适用 | — | Compose `SelectionContainer` 专有行为，dsh-Chat 无 Compose |
| 18 | delta 帧缺 turn/step 被静默丢弃 | 已避免 | `app/lib/bridge/models.dart:133-143` | `turn/step/index` 缺省兜底 0，不因字段缺席整帧丢弃 |
| 19 | vivo 输入法拒绝外部文本注入 | 不适用 | — | 客户端没有「外部文本注入 / 自动填连接串」功能，连接串由用户手输 |
| 20 | 键盘弹起让对话框上移：点旧坐标会点空，表现为「点了没反应」 | 不适用 | — | 无「记住坐标再点」的自动化链路；Flutter 点击按控件矩形中心，键盘弹起只改 insets/SafeArea |
| 21 | 诊断日志：开关只该管「记不记」，不该管「通道建不建」 | 已避免 | `app/lib/bridge/dlog.dart:17-23`、`:31` | `init()` 无条件建文件与写 session 头，`enabled` 只拦写入 |
| 22 | 诊断日志的噪音：重复行必须按指数抑制 | **命中** | `app/lib/bridge/dlog.dart:31-33`；`app/lib/bridge/gateway.dart:172`、`:245`（`gw <- kind=…` / `gw event …`） | 每帧同步 `writeAsStringSync`，无 2 的幂去重、无轮转、无大小上限 |
| 23 | 数字口径不可混用（诊断日志版） | 不适用 | — | 无「诊断日志条数」类统计展示 |
| 24 | history 重建冲掉滚动位置，贴底跟随被自己的守卫锁死 | 已避免 | `app/lib/ui/scroll_follow.dart:26-33`；`app/lib/ui/chat_message_list.dart:25`、`:152-153` | `wantsBottom` 是粘性意图标志（只有用户真拖拽才撤销），翻页 prepend 后 `historyPageJustLoaded` 跳过一次贴底 |
| 25 | Markdown autolink 的尖括号目标被当成相对路径 | 不适用 | `app/lib/ui/md_view.dart:157-172` | 链接只 `launchUrl(..., externalApplication)`，没有「按工作区路径打开文件」链路 |
| 26 | 诊断浮层贴在 TopStart：连撞四个导航入口（已改为可拖动） | 不适用 | — | 无诊断浮层（诊断信息只在设置页文本区） |
| 27 | 客户端自渲染 ≠ 内核会替你画：两处注释都以为对方在画 | 已避免 | `app/lib/ui/chat_state_events.dart:68`；`app/lib/ui/chat_message_list.dart:334`、`:478` | `turn.end reason=max-tokens` 置 `maxTokensNotice`，列表出提示条，新轮 `turn.start`/`send()` 复位 |
| 28 | 表格贴上一行：intellij-markdown 不认无空行 GFM 表格 | **命中** | `app/lib/ui/md_view.dart:19-45`、`:148`、`:171`；`gpt_markdown-1.4.0/lib/plusparse/block_parser.dart:415-470`、`:1256-1279` | 无 `normalizeMarkdownTables`；块解析器 switch 不含 `0x7C`，紧贴上一行的表格整块退化成段落（离屏探针实测 tables=0）。鸿蒙侧已避免 |
| 29 | 连接状态位是「曾经连上过」，不是「此刻还连着」 | 已避免 | `app/lib/ui/chat_page.dart:215`、`:236`；`app/lib/bridge/gateway.dart:349-370` | 连接状态是枚举，掉线即转 `connecting/closed/authFailed`；UI 只认 `GatewayState.ready` |
| 30 | busy 只在 launchOperation 里收尾：绕过它的路径会把标志永久卡住 | 已避免 | `app/lib/ui/chat_state_events.dart:62`、`:72`；`app/lib/ui/chat_state.dart:194`、`:305`、`:316` | `streaming` 在 committed、turn.end、turn.failed、send 失败、openSession 五处都归零 |
| 31 | 文档链接带位置后缀（:行号 / #L行号）被当成路径的一部分 | 不适用 | `app/lib/ui/md_view.dart:157-172` | 无路径解析链路（同 #25） |
| 32 | 目录结构与接口说明漂移 | 已避免 | `scripts/ci/docs-check.sh:33-70` | 双向锚点（lib/harmony 每个文件必须登记 + 登记的必须真实存在）＋旧仓名拦截；无「下限断言」但覆盖更细 |
| 33 | 空助手消息把过程组劈成几十个组头 | 已避免 | `app/lib/bridge/history_page.dart:171-172`、`:277-278`、`:292` | 只有 reasoning/tool-call 的 `assistant/message` 不算消息，工具调用并入当前过程组，有正文时先 `flushGroup()` |
| 34 | 内核 schema 是 schemastery，不是 JSON Schema | 不适用 | `grep -rn "settings/namespaces"` 零命中 | 不渲染内核设置 schema，没有 schema→表单的转换 |
| 35 | 设置页照抄 WebUI 命名空间：一排拨不动的开关 | 已避免 | `grep -rn "settings/namespaces\|settingsNs" app/lib harmony/…` 零命中 | 设置页只有本地项（连接/外观/字号/诊断/关于），不展示服务端命名空间开关 |
| 36 | 设置页「能看不能存」：配对默认没有 settings.write | 已避免 | 同上；`grep -rn "/api/v1/settings" app/lib` 仅注释 | 不做 PATCH settings 调用，故不存在「一排拨不动的开关」 |
| 37 | 刷新历史把「加载更早」的成果抹掉，屏幕上只剩一片空白 | **命中** | `app/lib/ui/chat_history_actions.dart:32`；`harmony/…/core/ChatHistory.ts:37` | 刷新用最后一页整体替换 `messages`，已翻页加载的更早内容全部消失 |
| 38 | 建议面板硬截 N 条又不可滚：第 N+1 条之后的命令既看不见也够不着 | 已避免 | `harmony/entry/src/main/ets/components/ComposerPanels.ets:17`、`:63` | 无 `.take(N)` 截断，列表在 `Scroll` 内且高度 `min(320, …)` 可滚；安卓侧无该形态面板 |
| 39 | WebSocket 断连只挂 onClosed：桥重启后连接永远「还在」 | 已避免 | `app/lib/bridge/gateway.dart:136-140` | `onDone` 与 `onError` 都进 `_onDown`，且 closeCode/closeReason 在 teardown 前读取 |
| 40 | 契约文档写着「requestId 回显」，实测一半的帧不回显 | 已避免 | `app/lib/bridge/gateway.dart:174-215`（`frame['requestId'] ?? data['requestId']`）；`app/lib/bridge/gateway_api.dart:316-333` | 以 requestId 为主键关联 pending；桥侧现版本对应答帧普遍回显（排除表只含 hello/paired/pong/event 等） |
| 41 | 两个事件通道交接时，旧通道的「告别」会把新通道的状态改回断开 | 不适用 | — | 只有 WS 一条事件通道，没有 REST/SSE 事件流与之交接 |
| 42 | 整份状态重建只填服务端字段，其余五十多个字段被打回默认值 | 已避免 | `app/lib/ui/chat_history_actions.dart:32-48`；`harmony/…/core/ChatHistory.ts:37-44` | 只覆盖 messages/rawEvents/与同步字段，流式态、本地命令卡、展开态不动 |
| 43 | 共用 kind 的应答：靠 data.type 判别，漏一个就会互相把请求「确认」掉 | 已避免 | `app/lib/bridge/gateway_api.dart:316-333` | 主键是 requestId；`data.type` 只在注释里说明用途，不参与「谁完成谁」 |
| 44 | 同一份列表，REST 包 items、WS 直接给数组：套同一个反序列化模型必炸 | 已避免 | `app/lib/bridge/gateway_api.dart:25`（`r['sessions']` 裸数组）与 `:123`（`r['items']`） | 两处各自解析、不共用同一个反序列化模型，不会出现「Expected JsonObject, but had JsonArray」 |
| 45 | 渲染库回调拿到的 content 是整篇，别拿它重新解析自己那一块 | 已避免 | `app/lib/ui/md_view.dart:166-171`；`app/lib/ui/md_table.dart:23-50` | `tableBuilder` 只吃 `rows` 参数自绘，不拿全文重新解析 |
| 46 | WS 半死：socket 断了但状态还写着「已连接」，帧写进去等满超时且不回落 REST | **命中** | `app/lib/bridge/gateway.dart:414-430`、`:440-460`；`harmony/…/core/GatewayClient.ts:273`（心跳）＋`Transport.ts:27` | 心跳不记 pong/最后入站时间，死 socket 上 `_sendRaw` 仍返回 `true`，请求挂 30s 才报超时，期间不重连、不回落 REST |
| 47 | 透明灰幕照样吃点击：视觉上看不见不等于不参与命中 | 已避免 | `app/lib/ui/chat_page.dart:112-131` | 抽屉关闭时 scrim 直接 `SizedBox.shrink()`（根本不挂树上），打开时才是 `Positioned.fill(GestureDetector)` |
| 48 | 发布脚本把「列表首项」当「最新」：接口不倒序，探测永远探不到刚发的 tag | **命中** | `scripts/release.sh:250-252` | AtomGit `releases?per_page=1` 升序返回（实测首项恒 v1.0.0），当前 v1.0.18 永远判「不存在」→ 每次发版重复 POST |
| 49 | 能力位只认一条来源，就会在竞速里丢掉整块入口 | 已避免 | `app/lib/bridge/gateway.dart:52-56`、`:188-195`、`:398` | 能力位只从 hello 读（本仓无第二条事件通道，不存在竞速），`hasCapability()` 统一查询；注：当前无调用点，属「已具备但未消费」 |
| 50 | 带默认值的字段会被序列化器整条省掉 | 已避免 | `app/lib/bridge/questions.dart`（`QuestionAnswerItem.toJson`）；`app/lib/bridge/gateway_api.dart:335-350` | Dart 侧显式构造 map，无 `encodeDefaults` 语义；必填字段恒写，只有可选 `custom` 才省略 |
| 51 | 底部面板内容不避让系统手势条：药丸看得见、点不动 | 已避免 | `app/lib/ui/projection_sheets.dart:28`；`app/lib/ui/model_sheet.dart:54`；`app/lib/ui/session_location_sheet.dart:85`；`app/lib/ui/work_view_sheet.dart:123` | 6 处 `showModalBottomSheet` 的内容根都包 `SafeArea`，最底行不会落在手势条里 |

---

## 3. 命中项详述

### 3.1 【#16】过期响应覆盖新上下文（严重度：高）

**现象（companion 原坑）**：切换会话/切换 Host 时，上一次请求的响应晚到，把旧上下文写进新上下文——界面显示上一个会话的消息，用户发出的消息却进新会话。

**dsh-Chat 现状代码**

- Flutter：`app/lib/ui/chat_history_actions.dart:24` 取 `final id = state.sessionId;` → `:27` `final page = await state.gateway.history(id, maxMessages: 200);` → **`:32` 起直接 `state.messages = page.items;`**，随后 `:35` `dropPersistedToolRows()`、`:36` `state.rawEvents = page.rawEvents;`、`:37` `historyHasMore`、`:39` `historyTruncated`、`:48` `state.projections = page.projections ?? state.projections;`。整段**没有任何 `if (id != state.sessionId) return`**。
- 鸿蒙：`harmony/entry/src/main/ets/core/ChatHistory.ts:23-58` 的 `reloadHistoryIn` 同样在 `:24` 取 `id`，`:36` 发 `store.api.history(id, …)`，`.then` 里直接 `:37 store.messages = …`，**不校验 `store.sessionId !== id`**。
- 对照证据（同一仓里已有正确写法）：`chat_history_actions.dart:84` `if (id != state.sessionId) return; // 翻页期间切了会话：丢弃`；`ChatHistory.ts:73` 同款。说明「翻页」那条路径想到了，「刷新」这条漏了。

**为什么等价**：触发面比 companion 更大——`chat_state_events.dart` 里 `committed`(:43-44)、`turn.end`(:68 附近)、`resync`、工具调用防抖(:49/87/96/105)、`session.event` 都会调 `reloadHistory()`，一次长回复期间可触发多次；用户在 200ms 窗口内切会话即可撞上。

**后果**：B 会话界面出现 A 会话的历史；更糟的是 `streaming`/`maxTokensNotice` 等状态仍在 B 的实例上，用户看到 A 的截断提示却对着 B 发消息；调试时表现为「消息串台」，极难复现定位。

**修复建议**

1. `app/lib/ui/chat_history_actions.dart`：await 之后、任何写操作之前加守卫，并把整段写入包在守卫内：
   ```dart
   final page = await state.gateway.history(id, maxMessages: 200);
   if (id != state.sessionId) return; // 切了会话：丢弃过期页
   ```
2. `harmony/.../core/ChatHistory.ts` 的 `.then` 首行加 `if (store.sessionId !== id) return;`（注意 `finally` 里已有 `loadingOlder` 复位逻辑，刷新侧无此字段）。
3. 更彻底（推荐，companion 的最终解）：引入连接/会话代际号 `_gate = ++_gateSeq`，await 后比对 `_gate`，一处收口所有异步回写（reload/loadOlder/projections/模型列表）。

**验证方式**

- 单测（`app/test/`）：两个假会话，A 的 `history` 用 `Completer` 延迟返回；调用 `reloadChatHistory` 后立刻 `openSession(B)`，再 complete A；断言 `state.messages` 全是 B 的、`state.rawEvents` 未变。鸿蒙侧同法写进 `harmony/test/`（node:test 直测 `core/ChatHistory.ts`）。
- 真机：长回复进行中快速切会话（10 次），确认无串台。

---

### 3.2 【#46】WS 半死：状态写着「已连接」，帧写进去等满超时（严重度：高）

**现象（companion 原坑）**：socket 实际已断/被冻结，但状态机只在收帧时更新，于是界面仍显示「已连接」；发送帧写进死 socket 不报错，请求挂到超时才失败，且不回落 REST。

**dsh-Chat 现状代码**

- `app/lib/bridge/gateway.dart:414-420`：
  ```dart
  _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
    _sendRaw({'type': 'ping'});
  });
  ```
  **只发不问**：没有 `_lastInboundAt`、没有 pong 计数、没有「静默超阈值即判死」。
- `:422-430` `_sendRaw`：`ws == null` 才返回 false；`ws.sink.add(...)` 不抛即 `return true`。半死 socket 上 `sink.add` 照样成功 → 调用方认为「发出去了」。
- 请求层：`requestWithTimeout` 用 30s 超时（`gateway.dart:466` `Duration(seconds: 30)`，超时抛在 `:457`）；超时只 `RequestException('TIMEOUT', …)`，**不触发 `_onDown`、不排重连、不回落 REST**。
- 鸿蒙同款：`harmony/.../core/GatewayClient.ts:273` `scheduleHeartbeat()` 自续 25s 只发 ping；`Transport.ts:27` `HEARTBEAT_INTERVAL_MS=25000`，无入站时间戳字段。

**为什么等价**：companion 的判据是「状态机只在收帧时更新 + 写 socket 前不校验静默时长」，dsh-Chat 两条都成立；companion 的修法（`refuseIfStale()` + `livenessTimeoutMillis = 心跳×2 + 5s`）在本仓完全缺失。

**后果**：熄屏/切网/进程冻结后，用户点发送 → 按钮转圈 30s → 报「请求 chat.send 超时」；期间 `GatewayState` 仍是 `ready`，用户不会看到「正在重连」，也不会自动重连（`onDone` 可能永不触发，尤其 NAT 超时/蜂窝切换）。长回复流式中途静默时，UI 也永远停在「正在生成」。

**修复建议（`app/lib/bridge/gateway.dart`）**

1. 字段 `DateTime? _lastInboundAt;`；`_onFrame` 第一行（decode 之前）刷新它；`_onDown` 里清空。
2. 心跳回调改为：
   ```dart
   final last = _lastInboundAt;
   final idle = last == null ? null : DateTime.now().difference(last);
   if (idle != null && idle > const Duration(milliseconds: 45000)) {
     _onDown(null, 'stale'); // 复用掉线收口：failAll + 重连
     return;
   }
   _sendRaw({'type': 'ping'});
   ```
3. `_sendRaw` 前加 `if (_isStale()) return false;`，`requestWithTimeout` 在「未发出」分支抛 `RequestException('WS_CHANNEL_STALE', …)`；该错误码与 `TIMEOUT` 都要能触发一次主动重连（幂等语义的 REST 回落另议，`chat.send` 不幂等，仍只走 WS）。
4. 回前台（若补 #6 的生命周期监听）调一次探活：`/api/v1/` HEAD 或 WS 重连，成功前不置 `ready`。
5. 鸿蒙：`GatewayClient.ts` 加同样的 `lastInboundAt` 与 `refuseIfStale()`，常量放 `Transport.ts`（如 `LIVENESS_TIMEOUT_MS = 45000`）。

**验证方式**

- 单测：假 transport 只发不收回执，推进假时钟 46s，断言状态转 `connecting` 且 `_pending` 全部 failAll；再推进到退避触发一次 connect。
- 真机：飞行模式开 60s 再关；或在路由器层断外网 60s。验收：45s 内状态离开 `ready`，网络恢复后自动回 `ready`，随后发送成功（不是 30s 超时）。

---

### 3.3 【#37】刷新历史抹掉「加载更早」的成果（严重度：高）

**现象（companion 原坑）**：用户点了若干次「加载更早」，一次 `refreshHistory` 拿最后一页整体替换列表，屏幕只剩最后一页，`hasMore` 语义也被打断。

**dsh-Chat 现状代码**

- `app/lib/ui/chat_history_actions.dart:32` `state.messages = page.items;`（`maxMessages: 200`，最后一页）——直接覆盖，**没有把 `seq < page.items.first.seq` 的已加载更早页拼回去**；`:37` 用新页 `hasMore` 覆盖。
- `loadOlderMessages`（同文件 `:64-107`）是正确的：`:89-93` 按 seq 去重 prepend、`:95` 置 `historyPageJustLoaded`、`:97` 续 `hasMore`。也就是说**能力已有，只是被刷新抵消**。
- 鸿蒙 `ChatHistory.ts:37` 同款整体替换；`loadOlderIn:61-100` 亦正确。

**为什么等价**：与 companion 完全同构（刷新拿最后一页整体替换），且本仓刷新触发点更多（每轮结束必刷）。

**后果**：长会话里用户往上翻到 500 条前，一次回复结束就弹回最后 200 条，且要重新翻 3 次；`historyTruncated`/`hasMore` 也随之失去意义。

**修复建议（`chat_history_actions.dart`）**

```dart
final page = await state.gateway.history(id, maxMessages: 200);
if (id != state.sessionId) return;
final firstNewSeq = page.items.isEmpty ? null : page.items.first.seq;
final older = firstNewSeq == null
    ? <ChatMessage>[]
    : state.messages.where((m) => m.seq >= 0 && m.seq < firstNewSeq).toList();
state.messages = [...older, ...page.items];
state.historyHasMore = page.hasMore || older.isNotEmpty; // 更早段仍可能有未加载部分
```

鸿蒙 `ChatHistory.ts` 同法（`mergeOlderMessages` 已有，可复用其去重逻辑）。注意命令卡（`seq<0`）与 `older` 的拼接顺序：先 `older`、再新页、最后本地命令卡。

**验证方式**：单测构造 3 页（seq 1-200/201-400/401-600），先 `loadOlder` 两次，再调 `reloadChatHistory`，断言首条 seq 仍为 1、条数 600、`historyPageJustLoaded` 不被误置；真机上下翻后再触发一轮回复，确认视口不跳。

---

### 3.4 【#28】表格紧贴上一行：块解析器不认（严重度：中）

**现象（companion 原坑）**：`下面是结果：\n| A | B |\n|---|---|` 这种「表格直接贴在说明行后面」的 Markdown，渲染库不识别，退化成一整段竖线文本。

**dsh-Chat 现状代码**

- `app/lib/ui/md_view.dart:19-45` 只有 `normalizeTaskLists`（修任务列表圆点），**:148** 渲染前 `normalizeTaskLists(text)` 之后直接喂 `GptMarkdown`，**没有表格规整**。
- 离屏探针（`app/build/table_probe.dart`，跑完已删）实测 `parseBlocks`：
  - `下面是结果：\n| A | B |\n|---|---|\n| 1 | 2 |` → **tables = 0**（整块 1 个 `MdParagraph`）
  - 中间加空行的同一内容 → **tables = 1**
- 源码依据：`gpt_markdown-1.4.0/lib/plusparse/block_parser.dart` 的 `_startsBlock`（`:415-470`）switch 里没有 `0x7C`（`|`）分支；`_mayStartBlock`（`:1448`）虽列了 `0x7C` 却未被 switch 使用；`_tryTable`（`:1256-1279`）只在块首被调用。
- 鸿蒙侧**已避免**：`harmony/.../core/MdParser.ts:272-276` `isTableStart()` 在主循环 `:89` 先判表，`readParagraph`（`:384-388`）显式在「下一行是表头」处 break。

**为什么等价**：companion 修的是 intellij-markdown，dsh-Chat 换了 gpt_markdown 但**同款缺陷**（都是「表格必须独占块首」），且本仓也没有 `normalizeMarkdownTables()` 这层兜底。

**后果**：模型输出「说明 + 紧贴表格」时（很常见），安卓端把表格渲染成一行行 `| a | b |`；鸿蒙端正常 → **双端视觉不一致**，与官方 App 也对不上。

**修复建议（`app/lib/ui/md_view.dart`）**

1. 新增纯函数 `normalizeMarkdownTables(String raw)`：逐行扫描，
   - 跳过围栏代码块（``` / ~~~）内的行；
   - 若当前行 `indexOf('|') >= 0` 且下一行是分隔行（`^\s*\|?\s*:?-{3,}` 形态）、且上一行非空，则在当前行前插入空行；
   - 幂等（已空行不重复插）；流式安全（末尾 1 行不完整时不动）。
2. 在 `:148` 处改为 `normalizeMarkdownTables(normalizeTaskLists(text))`，顺带检查其它直接喂 GptMarkdown 的分支（`work_view_sheet`/`md_viewer` 若共用同一入口则自动生效）。
3. 补 `app/test/render_md_test.dart` 用例：无空行 / 已有空行 / 围栏内 / 表格贴列表项 / 流式半行。

**验证方式**：`flutter test test/render_md_test.dart` 断言 `MdTable` 数量；真机对比同一段回复在安卓与鸿蒙的渲染（鸿蒙已正确，作为参照）。

---

### 3.5 【#22】诊断日志噪音：重复行必须按指数抑制（严重度：中）

**现象（companion 原坑）**：诊断日志把每一帧都落一条，一次流式会话写几百上千行，文件涨到几十 MB，排查反而更难；companion 用「连续重复按 2 的幂落一条」把 344 条降到 17 条。

**dsh-Chat 现状代码**

- `app/lib/bridge/dlog.dart:31-33`：
  ```dart
  if (!enabled) return;
  try { _file?.writeAsStringSync('$ts $msg\n', mode: FileMode.append); }
  ```
  **每帧一次同步写**；无去重、无缓冲、无轮转、无大小上限。
- 打点量：`app/lib/bridge/gateway.dart:195` 每个非 pong 帧一条 `gw <- kind=… rid=…`；`:202` 每个事件一条 `gw event … sid=…`；delta 另有每 25 条一条 `debugPrint`。
- 鸿蒙 `harmony/entry/src/main/ets/platform/Dlog.ets` 同样无去重（`grep dedupe|repeat` 零命中）。

**为什么等价**：companion 的两个症状（数量爆炸 + 单条无抑制）在本仓都成立，只是缺「开关只该管记不记」那条已避开（`init()` 无条件建文件，`enabled` 只拦写入）。

**后果**：① 流式期间 UI isolate 上每帧一次磁盘 fsync → 掉帧（尤其 vivo 中低端机）；② 文件无上限，长期开启可涨到 GB 级；③ 设置页「查看日志」若整文件读入内存，会卡顿甚至 OOM；④ 真正有用的几条被淹没。

**修复建议（`app/lib/bridge/dlog.dart`）**

1. 连续重复抑制：保留 `_lastKey`、`_repeatCount`；`w(msg)` 时若 key 相同则 `count++`，只在 `count` 为 2 的幂时落一条并附 `×N`。
2. 异步批量写：内存缓冲 + 200ms 定时 flush（或 64KB 触发），不用 `writeAsStringSync` 阻塞 UI。
3. 轮转：单文件 > 4 MiB 时 `dsh.log.1` / `dsh.log.2` 滚动，只留 3 份。
4. `read()` 只读尾部 256 KB（设置页预览足够）。
5. 鸿蒙 `Dlog.ets` 同法（hilog 本身有频率限制，但仍要抑制重复）。

**验证方式**：单测对同一行 `w()` 1000 次，断言实际落盘 ≤ 11 条（1,2,4,…,512）；真机开日志跑一次长回复，用 `adb shell` 看文件大小与 UI 帧时间（`--profile` 或肉眼卡顿）。

---

### 3.6 【#48】发布脚本把「列表首项」当「最新」（严重度：中）

**现象（companion 原坑）**：AtomGit 的 `GET releases?per_page=1` 不按时间倒序，脚本把首项当最新 → 永远探不到刚发的 tag，每次发版重复创建 release。

**dsh-Chat 现状代码**

- `scripts/release.sh:250-252`：
  ```sh
  cur=$(curl -s -H "Authorization: Bearer $AT" \
        "https://atomgit.com/api/v5/repos/$REPO_ATOMGIT/releases?per_page=1" \
        | python3 -c "…print((d[0] if isinstance(d,list) and d else {}).get('tag_name',''))")
  ```
  随后 `if [ "$cur" = "$TAG" ]` 判存在。
- **实测**（2026-11-19）：`curl …/releases?per_page=3` 返回首项 `v1.0.0`（2026-11-04T19:35:43），第二项 `v1.0.1`，第三项 `v1.0.2`；当前最新是 `v1.0.18` ⇒ **升序**，`d[0].tag_name` 恒为 `v1.0.0`。
- 且该段的 `curl` 未加 `-f`、响应被 `>/dev/null` 吞掉，失败也会打印「AtomGit Release 已建」。

**为什么等价**：与 companion 完全同构（首项当最新 + 失败被吞）。

**后果**：每次 `release.sh --publish` 都对 AtomGit 重复 POST 创建 `v1.0.18` 之类的 release（服务端若允许同名 tag 会产生重复条目，若 409 则被吞掉、脚本仍报成功）；发版台账与实际不一致，「幂等」承诺失效；后续「更新已有 release」的分支永远走不到。

**修复建议（`scripts/release.sh`）**

1. 改为按 tag 直查（不依赖列表顺序）：
   ```sh
   code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $AT" \
     "https://atomgit.com/api/v5/repos/$REPO_ATOMGIT/releases/tags/$TAG")
   ```
   `200` → 已存在（走更新 / 跳过）；`404` → 创建；其它 → 报错退出。
2. 或退一步：`per_page=100` 取全量，`any(d['tag_name'] == TAG for d in d)`，不要 `d[0]`。
3. 创建/更新的响应保存到 `artifacts/atomgit-release.json` 并打日志，别 `>/dev/null`。
4. 更新已有 release 用 `PATCH .../releases/{tag}`（URL 带 `tags/` 的 PATCH 一律 405）。

**验证方式**：拿已存在的 `v1.0.18` 跑一次该分支，断言输出「已存在」且未发 POST（`set -x` 或 mock curl）；再核对 AtomGit releases 列表条数不变。

---

## 3.5 真机复测（2026-11-20，vivo V2080A / Android 11）补充

装机后暴露了一个**本报告 §3 未列**的问题，已修，记在这里以免下次重踩：

| 现象 | 根因 | 修法 | 归属 |
|---|---|---|---|
| 启动 40–50 s 或流式期间任意点击 → `Input dispatching timed out` → ANR；现场进程 CPU 97%、主线程停在 `libflutter.so` + `nativePollOnce` | ①每收到一帧就同步写一次诊断日志（`gw <- kind=…`、`gw event …`、`ui delta …`），流式期每秒数十次写盘；②`dlog.dart` 的尾部保留按行触发 → 每行都要读+写 2 MiB | 删掉三处逐帧打点；裁剪阈值 `2 MiB → 2.5 MiB` 才重写一次 | #22 的延伸（本次真机发现） |
| 每 ~50 s 一次无谓重连；随后点击 ANR | 上一轮为 #46 加的「客户端 45 s 静默判死」在活连接上误杀（心跳 25 s ×2 跨阈值），收尾路径拖住主线程 | 静默只记日志、帧照发，判死交回服务端心跳；Flutter `Liveness` + Harmony `LinkLiveness` 两端同步 | #46 的**过度修复**回退 |

> 说明：旧构建（11-17 那份、不含本轮改动）在同一台机上也 ANR，所以「逐帧同步写盘」
> 是既有设计问题，不是本轮引入；本轮把 #22 的裁剪做成按行触发，才让它从「偶发卡」
> 变成「必卡」，一并修掉。

真机通过项（会话抽屉 / 历史 / 流式工具行 / 服务端统计 / 无截断不误报）见
`docs/protocol-conformance.md` §8。

## 4. 待真机验证清单

> 判定「待真机验证」的只有 #6；此外把 4 条「代码看着对/有残留风险」的项一并列出，装机时顺带验。

| 编号 | 关联坑位 | 要验什么 | 验收步骤 | 通过标准 |
|---|---|---|---|---|
| V1 | #6 熄屏断流与亮屏接回 | vivo 灭屏后 WS 是否被冻结/断开，亮屏能否自愈 | ① 连上桥、进入会话；② 灭屏 10 分钟；③ 亮屏后立刻发一条消息；④ `logcat -s flutter` 看 `gw down` / `hello` 序列 | 亮屏 5s 内状态回 `ready` 且消息送达（允许一次自动重连；不允许必须杀进程重进） |
| V2 | #39/#45 残留：一次掉线排两次退避 | `onError` 与 `onDone` 是否在同一次掉线中各调一次 `_onDown` | 拔桥/杀桥进程制造掉线，读日志的 `scheduleReconnect delay=` 序列 | 序列应为 1,2,4,8,… 秒；若出现 1 之后直接 4（跳档）说明双排，需要给 `_onDown` 加 claim 守卫（参照鸿蒙 `downAttempt`） |
| V3 | #10 审批 10 分钟超时与电脑端抢占 | 客户端是否会被服务端超时/电脑端先答正确收口 | 制造一个审批，等 10 分钟；另一路在电脑端先点「允许一次」 | 手机端卡片自动消失且不误报错误；不出现「答案已提交但卡片还在」 |
| V4 | 补充②（鸿蒙逐会话探测） | 打开抽屉时对 N 个会话逐个 `GET /questions` 与 `/approvals` 是否拉活冷会话 | 鸿蒙端打开抽屉，抓桥日志看是否出现 `resolveAgent`/会话激活；对比未打开抽屉时的会话数 | 若确实拉活冷会话：改为不做全量探测（只标审批，或用 `/chat/sessions` 的 `pendingInteraction` + 当前会话实时表），或加 60s 缓存与并发上限 |
| V5 | #28 表格视觉 | 安卓/iOS 与鸿蒙同一段「说明+紧贴表格」的渲染 | 发一条含「下面是结果：」+ 紧贴表格的回复，两端截图对比 | 两端都渲染成真表格；修复前安卓是竖线文本 |
| V6 | #22 日志开销 | 开诊断日志后流式回复的帧率与文件增长 | `flutter run --profile` 开日志跑 3 分钟长回复，记录 jank 与 `dsh.log` 大小 | 无明显掉帧；3 分钟日志 < 2 MiB（修复前通常 > 10 MiB） |

---

## 5. 无法判定项、补充命中与覆盖声明

### 5.1 补充命中（不在 companion 51 个锚点内，但同属该类坑）

| 编号 | 缺陷 | 证据 | 严重度 | 说明与建议 |
|---|---|---|---|---|
| S1 | Flutter「命令卡保留」写成先覆盖再筛选，逻辑恒空 | `app/lib/ui/chat_history_actions.dart:32`（先 `state.messages = page.items`）→ `:41-44`（再 `state.messages.where(role=='command')`） | 中 | 服务端历史永不含 `role=='command'`，`cards` 恒空。`app/lib/ui/chat_state.dart:340-348` 注入命令卡后 `:370` `await reloadHistory()` 立刻抹掉。修法照鸿蒙：**先**收集 `localCards` 再 fetch（`ChatHistory.ts:30-37`） |
| S2 | 鸿蒙逐会话探测待答标记（companion 明文禁止的遍历） | `harmony/.../core/ChatHitl.ts:29-66` + `core/GatewayRest.ts:194-207` | 中 | 抽屉打开时对 `store.sessions` 逐个 `GET /sessions/{id}/questions`（0 则再 `/approvals`）。N 个会话 = 最多 2N 次 REST；副作用（拉活冷会话）待 V4 证实。建议改为：只对「有 `pendingInteraction:'approval'` 的会话 + 当前会话」探测，其余靠实时 HITL 表 |
| S3 | 设备 token 明文落盘 | `app/lib/bridge/credentials.dart:13`、`:38`（`sp.setString('dsh.credentials', jsonEncode({'baseUrl','token'}))`）；`app/lib/bridge/hosts.dart:83/112/130` | 中 | 无 Keystore/加密；同机任意同 UID 读取或 root/备份即可导出长期 token。建议用 `flutter_secure_storage`（Android Keystore / iOS Keychain），hosts 里只存 `tokenId` 或加密串；迁移时做一次性迁移 + 清除旧键（已确认**不打印** token：`grep token\|log` 无命中） |
| S4 | 安卓重连链「退避双排」残留（鸿蒙已修） | `app/lib/bridge/gateway.dart:136-140`（onDone/onError 双入口）、`:352-370` `_onDown`（无 claim 守卫）、`:376-392` `_scheduleReconnect` | 低（待真机确认） | 鸿蒙用 `attempt` + `downAttempt` 双重防线；安卓 `_onDown` 无去重，若 `onError` 与 `onDone` 都触发会多排一次退避（1s 档被 2s 档顶掉）。见 V2 |

### 5.2 无法判定 / 判为「不适用」的边界说明

- **#6 熄屏断流**：代码层面既没有 companion 的错误做法（用 `onStop` 判熄屏），也没有正确做法（`ACTION_SCREEN_OFF/ON`）——它是「未实现」而非「实现错」。是否构成缺陷取决于 vivo 灭屏时 socket 是否被冻结，故列 V1。
- **#9 版本基线**：dsh-Chat 只有「协议 v3 + bridge ≥ 2.10.0 + 能力位」一条基线，没有 companion 那张逐特性版本表（beforeSeq 2.3.1 …）。当前不按版本判特性，所以表不必要；若未来消费新特性，应改用能力位（`hasCapability`）而不是补版本表。
- **#5 中的 24 MiB / 分块上传**：本仓无文件上传入口（无 upload 端点调用），故该子项不适用；图片/交接图读取本身已正确带 `sessionId`（两渠道都是）。
- **#10 / #31 / #25 / #17 / #19 / #20 / #23 / #26 / #34 / #41**：均为「技术栈绑定」或「功能不存在」——Compose 专有（17）、WebView（4）、Java 正则递归（15 的引擎侧）、外部文本注入（19）、坐标重放（20）、诊断浮层（26）、WebUI 设置命名空间（34/35/36 那套 schema 渲染）、REST+SSE 双通道（41）、文档链接打开工作区文件（25/31）。
- **#49**：能力位已解析（`gateway.dart:52-56`、`:188-195`）但 `hasCapability()` 当前**零调用点**；这不构成「入口丢失」（因为入口不依赖能力位），属「已具备未消费」。若将来按能力位门控入口，必须保持「只从 hello 取」这条（本仓无第二条通道，天然满足）。
- **#7 的 continued 文案**：官方内核在超时后会给 `Continue useful independent work. The user can still answer.` 的提示；本仓 `question_card.dart` 对 continued 不显示专属提示条（只通用渲染）。属文案/交互细节缺口，不影响三态可用性，故判「已避免」而非命中。

### 5.3 覆盖声明（实际读了什么、怎么统计的）

**整篇读完**

| 文件 | 行数 | 用途 |
|---|---|---|
| `dsh-companion/docs/project/PITFALLS.md` | 1598 | 51 条坑位正文（逐条读完，非抽样） |
| `dsh-companion/AGENTS.md` §7 | — | 坑位索引，与锚点做集合比对（差集为空） |
| `dsh-Chat/docs/STRUCTURE.md` | 351 | 组件/文件职责（判「代码是否真做到」时以源码为准，不以文档自述为准） |
| `dsh-Chat/AGENTS.md` | — | 工程宪法（§11 是 dsh-Chat 自己的坑位，只用于区分，不混入 companion 判定） |
| `app/lib/bridge/gateway.dart` | 487 | WS 状态机/重连/心跳/帧分派 |
| `app/lib/ui/chat_history_actions.dart` | 108 | reload/loadOlder 全文 |
| `app/lib/bridge/dlog.dart` | 48 | 日志实现全文 |
| `app/lib/ui/md_view.dart` / `md_table.dart` | — | 渲染入口与表格组件 |
| `app/lib/ui/question_card.dart` / `hitl_state.dart` / `bridge/questions.dart` | — | 审批/提问卡片与合流 |
| `app/lib/bridge/credentials.dart` / `hosts.dart` | — | 凭据落盘 |
| `harmony/.../core/ChatHistory.ts` / `ChatHitl.ts` / `GatewayClient.ts` / `Transport.ts` / `GatewayRest.ts` / `MdParser.ts` / `ImageFetcher.ts` / `HistoryPage.ts` | — | 对应功能的鸿蒙实现 |
| `harmony/.../components/ComposerPanels.ets` | — | 建议面板 |
| `scripts/release.sh` / `scripts/ci/docs-check.sh` / `scripts/push-all.sh` | 323 / 112 / 143 | 发版、文档门禁、推送 |
| `app/android/.../MainActivity.kt` / `ImagePickHelper.kt` / `gradle-wrapper.properties` | — | Kotlin 注释坑、图片选择、gradle 镜像 |

**grep 统计（用于「已避免」的反证）**

| 检查 | 结果 |
|---|---|
| `grep -c '^### ' PITFALLS.md` | **51** |
| companion AGENTS §7 条目 vs 51 锚点集合比对 | 51 / 51，差集空 |
| `grep -rniE "webview" app/lib harmony/…/core` | 0 命中（#4 不适用） |
| `grep -rn "WidgetsBindingObserver\|didChangeAppLifecycleState\|AppLifecycle" app/lib` | 0 命中（#6 无生命周期处理） |
| `grep -rn "capabilit" app/lib app/test` | 仅 `gateway.dart` 内 3 处（字段/解析/查询）；UI 无调用 |
| `grep -rn "/api/v1/settings\|settings/namespaces\|settingsNs" app/lib harmony/…` | 0 实调用（#35/#36 不适用/已避免） |
| `grep -rn "3090" app/lib harmony/entry` | 0 命中（#10 已避免） |
| `grep -rn "matchMediaSync\|Record<string" …` | — |
| `grep -rn "Duration(minutes\|600000\|10 \* 60" app/lib/ui/hitl*.dart question_card.dart` | 0 命中（#10 客户端无超时常量） |
| `grep -n "showModalBottomSheet" -A3` | 6 处，内容根均 `SafeArea`（#51 已避免） |
| `grep -rn "writeAsStringSync\|dedupe\|rotate" dlog.dart Dlog.ets` | 同步写 2 处（双端），去重/轮转 0 处（#22 命中） |
| `grep -n "releases?per_page=1" scripts/release.sh` | 1 处（#48 命中） |

**离屏探针（唯一一次动态验证）**：`app/build/table_probe.dart` 调用 `gpt_markdown` 的 `parseBlocks`，输入「无空行表格」与「有空行表格」各一次，输出 `tables=0` / `tables=1`；运行后已删除，未入库。

**未做的验证（如实声明）**：未跑 `flutter test` / `harmony/test npm test` 全套（本任务只审计、不回归）；未装机（§4 的清单即为待验项）；未改任何源码。

### 5.4 审计期间的工作树变动（影响判定时效）

审计开始时读到的 `gateway.dart` 版本只有 `onDone`→`connect` 的简单重连；审计进行到一半该文件被（另一写者/会话）改成当前版本：新增 `capabilities` / `listenerPort` 解析（`:52-56`、`:188-195`）、`_onDown(code, reason)` 统一收口（`:352-370`）、`_scheduleReconnect()` 非致命失败继续接力（`:376-392`）、`_pending.failAll` 掉线即失败在途请求。因此本报告对 **#39 / #45 / #49** 的判定以**最终快照**为准（已避免），并据此把「安卓重连链提前终止」降级为 S4（仅剩「双排退避」残留，待 V2）。

关键文件快照（sha256 前 16 位，便于复核）：

| 文件 | sha256 |
|---|---|
| `app/lib/bridge/gateway.dart` | `36fc6ec9534dda4e` |
| `app/lib/ui/chat_history_actions.dart` | `a75b928d8af66e70` |
| `app/lib/bridge/dlog.dart` | `78ca7b2dc6197860` |
| `app/lib/ui/md_view.dart` | `0cd8f760e8d728fc` |
| `scripts/release.sh` | `04c6d51fe2576ec7` |

复核命令：`cd dsh-Chat && sha256sum app/lib/bridge/gateway.dart app/lib/ui/chat_history_actions.dart app/lib/bridge/dlog.dart app/lib/ui/md_view.dart scripts/release.sh`。若哈希已变，请以本报告给出的 file:line 为线索重读，而不是直接采信判定。

---

### 5.5 文档契约门禁现状：既有红（非本报告引入）

按要求跑了 `bash scripts/ci/docs-check.sh`，**结果为失败**。失败与本报告无关：两个**未跟踪的新文件**（`?? app/lib/bridge/gateway_pending.dart`、`?? harmony/entry/src/main/ets/core/ChatStats.ts`，均不在 HEAD `d15df30` 中，属审计期间另一写者的在途重构；收尾时未跟踪新文件已增至 9 个，其中 `ChatResync.ts` 等已登记、这两个还没有）尚未登记进 `docs/STRUCTURE.md`。该脚本只扫 `app/lib/` 与 `harmony/entry/src/main/ets/` 的**实际文件**及 `STRUCTURE.md` 的内容，本报告不被其任何一条规则覆盖（旧仓名残留检查 0 命中）。

原始输出（原样保留）：

```
检查 app/lib/ 全部文件是否已登记进 docs/STRUCTURE.md …
  ❌ 未登记：lib/bridge/gateway_pending.dart  →  请在 docs/STRUCTURE.md 的「## app/lib/」表里补一行
检查 harmony/entry/src/main/ets/ 全部文件是否已登记进 docs/STRUCTURE.md …
  ❌ 未登记：harmony/core/ChatStats.ts  →  请在 docs/STRUCTURE.md 的「## harmony/」表里补一行（写 `ets/core/ChatStats.ts`）
检查 docs/STRUCTURE.md 中登记的文件是否仍存在 …
  ✅ 无死链
检查 docs/STRUCTURE.md 中登记的 ArkTS 文件是否仍存在 …
  ✅ harmony 无死链
检查改名前缀残留 …
  ✅ 无残留

❌ 文档契约检查失败：改了 lib/ 就请同提交更新 docs/STRUCTURE.md（宪法 §8）
```

退出码 1。**未代修**：这两个文件是另一写者进行中的拆分/新功能（`gateway_pending.dart` 头注释写明「从 gateway.dart 拆出：宪法 §7 单文件 ≤500 行」），其登记应由该改动作者在同一提交内补 `docs/STRUCTURE.md`（补 `bridge/gateway_pending.dart` 与 `ets/core/ChatStats.ts` 两行即可转绿）。本任务的范围是「只写一份报告文档」，故不代改他人正在编辑的文档，避免并发写冲突（对应 companion 坑 #12「并发写者与未提交改动」的纪律）。

---

## 6. 修复进度（2026-11-20 更新）

审计交付后，同一轮里 6 条命中**全部修完**（三条高危 + 两条观感/诊断 + 一条发版脚本）。
完整的协议侧改动与验证记录见 `docs/protocol-conformance.md`。

| 编号 | 坑 | 状态 | 修法与回归用例 |
|---|---|---|---|
| #16 | 过期响应覆盖新上下文 | ✅ 已修 | 双端 `reloadChatHistory` / `reloadHistoryIn` 在 await 回来先比 `sessionId`，变了整块丢弃。用例：`app/test/history_merge_test.dart`、`harmony/test/cases/chat-history-merge.test.ts` |
| #37 | 刷新抹掉「加载更早」的成果 | ✅ 已修 | 双端 `mergeRefreshedHistory` / `mergeRefreshedRawEvents`：保留新页首条 `seq` 之前的旧消息前置，`hasMore` 延续旧结论而非重置；命令卡（`seq=-1`）不进前置区。用例同上（4 + 3 例） |
| #46 | WS 半死（状态还写已连接，帧写进死连接等满超时） | ✅ 已修 | 新增活性判据 `app/lib/bridge/gateway_liveness.dart` / `harmony/.../core/LinkLiveness.ts`（静默 > 45s 判死，判据是**最近一次收到帧**）；心跳内判 + **写 socket 之前** `refuseStaleLink()` → `WS_CHANNEL_STALE` 立刻失败、按安全判据回落。用例：`gateway_liveness_test.dart`、`link-liveness.test.ts`（3 例，含「帧未写进 socket」断言） |
| #48 | 发版脚本把列表首项当最新 tag | ✅ 已修 | `scripts/release.sh` 改在整页（`per_page=100`）里找本 tag（该接口按创建时间升序，取首项恒为最老） |
| #28 | GFM 表格贴上一行 | ✅ 已修 | `app/lib/ui/md_view.dart` 新增 `normalizeTables()`：表格行前面是**非空且非表格行**时补一个空行（GFM 规范允许表格紧跟段落，`gpt_markdown` 1.4.0 只在空行后才认），围栏代码块（``` / ~~~）整段跳过，**只补换行不动单元格**。用例：`app/test/md_view_test.dart`（4 例：紧贴段落、本来有空行不重复、代码块内不误判、无竖线原样） |
| #22 | 诊断日志噪音（每帧同步写） | ✅ 已修 | `app/lib/bridge/dlog.dart`：①`dedupeWindow`=2s 内同一条消息只计数不落盘，下一条不同消息到来时先落一行「（上一条重复 N 次）」——重复不再无声丢失；②`maxBytes`=2 MiB，超限只保留尾部并**对齐到行首**（`trimOffset()` 保证不留半行）。判据抽成纯函数 `shouldSuppress()` / `trimOffset()`，单测不碰文件系统。用例：`app/test/dlog_test.dart`（2 例） |

验证（全绿）：`bash scripts/ci/docs-check.sh` ✅ / `flutter analyze` ✅ No issues /
`flutter test` ✅ 273 passed / `cd harmony/test && npm test` ✅ 362 passed。

---

*报告结束。全程只读代码 + 一次离屏探针，未修改 `app/`、`harmony/` 任何源码，未使用 `/tmp`。*
