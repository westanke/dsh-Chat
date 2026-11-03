# AGENTS.md — dsh-Chat 工程宪法

> 本文件是每次会话**必然读到**的那份约定。本工程由 AI 自主开发，规矩写在前面，
> 谁（包括未来的 AI 会话）动手前先读完这条。与 `dsh-remote-bridge` / `dsh-companion`
> 的宪法同源同制度，按 Flutter 客户端特色裁剪——**三边职责不同，不要互相照抄**。

---

## 0. 一分钟上手

| 我想… | 先读 |
|---|---|
| 知道设计基准（颜色/字号/布局怎么来的） | `docs/design-tokens.md` |
| 知道协议怎么接 | `dsh-remote-bridge/docs/api/openapi.yaml` + `asyncapi.yaml` + `docs/project/API.md` |
| 知道某目录干什么 | 本文件 §3 + `docs/STRUCTURE.md` |
| 复刻得像不像 | `ref/md-shot-*.png`（官方 6 屏基准）、`ref/official-*.png`（空态/深色/抽屉）与装机截图对比 |
| 离屏看渲染（不装机） | `flutter test test/render_md_test.dart` / `render_mark_test.dart` |

## 1. 本项目是什么（边界）

- **一句话**：Flutter 一套代码（Android + iOS）复刻官方 DeepSeek App 的**界面**，
  对话内容由本机的 `dsh-remote-bridge`（REST `/api/v1` + WS `/ws/mobile`）提供。
- **上游依赖**：`dsh-remote-bridge` ≥ 2.10.0（协议 v3）。本仓**只消费协议**，不改协议。
- **不是什么**：不是官方客户端的分支；不接官方服务器；不逆向官方 APK 的代码/资源。

## 2. 法律红线（用户 2026-11-02 定，起步就不得违犯）

1. **产物标识符零 DeepSeek**：applicationId / bundle id / 类名 / 资源名 / 应用显示名 /
   About 文案，一律不含 `deepseek`（不区分大小写）。当前注册名：
   `com.dsh.dshchat`，显示名 `DSH Chat`。改包名须先改本条再动 `build.gradle.kts`。
2. **不复用官方资产**：官方 APK 里的图标、字体、so、混淆资源一个都不拷贝；
   图标自绘或用开源图标集（Material Symbols / 自绘 path）。
3. **仿界面不冒品牌**：布局、间距、配色对齐官方是工程要求；但启动页 logo、
   关于页、客服/官网链接等品牌触点必须用本工程自己的。
4. 本仓原名 `dsh-flutter-deepseek`（改名纪律：旧名仅此行留档），2026-11-03 已整体改名为
   **`dsh-Chat`**（目录、文档、测试路径、设备 ID 前缀全部同步，`ref/daemon-stack.txt` 等历史快照除外）。
   现在**仓库名、目录名、产物标识符里都没有 `deepseek`**，可以公开源码。
   改名纪律：任何新增文件/文档不得再出现旧名（`scripts/ci/docs-check.sh` 会拦住）。

## 3. 目录与嵌套

```
dsh-Chat/
  AGENTS.md            ← 本文件（工程根 = 宪法所在）
  docs/                ← design-tokens.md / STRUCTURE.md（平铺，不加子目录）
  ref/                 ← 官方基准材料（css/apk/截图），只读，不参与构建
  app/                 ← flutter 工程根
    lib/
      design/          ← tokens.dart（设计 token 单一来源）
      bridge/          ← gateway.dart（WS）/ models.dart（协议模型）/ credentials.dart / device.dart / dlog.dart
      ui/              ← chat_page / chat_state / composer / connect_page / md_view /
                         md_code_block / md_table / message_actions / process_group /
                         sessions_drawer / brand_mark
    android/ ios/      ← 平台壳（改动要在提交说明里点名）
```

铁律：
- **目录嵌套 ≤ 3 层**（用户长期规矩）；`lib/` 下子目录只许 `design/`、`bridge/`、`ui/` 三个。
- 严禁 `/tmp`（用户长期规矩）；临时文件进 `app/build/` 或用户家目录。
- `ref/` 只进参考材料，**绝不**被 `app/` 的 Dart/gradle 引用。

## 4. 设计 token 纪律（「严格对称」怎么落地）

- 单一来源：`docs/design-tokens.md`（由 `ref/main.pretty.css` 官方 Web token +
  真机 6 屏像素实测合成）。**改样式先改 token 文档，再改 `lib/design/tokens.dart`，再改 UI**。
- UI 代码里禁止出现裸颜色/裸字号（`Color(0xFF3964FE)`、`fontSize: 24` 这类）；
  一律引用 `DsColors` / `DsTypography` / `DsSpacing`。review 时 grep `Color(0x` 兜底。
- 官方 Web 与 App 实测不一致时，**以 App 实测为准**（我们复刻的是 App）。

## 5. 协议纪律

- bridge 协议的事实来源是 bridge 仓 `docs/api/`（openapi/asyncapi）与 `docs/project/API.md`；
  kotlin-sdk `MobileGatewayClient.kt` 是参考实现。
- 发现协议文档与 bridge 实际行为不符：**去 bridge 仓开 issue**，本仓不许私自兼容魔改。
- 关键常量（子协议 `dsh-mobile-v1`、hello.protocol=3、close 4001=鉴权失败）
  只写在 `lib/bridge/gateway.dart` 一处，加注释指向 bridge 文档锚点。
- 推送流（`chat.message.delta`/`committed`/`resyncRequired`）必须处理背压与重连；
  重连退避 1s→2s→4s→8s→16s 封顶 30s（与 kotlin-sdk 一致）。

## 6. 命令（本地唯一可信口径）

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd app
flutter pub get          # 依赖变更后必跑
flutter analyze          # 提交前必绿
flutter test             # 有测试后提交前必绿
flutter build apk --debug  # 真机验证前
```

文档与 Git 门禁（仓库根执行）：

```sh
bash scripts/ci/docs-check.sh   # STRUCTURE.md 契约机检（CI 第一道闸门）
bash scripts/setup-remotes.sh   # 配三远端（幂等）
bash scripts/push-all.sh        # 推 Gitee 主 + AtomGit 备（**须用户同意**，见 §10）
```

- Android 工具链：`/media/wangke/OFFICE/workspace/android-toolchain/`（jdk17、sdk）。
  gradle 依赖走国内镜像（腾讯 gradle wrapper 镜像），pub 走 flutter-io.cn。
  ⚠️ 2026-11-03 实测该目录与 `~/flutter` **在本机均不存在**，`flutter`/`dart`/`java`
  也不在 PATH —— 需要构建时先补齐工具链，别照抄命令硬跑。
- 真机：vivo V2080A（serial 9540718532001JR），`adb` 在
  `…/android-toolchain/sdk/platform-tools/adb`。vivo 装机拦截页需勾风险确认再点继续安装。

## 7. 代码纪律

- **单文件 ≤ 500 行**（Dart 心智负担高于 TS？低于 Kotlin，折中取 500）。超了拆文件，不许 `// ignore` 糊弄。
- 禁 `print`（用 `debugPrint`）；禁 `dynamic` 满天飞（协议模型必须显式 `fromJson`/`toJson`，字段可空性如实声明）。
- 每个 bridge 帧模型要有 JSON round-trip 单元测试（构造 → toJson → fromJson → 字段相等）。
- 样式值必须有 token 依据（§4）；新 UI 元素先在 `design-tokens.md` 登记。
- `flutter analyze` 的 warning 不许积压；info 级要注释理由才能留着。

## 8. 文档同步（同提交）

| 改动 | 同一提交内必须同步 |
|---|---|
| 新增/移动/删除 `lib/` 下文件 | `docs/STRUCTURE.md` 的清单表 |
| 新增/修改设计 token | `docs/design-tokens.md` + `lib/design/tokens.dart` 一起 |
| 协议用法变更（新增帧/字段） | 在 `docs/STRUCTURE.md` 的 bridge 章节登记引用的协议版本 |
| 依赖变更 | pubspec 注释说明用途；新增重量级依赖（>10 传递依赖）先在本文件登记 |

门禁靠人肉 + grep：提交前自查「文档改了吗」；AI 会话开场先读本文件。

## 9. 对外表述纪律（同源三仓共守）

- 「仿官方界面」表述只用于工程内部沟通；对外（README、release notes）写
  「DSH Chat — Flutter client for dsh-remote-bridge」，不写「DeepSeek 克隆」。
- 未装机验证过的功能不许写「已完成」；真机截图是验收证据。
- 推送/发布类远端动作未经用户明确同意不做（同源规矩）。

## 10. Git 渠道与推送纪律（与 dsh-remote-bridge / dsh-companion 同制度）

**三远端拓扑**（2026-11-03 起，与姊妹仓完全一致）：

| remote | 平台 | 地址 | 角色 |
|---|---|---|---|
| `gitee` | Gitee | `git@gitee.com:westanke/dsh-Chat.git` | **主站**，日常唯一推送目标 |
| `atomgit` | AtomGit | `git@atomgit.com:westanke163/dsh-Chat.git` | **备站**，与主站同批推 |
| `origin` | GitHub | `git@github.com:westanke/dsh-Chat.git` | **从站**，不手工推 |

- GitHub 是**镜像从站**：由 `.github/workflows/mirror-sync.yml` 每 3 小时从 Gitee
  `push --mirror`（含 tag）单向同步。本机到 github.com:443 长期被阻断，所以
  默认不推 GitHub；确有需要手工补推用 `INCLUDE_GITHUB=1 bash scripts/push-all.sh`。
- 三远端一律走 **SSH**（`~/.ssh/id_ed25519_{gitee,atomgit,github}`），本机没有
  PAT（`~/.config/dsh-git/tokens.conf` 为空），不要改成 HTTPS —— 那会要求 token。
- 首次配远端：`bash scripts/setup-remotes.sh`（幂等，可反复跑）。

**推送纪律（铁律）**：

- **禁止**：推送（push / release / tag / 上传产物）未经用户**明确同意**。
  本地 commit、构建、测试、清理、写文档可直接做。
- 推送唯一入口是 `bash scripts/push-all.sh`，它会先推分支、再**逐个**推 tag
  （不用 `git push --tags` —— 远端有任意同名旧 tag 会整条被拒）。
- 分支与 tag 必须分开推，不许写成 if/else 互斥（历史上因此「只推了一半」）。
- 历史分叉时脚本会提示，确认内容一致才可用 `FORCE=1`（--force-with-lease），
  **绝不允许**裸 `--force`。

**提交纪律**：

- 提交信息用 `<type>(<scope>): <中文摘要>`，如 `feat(bridge): 心跳 25s 可配`。
- 一次提交只做一件事；改了 `lib/` 就必须同提交改 `docs/STRUCTURE.md`（§8），
  `bash scripts/ci/docs-check.sh` 是这条的机检。
- 不提交构建产物：`app/build/`、`app/.dart_tool/`、`ref/apk-extract/`、
  `ref/deepseek.apk`、`ref/apk-resources.txt` 已在 `.gitignore`（§3 的 ref/ 例外）。
- **绝不提交凭证**：`ref/probe-token.json`、`ref/pairing.json`、`ref/math-session.txt`
  含真实 token/配对码/会话 id，已在 `.gitignore` 拉黑。往 git 历史里塞一次就得改写历史。

**CI 口径**（`.github/workflows/ci.yml`，两道闸门）：

| 闸门 | 命令 | 说明 |
|---|---|---|
| 文档 | `bash scripts/ci/docs-check.sh` | STRUCTURE.md 覆盖全部 lib/ 文件、无死链、无旧仓名 |
| 代码 | `flutter analyze` → `flutter test` | 在 `app/` 下跑；跟 stable 通道的 Flutter |

刻意不跑 `flutter build apk`：产物不入库，验收在本机真机，CI 构建没人用（理由见 ci.yml 头注释）。

---

## 11. 坑位索引（名字 = 触发词；新坑加这里）

- `vivo 装机拦截` —— 安装后出现 PackageInterceptActivity：先点 checkbox「已了解应用的风险检测结果」再点「继续安装」。
- `剪贴板注入` —— vivo 拒绝后台读剪贴板，中文输入走 ADBKeyboard 或输入法直发；自动化测试用 ASCII。
- `官方 flutter_markdown 已废弃` —— 用 `gpt_markdown`；它的 API 是位置参数 `GptMarkdown(text, onLinkTap:)` 不是 `data:`。
- `FLUTTERTELEMETRY` —— 首跑 `flutter --version` 输出被遥测提示盖住，先 `--disable-analytics`。
- `nohup 会被会话回收` —— 长任务别指望 nohup 跨轮次存活，要么当轮等完，要么 job 系统。
- `gradle wrapper 下载慢` —— distributionUrl 用 `mirrors.cloud.tencent.com/gradle/`。
- `空快照树` —— Flutter 自绘界面 uiautomator 树可能没文字：`adb_ui` 自动 OCR 兜底，或 `adb_ocr`。
- `adb install 互相卡死` —— 多个 `adb install` 并存会全部挂住（设备 `mCurrentFocus=null`、应用装不上也起不来）：`ps -ef | grep "adb .*install" | awk '{print $2}' | xargs kill` 后 `adb kill-server && adb start-server`。
- `RenderRepaintBoundary 导出图` —— 要 `import 'package:flutter/rendering.dart'` 与 `import 'dart:typed_data'`，否则编译报 "isn't a type"。
- `gpt_markdown 任务列表溢出` —— 1.4.0 把 Material Checkbox 塞进 WidgetSpan，中文行高算出 ~10 万像素宽 → RenderFlex 溢出（debug 红底黄黑斜纹）：必须传 `checkboxBuilder` 自绘。
- `gpt_markdown 任务列表圆点` —— 源码 `- [x] foo` 会先被 listMarker 吃掉成无序列表项：渲染前用 `normalizeTaskLists()` 去掉列表符号。
- `外部写入不刷新` —— bridge 只在 `chat.session.event` 推 eventType（无事件体），且 `committed role=user` 分支容易漏：所有 session event 都要防抖重拉 history。
