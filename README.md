# dsh-Chat

<p align="center">
  <strong>DSH Chat — Flutter client for dsh-remote-bridge</strong><br>
  一套 Flutter 代码（Android + iOS），把本机 <a href="https://github.com/westanke/dsh-remote-bridge">dsh-remote-bridge</a>
  的对话流渲染成原生聊天界面。对话、会话、历史全部留在你自己的机器上。
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-087f8c">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-2da44e">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-586069">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
</p>

`dsh-Chat` 是 [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge) 的 Flutter 客户端：
通过 REST `/api/v1` 取会话与历史，通过 WS `/ws/mobile`（子协议 `dsh-mobile-v1`，`hello.protocol=3`）
接收流式增量。本仓**只消费协议**，不改协议；协议的事实来源在 bridge 仓的 `docs/api/`。

**边界**：不是任何官方客户端的分支，不连接官方服务器，不复用其图标、字体或二进制资源。
界面尺寸与配色以官方 App 的实测像素为视觉基准（见 [`docs/design-tokens.md`](docs/design-tokens.md)），
但品牌触点（启动页标记、显示名、包名）全部是本工程自己的。

## 它能做什么

- **流式对话**：`chat.message.delta` 增量渲染 → `committed` 后重拉历史；外部端（REST）写入也会防抖刷新。
- **Markdown**：标题、嵌套列表、任务列表、代码块（Atom One Light 高亮 + 语言标签 + 复制）、
  表格（官方通栏表头）、引用、行内与块级公式、链接角标，全部按 token 映射。
- **工具调用折叠**：连续调用收成一行摘要，点开展开逐条明细（参数、失败标记、耗时）。
- **思考流**：`已深度思考` 折叠块。
- **深色模式**：跟随系统，两套色板分别校准。
- **侧边抽屉**：即时搜索 + 日期分组 + 设备账号栏；凭证持久化，配对一次后自动重连。
- **失败可见**：`turn/end` 失败（限流、额度耗尽等）以错误条呈现，不静默。
- **重连**：退避 1→2→4→8→16s 封顶 30s，与 bridge 的 kotlin-sdk 参考实现一致。

## 当前状态

| 平台 | 状态 |
|---|---|
| Android | **已装机验证**（vivo V2080A 真机）：配对、自动重连、流式对话、Markdown 全家福、工具折叠、抽屉、深色模式 |
| iOS | **未验证**。`ios/Runner` 平台壳（IANA 时区通道、显示名、ATS 放行）已就位，但未在 iOS 设备或模拟器上构建运行过 |
| 版本 | `app/pubspec.yaml` 为 `1.0.0+1`；尚无 tag 与正式 release 产物 |

未验证的功能不会被写成「已完成」。真机截图是唯一验收证据。

## 怎么跑

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd app
flutter pub get             # 依赖变更后必跑
flutter analyze             # 提交前必绿
flutter test                # 24 例
flutter build apk --debug   # 真机验证前
```

首次启动进「连接到 DSH Bridge」页：填 bridge 地址（如 `http://192.168.1.126:3090`；
真机可先 `adb reverse tcp:3090 tcp:3090` 再填 `http://127.0.0.1:3090`），
加上桌面端「手机设置 → 远程访问」生成的一次性配对码。配对成功后凭证落本地，
之后自动连接。

Android 工具链在 `/media/wangke/OFFICE/workspace/android-toolchain/`（jdk17 + sdk），
真机安装时 vivo 会弹风险拦截页，需勾选确认后再点继续安装。

## 仓库结构

```
dsh-Chat/
  AGENTS.md     ← 工程宪法：红线、命令、token 与协议纪律、文档同步表、坑位索引
  docs/         ← STRUCTURE.md（文件清单）/ design-tokens.md（设计基准）/ project/（文档索引）
  ref/          ← 官方界面基准截图、样式表与抓包记录，只读，不参与构建、不被 app/ 引用
  app/          ← Flutter 工程根（lib/ 下仅 design/、bridge/、ui/ 三个子目录）
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
| [`docs/终版对比-官方vs本工程.png`](docs/终版对比-官方vs本工程.png) | 终版并排对照图 |

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
  与本仓共用同一套 bridge 协议。

## 许可证

[GNU Affero General Public License v3.0](LICENSE)。
