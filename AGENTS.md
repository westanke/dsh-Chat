# AGENTS.md — dsh-Chat 工程宪法

> 本文件是每次会话**必然读到**的那份约定。本工程由 AI 自主开发，规矩写在前面，
> 谁（包括未来的 AI 会话）动手前先读完这条。与 `dsh-remote-bridge` / `dsh-companion`
> 的宪法同源同制度，按客户端特色裁剪——**各边职责不同，不要互相照抄**。
> 本仓现含三个客户端：`app/`（Flutter 一套代码，Android + iOS + **鸿蒙**，Android 已发版）、
> `app/ohos/`（Flutter-OH 鸿蒙宿主工程，2026-11-25 起步）与
> `harmony/`（旧 ArkUI 原生鸿蒙版，2026-11-15 起步，**已冻结维护、后续退役**，
> 签名材料仍保留，规程见 `harmony/docs/PORT-MAP.md`）。

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

- **一句话**：本仓承载 DSH Chat 双客户端——`app/`（Flutter 一套代码，Android + iOS）
  与 `harmony/`（ArkUI 原生鸿蒙版），各自复刻官方 DeepSeek App 的**界面**，
  对话内容由本机的 `dsh-remote-bridge`（REST `/api/v1` + WS `/ws/mobile`）提供。
- **上游依赖**：`dsh-remote-bridge` ≥ 2.10.0（协议 v3）。本仓**只消费协议**，不改协议。
- **不是什么**：不是官方客户端的分支；不接官方服务器；不逆向官方 APK 的代码/资源。

## 2. 法律红线（用户 2026-11-02 定，起步就不得违犯）

1. **产物标识符零 DeepSeek**：applicationId / bundle id / bundleName / 类名 / 资源名 /
   应用显示名 / About 文案，一律不含 `deepseek`（不区分大小写）。当前注册名：
   `com.dsh.dshchat`，显示名 `DSH Chat`（Android applicationId、鸿蒙 bundleName
   —— `app/ohos/AppScope/app.json5` 与 `harmony/AppScope/app.json5` —— 同名同源，
   改包名两平台一起改，先改本条再动 `app/android`、`app/ohos/AppScope/app.json5`、
   `harmony/AppScope/app.json5`）。
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
  app/                 ← flutter 工程根（Android+iOS+鸿蒙，Android 已发版）
    lib/
      design/          ← tokens.dart（设计 token 单一来源）
      bridge/          ← gateway.dart（WS）/ models.dart（协议模型）/ credentials.dart / device.dart / dlog.dart
      ui/              ← chat_page / chat_state / composer / connect_page / md_view /
                         md_code_block / md_table / message_actions / process_group /
                         sessions_drawer / brand_mark
    android/ ios/      ← 平台壳（改动要在提交说明里点名）
    ohos/              ← 鸿蒙宿主工程（Flutter-OH 生成，2026-11-25 起）
      AppScope/        ← 应用级配置 app.json5（bundleName=com.dsh.dshchat）
      entry/src/main/  ← ets 插件源码（entryability/pages/plugins）+ module.json5 + 资源
      hvigor/          ← hvigor 工程配置（json5/ts）
    vendor/            ← 本仓打补丁的第三方包（gpt_markdown，见 README.dsh.md）
  harmony/             ← 旧鸿蒙工程根（ArkUI 原生，**冻结维护**，后续退役；
                        签名材料保留在 harmony/signing/ 与 harmony/docs/RELEASE.md）
    AppScope/          ← 应用级配置 app.json5 + 分层图标（bundleName=com.dsh.dshchat）
    entry/src/main/    ← ets 业务代码（ability/pages/components）+ module.json5 + 资源
      core/            ← 纯逻辑层（协议/模型，.ts，node 直测，不 import 任何 ets；
                           在 entry 模块内，ArkTS 禁跨模块相对 import，见 §7 分层铁律）
    test/              ← node:test + tsx 纯逻辑测试（CI 跑这里，无鸿蒙 SDK 依赖）
    docs/              ← PORT-MAP.md（移植对照）/ RELEASE.md（签名发版）/ STATUS.md（进度台账）
    scripts/           ← package.sh（构建发版）/ toolchain-env.sh（工具链 env）
```

铁律：
- **目录嵌套 ≤ 3 层**（用户长期规矩）；`lib/` 下子目录只许 `design/`、`bridge/`、`ui/` 三个；
  `harmony/entry/src/main/ets/` 下同口径（`pages/`、`components/` 等按功能平铺，不叠壳）。
- **平台豁免（用户已批，2026-11-15）**：`harmony/` 的 ArkTS 工程结构
  （`AppScope/`、`entry/src/main/`、`hvigor/` 等）由 DevEco/hvigor 约定死，豁免嵌套限制；
  `harmony/entry/src/main/ets/core/`、`harmony/test/`、`harmony/docs/`、`harmony/scripts/` 照旧严格执行。
- **平台豁免（用户已批，2026-11-25）**：`app/ohos/` 的 ArkTS 工程结构与 `harmony/` 同等豁免
  （`AppScope/`、`entry/src/main/ets/{entryability,pages,plugins,platform}`、`hvigor/`）。
- 严禁 `/tmp`（用户长期规矩）；临时文件进 `app/build/`、`harmony/build/` 或用户家目录。
- `ref/` 只进参考材料，**绝不**被 `app/` 的 Dart/gradle 或 `harmony/` 的 ets/hvigor 引用。

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
# 工具链一次性引入（2026-11-25 起，tools/ 统一口径）
source /media/wangke/OFFICE/workspace/tools/env.sh

cd app
flutter pub get          # 依赖变更后必跑
flutter analyze          # 提交前必绿
flutter test             # 有测试后提交前必绿
flutter build apk --debug          # Android 真机验证前
flutter build hap --debug --no-codesign   # 鸿蒙 HAP（本机无签名，走 unsigned）
flutter build apk --release --target-platform android-arm64   # 发版 APK（只 arm64）
flutter build hap --release --no-codesign  # 发版 HAP（AOT；需先补 product 版 patched SDK，见 §11）
```

文档与 Git 门禁（仓库根执行）：

```sh
bash scripts/ci/docs-check.sh   # STRUCTURE.md 契约机检（CI 第一道闸门）
bash scripts/setup-remotes.sh   # 配三远端（幂等）
bash scripts/push-all.sh        # 推 Gitee 主 + AtomGit 备（**须用户同意**，见 §10）
```

- **工具链根目录（2026-11-25 起，AGENTS.md §7 用户要求「正式使用的非源码类工具统一放 tools/」）**：
  `/media/wangke/OFFICE/workspace/tools/`
  - `env.sh` —— 唯一入口，先 `source` 它再跑任何构建命令。里面设了
    `FLUTTER_ROOT=$DSH_TOOLS/flutter-oh`（**Flutter-OH 3.50.0+ohos-1.3.3，三端统一 SDK**）、
    `JAVA_HOME=$DSH_TOOLS/jdk17`、`ANDROID_HOME=$DSH_TOOLS/sdk`、
    `GRADLE_USER_HOME=$DSH_TOOLS/gradle-home`、`DEVECO_SDK_HOME=$DSH_TOOLS/ohos-sdk/sdk`、
    `HOS_SDK_HOME`、`HDC_HOME`、`DEVECO_HOME`、`DEVECO_NODE_HOME`、
    `FLUTTER_OHOS_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com`，
    并把 ohos-sdk 的 bin/ohpm/hvigor/tool/node 与 hdc 加进 PATH。
  - `flutter-oh/` —— Flutter-OH SDK（atomgit.com/oh-flutter/flutter_flutter，tag `3.50.0+ohos-1.3.3`）。
    **只能用这一个 SDK 跑三端**：material_ui/cupertino_ui 已切 CPF ohos fork（§11 `material_ui 穷尽 switch`），
    上游 Flutter 编译不过 `case TargetPlatform.ohos:`。
  - `ohos-sdk/` —— HarmonyOS SDK **API 26**（26.0.0.105）。**API 18 不够**，OH-Flutter 1.3.3 要求 26。
  - `sdk/`（Android）、`jdk17/`、`gradle-home/`、`npm-cache/`、`dsh-home/`。
  - gradle 依赖走国内镜像（腾讯 gradle wrapper 镜像），pub 走 flutter-io.cn。
  - ⚠️ **不 source `tools/env.sh` 就构建会踩**：用系统 `/usr/lib/android-sdk` 报
    `LicenceNotAcceptedException: Failed to install the following Android SDK packages ... ndk;28.2.13676358`。
- 真机：vivo V2080A（serial 9540718532001JR），`adb` 在
  `…/tools/sdk/platform-tools/adb`。vivo 装机拦截页需勾风险确认再点继续安装。

**鸿蒙（`app/ohos/`，2026-11-25 起口径，全部实跑验证过）**：

```sh
source /media/wangke/OFFICE/workspace/tools/env.sh   # 含 hvigorw/ohpm/hdc/node
cd app
flutter build hap --debug --no-codesign    # 产物 app/build/ohos/hap/entry-default-unsigned.hap（不入库）
```

- 旧鸿蒙工程 `harmony/`（ArkUI 原生）**冻结维护，后续退役**；签名与 AGC 上架材料仍保留在
  `harmony/signing/`（**绝不入库**，.gitignore 已拉黑）与 `harmony/docs/RELEASE.md`。
- `app/ohos/local.properties` 由本机路径生成（hwsdk.dir / flutter.sdk），**不入库**；
  换机器要重跑 `flutter create --platforms ohos` 或手改这两行。
- 真机：HarmonyOS 6.0 手机（`hdc list targets`）。**本轮尚未在真机验证过**（`hdc list targets` 空）。
- 旧 `harmony/` 口径（2026-11-15 起，仅供冻结目录参考）：`hvigorw assembleHap --no-daemon`、
  `npm --prefix test install` / `npm --prefix test test`（纯逻辑 node:test，CI 跑这里）。

## 7. 代码纪律

- **单文件 ≤ 500 行**（Dart 心智负担高于 TS？低于 Kotlin，折中取 500）。超了拆文件，不许 `// ignore` 糊弄。
- 禁 `print`（用 `debugPrint`）；禁 `dynamic` 满天飞（协议模型必须显式 `fromJson`/`toJson`，字段可空性如实声明）。
- 每个 bridge 帧模型要有 JSON round-trip 单元测试（构造 → toJson → fromJson → 字段相等）。
- 样式值必须有 token 依据（§4）；新 UI 元素先在 `design-tokens.md` 登记。
- `flutter analyze` 的 warning 不许积压；info 级要注释理由才能留着。

**ArkTS（`harmony/`）追加条目**：

- **分层铁律**：`harmony/entry/src/main/ets/core/` 只写纯逻辑（协议/模型/状态机，.ts 文件），
  **不 import 任何 `@kit`/ets/UI**，保证 `harmony/test/` 用 node 直测（CI 无鸿蒙 SDK 也能跑）。
  UI 层（entry/src/main/ets 非 core 部分）只做渲染与事件转发，业务逻辑下沉 core。
  core 必须在 entry 模块**内部**：ArkTS 禁跨模块相对 import（Error00309001 实证），
  放工程根 harmony/core/ 的方案已否决（2026-11-15）。
- ArkTS 不是 TypeScript：禁 `any`/`unknown` 满天飞、禁结构化破坏性赋值、禁运行时修改对象
  shape、禁「对象 interface 联合 type」判别联合（→ 扁平类 + type 字段分派）、禁可选捕获组的
  `m[n] === undefined`（拆必组正则）；动态键值映射用 `Map<string,T>`（姊妹仓无
  `Record<string,类>` 先例）；import 不带 `type` 修饰符。协议模型显式定义 class + `fromJson`，
  同 Dart 口径（§5 round-trip 测试同样适用）。
- 单文件 ≤ 500 行对 ets/.ts 同样生效；禁 `print`（鸿蒙用 `hilog`，封装在
  `harmony/entry/src/main/ets/platform/Dlog.ets`——core 层禁 import @kit，实现只在 platform）。
- 鸿蒙工程配置（build-profile.json5 / hvigorfile.ts / module.json5）改动要在提交说明里点名；
  `compatibleSdkVersion` 升级需在 `harmony/docs/PORT-MAP.md` 记录原因。

## 8. 文档同步（同提交）

| 改动 | 同一提交内必须同步 |
|---|---|
| 新增/移动/删除 `lib/` 下文件 | `docs/STRUCTURE.md` 的清单表 |
| 新增/移动/删除 `harmony/` 下 ets/ts 文件 | `docs/STRUCTURE.md` 的 harmony 清单表（docs-check 机检） |
| 新增/修改设计 token | `docs/design-tokens.md` + `lib/design/tokens.dart` 一起 |
| 协议用法变更（新增帧/字段） | 在 `docs/STRUCTURE.md` 的 bridge 章节登记引用的协议版本 |
| 依赖变更 | pubspec 注释说明用途；新增重量级依赖（>10 传递依赖）先在本文件登记 |

门禁靠人肉 + grep：提交前自查「文档改了吗」；AI 会话开场先读本文件。

## 9. 对外表述纪律（同源三仓共守）

- 「仿官方界面」表述只用于工程内部沟通；对外（README、release notes）写
  「DSH Chat — client for dsh-remote-bridge（Android / iOS / HarmonyOS）」，
  不写「DeepSeek 克隆」。
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

**CI 口径**（`.github/workflows/ci.yml`，三道闸门）：

| 闸门 | 命令 | 说明 |
|---|---|---|
| 文档 | `bash scripts/ci/docs-check.sh` | STRUCTURE.md 覆盖全部 lib/、harmony ets/ts、**app/ohos ets/ts** 文件、无死链、无旧仓名 |
| 代码（Android/iOS/鸿蒙） | `flutter analyze` → `flutter test` | 在 `app/` 下跑；**用 Flutter-OH SDK**（`3.50.0+ohos-1.3.3`，CI 里 clone 自 atomgit + 改 `dart-sdk-url.ohos` 指向 CPF 的 linux-x64 定制 Dart SDK）。**不能用上游 stable**：material_ui/cupertino_ui 的 ohos fork 里 `TargetPlatform.ohos` 有 89 处引用，上游 SDK 直接报 `undefined_enum_constant` |
| 代码（鸿蒙旧版纯逻辑） | `npm ci && npm test`（`harmony/test`） | 纯逻辑 node:test，无鸿蒙 SDK 依赖，ubuntu runner 直跑（冻结目录，仍保留闸门） |

刻意不跑 `flutter build apk` 与 `hvigorw assembleHap`：产物不入库，验收在本机真机，
CI 构建没人用（理由见 ci.yml 头注释）；鸿蒙构建需 DevEco 工具链，runner 上没有
（发版口径见 `docs/project/RELEASE.md`）。

**发版全流程（两段式，v1.0.17 实测定稿，照做不出错）**：

- 阶段 A（本机 APK）：版本 bump（pubspec versionName+versionCode，版本号构建期注入）
  → analyze/test/docs-check 全绿 → `SKIP_CHECK=1 bash scripts/release.sh`
  （产出 `artifacts/dsh-Chat-v<ver>.apk` + README/SHA256SUMS 回填 + commit）。
- 阶段 B（双站 Release）：`SKIP_CHECK=1 bash scripts/release.sh --publish`
  （PUSH_TAGS=1 推分支+tag；建 Gitee Release 传 APK/SHA256SUMS；AtomGit Release 正文链 Gitee；
  回读下载验证 SHA 一致）。**推送须用户明确同意**（见上）。
- 阶段 C（iOS IPA，两段式：本机 Linux 打不了 iOS，产物只在 GitHub Actions macOS）：
  1. API 触发镜像立即同步（别等 3h cron）：
     `POST https://api.github.com/repos/westanke/dsh-Chat/actions/workflows/mirror-sync.yml/dispatches -d '{"ref":"main"}'`
  2. 等 main 就位（约 45s；GitHub main HEAD == 本地 HEAD 才继续）→ tag 随 mirror 上去后
     release.yml（on: push tags v*）自动跑：ubuntu 用 `scripts/ci/setup-flutter-oh.sh` 装
     Flutter-OH 后打 APK；macos-15（arm64）用同一脚本打未签名 IPA；HAP 是可选 job
     （`vars.BUILD_HAP=true` + self-hosted `[linux, harmonyos]` runner）→ workflow artifact。
  3. `bash scripts/sync-gitee-release.sh v<ver> <run-id> ios-ipa` 把 IPA 传上 Gitee Release。
  4. ⚠️ 该脚本会删 Gitee release 旧附件再传——APK/SHA256SUMS 会被删，须用
     `POST /repos/westanke/dsh-Chat/releases/<id>/attach_files -F file=@…` 重传。
- 阶段 D（GitHub Release + CI 绿检查）：GitHub Release 对象**不随 mirror**，必须 API 补建：
  `POST /releases -d '{"tag_name":"v<ver>",…}'`；附件 APK/SHA 从 artifacts/ 上传、IPA 从 Gitee
  Release 下载后上传（uploads.github.com）。最后查 Actions 全绿（ci.yml 门禁 +
  release.yml 的 Android / iOS job；HAP job 启用时也要绿）。
  release.yml Android job 曾因 runner 走阿里云 maven 镜像超时失败——gradle 仓库段已改为
  `CI=true`（GitHub Actions 自动注入）时跳过国内镜像直连官方源（settings.gradle.kts / build.gradle.kts）。
- token 口径：GitHub API 用 `~/.git-credentials` 里的 token（`tokens.conf` 的 github 行已 401 失效勿用）；
  Gitee/AtomGit 用 `~/.config/dsh-git/tokens.conf`。api.github.com 可达，github.com:443 被阻断。
- 错位 tag 修法：`DELETE /git/refs/tags/<tag>` 后再 `POST /git/refs`（annotated tag 的
  object.sha 是 tag 对象非 commit，核对时看 workflow head_sha）。

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

**鸿蒙坑位（详表见 `harmony/docs/PORT-MAP.md`，此处只留触发词）**：

- `hvigorw 不在工程内` —— hvigorw/ohpm/hdc 是工具链可执行文件：先 `source /media/wangke/OFFICE/workspace/tools/env.sh`，别找工程内 wrapper。
- `hvigor 拒明文口令` —— 签名口令不能写在 build-profile.json5，走环境变量或手动 hap-sign-tool（见 harmony/docs/RELEASE.md）。
- `分层图标覆盖` —— AppScope 与 entry 的图标资源名必须不同，否则后者覆盖前者。
- `AGC 图标 1024` —— AGC 上架审核拒收非 1024×1024 应用图标（姊妹仓实踩）。
- `npm ci 无 lock` —— harmony/test 要提交 package-lock.json，否则 CI `npm ci` 直接失败。
- `ArkUI getter 崩进程` —— `@Builder`/`ForEach` 里 `private get c()` 取到 undefined → TypeError → AMS 杀进程；一律用普通方法 `private c()`。
- `@Prop 无 @Watch 不重渲染` —— ArkUI 只认 build 期间读到的 @State/@Prop；store 派生值必须在 setNotify 里抄进 @State，@Prop version 配 @Watch。
- `hilog 抓 JS 崩溃栈` —— 先 `hilog -G 16M`（上限 16M）再 `hilog -r` 复现，`grep -iE 'JsError|Stacktrace|TypeError'` 才能拿到 .ets:行:列。
- `hilog 读应用日志要带域` —— 应用日志 TAG 是 `Dsh`、domain `0xD5C0`，必须 `hdc shell "hilog -x | grep 'A0D5C0'"` 才取得到；`hilog -T Dsh` 与裸 `hilog` 都不可用（后者数千行易超时）。前提是代码里先有 `Dlog` 打点（连接状态机走 `GatewayDeps.trace?` 的 applyState/onDown/scheduleReconnect 三处 + `WsTransport` 的 `[ws]` 四条）；另可配 mock bridge 抓帧 / REST 直查。注意 `webSocket` 的 error 回调 `err.message` 实测为 undefined，只能靠状态序列判断。
- `node WebSocket 无 header` —— 探针要打 Authorization 头必须 require ws 包，内置全局 WebSocket 不认 headers。
- `uitest inputText 是追加` —— 不清空会双拼（DSH1 报「配置文本无法识别」）。
- `设备上无 sed -i` —— 报 `sed: no temp file`；改设备文件用 `hdc file send` + `hdc shell cp`。
- `bindContentCover 与 bindSheet 同节点失效` —— 两个弹层修饰器挂同一节点时后者不弹；改用 Stack 内联 `if (open)` overlay + 遮罩。
- `getRouter().back() 退应用` —— 本项目用 `@State route` 切页不是 Router 栈，back() 会退出应用；返回一律传回调给父组件。
- `私有方法只定义没调用` —— ArkTS 不报未使用告警，`load()`/`ensureCommands()` 漏调用会静默卡「加载中…」/无补全；新组件挂载点自查 `aboutToAppear`。
- `切权限不刷投影` —— permission 帧只改服务端投影、不产生 chat 事件，成功后必须 `reloadHistory()` 才能更新 chip。
- `子组件普通成员收数组` —— `HitlPanel` 的 `questions/approvals` 写成普通成员，父层 @State 换新数组不重建子组件（提问卡提交后不消失、审批卡不出现）；接收父层数组一律 `@Prop`。
- `键盘遮输入框` —— 默认 OFFSET 避让会整页上移压住 composer；`onWindowStageCreate` 的 `loadContent` 回调里 `getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)`。
- `连接历史不落盘` —— `enterWith` 只存 credentials 不存 hosts，`reloadHosts()` 永远空；按安卓口径补 `host.id = stableId(baseUrl)` + `persistHosts(upsertHost(...))`。
- `权限显示英文档位` —— 投影 `currentValue` 是 `workspace-write` 这类 ASCII 名，界面必须过 `permissionLabelOf()` 转中文（仅可查看/工作区读写/完全权限/自动审查）。
- `纯文本模型发图气泡` —— bridge 把图片写成两个 text 块（原文 + 给模型看的「🖼️ 图片 1「x.png」…[Image: source: …]」说明），没有 image 块；气泡要剥掉说明行（逐行滤，别贪婪正则）并靠 `handoffRefOf(rawText)` 渲染缩略图。
- `覆盖式抽屉漏边` —— 官方抽屉是推挤式（聊天页整体右移一抽屉宽），覆盖式会在抽屉右缘漏出输入框；`translate({x: open ? '80%' : '0%'})` 用百分比别用像素。
- `@ 面板/命令面板不刷新` —— `ComposerPanels.ets` 的 `commands`/`entries`/`loading` 写成普通成员 → 父层 @State 换新值不重建子组件（实测 @ 面板永远卡「正在加载目录…」）；一律 `@Prop`。
- `@ 下钻整面板报错` —— 多根并发 `Promise.all` 里某根 404 会拖垮整张面板；逐根 `.catch(() => [])` 容错，全部为空才判失败。
- `新建会话没目录选项` —— 安卓空态有「工作目录」chip（默认手机会话，可换授权根下目录）；鸿蒙要 `store.pendingLocation` + 首条消息走 `session-create{rootId,cwd}`（core/SessionLocation.ts + components/SessionLocationSheet.ets）。
- `目录浏览显示空根` —— 首个授权根常是空的 `default-workspace`；REST 必须显式给 rootId，浏览时自动跳到下一个有子目录的根。
- `切界面风格不生效` —— 设置页只 `AppStorage.setOrCreate('dshThemeMode')` + `PrefsStore.putString`，但没人监听：`applyTheme` 只在 mediaquery 变化时被调。修法：Index 加 `@StorageProp('dshThemeMode') @Watch('onThemeModeChange')` + 缓存 `sysDark`，回调里 `applyTheme(this.sysDark)`；启动时异步读偏好回来再重算（`PrefsStore.getString` 返 Promise，`?? 'system'` 会编译成 `string | Promise<string>` 报 10505001）。
- `重连链提前终止` —— `GatewayClient.onDown` 原写 `!wasReady → CLOSED` + 重连 catch 里 `state=CLOSED`，掉线后第一次重连失败就永久 CLOSED（得重启 App）；安卓 `_onDone` 是无条件继续退避。改成 `reconnecting` 标志 + `scheduleReconnect()`，只有 `isFatal`（NO_TOKEN/PROTOCOL/DISPOSED）才收口；初连失败仍不自动重连（安卓同口径）。真机实测 1→2→4→8→16→30→30 且能自动连回。
- `一次掉线排两次退避` —— `@ohos webSocket` 一次掉线连发 `error` + `close` 两个回调，两个都 `onDown` → 1s 档被 2s 档顶掉。`WsTransport` 用 `claimDown()` 去重 + `GatewayClient.downAttempt` 二次防线。
- `历史分页没入口` —— `ChatStore.loadOlder()` 早有实现和单测，但 `pages/`+`components/` 里 grep `loadOlder` 零命中：UI 从未调用，用户无从触发（安卓 `chat_message_list.dart:196-215` 列表头「加载更早消息」）。入口在 `components/MessageList.ets` 的 `List` 首项，`hasMore` 由 `syncVersion()` 从 `st.historyHasMore` 抄；翻页 prepend 必须 `consumeHistoryPageJustLoaded()` 跳过贴底。**单测绿 ≠ 功能可达**，冒烟要按「用户能不能点」验，不是按核心类有没有方法验。
- `ui.sh dump 读旧快照` —— `harmony/build/ui.sh` 的 dump 分支直接 `hdc file recv`，命令失败时留下上一轮 `ui.json`，看起来「滑动完全没生效」；已改成先 `rm -f` + `stat -c%s > 100` 校验 + 重试 3 次。真机滑动验证前先确认这次 dump 是新鲜的。
- `hasMore=false 是正常` —— 会话事件数 < 200 时桥就返 `hasMore:false`，列表头本就不该出「加载更早消息」；查按钮不出现先用 `/home/wangke/probe-history.cjs <sessionId>` 直连 WS 看该会话首屏 `hasMore`，别一上来怀疑 UI 绑定。
- `翻页后跳底/跳顶` —— 点「加载更早消息」时 `ChatHistory.loadOlderIn` 会 `changed()` **两次**（开头置 `loadingOlder=true`、结尾 `.finally` 清），只有中间那次带 `historyPageJustLoaded`。若只在带标志那次做补偿、其余仍走「新消息贴底」分支，30ms 后 `jumpToBottom` 就把视口拉走（真机现象：跳到最新或跳到最顶）。修法：`syncVersion()` 里翻页期间（`loadingOlder || anchorIdx >= 0`）一律 return，补偿用 `scrollToIndex(target, false, ScrollAlign.START)` 并推迟 60ms（0ms 时 List 还没按新数据排完，索引会被夹到首尾）。
- `ForEach key 不能含 index` —— `` `${m.seq}-${idx}-${m.text.length}` `` 里带 idx，翻页把旧消息 prepend 到数组前部时 index 全体后移、key 全变，ArkUI 判定整列重建 → 滚动位置重置。key 只用稳定业务字段（`m.role + m.seq + 文本长度`）。
- `应用更新走市场` —— 鸿蒙应用只能 AppGallery 分发、不允许自更新；不要照搬安卓 Gitee/GitHub Release 检查，改 `@kit.AppGalleryKit` 的 `updateManager.checkAppUpdate(ctx)`（`updateAvailable===1` 有新版）/ `showUpdateDialog(ctx)`（系统弹官方更新框）。错误码 1009400001~7 见 `core/AppUpdate.ts`。
- `会话列表时间优先` —— 用户口径（2026-11-16）：先按时间（今天/昨天/更早）分桶、桶内再按工作区聚合，超过 2 天收进可折叠「更早」；安卓同口径（`app/lib/ui/session_groups.dart` 的 `groupSessionsByTime`，a91c1d9），两端一致。纯函数在 `core/SessionGroups.ts`。
- `TTS 必须先 setListener` —— CoreSpeechKit 不先 `setListener` 就 `speak`，onStart/onComplete/onError 全部收不到（引擎照读但无回调、无法判断结束）；`CreateEngineParams.online` 是 **0=在线 / 1=离线**，别当布尔用；引擎是进程级单例，Ability `onDestroy` 要 `shutdownTts()` 释放音频焦点。
- `分享要先 ShareKit` —— 只用 Want `action:ohos.want.action.sendData` 不一定弹系统分享面板；首选 `@kit.ShareKit` 的 `systemShare.SharedData`（UTD `general.plain-text` + content）→ `ShareController(data).show(context, {selectionMode: SINGLE, previewMode: DEFAULT})`，拿不到再退 Want。
- `发送键白底看不见` —— 禁用态不能用 `inputFill`（浅色主题等于白底白箭头），走 `sendDisabledBg/sendDisabledFg` 浅灰底 + 中灰箭头。
- `挂起提问只有 REST 有` —— 桥的 `chat.userQuestions/requested` 只在提问发生当时推送；WS 重连后 `replayPendingInteractions` 只补 **open** 的，`state:'continued'`（已续跑还没终答）的卡片**只有** `GET /chat/sessions/{sid}/questions` 拉得到。所以进会话必须 REST 兜底合流：`ChatStore.openSession` → `refreshPendingQuestions` → `HitlStore.mergeQuestions`（按 callId upsert，REST 侧 rpcId 空时保留 WS 侧旧值，空 callId 跳过），合流有变再 `changed()`。寿命口径：桌面端 delegate 未决 → 永不给卡片设超时；只有 delegate 拒绝才起 10 分钟自愈（服务端逻辑，客户端不持任何超时常量）。
- `REST 合流别用 JsonAccess.arr` —— `core/JsonAccess.ts` 的 `arr` 返 `Object[]`（拿不到字段），要 `objArr` 才是 `JsonMap[]`；`fetchQuestions` 就踩过这个。
- `会话列表待回答标记靠 REST` —— bridge 的 sessions 列表只下发 `pendingInteraction:'approval'`（挂起审批），**挂起提问不发**；非当前会话的 HITL 帧也不补推。标记必须靠 `GET /chat/sessions/{sid}/questions` + `/approvals` 逐会话探测，结果抄进 `@State` 数组（Map 不触发 ArkUI）。
- `GatewayApi 忘注入 HTTP transport` —— `new GatewayApi(gateway, null)` 会让所有 REST 功能（附件/图片交接/根列表/文件全文/挂起项）报 `NO_TRANSPORT`；两条连接路径（ConnectView 与 Index.autoConnect）都必须传 `new HttpTransportImpl()`。
- `bindContentCover 不含安全区` —— 全屏模态的内容从屏幕顶起算，顶栏会压在状态栏下（返回键只剩 16px 高）；`aboutToAppear` 里取 `win.getWindowAvoidArea(AvoidAreaType.TYPE_SYSTEM).topRect.height` 转 `px2vp` 存 `@State topInset`，根容器加 `.padding({ top: this.topInset })`。
- `image-handoff 缺 sessionId` —— bridge `attachmentsAndImage()` 强制要求 `name` 与 `sessionId` 两个 query 参数，缺一即 400 `BODY_INVALID`；`fetchImageHandoff(name)` 必须加 sessionId 实参（安卓 `gateway_api.dart:140` 漏传，同款潜在缺陷）。
- `createImageSource 要 ArrayBuffer` —— 传 `Uint8Array` 类型不符返回 undefined，随后 `createPixelMap` 抛 `Cannot read property 'createPixelMap' of undefined` 崩进程；先 `bytes.buffer as ArrayBuffer` 再建源并判空。
- `TTS 建引擎要探测参数` —— 真机 `{language:'zh-CN',person:0,online:0}` 报 `1002300005 create engine error`，加 `extraParams:{style,locate,name}` 报 `202 this is not systemCap`（未声明的 key 全校验失败）；按 `probeParams()` 依次试 `(online,person)` 组合，首个成功即缓存引擎。
- `命令卡被 reloadHistory 冲掉` —— 本地注入的 `role='command'、seq=-1` 消息不在服务端历史里，`reloadHistory` 整体替换 messages 会把它冲掉；替换前要收集 seq<0 的命令卡再拼回尾部（安卓 chat_history_actions.dart:36-40 同口径）。
- `字号/间距只能用官方刻度` —— 鸿蒙开发台（harmony_check review）的 R023 允许字号集 = `{8,9,10,12,14,16,18,20,22,24,28,30,36,38,46,48,56}`，R003 允许间距与圆角集 = `{0,2,4,6,8,10,12,14,16,18,20,22,24,26,32,36,40,56,64}`（圆角也不认 0，最小合法档 2）；13/15/11/17/7/3/1 这些「看着挺合理」的值全部算违规。写死在 `ui/theme.ets` 的 token 一旦越界，会连带报一串，先修 token 再修引用处。
- `hilog 只在 Dlog.ets` —— `entryability/EntryAbility.ets` 曾直调 7 处 `hilog.`（DOMAIN `0x0000`/TAG `DshChat`），与 `platform/Dlog.ets` 的 `0xD5C0`/`Dsh` 不一致 → 真机 `hilog -x | grep A0D5C0` 抓不到 Ability 生命周期日志；统一走 `Dlog.info/warn/error`。
- `剪段拆文件会静默带走别的方法` —— 按行号区间把 ChatStore 的历史段剪成 ChatHistory 时，夹在区间里的 `setPermission` 被一起带走，单测报 `TypeError: ctx.store.setPermission is not a function`。剪完必须 grep 原有公开方法名是否齐全；边界行先 `print(repr(line))` 核对，插入点用「唯一锚点字符串 + assert in」而不是行号。
- `拆帧模块漏 hello 分支` —— 把 `onFrame` 拆到 `core/GatewayRequests.ts` 时只搬了 event/error/ping/pong 分支、漏了 `kind==='hello'` → 连接永远不 READY，所有客户端用例挂满 300s 报 `Promise resolution is still pending but the event loop has already resolved`。拆这种 if 链函数要用「原分支数 == 新分支数」核对。
- `触控热区 ≥40vp` —— `harmony_check a11y` 的 R009 只认 `.height()/.width()` ≥40；加载指示器
  写成 `width(20)`/`width(32)` 也算「小热区」被拦（`ImageTile`、`MdDocViewer` 实踩）。
  纯装饰性图标可给 `.accessibilityGroup(true)` 或直接放大到 40；输入框高度 36 同样违规（`HitlPanel` 实踩 → 40）。
- `脚本拼 head+tail 会坏括号` —— 拆 GatewayApi 时尾部多出一个 `}`（`Unexpected "}"`），剪出的段又少一个方法闭合 `}`（`Expected identifier but found end of file`）。剪接脚本必须 assert 首尾行内容。
- `清 R005 用 Repeat 不是 LazyForEach` —— 鸿蒙开发台 R005（「ForEach 全量渲染」）在任何父容器下都报；
  `LazyForEach` 只能放 `List`/`ListItemGroup`/`Grid`/`Swiper`/`WaterFlow`，放 `Column` 里编译直接报
  `10905236 ERROR: UI component 'Column' cannot be used in this place`。**`Repeat<T>(list).each((item: RepeatItem<T>) => ...).key(...)`
  不受父容器限制**，是 Column/Scroll/Flex 内列表的唯一解；无稳定 id 的列表（Markdown 片段）key 要带
  index 参数：`.key((entry, index) => index.toString() + '-' + entry.text.length)`。
- `R006「LazyForEach 缺 keyGenerator」是误报` —— 第三参明明传了也报，触发条件是 itemBuilder 内是多行
  if/else 组件链。把帧内容抽成 `@Builder xxx(item)`、帧里只留 `ListItem(){ this.xxx(m) }` 即 pass。
- `R007 只认 matchMediaSync 调用` —— 文件里出现 `this.getUIContext().getMediaQuery().matchMediaSync('(width>=600vp)')`
  才 pass；只读 `@StorageProp('dshBreakpoint')`、或写成 `constraintSize({maxWidth: bp==='sm' ? '100%' : 720})`、
  或 `.onAreaChange(...)` 都**不算**断点分支（探针实测）。统一 helper 形态见 `core/Breakpoints.ts`。
- `往类里插方法要用类成员区锚点` —— 把 helper 插在 `aboutToAppear(): void {` 之后会插进函数体内部，
  连锁报 185 条 `10905236 UI component cannot be used in this place` + 大量 `10505001`；插在 import
  之后又可能插到文件首行之前（`arkts-no-misplaced-imports`）。锚点必须选「另一个方法签名之后」。
- `Repeat/@Builder 别插错 struct` —— 一个 .ets 里有多个 `export struct` 时，按行号插入很容易把
  `@Builder` 插到隔壁 struct，报 `Property 'xxx' does not exist on type 'TeamSheet'`。按 `export struct`
  边界精确定位，插在目标 struct 的 `build()` 之前。
- `带参 @Builder 不随 @State 刷新` —— ArkUI 的 `@Builder xxx(a, b)` 只要**带参数**（哪怕参数是稳定
  字符串 id、值全程不变），父组件重跑也不会重跑 builder，builder 内部读 `this.<@State>` 一律拿不到新值。
  真机实证两轮：①先按值传 `glyph/color/label` 不刷新；②改成只传稳定 id + builder 里 `this.glyphOf(id)`
  仍不刷新。**修法：显示值随状态变的部分一律内联到 `build()` 里**（`Text(this.speaking ? '⏹' : '🔊')`），
  或改成**无参** @Builder。症状特征：父层提示文案（如「正在朗读」）已出现、按钮图标/颜色纹丝不动。
- `bm dump 的版本段看错地方` —— `hdc shell "bm dump -n <bundle>"` 开头
  `applicationInfo.appQuickFix` 段是 `versionCode: 0` / `versionName: ""` / `bundleName: ""`（不是真实值），
  真正的版本在后面的 bundle 段（`versionCode: 1000000` / `versionName: "1.0.0"`）。别据此判「版本读不到」；
  `bundleManager.getBundleInfoForSelf(GET_BUNDLE_INFO_WITH_APPLICATION)` 本身是好的。

**Flutter-OH 构建坑位（`app/ohos/`，2026-11-25 实跑踩出，全部已修）**：

- `ohos SDK 必须 API 26` —— API 18 编不过；本机装 `tools/ohos-sdk`（HarmonyOS 26.0.0.105）。
  社区包布局是 `ohos-sdk/{bin,ohpm,hvigor,tool/node,sdk}`，**不是**官方文档写的 `tools/ohpm/bin`。
- `OH-Flutter 没有 linux-x64 定制 Dart SDK` —— `bin/internal/dart-sdk-url.ohos` 只发 darwin-arm64 /
  windows-x64 / linux-arm64；官方 Release 上 `dart-sdk-linux-x64-ohos.zip` 全 404。本机 x86_64 Linux 的
  解法：把该文件里 `dart-sdk-linux-x64.zip` 条目改指 CPF engine 路径
  `https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com/flutter_infra_release/flutter/d55dc4bdf08dd31de6cb88fd8e56c8bccea7656b/dart-sdk-linux-x64.zip`
  （含 `Abi.ohosArm*`，否则编译 flutter_tools 报 `Error: Member not found: 'ohosArm'`）。
- `cp -a 进已存在目录会嵌套` —— 换 dart-sdk 前先 `rm -rf`，否则变成 `dart-sdk/dart-sdk`，bootstrap 仍报
  `Member not found: 'ohosArm'`。
- `dart-sdk-ohos 是 macOS 二进制` —— `bin/cache/dart-sdk-ohos/bin/dartaotruntime` 是 Mach-O arm64，
  在 Linux 上当脚本执行报 `Syntax error: Unterminated quoted string` → `Target kernel_snapshot_program failed`。
  解法：把 `bin/cache/dart-sdk/bin/dartaotruntime`（Linux x64 ELF）拷过去覆盖。
  `bin/cache/dart-sdk-ohos/bin/snapshots/frontend_server_aot.dart.snapshot` 同理（macOS 版报
  `Architecture mismatch`），也要从 `bin/cache/dart-sdk/bin/snapshots/` 拷 Linux 版。
- `release 要补 product 版 patched SDK` —— AOT 构建要 `artifacts/engine/common/flutter_patched_sdk_product/`
  （含 `platform_strong.dill`），缺了报一串次生错（`dart:async is not available`、`Type 'Color' not found`）。
  下载 URL **不带 `common/` 这一层**（带 404、不带 206）。
- `HAP 构建默认要签名` —— 本机没有 AGC 账号，`flutter build hap` 会卡在「Auto-signing: AGC login required」。
  本机验证一律加 `--no-codesign`（产物 unsigned，不上架）。要本地签名用
  `scripts/sign-hap.sh`（release/debug 材料都在 `harmony/signing/`）；上架仍走 AGC。
- `上架用 .app 不是 .hap` —— `flutter build` 顶层有 `app` 子命令（Build an Ohos App file），上架用那个。
- `上游 Flutter 编不过 ohos fork` —— `TargetPlatform.ohos` 只在 Flutter-OH SDK 里有；
  用上游 SDK 编 material_ui 的 ohos fork 会挂在 `case TargetPlatform.ohos:` → **三端必须统一用 `tools/flutter-oh`**。
- `material_ui 穷尽 switch` —— pub.dev 的 material_ui 1.11.1 / cupertino_ui 1.1.7 有 62/90 处穷尽
  `switch (platform)` 缺 `TargetPlatform.ohos` → 鸿蒙端编译失败。已切 CPF ohos fork
  （`gitcode.com/CPF-Flutter/flutter_packages.git` ref `oh-3.47.7-dev`，走 `dependency_overrides`）。
  gpt_markdown 也有一处穷尽 switch，已 vendor 打补丁（`app/vendor/gpt_markdown/README.dsh.md` 记了原因）。
