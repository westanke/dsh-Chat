# STATUS —— 鸿蒙版阶段进度

> 每轮交付后更新本表。对照基准：安卓版 `docs/STRUCTURE.md`（唯一功能清单来源）。

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 工程骨架：ArkTS 空工程 + 未签名 HAP 构建通 + node 测试骨架 + 门禁/文档同步 + 首提交 | ✅ 2026-11-15 |
| 1 | core 协议层：全部帧模型 + gateway 状态机 + REST 封装 + node 用例全绿 | ◐ 123 用例全绿；仅剩 platform/dlog（阶段 4 entry 层）|
| 2 | 连接页三路径 + 聊天页骨架 + 流式对话 + 历史翻页 + 发送 | ☐ |
| 3 | Markdown 全家福（含**首版轻量 LaTeX**，用户拍板）+ 工具折叠 + 命令卡 + 文件卡 + 图片 | ☐ |
| 4 | 抽屉 / 设置 / HITL / 投影 / 子会话 / 统计 / 平台 7 通道 / 深色 / 字号 / 检查更新改口径 | ☐ |
| 5 | 签名 + 真机逐项验收 + PARITY 对账 + Gitee Release（AGC 可选） | ☐ 需 AGC 材料 |

## 阶段 0 交付清单（2026-11-15）

- 工程骨架：`AppScope/` + `entry/`（EntryAbility + Index 占位页，深浅色跟随系统已做对）。
- 未签名 HAP：`hvigorw assembleHap` BUILD SUCCESSFUL（14.8s），产物 107KB。
- 测试：`test/cases/version-contract.test.ts`（版本契约冒烟，npm test 1/1 绿）。
- 脚本：`scripts/package.sh`（双闸门）+ `scripts/toolchain-env.sh` + 工具链重放脚本。
- 文档：`docs/PORT-MAP.md`（对照表 + 决策记录 + 坑位）、`docs/RELEASE.md`（流程骨架）、本文件。
- 根仓同步：STRUCTURE.md 增 harmony 章、AGENTS.md 双平台化、docs-check.sh 扩展 ets 登记、
  CI 增 harmony-test job、.gitignore 增 harmony 段。
- 首提交（不推送）。

## 阶段 1 首批（2026-11-15）

- core 首批 5 文件 + WireBuilder（`entry/src/main/ets/core/`）：JsonAccess / Wire / Models /
  Content / Credentials / ImageMediaType；node 用例 48 个全绿（npm test）。
- **core 落位定案**：物理在 entry 模块内——ArkTS 禁跨模块相对 import（Index.ets 引
  `../../..../core/Models` 实测 Error00309001 BUILD FAILED），放工程根 harmony/core/ 方案否决；
  与姊妹仓（90+ core .ts 在 entry/src/main/ets/core/，已过真机+AGC）同款。
- ArkTS 兼容化改写（hvigorw assembleHap 全过）：PromptPart 判别联合→扁平类+type 分派；
  builtinTokens Record→Map；import 去 type 修饰符；可选捕获组正则拆必组；`?? {}`→显式空表。
- 文档同步：AGENTS.md（§3 目录树/§7 分层+ArkTS 条目）、PORT-MAP 对照表、STRUCTURE harmony 章。

## 阶段 1 WS 层（2026-11-15）

- core 新增 6 文件：Transport.ts（传输抽象+协议时序常量）/ GatewayEvents.ts / Questions.ts /
  GatewayClient.ts（状态机）/ GatewayApi.ts（WS 17 端点 + REST 3 端点）/ Models.ts 补 listFrom。
- 测试：fake-ws.ts（FakeTimers/FakeSocket/FakeHttp）+ gateway-client 15 用例 + questions 9 +
  gateway-api 13 + gateway-rest 8；npm test **91/91 绿**；hvigorw assembleHap BUILD SUCCESSFUL。
- 关键实现口径：响应帧 `kind`/请求帧 `type`；requestId 在 data（顶层双兜底）；Bearer 头+单子协议
  'dsh-mobile-v1'（@ohos 配不了 dsh-auth 双子协议，配对走 REST pairings/exchange）；
  连接代数 attempt 防迟到 catch 覆盖；READY 掉线才退避（1,2,4,8,16,30 封顶），hello 归零 index。
- 偏差记录：Android 的 authFailed 态是死字段未实现；onDone 不看状态一律重连较粗糙，鸿蒙版
  改为语义清晰版（重连中掉线 CLOSED 终止），PORT-MAP 已记。

## 阶段 1 历史装配层（2026-11-15）

- core 新增：ToolCall.ts（ToolCallInfo/措辞表/toolSummary/toolResultText/RawToolCall/extractToolCalls）、
  HistoryPage.ts（SessionEvent/DeliverableFile/ChatMessage/HistoryPage.fromEvents）。
- GatewayApi 补 history()（history 帧，maxMessages/beforeSeq 翻页）与 subagentHistory()
  （REST GET /chat/sessions/{lead}/subagents/{sub}/messages）。
- 测试：history-page.test.ts 11 用例 + gateway-api 补 2 用例；npm test **104/104 绿**；
  hvigorw assembleHap BUILD SUCCESSFUL。
- 真 bug 修复：flushGroup 曾把 items 持有的同一数组引用 length=0 清空（安卓是
  List.unmodifiable 拷贝），鸿蒙版改 slice() 拷贝——历史分组全空只剩首条会话的场景。
- run_code 短语顺序：INNER_TOOL_ACTIONS 表序 bash 先于 grep（安卓元组表同序），测试期望已对齐。

## 阶段 1 收尾批次（2026-11-15）：hosts/models_view/permissions/projections/release_check

- core 新增 6 文件：Hosts.ts（FNV-1a BigInt 64 位 + DSH1 宽容解码 + 列表纯操作）、
  ModelsView.ts、Permissions.ts、Projections.ts（轨迹分组 + 服务端投影）、
  ReleaseCheck.ts（纯解析，HTTP 留 entry）。
- platform.dart/dlog.dart 无 core 对应物（MethodChannel/文件日志 → 阶段 4 entry 层
  platform/*.ets + debug.ets（hilog）），PORT-MAP 已标 ☐。
- 测试：hosts-models-permissions.test.ts 12 用例 + projections-release.test.ts 8 用例；
  npm test **123/123 绿**；hvigorw assembleHap BUILD SUCCESSFUL。
- 教训：trajectoryOf 断言踩「垫底=排最后」（安卓 `aUnknown ? 1 : -1`）与
  other 类事件收录（turn 99 组存在）两处期望写反；raw 是普通对象非 Map。

## 阶段 2 平台层 + 连接流（2026-11-15）

- platform/*.ets 四件：WsTransport（@ohos websocket；header 小写 + protocol 单值 +
  settled 防竞态）、HttpTransport（@ohos http；响应头小写；PATCH 枚举缺失字符串透传
  待真机验证）、PlatformBridge（ArkTimers/timeZoneId/PrefsStore preferences 单例）、
  Dlog（hilog；core 层禁 import @kit，AGENTS.md §7 那句「封装在 ets/core/debug」
  已随本提交修正为 platform/Dlog）。
- ui/theme.ets：design-tokens.md 全量翻译（DsPalette/DsColors 语义别名/DsTypography/
  DsSpacing），补 msgPad=30。
- EntryAbility：PrefsStore.init + 深浅色（mediaquery 官方口径，ApplicationContext 无
  getColorMode 实测）；pages/ConnectView.ets 连接页三级路径全功能；pages/Index.ets
  根路由 boot（自动连接）→ connect → chat。
- 编译修复 10 错（BusinessError 导入/mediaquery 方案/WsTransport 签名对齐 core 接口/
  Scroll 外包/http 无 PATCH 成员/header Object 收敛/TextDecoder 解 ArrayBuffer）。

## 阶段 2 对话页（2026-11-15）

- core/ChatStore.ts：chat_state.dart 全语义（send 乐观上屏 + ensureMobileWorkspace
  预建手机工作区、流式收束、committed assistant/user 分支防抖重拉 800ms、loadOlder
  翻页去重 + justLoaded 标记、isCurrent 空态防串台）；GatewayClient 补 getState()/
  applyState 统一状态出口；GatewayApi 补 createWorkspaceRest/renameWorkspaceRest。
- pages/ChatView.ets + components/{MessageList,Composer,SessionsDrawer}.ets：
  顶栏/空态问候/消息气泡（86.4% 宽）/流式文本/过程组短语行/错误条/输入发送停止/
  分组会话抽屉（覆盖式简化，推挤动画阶段 4）。ChatStore.changed() 递增 version
  驱动重渲染。
- 测试：chat-store.test.ts 18 用例（时序铁律固化进文件头：先发起动作→注入应答帧
  （respond 自动读 lastRequestId）→await；`new DshSession()` 无参会把 undefined
  传进构造器炸 'in' operator，必须 null）；npm test **141/141 绿**；hvigorw
  assembleHap BUILD SUCCESSFUL；docs-check 全绿。
- 教训：FakeHttp 同步出队——REST 请求发出前必须先 push 应答；防抖计数要把 READY
  心跳 timer 算进基线。

## 阶段 3：Markdown 渲染 + 轻量 LaTeX（2026-11-16）

**交付**（用户拍板：公式首版就上不降级）：

- core 四件（node 直测，md-parser.test.ts 22 用例）：
  `MdParser.ts`（块级：围栏/#/hr/引用/列表+任务项 normalizeTaskLists 口径/表格对齐行/块公式/段落）
  `MdInline.ts`（行内：code/bold/italic/strike/link/裸 URL 最早匹配优先，snake_case 不误判）
  `LatexLite.ts`（递归下降 \frac/\sqrt/^/_/\text + SYMBOLS ~90 项；splitLatex 切 $..$/$$..$$）
  `SimpleHighlight.ts`（PY/JS/GO/SQL/BASH 关键词 + str/num/comment/kw 四类 token）。
- UI 五件：`components/md/{MdView,MdCodeBlock,MdTable,MdLatex}.ets` + theme.ets 补 syn*/md* token；
  MessageList.ets 助手正文接 MdView（空文本仍走占位 Text 防 ForEach 高度塌陷）。
- 链接外跳：openExternal → Want action viewData startAbility，失败静默（安卓 externalApplication 同口径）。

**回归**：npm test 170/170；hvigorw assembleHap BUILD SUCCESSFUL；package.sh 双闸门通（dist 804KB unsigned）。

**偏差**（PORT-MAP 已记）：高亮四类简化/流式光标不闪烁/表格下载展开延后/☑☐ Unicode/HTML 纯文本化。

**编译坑**（ArkTS 严格）：theme 缺 h1/h2 定义；SimpleHighlight LANG_KW Map 泛型 string→string[]；
MdTable 属性名 align 撞框架 `.align()` → aligns；Font.size 是 Length 联合类型，算术要 `as number`；
Flex 链式 .alignItems 不存在（构造参数里传）。

## 阶段 4：全功能对齐（2026-11-16）

**第一批 工具折叠组 + HITL 全链**：core/HitlStore.ts（挂起表 callId/approvalId 全连接、sessionQuestions/sessionApprovals 过滤、on*Requested/Resolved 摘卡、answerQuestion/cancelQuestion/decideApproval(api)）+ components/ToolBlock.ets（摘要行 phraseText 单行省略/展开逐条 ✓✗ phrases join/详情 prettyArgs 值截 200/bash 走 MdCodeBlock）+ components/HitlPanel.ets（审批卡 settingsWarnBg ⚖/提问卡 chipSelectedBg/单选清旧/自定义回答 canSubmit）；ChatStore 接线 hitl 四事件分支 + 三动作转发 + pendingQuestions/pendingApprovals getter；ChatView 挂 HitlPanel。

**第二批 composer 全家**：core/Files.ts（GatewayRoot/GatewayEntry/ResolvedFile）+ GatewayApi roots 四件 REST（listRootsRest/listEntriesRest/resolvePathRest/readFileBytes）；ChatStore send(text,imagePart?,mode)/runCommand/sendWithImage/regenerateAt/setPermission(currentPermission getter)；Composer.ets 重构（发送键三态/命令补全缓存切会话失效/`@` 文件补全多根下钻/图片 chip 8MiB/权限 chip）；PhotoPicker 走 platform/ImagePick.ets。

**第三批 收图渲染**：core/ImageRef.ts（DsImageRef attachment|handoff/cacheKey/imageRefsOf/handoffRefOf）+ core/ImageFetcher.ts（进程内字节缓存不淘汰+EMPTY 校验）+ components/ImageTile.ets（loading/error/重试/点按全屏 coverOpen；createImageSource→createPixelMap）；MessageList 用户气泡图片组+助手 handoff 图。Transport HttpResponse 加 bodyBytes（@ohos http ArrayBuffer 直读）。

**第四批 五面板 + 模型切换**：core/Projections.ts 补 chatStatsOf（七键）+ components/ProjectionSheets.ets（Stats/Trajectory/Team/Todo 四 bindSheet）+ components/ModelSheet.ets（分组折叠/effort chips/确认 selectModel→parseSelectModelReply）；ChatView ⋮ 溢出菜单五项 + bindSheet 挂载。

**第五批 设置页**：pages/SettingsView.ets（连接只读 stateLabel/deviceLine（getServerDevice 代理）/外观 themeChip 三档（system/light/dark 写 AppStorage dshThemeMode+PrefsStore）/发送 sendChip queue|steer（Composer 读 dshBusySend 传 send mode）/关于 appVersion()+检查更新 fetchLatestRelease（ReleaseCheck Gitee→GitHub 落级，8s 超时）/断开连接 confirmDiscard 清凭证）；Index settings 路由+applyTheme（dshThemeMode 应用到 dshDark）+ SessionsDrawer 底部设置入口。

**第六批 消息操作/命令卡/文档页**：platform/Tts.ets（CoreSpeechKit zh-CN/person 0/online 1，音量语速走 extraParams）+ platform/Share.ets（Want sendData）+ components/MessageActions.ets（复制/喜欢/朗读 hint/分享/⟳ regenerateAt）；MessageList commandCard builder（role='command' 本地命令卡 ⌨ ✗ danger）+ fileCard builder（.md 点开 bindContentCover）+ pages/MdDocViewer.ets（gatewayResolvePath/readFileBytes→MdView，KB/MB caption，失败重试）。

**500 行合规拆分**：core/ChatActions.ts（runCommandIn/regenerateAtIn/cancelTurnIn/setPermissionIn 收 store 参数）→ ChatStore 450 行；GatewayEvents.ts 收编 eventFromFrame（十一支事件映射纯函数）→ GatewayClient 473 行；components/PermissionSheet.ets（权限 sheet 组件化，aboutToAppear 拉清单）→ Composer 423 行。另拆 core/MobileWorkspace.ts（ensureMobileWorkspace/prepareSessionFor/oldestSeqOf）、core/ChatLabels.ts（四个 label 纯函数）、HistoryPage.mergeOlderMessages。

**测试**：npm test 179/179 全绿（chat-store 22/22 含 sendWithImage/runCommand/权限 NO_SESSION）；**根因教训**：全量测试卡死=拆分时 setPermission 丢 NO_SESSION 校验发空 sessionId 帧等 30s 超时——`import test, { after } from 'node:test'` 收口 dispose + --test-name-pattern 逐用例定位。hvigorw assembleHap BUILD SUCCESSFUL（唯一 WARN=已知 PATCH 枚举透传）。

## 阶段 5：真机签名装机与端到端打通（2026-11-16）

**签名材料就绪**：本机 JDK17 `keytool` 生成 ECC 密钥库 `harmony/signing/dsh-chat-harmony.p12`（alias `dsh-chat-harmony`、secp256v1/SHA256withECDSA、9125 天）+ CSR；用户在 AGC 办回调试/发布证书 `.cer`、两份 `.p7b` Profile、`agconnect-services`。`signing/` 整个目录 `.gitignore` 拉黑。命令口径见 `harmony/docs/RELEASE.md`。

**装机链路打通**：`hvigorw assembleHap` → `hap-sign-tool sign-app -mode localSign` 签出 debug hap（~1.43MB）→ `hdc shell bm uninstall -n com.dsh.dshchat` → `hdc install` → `hdc shell aa start -a EntryAbility -b com.dsh.dshchat`。DSH1 导入（REST 配对路径，不走 `dsh-pair` 双子协议）→ 连接成功进对话页，顶栏/空态/设备名/权限 chip/免责声明全渲染。

**四个阻塞性 bug（真机定位 + 修好 + 复验）**：

1. **时区错传**（`platform/PlatformBridge.ets:28`）：`new Intl.DateTimeFormat().resolvedOptions().timeZone` 在 ArkTS 运行时给出 `America/Chicago`。改走 `i18n.getTimeZone().getID()`（`@kit.LocalizationKit`），失败降级 Intl 再回 `'UTC'`；真机 REST 读回 `clientTimeZone = Asia/Shanghai`。
2. **流式事件读不到 payload**（`core/GatewayEvents.ts` `eventFromFrame`）：真实 event 帧的载荷在**内层 `data.data`**（安卓 `gateway.dart:219` 同口径），原实现直接把外层 `data` 当 payload → `MessageDelta` 取到空 text → 正文空白。修法：内层优先、退回外层，并统一剥 `chat.` 事件名前缀（bridge `normalizeDshEvent` 会加，测试桩不加），`payloadSessionId` 同样两级取值。
3. **ArkUI 观察失效**（`pages/ChatView.ets`、`components/{MessageList,Composer,SessionsDrawer}.ets`）：`version` 已递增、`store.messages` 已有数据，界面仍停在空态——ArkUI 只对 build 期间读到的 `@State`/`@Prop` 建依赖，`if (this.isEmpty())` / `ForEach(this.messages())` 直读 store 普通成员永不重新求值。统一改成「setNotify 回调里把派生值抄进 `@State` 快照 + `@Prop @Watch('syncVersion') version`」。
4. **Markdown 渲染整进程崩溃**（`components/md/*.ets`）：发消息后进程静默消失。抓栈靠 `hilog -G 16M` 扩容 + `hilog -r` 清空 + 复现 + `grep -iE 'JsError|Stacktrace|TypeError'`，拿到 `Cannot read property labelPrimary of undefined` @ `MdView.ets:168`。根因是 MdView 用了 `private get c(): DsColors`（getter），`@Builder`/`ForEach` 生成器里取到 undefined；六个文件统一改成普通方法 `private c()` + `this.c().`。

**验收**：发「1+1等于几？只回答数字」→ 用户气泡 + 助手 Markdown（reasoning 折叠块、正文、⧉/👍/🔊/⤴/⟳ 操作行）全渲染，进程稳定不退出；`npm --prefix harmony/test test` 179/179 全绿。

**排障方法论**（写进 PORT-MAP §3 坑位索引，共 7 条）：真机 hilog 取不到应用域日志，protocol 层排障靠 `mock-bridge`（`ws` 包 + `handleProtocols: dsh-mobile-v1`）抓 App 实际帧、REST 直查 bridge 会话历史；`uitest inputText` 是追加语义；设备上无 `sed -i`。

## 阶段 5 第二批：全功能冒烟修复（2026-11-16）

真机逐项冒烟，发现并修掉七个功能缺口（全部装机复验）：

1. **会话抽屉结构错位**（`components/SessionsDrawer.ets`）：早前脚本改文件留下残迹，`@Builder sessionRow` 里混进了 `Divider` + 「设置」Row，且标题 Row 的 `.onClick` 链挂到了设置行上 —— 界面上每个会话后面都多出一行「⚙️ 设置 ›」，标题行反而点不动。修法：设置行移出 `sessionRow`、放到 `build()` 的 List 之后（全抽屉唯一入口），修饰链归还标题 Row。
2. **设置页返回退应用**（`pages/SettingsView.ets` + `pages/Index.ets`）：`getRouter().back()` 在 `@State route` 条件渲染结构下会退出整个 App。改成 `onBack` 回调，Index 里 `this.route = 'chat'`。
3. **⋮ 溢出菜单不弹**（`pages/ChatView.ets`）：`bindSheet` 与 `bindContentCover` 挂在同一节点，后者不生效。改成 Stack 内联 `if (this.menuOpen)` 遮罩 + 菜单，走 `justifyContent(FlexAlign.Start)` 定位。
4. **模型面板永远「加载中…」**（`components/ModelSheet.ets`）：`load()` 没有挂载点，补 `aboutToAppear()`。
5. **命令补全不弹**（`components/Composer.ets`）：`ensureCommands()` 无调用点，`updatePanel()` 开头补一次（按会话懒加载，切会话失效）。
6. **切权限档位不生效**（`core/ChatActions.ts` + `components/PermissionSheet.ets` + `components/Composer.ets`）：`permission` 帧只改服务端投影、不产生 chat 事件，客户端不会自己刷新。`setPermissionIn` 成功后链 `reloadHistory()`；PermissionSheet 成功后写 `this.current` 并把「权限已切换为「X」」经 `onDone` 传给 Composer 的 `permHint` 提示条。
7. **交付文件卡缺失**（`components/MessageList.ets`）：import 了 `MdDocViewer` 却从未挂载，`role === 'files'` 也从无渲染分支。补 `fileCard(m)` builder（📄/📎 按 `isMarkdown(path)` 选，标题退回 `f.path`，描述透传）+ `.bindContentCover(this.docOpen, this.docViewer())` 站内查看 `.md`。

**输入框对齐官方**（`components/Composer.ets`）：底部行改为「圆形 ＋」→「🛡 权限 ≤200px ⌄」→ 右侧 44×44 发送/停止圆键；占位文案改官方口径「发消息或创建任务，/ 调用指令，@ 文件或对话」。用户明确要求不做识图与模型选择入口，故不摆。

**冒烟已验证**：主对话页（气泡/Markdown/操作行）、会话抽屉（分组+切会话）、设置页六分区、权限四档切换（chip 与面板 ✓ 同步）、📊会话统计、🧭运行轨迹（轮次/事件节点可展开）、🧠智能团队、✅待办任务、🎛️调整模型（六分组 + effort chips + 确认切换）、`/` 命令补全列表、发消息端到端（reasoning + 正文）。

**测试**：`npm --prefix harmony/test test` 179/179；`setPermission` 用例补 `respondHistory` 应答（修复后多了一次重拉 history）。

## 阶段 5 第三批：全功能冒烟修复与体验对齐（2026-11-16）

**bug⑫ HITL 提问卡不渲染 / bug⑬ 选项选中态不更新**：`pages/ChatView.ets` 原给 `HitlPanel` 传 `store.pendingQuestions`（直读 store 普通成员，ArkUI 观察失效）→ 改为 `@State questionsView/approvalsView` 快照，在 `st.setNotify()` 与 `aboutToAppear()` 同步。`components/HitlPanel.ets` 原用 `private selected: Map<string,string[]>` + `version++` —— ArkUI 对 Map 内部变更不建观察依赖，chip 样式表达式不重新求值（真机：点选项无高亮、提交键恒灰）→ 删 Map 与 version，改两个 `@State` 数组 `picked` / `customs`（每项编码 `qid + '\u0001' + label`），`toggleOption` 整体替换数组（多选取并、单选替换、再点取消）。真机闭环：提问卡渲染 → 点「蓝色」高亮、提交键变蓝 → 提交 → bridge 收答案 → 助手回「你选了**蓝色**，已经记下来了。」+ Markdown 表格。

**bug⑭ 审批卡不出现 / 提卡提交后不消失**：`components/HitlPanel.ets` 的 `questions` / `approvals` 是普通成员，只在组件首次创建时赋值，父层 `@State` 换新数组不会重建子组件 → 改 `@Prop`。bridge 审批链路经 ws 探针确认真实可用（`chat.approval.requested {sessionId,approvalId,toolName,risk}` / `chat.approval.resolved`）。

**键盘遮挡输入框发送键**：`entryability/EntryAbility.ets` 的 `onWindowStageCreate` 原只 `loadContent`，默认 OFFSET 避让整页上移压住 composer → 在 `loadContent` 回调里 `getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)`（`import { window, KeyboardAvoidMode } from '@kit.ArkUI'`）。RESIZE 压缩页面高度，`Column(height 100%)` 随之收缩、List 的 `layoutWeight` 吃多余空间。真机验证：键盘弹出后整页 1355px，＋/🛡 权限/↑ 全部可见可点，键盘下发消息正常收回复。

**连接历史不保存**：`pages/ConnectView.ets` 的 `enterWith()` 只写 `dsh.credentials` 不写 `dsh.hosts`（构造了 `DshHost` 却从未 persist）→ 按安卓 `connect_page.dart:55` 口径补 `host.id = stableId(baseUrl); this.persistHosts(upsertHost(this.hosts, host));`。真机验证：设备偏好文件出现 `dsh.hosts` 条目（id `0e184924befd1b3a`），`aa force-stop` 后重启自动连接直达对话页。

**发送键配色**：原禁用态 `inputFill`（浅色主题纯白）+ `labelTertiary` 浅灰箭头几乎不可见 → `ui/theme.ets` 新增 `sendDisabledBg`（亮 `#EBEEF2` / 暗 `c800`）与 `sendDisabledFg`（亮 `c500` / 暗 `c400`）；可用态实心 `brand` + `onBrand` 白箭头、字号 20 加粗、去描边。截图比对与官方一致。

**权限中文化**：`components/Composer.ets` 的 `syncVersion()` 直接把投影 ASCII 值上屏（显示 `workspace-write`）→ 改 `this.permView = permissionLabelOf(perm)`（`core/Permissions.ts:144` 已有映射：仅可查看 / 工作区读写 / 完全权限 / 自动审查）。

**第二版输入框与官方对齐**（`components/Composer.ets`）：TextArea 与底部按钮行包进同一外层 `Column`，该 Column 承担 `inputFill` 底色 + `borderRadius(24)` + `inputBorder` 描边 + `padding({left:10,right:10,top:6,bottom:8})`，即「＋ / 🛡 权限 chip / 圆形 ↑」全在同一个圆角悬浮输入框内部；TextArea 透明底、`constraintSize({minHeight:44,maxHeight:120})`。用户明确要求不做识图与模型选择入口。

**自动贴底**：`components/MessageList.ets` 的 `syncVersion()` 末尾 `setTimeout(() => this.jumpToBottom(false), 30)`，新消息与流式增量后自动滚到底。

**测试**：`npm --prefix harmony/test test` 179/179；`bash scripts/ci/docs-check.sh` 通过。

## 阶段 5 第四批：命令卡保活、会话列表待回答标记、REST transport 修复（2026-11-16）

**bug⑮ 命令卡被重拉历史冲掉**：真机发 `/help`、`/permission` 等斜杠命令后看不到 ⌨ 命令卡。根因是 `core/ChatStore.ts` 的 `reloadHistory()` 用 `self.messages = page.items` 整体替换消息表，而本地注入的命令卡（`role='command'`、`seq=-1`）不在服务端历史里；`core/ChatActions.ts` 的 `runCommandIn` 成功链恰好会调 `reloadHistory()`。修法对齐安卓 `chat_history_actions.dart:36-40`：替换前先收集 `role === 'command' && seq < 0` 的卡片，再 `[...page.items, ...localCards]`。真机验收：`/help` 渲染 `⌨ /help ✗ The command is not available for this session.`，`/permission` 弹出命令补全面板。

**会话列表「待回答 / 待审批」标记**（用户反馈「电脑端显示有待回答 手机上不显示」）：bridge 的 `sessions` 列表只对**挂起审批**下发 `pendingInteraction:'approval'`，挂起提问不下发；WS 连接也不会补推其它会话的 HITL 帧。因此标记改为双来源：
- 当前连接实时收到的挂起项 → `core/HitlStore.ts` 的 `pendingQuestions` / `pendingApprovals`；
- 其它会话 → 新增 `core/GatewayApi.ts` 的 `countPendingQuestions()` / `countPendingApprovals()`（REST `GET /chat/sessions/{sid}/questions` 与 `/approvals`）逐会话探测，结果存 `core/ChatStore.ts` 的 `pendingMarks`，对外只暴露 `pendingMarkOf(sessionId)`（实时挂起表优先，退回探测结果）。
- UI 在 `components/SessionsDrawer.ets`：`@State marksView: string[]`（编码 `id + '\u0001' + mark`，**ArkUI 不观察 Map 内部变更**），`sessionRow` 标题后加橙色「待回答」胶囊或品牌色描边「待审批」；`aboutToAppear()` 里 `loadSessions()` → `refreshPendingMarks()` → 再 `syncVersion()`（不等待会读到打开时的空快照）。
- 新 token：`ui/theme.ets` 的 `markQuestion`（暗 `#FFB454` / 亮 `#B26A00`）与 `markQuestionBg`（暗 `#26F5A623` / 亮 `#1AF5A623`）。
- 真机验收：抽屉「手机会话」组里「询问晚餐选项」行右侧显示橙色「待回答」胶囊（截图 `harmony/build/smoke/mark.jpeg`）。

**严重缺陷：自动连接未注入 HTTP transport**（顺带发现）：`pages/Index.ets` 的 `autoConnect()` 里 `new GatewayApi(gateway, null)` 把 REST 传输传成 null，导致**自动连接（重启后走的那条路）下所有 REST 功能失效** —— 附件上传、图片交接、授权根列表、文件全文读取、挂起项探测全部 `NO_TRANSPORT`。修法：注入 `new HttpTransportImpl()`（`ConnectView` 的两条路径本来就注入了，只有 Index 漏）。

**测试**：`npm --prefix harmony/test test` **181/181 全绿**，新增用例「refreshPendingMarks：REST 探测挂起项 → pendingMarkOf 返 question/approval」（覆盖三会话三分支 + 实时挂起表优先；**FakeHttp 是队列式应答，questions 先全发、approvals 在 questions 回来后才发，应答顺序必须按此排**）。

**排障手法沉淀**：真机没有可用应用日志，验证「REST 探测是否跑通」的办法是把计数拼进稳定渲染的 Text（曾把副标题临时改成 `S[ok42/42:1]` 再 `uitest dumpLayout` 读回），确证后清理。

**推挤式抽屉**：真机截图发现抽屉是覆盖式、右侧漏出聊天页 composer 一角，与官方口径不符。按 `docs/design-tokens.md` §4.2 改成推挤式——`pages/ChatView.ets` 把 `chatScaffold()` 包进 `Column().width('100%').height('100%').translate({ x: this.drawerOpen ? '80%' : '0%' }).animation({ duration: 240, curve: Curve.EaseOut })`（百分比位移，不依赖 screenW）；`components/SessionsDrawer.ets` 宽度 `78%` → `80%` 对齐官方 `drawerWidth = 288dp / 360dp`。真机截图 `harmony/build/smoke/drawer4.jpeg` 与官方 `ref/verify2-drawer-push.png` 形态一致（官方同样露出输入框一条）。抽屉点遮罩关闭、点会话行切换均正常。

**图片消息气泡（bug⑯）**：真机发图后发现用户气泡没渲染缩略图，而是把 `[Image: source: /abs/.dsh-images/<64hex>.png]` 整段当纯文本显示、上方还有一整段 bridge 注入的说明。根因：图片走纯文本模型时，`user/message` 的 content 是**两个 text 块**（原文 + 说明+占位），没有 `type:'image'` 块 → `ContentParts.from()` 取不到 images、说明也原样进 text。修法：`core/Content.ts` 新增 `stripBridgeImageNote()` 逐行滤掉以 `🖼` / `[Image: source:` 开头的行（不能贪婪整段匹配，会吃掉用户原文）；`core/HistoryPage.ts` 装配时 text 存清洗结果、原文留新的 `rawText` 字段；`components/MessageList.ets` 用户气泡（原先只有 `userImages(m)`）与助手气泡统一用 `handoffRefOf(rawText !== '' ? rawText : text)` 挂 `ImageTile` 缩略图。新增 2 条 `stripBridgeImageNote` 用例 → 183/183 绿。

## 阶段 5 验收清单（真机逐项，2026-11-16 结项）

**已真机验收通过**（截图/文本树为证，见 `harmony/build/smoke/`）：

| 功能 | 验证方式 |
|---|---|
| DSH1 导入 → 连接 → 进对话页 | 导入区粘贴 463 字符配置 → 「导入并连接」→ 空态问候/Mobile device/权限 chip/免责声明全渲染 |
| 连接历史落盘 + 重启自动重连 | 偏好文件出现 `dsh.hosts` 条目；`aa force-stop` 后重启直达对话页 |
| 发消息 → 流式回复 → Markdown 渲染 | 「1+1等于几」→ 用户气泡 + reasoning 折叠块 + 正文 + ⧉👍🔊⤴⟳ 操作行 |
| 会话抽屉 | 分组「手机会话」、点行加载历史并切标题、待回答橙胶囊、推挤式位移 |
| 五面板（统计/轨迹/团队/待办/模型） | 逐面板展开，轨迹节点可展开，模型面板六分组 + effort chips + 确认切换 |
| 设置页六分区 + 检查更新 | 连接/设备/外观/发送/关于/协议全渲染，「发现新版本 v1.0.17」 |
| 权限面板切档 + 中文化 | 点「仅可查看」→ chip 变「🔒 read-only」→ 提示条；chip 显示中文档位 |
| 命令补全 + 命令卡 | 输入 `/` 弹 6+ 命令；`/help` 渲染 ⌨ 卡片；`/permission` 弹面板 |
| HITL 提问卡全链路 | 卡片渲染 → 点选项高亮 → 提交键激活 → bridge 收答案 → 助手回「你选了蓝色」+ 表格 |
| 键盘避让 | 弹键盘后整页 1355px，＋/权限/↑ 全可见可点，键盘下发消息收回复 |
| 图片发出（bridge 侧） | 相册选图 → chip「🖼 IMG_1657.png ✕」→ bridge 存到 `.dsh-images/<hex>.png` → 委派识图子代理 |
| 自动贴底 | 新消息/流式增量后自动滚到底 |

**已离屏验证、待真机复验**（代码面已确认，缺一次装机目视）：

| 项 | 离屏证据 | 待验内容 |
|---|---|---|
| 文件卡（deliverables/presented） | 用真实事件流 `build/smoke/deliv-history.json`（33 事件，含 seq 25 的 `deliverables/presented`）跑 `HistoryPage.fromEvents` → items 5 条，`files` 卡落位正确，`hello-deliverable.md` 的 path/name/description 全对 | 真机看卡片样式 + 点 .md 能否打开 `MdDocViewer` |
| 图片缩略图（bug⑯） | 183/183 含 2 条 `stripBridgeImageNote` 用例；事件流证明 content 是两个 text 块 | 用户气泡应只剩原文 + 「看不到图...」说明段消失 + 出现缩略图 |
| 审批卡（bug⑭） | ws 探针抓到 `chat.approval.requested`/`resolved`；`HitlPanel` 已改 `@Prop` | 真机触发一次升级审批，看卡片出现/回答后消失 |

**尚未冒烟**：深色模式整屏；`@` 引用文件；历史分页（`mergeOlderMessages`）；断线重连退避（1→2→4→8→16s）；检查更新跳转。

## 阶段 5 第五批：设备恢复后真机复验（2026-11-16 17:20）

设备（3AX0225103005398）恢复后逐项复验第四批遗留三项 + 两个平台层通点，**过程中又抓到四个真机级 bug**：

| 项 | 结果 | 说明 |
|---|---|---|
| 文件卡渲染 | ✅ | 会话「用present工具交付测试文件」→ `📄 hello-deliverable.md` + 描述「交付测试文件，内容为…」渲染在 assistant 收尾正文之后（落位正确） |
| 文件卡 → 文档页 | ✅ | 点卡片打开 `MdDocViewer`：标题 `hello-deliverable.md`、`1 KB`、正文「交付测试：文件卡验收用」；点 `‹` 返回会话 |
| 图片缩略图（bug⑯） | ✅ | 用户气泡只剩原文「发图测试」，bridge 注入的「🖼️ 图片 1…」说明段与 `[Image: source: …]` 占位都不显示，缩略图正常渲染原截图 |
| TTS 朗读 | ✅ | 点 🔊 → 提示「正在朗读」、图标变 ⏹ 品牌色；约 20s 读完自动复位 |
| 系统分享面板 | ✅ | 点 ⤴ → 弹出系统「分享」面板（文本预览 + 华为分享/微信/电子邮件/UC浏览器/复制/小艺帮记/打印） |
| 推挤式抽屉 | ✅ | 抽屉宽 864px（80%），聊天页整体右推，「⚙️ 设置」行仅在末尾一处 |

**本轮修的真机级 bug（4 个）**：

1. **文档页顶栏被状态栏盖住**（`pages/MdDocViewer.ets`）：`bindContentCover` 全屏模态内容从屏幕顶开始，不含系统安全区，标题与 `‹` 返回键压在状态栏下（真机截图实证）。修法：`aboutToAppear` 里 `window.getLastWindow(...)` → `win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)` 取 `topRect.height`，`px2vp` 转 vp 存 `@State topInset`，根 `Column` 加 `.padding({ top: this.topInset })`。
2. **`/api/v1/image-handoff` 缺 sessionId**（`core/GatewayApi.ts` + `core/ImageFetcher.ts`）：bridge `attachmentsAndImage()` 对该路由校验 `if (!name || !sessionId) throw ApiError(400,'BODY_INVALID','name and sessionId query parameters are required.')`，原实现只传 `name` → 恒 400，真机表现「图片加载失败」。修法：`fetchImageHandoff(name, sessionId)` 双参，`ImageFetcher.fetch` 把已有的 `sid` 一起传下去（`fetchAttachment` 早就传了 sessionId，交接图漏了）。
3. **`createImageSource` 传 Uint8Array 返回 undefined**（`components/ImageTile.ets`）：SDK 重载是 `createImageSource(buf: ArrayBuffer)`，传 `Uint8Array` 类型不符 → 返回 undefined → `Cannot read property createPixelMap of undefined`。修法：`image.createImageSource(bytes.buffer as ArrayBuffer)` + 判 undefined 走「解码失败」分支。
4. **TTS 建引擎参数不合法**（`platform/Tts.ets`）：`{language:'zh-CN', person:0, online:0}` 真机报 `1002300005 create engine failed`；加 `extraParams.style/locate/name` 报 `202 this is not systemCap`（extraParams 未声明 key 全校验失败）。修法：`probeParams()` 依次试 `(online, person)` 组合（`0/1` × `person 0/1`，外加 `en-US` 兜底），首个成功即缓存；全失败才回「朗读暂不可用」。

**顺带清理**：`MessageActions.ets` 去掉调试期把 `lastTtsError` 拼进提示的代码（改回固定文案「朗读暂不可用」）；`platform/Tts.ets` 的 `lastTtsError` 不再 `export`，改由 `ttsLastError()` 读取（排障用）。183/183 用例全绿。

## 阶段 5 收尾：TTS / 分享面板代码修正（设备离线期，2026-11-16）

真机 hdc 掉线后不空转，把两个**尚未冒烟**的平台层按 SDK 声明逐一核对，修掉两处会在真机上出问题的实现：

**TTS（`platform/Tts.ets`）**：原实现 `createEngine` 后直接 `speak`，从未调 `setListener` —— SDK 明确「`setListener` 必须先于 `speak`，否则 onStart/onComplete/onError 一律收不到」，真机表现会是「能出声但 UI 不知道朗读何时结束、异常静默」。同时 `CreateEngineParams.online` 的原值是 `1`，而 SDK 注释是 **0=在线、1=离线**，被当成布尔用反了 → 改 `0`（在线音色）。重写后：完整 `SpeakListener`（onStart/onComplete/onStop/onError 都按 requestId 过滤过期回调）、`watchSpeaking()` 供 UI 切「朗读中/朗读」图标、`isSpeaking()` 走 `engine.isBusy()`、新增 `shutdownTts()` 并在 `entryability/EntryAbility.ets` 的 `onDestroy` 调用（引擎是进程级单例，不释放会长期占音频焦点）。

**分享（`platform/Share.ets`）**：原实现只发 Want `ohos.want.action.sendData` + `text/plain`，在部分机型不会弹系统分享面板。改为**首选 ShareKit**：`new systemShare.SharedData({utd: UniformDataType.PLAIN_TEXT, content})` → `new systemShare.ShareController(data).show(context, {selectionMode: SelectionMode.SINGLE, previewMode: SharePreviewMode.DEFAULT})`；拿不到 ShareKit 时退回原 Want 隐式拉起（两级兜底）。

两处均 `bash scripts/package.sh --no-test` 编译通过，183/183 用例不受影响（平台层不进 node 测试）。

**朗读按钮接上状态**（`components/MessageActions.ets`）：光有 `watchSpeaking` 不接 UI 等于没做（本仓 `私有方法只定义没调用` 坑）。改为 🔊 与 ⏹ 双态——说话中显示 ⏹ 且用品牌色，再点一次 `stopSpeak()`；朗读自然结束/出错时由观察者回调复位。观察者**用列表不用单槽位**：聊天页每条助手消息都挂一个 `MessageActions`，单槽位会被最后挂载的覆盖，其余实例图标永不复位；组件 `aboutToAppear` 注册、`aboutToDisappear` 注销（传同一个函数引用）。

**真机行为待设备恢复后验证**：🔊 点一次应出声且图标变 ⏹、读完自行复位、再点一次能中止；⤴ 点一次应弹系统分享面板。

## 阶段 5 第六批：主题切换修复 + 会话列表时间优先 + 应用市场更新（2026-11-16）

用户报「点深色不变」，加上两条新需求（会话列表排序口径、检查更新改走华为应用市场），一批完成并真机验收。

**bug⑰ 切「深色」不生效**（`pages/Index.ets`）：`SettingsView` 的 `themeChip` 只做
`AppStorage.setOrCreate('dshThemeMode', mode)` + `PrefsStore.putString`，但**全工程没有任何监听**——
`applyTheme` 只在 `bindDarkMode()` 的 mediaquery `on('change')` 回调里被调，所以点深色只有 chip 自己变色、整页不动。
修法：`Index` 加 `@StorageProp('dshThemeMode') @Watch('onThemeModeChange')` + 缓存 `sysDark`，
回调里 `applyTheme(this.sysDark)`；`aboutToAppear` 异步读回偏好再重算。
坑：`PrefsStore.getString` 返 `Promise<string | null>`，直接 `?? 'system'` 编译报 10505001，必须进 `.then()`。
真机验收：点「深色」整页转深色，重启后保持。

**会话列表按时间优先 + 超 2 天折叠**（用户口径）：新增纯逻辑 `core/SessionGroups.ts`（`COLLAPSE_AFTER_DAYS = 2`、
`dayBucketOf` 按本地日历天分桶、`groupSessionsByTime` 今天/昨天/更早 + 桶内工作区聚合小节、`visibleRowsOf` 折叠），
`components/SessionsDrawer.ets` 改 `@State groupsView` + `@State earlierOpen`。与安卓「工作区优先」相反，已记 PORT-MAP 偏差。
测试 `harmony/test/cases/session-groups.test.ts` 10 条。真机验收：抽屉「今天 / workspace / 未分组 / 手机会话」多层小节，
底部「更早 28 条 · 展开」↔「28 条 · 收起」。

**检查更新改华为应用市场**（用户要求「不能走 gitee」）：新增纯逻辑 `core/AppUpdate.ts`（结果模型 + 错误码 1009400001~7 映射），
`pages/SettingsView.ets` 改用 `@kit.AppGalleryKit` 的 `updateManager.checkAppUpdate(ctx)` / `showUpdateDialog(ctx)`，
删掉 `ReleaseCheck`/`HttpTransport`/`GITEE_RELEASES_URL` 相关代码；`projections-release.test.ts` 移除 6 个 ReleaseCheck 用例（现 7 条 Projections）。
原因：鸿蒙应用只能由华为应用市场分发，系统不允许自更新。
测试 `harmony/test/cases/app-update.test.ts` 6 条。真机验收：点「检查更新」→「已是最新版本」（调试签名未上架，市场回 0）。

**门禁**：`npm --prefix harmony/test test` → **193/193 全绿**；`bash scripts/ci/docs-check.sh` 通过；`bash scripts/package.sh --no-test` BUILD SUCCESSFUL；签名装机真机验证。
**文档**：`docs/STRUCTURE.md` 登记两个新 core 文件；`AGENTS.md` §11 +3 条坑位；`harmony/docs/PORT-MAP.md` §3 同 3 条详版。

## 阶段 5 第七批：@ 引用面板修复 + 新建会话可选工作目录（2026-11-16）

**两处 @ 面板 bug**（用户反馈「@ 引用不弹面板」）：
- `@` 面板不弹：`components/Composer.ets` 的 `onChanged` 里 `cursor` 还是旧值（`onChange` 先于
  `onTextSelectionChange` 触发，初值 0），`parseAtMentionDraft('@', 0)` 返回 null。修法：`onChanged`
  里先 `this.cursor = v.length` 再 `updatePanel()`；`onTextSelectionChange` 里位置变了才回填重算。
- 面板永远卡「正在加载目录…」：`components/ComposerPanels.ets` 的 `CommandPanel.commands` 与
  `AtFilePanel` 的 `entries/loading/failed/dirPath` 是**普通成员**（父层 @State 换新值不重建子组件）。
  全部改 `@Prop`。
- 下钻 404 拖垮整面板：`Composer.ets` 的 `loadAtEntries()` 裸 `Promise.all` 在多根下一根 404 即整批 reject。
  逐根 `.catch(() => [])` 容错，统计 `okRoots`，全部为空才置失败。

**新建会话可选工作目录**（用户要求「安卓新建会话有默认目录，可选目录」）：
- 新增纯逻辑 `core/SessionLocation.ts`：`SessionLocation(rootId,cwd,label)` + `key` 契约串、
  `locationLabel`（''=根目录）、`recentLocations`（历史会话 (rootId,cwd) 去重保序、跳过无根会话）、
  `locationSubtitle`（优先 cwdAbsolute 退回 rootId）、`parentPath`、`locationChipLabel`。
- 新增 `components/SessionLocationSheet.ets`：默认「手机会话」项 + 最近使用列表 + 授权根逐级浏览
  （空根自动跳到下一个有子目录的根、多根可点标题切换、面包屑「用此目录」）；选中写 `store.pendingLocation`。
- `core/ChatStore.ts` 新增 `pendingLocation: SessionLocation | null`；`core/MobileWorkspace.ts` 的
  `prepareSessionFor` 优先走 `createSessionAt(rootId,cwd)`（会话落「未分组」），失败显式报错不静默回退。
- `pages/ChatView.ets` 空态加「工作目录：…」chip（`@State pendingLocView` 快照 + `locSheet` 面板分支）。
- 真机验收：空态 chip 显示「工作目录：手机会话（默认）」→ 面板列出最近 4 个目录（含绝对路径）→
  浏览授权根自动跳过空 `default-workspace` 落到 `workspace` → 下钻 `.dhs-diff` 选「用此目录」→
  chip 变「工作目录：.dhs-diff」→ 发消息后 REST 确认 `cwd=dsh-Chat / cwdAbsolute=/media/wangke/OFFICE/workspace/dsh-Chat`（另一次 `.dhs-diff`）→ 新建对话后 chip 回默认。

**门禁**：`npm --prefix harmony/test test` → **200/200 全绿**（新增 `session-location.test.ts` 7 条）；
`bash scripts/ci/docs-check.sh` 通过；`bash scripts/package.sh --no-test` BUILD SUCCESSFUL；签名装机真机验证。
**文档**：`docs/STRUCTURE.md` 登记两个新文件；`AGENTS.md` §11 +4 条坑位（`@ 面板/命令面板不刷新`/`@ 下钻整面板报错`/`新建会话没目录选项`/`目录浏览显示空根`）。

## 阶段 5 第八批：挂起提问「寿命随桌面走」对齐（2026-11-16）

**背景**：桥端 56aa14c 改了挂起提问寿命（桌面端 delegate 未决 → 不摘卡、不设超时；只有
delegate 被拒即电脑端不在线，才起 10 分钟自愈），安卓 35f9deb 及配套补了「监听 HitlState、
提问卡按会话过滤、抽屉角标、进会话 REST 补拉挂起提问」。鸿蒙对照跟进（用户选 A 档：必做项
现在做，抽屉角标改由 hitl 表派生那部分延后）。

**鸿蒙原本已对的**：`HitlPanel` 早就按会话过滤（`pages/ChatView.ets:140` 传
`st.pendingQuestions`/`st.pendingApprovals`，`core/ChatStore.ts` 的 getter 最终走
`hitl.sessionQuestions(this.sessionId)`），不是漏项。

**本批补齐（A 档）**：
- `core/HitlStore.ts` 新增 `pendingQuestionSessionIds()` / `pendingApprovalSessionIds()`
  （返去重数组，`indexOf` 判重 —— core 层无 Set 先例）与 `mergeQuestions(incoming)`
  （按 callId upsert；`old.rpcId` 有值且新条目 `rpcId` 为空时保留旧值 —— rpcId 是取消提问的
  关联键；空 callId 直接跳过；有变更返 true）。
- `core/GatewayApi.ts` 新增 `fetchQuestions(sessionId)`：REST `GET …/questions` →
  `JsonAccess.objArr(data,'items')` → `PendingQuestion.fromJson`。**`arr()` 返 `Object[]`
  拿不到字段，必须用 `objArr()`**。
- `core/ChatStore.ts`：`openSession` 在 subscribe 后 `refreshPendingQuestions(s.id).catch(()=>{})`；
  新增 `refreshPendingQuestions(sessionId)`（空串短路 → fetch → merge → 有变才 `changed()`）。
  鸿蒙 HitlStore 是纯数据类没有 listener，不主动 `changed()` 卡片不会出现。
- `core/Questions.ts` 头注释改新寿命口径（delegate 未决不设超时、rejected 才 10 分钟自愈、
  客户端不持超时常量）。

**为什么只做 A 档**：B 档要把抽屉角标彻底改成 hitl 表派生、删掉 `pendingMarks` /
`refreshPendingMarks` / `countPending*` 与 `SessionsDrawer.aboutToAppear` 的逐会话 REST 探测。
桥的 replay 已保证连接期补推，但**不想在没真机取证的前提下拆掉唯一兜底**（代价只是每会话
2 个 REST 请求）。留待后续按实测再定。

**真机取证（本轮实测）**：真实桥 `GET /api/v1/chat/sessions` 返 36 个会话、`pendingInteraction`
全为 `None`；会话「重启后验证提问确认」（`session-c6413d15-…`）的 `/questions` 返
`{"callId":"bridge-97ccedc7-…","state":"continued"}`、`/approvals` 返 `{"items":[]}` ——
正是「WS replay 不补、只有 REST 有」的那一类。装机后进该会话：提问卡「重启验证 / 再次验证：
本轮提问与答案回传是否正常？」带「验证通过 / 验证失败」两个选项与提交键**正常渲染**（由
REST 兜底合流得到），点「验证通过」→ 提交 → 卡片消失、助手回「提问工具（ask_user_question）
调用正常，答案已成功回传 … 验证完成 ✅」。**REST 合流 → 渲染 → 作答 → 摘卡 全链路通。**

**门禁**：`npm --prefix harmony/test test` → **215/215 全绿**（新增 `hitl-store.test.ts` 10 条；
`chat-store.test.ts` +3 条：openSession REST 合流/失败静默/保留 WS rpcId 与空 sessionId 短路；
`gateway-rest.test.ts` +3 条：fetchQuestions 解析/宽容/403）。
**文档**：`AGENTS.md` §11 +2 条（`挂起提问只有 REST 有` / `REST 合流别用 JsonAccess.arr`）；
本文件 §3 同两条详版。

## 阶段 5 第九批：断线重连链修复（2026-11-16）

**背景**：冒烟剩余项「断线重连退避 1→2→4→8→16→30s」。真机实测发现两条真实缺陷 ——
掉线后的重连链会提前终止，以及一次掉线排两次退避；都不是设计意图，安卓无此问题。

**缺陷一：重连链提前终止**。原 `core/GatewayClient.ts` 的 `onDown()` 写
`if (this.disposed || !wasReady) { CLOSED; return; }`，重连的 `connect().catch` 里又写
`if (self.attempt === failedAttempt + 1) { self.state = CLOSED; }` —— 掉线后**只要第一次
重连尝试失败（TCP 拒连 / 握手失败 / hello 超时）就永久 CLOSED**，用户必须重启 App。
安卓 `app/lib/bridge/gateway.dart:303 _onDone()` 是无条件继续退避（只判
`_disposed || _authDead`），只有 `CONNECT_FAIL` 才收口，两端本应同语义。
**修法**：加 `private reconnecting: boolean` + `private scheduleReconnect()`；`onDown` 改三分支
—— `disposed → CLOSED`、`!wasReady && !reconnecting → CLOSED`（**初连失败仍不自动重连**，
安卓同口径）、否则 `scheduleReconnect()`；`scheduleReconnect` 里 `Math.min(1 << backoffIndex,
MAX_BACKOFF_SECONDS=30)`、index 封顶 `MAX_BACKOFF_INDEX=5`；`connect().catch` 里
`isFatal(err)`（只认 `NO_TOKEN`/`PROTOCOL`/`DISPOSED` —— 拒连与握手超时都不算致命）才
`teardown() + CLOSED`，否则接力重排；`onHello()` 里 `backoffIndex=0; reconnecting=false;` 收口。

**缺陷二：一次掉线排两次退避**。真机上 `@ohos.net.webSocket` 一次掉线连发 **error + close
两个回调**，`platform/WsTransport.ets` 只在 timeout 分支做了 `settleOnce()`（而它只清 timeout），
`error`/`close` 两处都直接 `callbacks.onDown(...)` → 状态机对同一次掉线排两次退避，
**1s 档被 2s 档顶掉**（日志实证：`scheduleReconnect delay=1s` 同一毫秒紧跟 `delay=2s`）。
**两层修法**：①`WsTransport.ets` 加 `let downSent` + `claimDown()`，`close`/`error`/`connect`
回调/`timeout` 四处统一走 `claimDown()` 只放行第一次（并补 `[ws] connect callback err=` 日志）；
②`core/GatewayClient.ts` 加 `private downAttempt: number`，`onDown` 里
`attemptOfThisConnection === downAttempt` 直接 return（平台层之外的二次防线）。

**真机验证（本轮全部实测）**：
- 拒绝期探针 `/home/wangke/probe-drop.cjs`（第 1 个连接放行握手 + 发 hello 进 READY，
  6s 后断；之后每个 TCP 都 destroy）→ hilog `[gw] scheduleReconnect delay=` 序列实测
  **1s→2s→4s→8s→16s→30s→30s，每档只排一次**；探针侧 REFUSE 时间戳
  `+15.9 / +18.0 / +22.0 / +30.1 / +46.1 / +76.2s` 与退避档完全吻合，**永不终止**。
- 恢复期探针 `/home/wangke/probe-recover.cjs`（先拒 20s 再放行 + 回 sessions 帧）→ App 在
  30s 档 `[ws] open` → `[gw] state -> 2`（READY）→ 探针侧 `ACCEPT` + `RECV sessions`，
  界面自愈（`ChatStore.onGatewayState` 的 READY 分支 resync 生效，安卓
  `chat_state.dart:387 _onGatewayState` 同口径）。掉线期间界面提示「加载会话失败：连接已断开」，
  重连成功后由 `loadSessions()` 清 `lastError`。

**门禁**：`npm --prefix harmony/test test` → **218/218 全绿**（`gateway-client.test.ts` 改
「重连中掉线继续接力 2s（不终止）」+ 新增「连续失败 1→2→4→8→16→30→30 七档永不终止」
「重连中 hello 协议不符（致命）→ CLOSED 终止链」「hello 超时算偶发继续接力」
「同一次掉线的重复 onDown 只排一次退避（`pendingCount()===1`、`nextDelay()===1000`）」）；
`bash scripts/ci/docs-check.sh` 通过；`bash scripts/package.sh --no-test` BUILD SUCCESSFUL。

**排障设施（保留，后续真机排障继续用）**：`core/GatewayClient.ts` 的可选
`GatewayDeps.trace?: (m: string) => void`（`applyState`/`onDown`/`scheduleReconnect` 三处
`traceMsg`），两个 pages 的 `buildGateway()` 注入 `Dlog.info('[gw] ' + m)`；
`platform/WsTransport.ets` 的 `[ws] open/close/error/timeout` 四条。
hilog 取法：`hdc shell "hilog -x | grep 'A0D5C0'"`（TAG `Dsh`、domain 0xD5C0）。
**文档**：`AGENTS.md` §11 +3 条（`重连链提前终止` / `一次掉线排两次退避` /
`hilog 读应用日志要带域`，并改写原「hilog 读不到应用日志」的错误结论）；
`harmony/docs/PORT-MAP.md` §3 同三条详版（含探针构造与真机日志序列）。

## 阶段 5 第十批：历史分页 UI 入口（2026-11-16）

**现象**：全功能冒烟最后一项「历史分页」——`ChatStore.loadOlder()`
（`harmony/entry/src/main/ets/core/ChatStore.ts:294`）已实现并有单测，但
`grep -rn loadOlder harmony/entry/src/main/ets/pages harmony/entry/src/main/ets/components`
**零命中**：UI 从未调用，用户无从触发。安卓侧 `app/lib/ui/chat_message_list.dart:196-215`
在列表头放「加载更早消息」`TextButton.icon`，由 `state.historyHasMore` 控制显示。

**修法**（`harmony/entry/src/main/ets/components/MessageList.ets`）：
- 新增 `@State hasMore` / `@State loadingOlder`，`syncVersion()` 里从 store 抄两个派生值
  （`@Prop @Watch('syncVersion') version` 已由 `pages/ChatView.ets:158-160` 传入）。
- `renderList()` 的 `List` 内、`ForEach` 之前插列表头项：`hasMore` 时渲染
  `⌃ 加载更早消息`（`loadingOlder` 期间换 `LoadingProgress`），整行
  `justifyContent(FlexAlign.Center)` + `.onClick(() => this.loadOlder())`。
- 翻页 prepend 不跳底：`syncVersion()` 里 `if (st !== null && st.consumeHistoryPageJustLoaded()) { return; }`
  —— 用户点按钮的意图是往上读旧内容，不是贴底（安卓 `chat_message_list.dart:147-158` 同口径注释）。
- 新增 `private loadOlder()`：`st.loadOlder().catch(() => {})`，错误文案由 store 写 `lastError`。

**桥侧分页基线（真机实测取证）**：`/home/wangke/probe-history.cjs` 直连 WS——
- WS 客户端帧是**扁平**对象 `{type:'history', sessionId, beforeSeq?, maxMessages?}`
  （`dsh-remote-bridge/src/host/ws-protocol.ts:212 ClientFrame`），不是 `{type, data}`；
  服务端连上即自动发 `hello`，客户端**不要**发 hello（发了报 `UNKNOWN_TYPE`）；
  history 应答事件是 `{type:'event', event:{type, seq, time, data}}`，**seq 在 `e.event.seq`**。
- `session-2bc4648d-…`（「安卓配对码连接失败」）：首屏 `maxMessages=200` →
  `events 757, hasMore true, seq 3003-3759`；`beforeSeq=3003` 翻页 →
  `events 1156, hasMore true, seq 1847-3002`，两页 seq 无缝衔接（3002 | 3003）。
- `session-c6413d15-…`（「重启后验证提问确认」）只有 42 个事件、`hasMore false` ——
  该会话**本就不该出按钮**，真机上「看不到按钮」是正确行为，不是缺陷。

**门禁**：`npm --prefix harmony/test test` → 218/218 全绿；`bash scripts/package.sh --no-test`
BUILD SUCCESSFUL；签名装机后真机进入有长历史的会话，列表头渲染正常。

**顺带修的排障设施**：`harmony/build/ui.sh` 的 `dump` 分支原先直接
`hdc file recv`，失败时**留下上一轮的 `ui.json`**，导致读到旧快照误判「滑动没生效」；
改为先 `rm -f`、recv 后校验 `stat -c%s > 100`、失败重试 3 次。

---

## 阶段 5 第十一批：工具卡三层折叠（官方 web 式）+ 深度思考折叠 + 翻页不跳底（2026-11-16）

**用户需求**（两条）
- 「执行了那些命令，只显示了一条。要具体点，像官方那样，有时间，可折叠，命令 Bash 式显示。」
  「所有工具类的都像官方 web 模式看起。」
- 「思考未自动收缩，界面内容过多。」
- 「点击『加载更早消息』自动跳转到最新消息了，应该位置不变。」

**工具卡三层折叠**（对照安卓 `app/lib/ui/process_group.dart` 1-300 行）
- 组头：`🔧` + 短语聚合（`修改了文件`）+ 总耗时（`20.1s`）+ `⌄/⌃`，点整组展开。
- 第二层 `ToolRow`：`○/⊘`（成功/失败）+ `phrases.join('，')` + 路径摘要（monospace）+ `⌄/⌃`，
  点行展开。
- 第三层 `detailBlock`：灰底描边卡片（`bgLayer1` + `inputBorder` 1px + `codeBlockRadius`）——
  卡片头 `call.name` monospace + 耗时 + `✓/✗`，分隔线，正文 bash 走
  `MdCodeBlock({lang:'BASH'})`、否则「参数」`prettyArguments`，「输出」/「错误」+ `resultText`，
  空结果非失败显「结果为空」。
- `core/ToolCall.ts` 新增三个纯函数：`formatDuration(ms)`（<1000 用 ms、<60000 用
  `x.xs`、否则 `Xm Ys`、负值/null 返 null）、`bashCommandOf(name, rawArguments)`
  （只认 `bash`/`tools.bash`，从 arguments JSON 取 `command` 原样返多行）、
  `prettyArguments(rawArguments)`（逐行 `k: v`，值超 200 字截断加 `…`，坏 JSON 原样返，`{}` 返 null）。
  **坑**：遍历 Record 必须 `Object.keys(map)` 循环，`map.forEach` 在 ArkTS 上不可靠。

**拆文件（宪法 §7 单文件 ≤500 行）**
`MessageList.ets` 加完 ThinkBlock + ProcessGroup 后到 675 行 → 切出两个独立文件：
`components/ThinkBlock.ets`（65 行）、`components/ProcessGroup.ets`（243 行，含
`export struct ProcessGroup` 与 `export struct ToolRow`），`MessageList.ets` 回落到 404 行。
**编译坑**：`ToolRow` 字段初值 `new ToolCallInfo('', '')` 报
`10505001 Expected 8 arguments, but got 2`，须补全 8 参
`new ToolCallInfo('', '', [], null, false, null, null, null)`。

**深度思考折叠**（对照安卓 `chat_message_items.dart:232 _ThinkBlock`）
`ThinkBlock` 的 `@Prop @Watch('onStreamingChange') streaming` —— `aboutToAppear` 里
`expanded = streaming`（流式默认展开），`onStreamingChange` 只在 `!streaming && expanded` 时
置 false（流式结束自动收起），用户手动展开后不再被强制折叠。文案 `深度思考中…` /
`已深度思考`，展开走 `MdView small`，左侧缩进 `DsSpacing.thinkHMargin = 12`。

**翻页跳底修复（两个根因叠加）**
1. `ForEach` 的 key 含 `idx`（`` `${m.seq}-${idx}-${m.text.length}` ``）→ 翻页把旧消息插到数组
   前部时 index 全体后移、key 全变、ArkUI 判定整列重建 → 滚动位置重置。改成
   `` `${m.role}-${m.seq}-${m.text.length}` ``（去掉 idx）。
2. 补滚动锚点：`firstIdx` 由 `.onScrollIndex` 维护，`loadOlder()` 触发前快照
   `anchorIdx = firstIdx` / `anchorLen = msgs.length`，`syncVersion()` 的
   `consumeHistoryPageJustLoaded()` 分支里 `added = msgs.length - anchorLen` →
   `scrollToIndex(anchorIdx + added)`。

**门禁**：`npm --prefix harmony/test test` → **227/227 全绿**（新增 `tool-detail.test.ts` 9 条）；
`bash scripts/package.sh --no-test` BUILD SUCCESSFUL；签名装机后真机验证：进「安卓配对码连接失败」
会话，顶部渲染 `🔧 [68,353][127,408]` + `修改了文件 [145,355][884,406]` + `20.1s [902,359][992,403]`
+ `⌄`；点开三条 `○ 修改了文件 <路径>` 行；再点第一条展开出 `edit` + `30ms` + `✓` + `参数` +
`file_path: …`。三层折叠与官方 web 观感正常。

## 阶段 5 第十二批：静态审查报告落地（P0/P1 全改）+ core 拆分（2026-11-16）

用「鸿蒙开发台」插件（harmony_check review）对 `harmony/entry/src/main/ets/` 全量静态审查，
报告落盘 `harmony/docs/REVIEW-20261116.md`；随后按报告把 P0/P1 全部改完。

**P0（合规硬伤）**
- `entryability/EntryAbility.ets` 的 7 处 `hilog.` 直调改走 `Dlog`（宪法 §7 要求 hilog 只在
  `platform/Dlog.ets`）。原来 DOMAIN `0x0000` / TAG `DshChat` 与 Dlog 的 `0xD5C0` / `Dsh`
  不一致，真机 `hilog -x | grep A0D5C0` 根本抓不到 Ability 生命周期日志。
- `components/md/MdCodeBlock.ets` 的 `spanColor(cls)` 9 处颜色字面量全换 token：亮色分支用
  既有 `DsPalette.synKeyword/synString/synNumber/synComment/synPlain`；暗色分支在
  `ui/theme.ets` 新增 `synDarkKeyword '#CC99CD'` / `synDarkString '#7EC699'` /
  `synDarkNumber '#7EC699'` / `synDarkComment '#999999'` / `synDarkPlain '#D4D4D4'`。
- `ui/theme.ets` token 落位到官方刻度（**R023 允许字号集** =
  `{8,9,10,12,14,16,18,20,22,24,28,30,36,38,46,48,56}`；**R003 允许间距/圆角集** =
  `{0,2,4,6,8,10,12,14,16,18,20,22,24,26,32,36,40,56,64}`）：
  `codeBlock/codeBlockLabel` 13→12、`table/tableHead` 15→16、`contentPadRight` 15→16、
  `actionIconSize` 17→16、`codeBlockPadH` 15→16、`inlineCodePadH` 5→6、
  `processIconSize` 15→16、`chipRadius` 15→16、`chipGap` 19→18、`settingsChipGap` 7→6。
- 引用处批量落位（脚本 + 复查脚本验证 0 残留）：字号 `{13:12,15:16,11:10,17:16,32:30,40:38}`
  共 **48 处 / 16 文件**；间距与圆角 `{7:8,3:4,1:2,11:12,9:10}` 共 **29 处 / 10 文件**；
  `Composer.ets` TextArea `.borderRadius(0)`→`2`（圆角集不含 0）。

**P1（规范项）**
- 无障碍：批量插入 **59 处 `accessibilityText`**（19 文件）—— 顶栏三键、消息操作六键、
  Composer 六处、HITL 四处、抽屉/面板/连接页/设置页各处；小热区放大：
  `SessionsDrawer` 新建对话 34→40、`ChatView` 顶栏三图标 36→40（R009 触控 ≥40vp）。
- `module.json5` deviceTypes 收窄为 `["phone"]` —— 未做 600/840vp 一多分档，声明 tablet/2in1
  会过不了上架一致性核查；`string.json`（base + en_US）各删 3 条未使用的 `skeleton_*`。
- 动效档位：`ChatView.ets` 抽屉 `duration: 240` → `200`（R017 档位 100/150/200/300/350）。

**core 拆分（宪法 §7 单文件 ≤500 行）**
拆前超限 3 个：`ChatStore.ts` 569、`GatewayClient.ts` 541、`GatewayApi.ts` 541。拆后：
- `core/GatewayRest.ts`（277 行）：GatewayApi 的 REST 实现整体搬出（restHeaders/restJson/
  encodePath + 13 个 REST 方法），`GatewayApi.ts` 留 13 个同名委托 → 365 行。
- `core/ChatHitl.ts`（90 行）：`refreshPendingMarksIn` / `pendingMarkOfIn` / `answerQuestionIn` /
  `cancelQuestionIn` / `decideApprovalIn` 五个 store 参数纯函数。
- `core/ChatHistory.ts`（93 行）：`reloadHistoryIn`（本地命令卡灌回尾部）/ `loadOlderIn`
  （beforeSeq=最小 seq、合并去重、跨会话结果丢弃）。
- `core/GatewayRequests.ts`（约 190 行）：`requestWithTimeoutOn` / `requestOn` / `subscribeOn` /
  `onFrameOn` 帧收发与分派。
- 终态行数：`ChatStore.ts` 456、`GatewayClient.ts` 434、`HistoryPage.ts` 469 —— 全部 <500 ✓。
- **三个踩坑**（详见 PORT-MAP）：①按行号区间剪段会静默带走区间内夹着的别的方法
  （`setPermission` 被删 → 测试 `TypeError`）；②`onFrameOn` 拆出去时漏了 `kind==='hello'`
  分支 → 所有客户端测试挂满 300s 超时（"Promise resolution is still pending"）；
  ③script 拼 head+tail 会多/少一个类闭合括号，报 `Unexpected "}"` / `Expected identifier
  but found end of file`。

**门禁**：`npm --prefix harmony/test test` → **227/227 全绿**；
`bash scripts/ci/docs-check.sh` → 通过；`bash scripts/package.sh --no-test` → BUILD SUCCESSFUL。

**未修（P2 延后，报告里已列）**：R007 窗口宽度断点（600/840vp 一多分档，deviceTypes 已收窄到
phone 规避）、R005 `LazyForEach`（长会话全量 ForEach）、R016 图片 `objectFit`、中文硬编码 92 处
（未做 `$r('app.string')` 资源化）。

**追加：Composer 501→488 行（@ 面板纯逻辑外提）**
`components/Composer.ets` 落位后仍 501 行超限 → 把 @ 面板的合并逻辑抽成
`core/AtMention.ts`（65 行，node 直测）：`AtEntry` 模型 + `mergeAtEntries(lists, labels, query,
inSubDir)`（多根 label 前缀、query **名字前缀**过滤且大小写不敏感、逐根 404 容错并统计
`okRoots`）+ `inSubDirectory(dir)`；`Composer` 只负责拉取与状态搬运。`ComposerPanels.ets`
的 `AtEntry` 定义随之迁走、改 import。新增 `harmony/test/cases/at-mention.test.ts` 8 条 →
**235/235 全绿**。顺手修了「单根时名字不带前缀」的用例（原写法喂了两条 list 却只给一个
label，属测试自身笔误）。
