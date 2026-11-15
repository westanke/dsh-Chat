# STATUS —— 鸿蒙版阶段进度

> 每轮交付后更新本表。对照基准：安卓版 `docs/STRUCTURE.md`（唯一功能清单来源）。

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 工程骨架：ArkTS 空工程 + 未签名 HAP 构建通 + node 测试骨架 + 门禁/文档同步 + 首提交 | ✅ 2026-11-15 |
| 1 | core 协议层：全部帧模型 + gateway 状态机 + REST 封装 + node 用例全绿 | ◐ WS 层 6 文件+91 用例全绿；HistoryPage/tool_call 等待补 |
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
