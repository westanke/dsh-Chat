# AGENTS.md — dsh-Chat 工程宪法

> 本文件是每次会话**必然读到**的那份约定。本工程由 AI 自主开发，规矩写在前面，
> 谁（包括未来的 AI 会话）动手前先读完这条。与 `dsh-remote-bridge` / `dsh-companion`
> 的宪法同源同制度，按客户端特色裁剪——**各边职责不同，不要互相照抄**。
> 本仓现含两个客户端形态：`app/`（Flutter 一套代码，Android + iOS + **鸿蒙**，Android 已发版）
> 与 `app/ohos/`（Flutter-OH 鸿蒙宿主工程，2026-11-25 起步）。
> 旧 ArkUI 原生版 `harmony/` 已于 2026-11-27 移除，只保留本机签名材料 `harmony/signing/`（不入库）。

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

- **一句话**：本仓承载 DSH Chat 客户端——`app/`（Flutter 一套代码，Android + iOS + 鸿蒙），
  复刻官方 DeepSeek App 的**界面**，
  对话内容由本机的 `dsh-remote-bridge`（REST `/api/v1` + WS `/ws/mobile`）提供。
- **上游依赖**：`dsh-remote-bridge` ≥ 2.10.0（协议 v3）。本仓**只消费协议**，不改协议。
- **不是什么**：不是官方客户端的分支；不接官方服务器；不逆向官方 APK 的代码/资源。

## 2. 法律红线（用户 2026-11-02 定，起步就不得违犯）

1. **产物标识符零 DeepSeek**：applicationId / bundle id / bundleName / 类名 / 资源名 /
   应用显示名 / About 文案，一律不含 `deepseek`（不区分大小写）。当前注册名：
   `com.dsh.dshchat`，显示名 `DSH Chat`（Android applicationId、鸿蒙 bundleName
   —— `app/android` 与 `app/ohos/AppScope/app.json5` —— 同名同源，改包名两平台一起改，
   先改本条再动 `app/android`、`app/ohos/AppScope/app.json5` 与 `app/ios`）。
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
  harmony/signing/     ← 仅本机保留的鸿蒙签名材料（.gitignore 已拉黑，不入库；2026-11-27 起）
```

铁律：
- **目录嵌套 ≤ 3 层**（用户长期规矩）；`lib/` 下子目录只许 `design/`、`bridge/`、`ui/` 三个。
- **平台豁免（用户已批，2026-11-25）**：`app/ohos/` 的 ArkTS 工程结构由 DevEco/hvigor 约定死，豁免嵌套限制
  （`AppScope/`、`entry/src/main/ets/{entryability,pages,plugins,platform}`、`hvigor/`）。
- 严禁 `/tmp`（用户长期规矩）；临时文件进 `app/build/` 或用户家目录。
- `ref/` 只进参考材料，**绝不**被 `app/` 的 Dart/gradle 或 `app/ohos/` 的 ets/hvigor 引用。

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

- 鸿蒙签名与 AGC 上架材料保留在本机 `harmony/signing/`（**绝不入库**，.gitignore 已拉黑）；
  旧的 `harmony/docs/RELEASE.md` 已随 ArkTS 工程移除，签名步骤见 `docs/project/RELEASE.md`。
- `app/ohos/local.properties` 由本机路径生成（hwsdk.dir / flutter.sdk），**不入库**；
  换机器要重跑 `flutter create --platforms ohos` 或手改这两行。
- 真机：HarmonyOS 6.0 手机（API 26）。2026-11-25 起步时 `hdc list targets` 为空、尚未装机；
  之后 Flutter-OH 版已完成真机验证（配对、聊天、会话、分享、TTS、选图、通知与点击回跳，
  截图见 README「实际效果」）。release HAP 仍需 AGC 正式签名。

## 7. 代码纪律

- **单文件 ≤ 500 行**（Dart 心智负担高于 TS？低于 Kotlin，折中取 500）。超了拆文件，不许 `// ignore` 糊弄。
- 禁 `print`（用 `debugPrint`）；禁 `dynamic` 满天飞（协议模型必须显式 `fromJson`/`toJson`，字段可空性如实声明）。
- 每个 bridge 帧模型要有 JSON round-trip 单元测试（构造 → toJson → fromJson → 字段相等）。
- 样式值必须有 token 依据（§4）；新 UI 元素先在 `design-tokens.md` 登记。
- `flutter analyze` 的 warning 不许积压；info 级要注释理由才能留着。

**ArkTS（`app/ohos/` 插件）追加条目**：

- 单文件 ≤ 500 行；禁 `any`/`unknown` 满天飞，协议与通道数据结构显式定义 class + `fromJson`。
- ArkTS 不是 TypeScript：禁结构化破坏性赋值、禁运行时改对象 shape、禁对象 interface 联合 type 判别；
  import 不带 `type` 修饰符。
- 日志统一走插件里的 Dlog/AppLog 封装，不直调 `hilog`；插件只做通道转发，业务状态机放 `app/lib/`。

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
| 文档 | `bash scripts/ci/docs-check.sh` | STRUCTURE.md 覆盖全部 lib/、app/ohos ets/ts 文件、无死链、无旧仓名 |
| 代码（Android/iOS/鸿蒙） | `flutter analyze` → `flutter test` | 在 `app/` 下跑；**用 Flutter-OH SDK**（`3.50.0+ohos-1.3.3`，CI 里 clone 自 atomgit + 改 `dart-sdk-url.ohos` 指向 CPF 的 linux-x64 定制 Dart SDK）。**不能用上游 stable**：material_ui/cupertino_ui 的 ohos fork 里 `TargetPlatform.ohos` 有 89 处引用，上游 SDK 直接报 `undefined_enum_constant` |

刻意不跑 `flutter build apk` 与 `hvigorw assembleHap`：产物不入库，验收在本机真机，
CI 构建没人用（理由见 ci.yml 头注释）；鸿蒙构建需 DevEco 工具链，runner 上没有
（发版口径见 `docs/project/RELEASE.md`）。

**发版全流程（两段式，v1.0.17 实测定稿，照做不出错）**：

- 阶段 A（本机 APK）：版本 bump（pubspec versionName+versionCode，版本号构建期注入）
  → analyze/test/docs-check 全绿 → `SKIP_CHECK=1 bash scripts/release.sh`
  （产出 `artifacts/dsh-Chat-v<ver>.apk` + README/SHA256SUMS 回填 + commit）。
- 阶段 B（双站 Release）：`SKIP_CHECK=1 bash scripts/release.sh --publish`
  （PUSH_TAGS=1 推分支+tag；建 Gitee Release 传 APK/SHA256SUMS；AtomGit 由
  `.gitcode/workflows/release-android.yml` 在 tag 上自动出 APK 并建 Release/传附件，
  本机脚本兜底建 Release 并用「tag 维度 upload_url + PUT」补传，幂等；回读验证 SHA 一致，
  AtomGit 附件缺失只提示不失败。详见 `docs/project/RELEASE.md` §3.5）。**推送须用户明确同意**（见上）。
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
  `GITHUB_ACTIONS=true`（GitHub 自动注入）时跳过国内镜像直连官方源；本机与 AtomGit 国内
  runner 仍走阿里云镜像（settings.gradle.kts / build.gradle.kts）。
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
