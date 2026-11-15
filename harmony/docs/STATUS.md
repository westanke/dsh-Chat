# STATUS —— 鸿蒙版阶段进度

> 每轮交付后更新本表。对照基准：安卓版 `docs/STRUCTURE.md`（唯一功能清单来源）。

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 工程骨架：ArkTS 空工程 + 未签名 HAP 构建通 + node 测试骨架 + 门禁/文档同步 + 首提交 | ✅ 2026-11-15 |
| 1 | core 协议层：全部帧模型 + gateway 状态机 + REST 封装 + node 用例全绿 | ☐ |
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
