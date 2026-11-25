# dsh-Chat

<p align="center">
  <strong>手机上的 DSH 聊天客户端 —— 一套 Flutter 代码，Android / iOS / 鸿蒙。</strong><br>
  连上你自己的 <a href="https://github.com/westanke/dsh-remote-bridge">dsh-remote-bridge</a>，
  对话、会话、工具调用都留在本机。
</p>

<p align="center">
  <img src="assets/promo-16x9.png" alt="dsh-Chat：聊天页、会话抽屉与连接设置（Android / iOS / HarmonyOS）" width="100%">
</p>

<p align="center">
  <a href="https://gitee.com/westanke/dsh-Chat/releases/tag/v1.0.36"><code>下载 v1.0.36 · APK / HAP</code></a>
</p>

<p align="center">
  <a href="./README.en.md">English</a> ·
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.36-087f8c">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-2da44e">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20HarmonyOS-586069">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <a href="https://github.com/westanke/dsh-Chat/actions/workflows/ci.yml"><img
     alt="CI" src="https://github.com/westanke/dsh-Chat/actions/workflows/ci.yml/badge.svg"></a>
</p>

`dsh-Chat` 是 [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge) 的 Flutter 客户端：
通过 REST `/api/v1` 取会话与历史，通过 WS `/ws/mobile`（子协议 `dsh-mobile-v1`，`hello.protocol=3`）
接收流式增量。本仓**只消费协议**，不改协议；协议的事实来源在 bridge 仓的 `docs/api/`。

**它适合谁**：把 DSH 当主力工具、又不想被“必须坐在电脑前”绑住的人。手机只负责显示和输入，
会话、工作区与文件都留在你自己的机器上；bridge 默认只监听回环地址，不会因为装了客户端就暴露机器。

**边界**：不是任何官方客户端的分支，不连接官方服务器，不复用其图标、字体或二进制资源。
界面尺寸与配色以官方 App 的实测像素为视觉基准（见 [`docs/design-tokens.md`](docs/design-tokens.md)），
但品牌触点（启动页标记、显示名、包名）全部是本工程自己的。

## 实际效果

<p align="center">
  <a href="assets/screenshots/chat.jpg"><img src="assets/screenshots/chat.jpg" width="280" alt="聊天页：Markdown、工具调用与改动卡片"></a>
  <a href="assets/screenshots/sessions.jpg"><img src="assets/screenshots/sessions.jpg" width="280" alt="会话抽屉：搜索、分组、运行中与当前主机"></a>
  <a href="assets/screenshots/settings.jpg"><img src="assets/screenshots/settings.jpg" width="280" alt="设置页：连接状态、设备权限与外观"></a>
</p>

左：聊天页，Markdown、工具调用、过程组与「改动了 N 个文件」卡片都在同一条时间线里。
中：会话抽屉，搜索、日期分组、运行中/待确认/未读筛选，以及当前桥接主机。
右：设置页，连接状态、设备权限、外观与通知入口；设备 ID 已隐去。

> 截图来自 HarmonyOS 真机（API 26）。Android 与鸿蒙共用同一套 Flutter UI；
> iOS 已补齐原生桥、尚未做真机视觉验收。

## 它能做什么

- **流式对话**：`chat.message.delta` 增量渲染 → `committed` 后重拉历史；外部端（REST）写入也会防抖刷新。
- **Markdown**：标题、嵌套列表、任务列表、代码块（Atom One Light 高亮 + 语言标签 + 复制）、
  表格（官方通栏表头）、引用、行内与块级公式、链接角标，全部按 token 映射。
- **工具调用**：按官方 Web 口径展示 —— 工具行标题三段分派（`运行命令`/`读取`/`编辑`/`搜索文件内容`/
  `网页搜索`/`工具调用 · 名字`…）、摘要取参数关键字段、五态（preparing/running/ok/stopped/failed）
  只进无障碍文案不占行、退出码徽标；展开后按工具类型给专属视图（Bash 等宽命令 + IO 区、
  diff `+N -M` 与行内差异、read 行窗口、search 命中、web 结果、提问卡）。实时帧驱动，不靠防抖重拉。
- **过程组**：连续调用收成一行标题，运行中带实时参数与闪烁；四档展示（简洁/标准/详细/完全展开）
  与收起时机都由设置驱动；轮尾一行 `已完成，用时 X` / `处理失败`。
- **思考流**：呼吸光点环 + 扫光亮标 + 三行高实时窗口；正文开始后收成首行摘要，轮结束自动收起；
  点一下展开全文（Markdown），再点收回。
- **改动与产出**：每轮结束补「改动了 N 个文件」（逐文件 `+N −M`，点开进 diff 页）与
  「生成了 N 个文件」（缩略图 + 类型说明，可复制路径/分享）；数据从工具结果的 `meta.diffs` 本地推导。
- **输入条**：一次可带多张图片（最多 6 张、逐张可删）、`@` 引用工程文件与历史会话
  （会话插 `@[标题](dsh-session:<id>)`）、`/` 斜杠命令；输入条上方常驻任务条；
  **草稿按会话各自保留**，切走再切回来还在（会话归档后自动丢弃）。
- **等待与重试可见**：模型已收到请求但还没输出时，输入区上方三个跳动的点；上游 504/限流触发
  内核自动重试时，消息流里出现可展开的「已重试模型请求（1/5）· 1s」，展开可见延迟与失败原因。
- **设备能力**：本地通知（回答完成/失败/待审批/待回答）、TTS 朗读、系统分享、相册选图、
  打开文件、私有目录；Android 支持 App 内下载更新，iOS / 鸿蒙走 App Store / AppGallery。
- **深色模式、侧边抽屉、失败可见、自动重连**：跟随系统两套色板；抽屉即时搜索 + 日期分组 + 设备账号栏；
  `turn/end` 失败以错误条呈现；退避 1→2→4→8→16s 封顶 30s。

## 支持的平台与当前状态

| 平台 | 现在到哪一步 |
|---|---|
| **Android** | **已真机验证**：配对、自动重连、流式对话、Markdown、工具行五态与详情、过程组四档、思考预览、提问卡、抽屉、深色模式、分享。v1.0.36 APK 26.6 MB |
| **iOS** | 原生桥已补齐 IANA 时区、私有目录、通知、TTS、分享、选图、打开文件；CI 已构建出未签名 IPA。**未在 iPhone 真机验证**；安装/更新走 App Store |
| **HarmonyOS** | **Flutter-OH 版已真机验证**（API 26）：配对、聊天、会话、分享、TTS、选图、通知与点击回跳均通过。正式 release HAP 需 AGC 正式签名 |
| 旧 ArkTS 版 | 在 `harmony/`，已冻结维护、后续退役 |

当前版本：`app/pubspec.yaml` 为 `1.0.36+37`，tag `v1.0.36`。

未验证的功能不会被写成“已完成”。真机截图是唯一验收证据。

## 下载安装

最新版 **v1.0.36**（Gitee 主站；GitHub 镜像同步同一 tag）：

| 产物 | 大小 | SHA-256 |
|---|---|---|
| [APK](https://gitee.com/westanke/dsh-Chat/releases/download/v1.0.36/dsh-Chat-v1.0.36.apk) | 26,615,566 字节 | `f91c7d37069abb12335a53f52d0f24eb697a8e29859c153b0973513a02369cd1` |
| [HAP](https://gitee.com/westanke/dsh-Chat/releases/download/v1.0.36/dsh-Chat-v1.0.36-harmony.hap) | 34,553,311 字节 | `2576f8b8da9c34a47d047063d28cb5ca75c346a13dd023ecf02e38663a6f754e`（项目发布证书签名） |

- Android：直接安装 APK；部分机型会弹风险拦截页，勾选确认后继续。
- HarmonyOS：HAP 需要设备信任的签名。开发机可用 `scripts/sign-hap.sh` 生成 debug 签名包；
  正式分发需 AGC 证书与 Profile。
- iOS：暂不提供 App Store 包；可按下方“从源码构建”在 macOS / GitHub Actions 出未签名 IPA。
- 历史版本与全部 SHA 见 [Gitee Releases](https://gitee.com/westanke/dsh-Chat/releases)
  与 [GitHub Releases](https://github.com/westanke/dsh-Chat/releases)。

> 版本号以 [`app/pubspec.yaml`](app/pubspec.yaml) 的 `version` 为准。

## 第一次使用

1. 在桌面端安装并启用 [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge)
   （要求 **≥ 2.10.0**，协议 v3），打开「手机设置 → 远程访问」。
2. 手机打开 dsh-Chat，进入「连接到 DSH Bridge」页，填 bridge 地址
   （局域网形如 `http://<主机地址>:3090`；Android 也可用
   `adb reverse tcp:3090 tcp:3090` 后填 `http://127.0.0.1:3090`）。
3. 粘贴桌面端生成的一次性配对码，点「配对并连接」。配对成功后凭证落本地，之后自动重连。

## 从源码构建

需要 Flutter-OH `3.50.0+ohos-1.3.3`、Android SDK、JDK 17；构建鸿蒙包还需要 HarmonyOS SDK API 26。仓库不附带这些 SDK。

```sh
cd app
flutter pub get             # 依赖变更后必跑
flutter analyze             # 提交前必绿
flutter test                # 590 例

flutter build apk --release --target-platform android-arm64
flutter build hap --release --no-codesign   # 鸿蒙 HAP（未签名）
```

- Flutter 必须用 **Flutter-OH**。上游 stable 没有 `TargetPlatform.ohos`，
  material_ui/cupertino_ui 的 ohos fork 编不过。
- iOS 在 macOS 上：`flutter build ios --release --no-codesign`，再把 `Runner.app/Payload`
  压成未签名 IPA；CI 的 `macos-15` job 已走通。

## CI 与发布

| 工作流 | 内容 |
|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | `docs-check` + `flutter analyze` + `flutter test`（590 例）+ 旧 `harmony/test` 的 `npm test`；用 Flutter-OH SDK |
| [`release.yml`](.github/workflows/release.yml) | tag 触发：Ubuntu 出 APK、`macos-15` 出未签名 IPA；HAP 为可选 self-hosted job（需 `BUILD_HAP=true` 与真实鸿蒙 SDK） |
| [`mirror-sync.yml`](.github/workflows/mirror-sync.yml) | Gitee → GitHub 镜像同步；GitHub 是从站，日常推送目标是 Gitee |

本仓发版以 Gitee 为主站：`scripts/release.sh` 负责门禁、APK/HAP 构建、可选签名、README 回填、
双站 Release 与附件回读；细节见 [`docs/project/RELEASE.md`](docs/project/RELEASE.md)。

## 仓库结构

```
dsh-Chat/
  AGENTS.md     ← 工程宪法：红线、命令、token 与协议纪律、文档同步表、坑位索引
  assets/       ← README hero 图与实际效果截图
  screenshots.json ← README/市场截图清单
  docs/         ← STRUCTURE.md（文件清单）/ design-tokens.md（设计基准）/ project/（文档索引）
  ref/          ← 官方界面基准截图、样式表与抓包记录，只读，不参与构建、不被 app/ 引用
  app/          ← Flutter 工程根（lib/ 下仅 design/、bridge/、ui/ 三个子目录）
  app/ohos/     ← Flutter-OH 鸿蒙宿主工程（bundleName com.dsh.dshchat）
  app/vendor/   ← 本仓打补丁的第三方包（gpt_markdown，见其 README.dsh.md）
  harmony/      ← 旧 ArkUI 原生鸿蒙版（已冻结维护、后续退役）
  LICENSE       ← AGPL-3.0 全文
```

`app/lib/` 的逐个文件职责见 [`docs/STRUCTURE.md`](docs/STRUCTURE.md)。

## 文档

| 文件 | 记的是 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | 工程宪法，改任何东西之前先读 |
| [`docs/STRUCTURE.md`](docs/STRUCTURE.md) | 目录与文件清单、协议引用、踩过的协议坑 |
| [`docs/design-tokens.md`](docs/design-tokens.md) | 颜色/字号/间距的唯一事实来源 |
| [`docs/project/README.md`](docs/project/README.md) | 项目文档索引与待建清单 |
| [`docs/project/RELEASE.md`](docs/project/RELEASE.md) | 三端构建、签名、发布与回读流程 |
| [`docs/终版对比-官方vs本工程.png`](docs/终版对比-官方vs本工程.png) | 终版并排对照图 |

## 已知限制

- **iOS 未真机验收**：原生桥已实现、CI 构建通过，但通知点击、TTS 音质、相册/文件权限等仍需
  iPhone 实机确认；iOS 不允许 App 内安装，更新只提示 App Store。
- **鸿蒙正式签名**：release HAP 用发布证书签名时，部分设备会报
  `signature verification failed due to not trusted app source`；正式分发需 AGC 证书/Profile。
- **应用名**：v1.0.36 已发布 HAP 的桌面名仍是 `dshchat`；源码已改为 `DSH Chat`，
  下个版本重打生效。
- **工具链锁定**：三端共用 Flutter-OH SDK；不要用上游 stable 替换，否则 ohos fork 依赖编译失败。
- **更新方式**：只有 Android 支持 App 内下载安装；iOS / 鸿蒙走各自应用商店。

## 仓库地址

| 站点 | 地址 | 说明 |
|---|---|---|
| Gitee | <https://gitee.com/westanke/dsh-Chat> | 主站 |
| AtomGit | <https://atomgit.com/westanke163/dsh-Chat> | 备站 |
| GitHub | <https://github.com/westanke/dsh-Chat> | 自动镜像从站，不手工推送 |

## 姊妹仓库

- [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge) —— 本仓的上游，桌面端插件
  （REST + WS + 手机设置面板）；协议与最低版本要求以它为准（当前要求 ≥ 2.10.0 / 协议 v3）。
- [`dsh-companion`](https://github.com/westanke/dsh-companion) —— 同生态的 Kotlin/Compose 客户端，
  与本仓共用同一套 bridge 协议；**已停止维护更新**，仅作历史参考。

## 许可证

[GNU Affero General Public License v3.0](LICENSE)。
