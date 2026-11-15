# harmony/ —— dsh-Chat 鸿蒙版（ArkUI 原生）

对照安卓版（`app/`，Flutter）全部功能的 ArkTS 原生重写，同一仓库同一 git。
技术方案与阶段划分见 workspace 根《鸿蒙版方案-dshChat-20261115.md》；规程文档：

| 文档 | 内容 |
|---|---|
| `docs/PORT-MAP.md` | 移植对照表、用户拍板的决策记录、坑位索引（**动手前必读**） |
| `docs/RELEASE.md` | 构建/签名/发版流程（含 AGC 待补材料清单） |
| `docs/STATUS.md` | 阶段进度（当前阶段 0 骨架 ✅） |

## 快速命令

```sh
# 工具链环境（ROOT 可用 DSH_HARMONY_TOOLCHAIN_ROOT 覆盖）
source harmony/scripts/toolchain-env.sh

# 双闸门打包：node 单测 + hvigorw assembleHap（未签名）→ dist/
harmony/scripts/package.sh

# 只跑纯逻辑层单测（core 层用例所在，阶段 1 起扩充）
cd harmony/test && npm test
```

## 纪律（与根仓 AGENTS.md 同源，鸿蒙侧裁剪）

- 产物标识符零 DeepSeek：bundleName `com.dsh.dshchat`，显示名 `DSH Chat`。
- 颜色/文案一律走 resources（`$r('app.color.*')` / `$r('app.string.*')`），dark/ 同步；
  设计 token 单一来源仍是根仓 `docs/design-tokens.md`。
- 单文件 ≤ 500 行；core/ 纯 TS 零 ArkUI 依赖，每条协议帧模型配 node round-trip 用例
  （`test/cases/`，姊妹仓同款模式）。
- `hvigorw assembleHap` 日志 `WARN: No signingConfig` 是预期输出（签名走 hap-sign-tool）。
- 推送/发布须用户明确同意。
