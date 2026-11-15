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
