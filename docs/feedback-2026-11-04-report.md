# 真机反馈 9 条（2026-11-04）调查报告

反馈来源：真机验收 dsh-Chat v2.2.x 后用户口述 8 条 + 追加第 9 条。
协议调查对象：dsh-remote-bridge @de39e3d（v2.10.0）。

## 逐条根因与协议依据

### 1. 图片手机端无显示
双根因，都在客户端：
- 协议侧：`ContentParts.from(content)`（models.dart）只提取 text/reasoning 块，
  **丢弃 image 块**。历史 user/message 的 content 里图片形状是
  `{type:'image', attachment:{attachmentId:'sha256:<hex>'}}`（引用，不含字节；
  依据 kernel-services.ts:54-58 注释、attachment-api.spec.ts:22）。
- UI 侧：chat_message_items.dart user 分支只 `Text(message.text)`，无图片渲染。

取字节通道（协议已有，无需改 bridge）：
- REST `GET /api/v1/attachments/{attachmentId}?sessionId=<sid>`（openapi.yaml:348-366；
  attachmentId 冒号须 percent-encode；files.read scope——设备默认 scope 含 files.read，
  contracts.ts:23-29；响应原始字节 + immutable 长缓存）。
- REST `GET /api/v1/image-handoff?sessionId=<sid>&name=<bare>`（openapi.yaml:314-344）：
  纯文本模型下图片被交接成工作区 `.dsh-images/<sha256>.<ext>`，消息文本里留
  `[Image: source: <绝对路径>]` 占位；文件名格式 `^[0-9a-f]{64}\.[A-Za-z0-9]+$`。
  **这条正是反馈第 8 条「电脑端识别」的手机端显示回路**。
- 认证：Bearer token（hosts.dart 已存 token）。

### 2. 单发图片不显示发送按钮
composer.dart:83-87 三态逻辑 `if (_hasText) return send; if (streaming) return stop; return disabled;`
—— `_hasText` 只看文本，pendingImage 不参与 → 单图时按钮 disabled。
修法：`_hasText || _pendingImage != null` 即 send。

### 3. "/" "@" 命令不可用
协议通道全部现成（ws-commands.ts）：
- `commands` {sessionId} → kind=commands data={commands:[{name,description,input?}]}
  （chat-adapter.ts:1190 listCommands：会话激活不了回 []，不报错）。
- `command-execute` {sessionId, line} → kind=command-executed data={sessionId,commandId,
  result:{kind:'success'|'error', text?, sourceEventSeq?}}；line 直接传 "/xxx" 字符串；
  正则要求 `/^\/([a-z][a-z0-9_-]*)/`，未知命令 404 COMMAND_NOT_FOUND。
- `command-options` {sessionId, command} → kind=command-options data={options:[{id,label,
  detail?,description?,selected}]}；只支持 model/permission，其他回 bad-request
  "command does not provide selectable options"。
- `command-select` {sessionId, command, optionId} → kind=command-selected。
- **@ 命令**：内核 listCommands 的 descriptor 里没有 @ 文件引用这种东西；
  bridge 对会话视图给了 `cwdAbsolute`（chat-adapter.ts:494 附近，"给手机端拼 @绝对路径 用"）。
  客户端可自己做 "@" 补全面板（从 files.read 相关接口拿文件树超范围，一期做纯文本 @提示 +
  已知路径注入即可，或只做 / 命令 + @ 提示 UI 占位）。
- @ 绝对路径：ChatSessionView.cwdAbsolute 已在 sessions 应答里，models.dart 未解析
  （DshSession 无该字段），需要补。

### 4. 模型面板按供应商分组收缩、默认展开当前供应商
model_sheet.dart 现在平铺 groups 全部模型。改 ExpansionTile 风格自绘分组行
（默认只展开 current.provider 所在组）。纯 UI 改动。

### 5. 无历史会话加载（翻页）
- WS `history` 帧支持 `beforeSeq`（ws-basic.ts:84-110 实测透传给 chat.history → 内核），
  应答 `{events, hasMore, projections?(仅首屏)}`。翻页帧**不带 projections**（1MiB 上限考虑）。
- REST GET /chat/sessions/{sid}/messages 也支持 beforeSeq+maxMessages（openapi.yaml:944-1009）。
- 客户端现状：chat_state.reloadHistory 只拉 200 条，models.dart HistoryPage.hasMore
  被硬编码 false（models.dart:479）→ 从 events 里取真值即可；gateway.history 需加 beforeSeq。
- 列表反向加载落点：chat_message_list.dart + chat_state.loadOlder()。

### 6. 已执行命令用 BASH 方式显示
process_group.dart _ToolDetail 用 mdInlineCodeBg 容器纯 Text 展示命令与输出。
落点：name==bash（及含 command 参数的调用）时，args 里的 command 用 DsMarkdownView
代码块（或 md_code_block 组件）渲染 bash 代码块样式。

### 7. 电脑端「开启新会话」未分组 → 加「手机会话」分组
用户截图证实：这是 **dsh 官方 Web GUI 侧栏**按 workspace 分组，无 workspace 的会话落
「未分组」。手机端对应诉求：抽屉日期分组（今天/昨天/更早）之外，无 workspaceId 的会话
单列一组。落点：chat_state.sessionGroups 之前先按 workspaceId 拆分：无 workspaceId 的
归「手机会话」组置顶（feedback 原话），有 workspaceId 的再按日期分组。
（另一解：手机新建会话时带 workspaceId 创建——session-create 帧支持 workspaceId 参数
（ws-sessions.ts:48-96），但「哪个 workspace」是用户决策，一期先做展示层分组。）

### 8. 不支持图片的模型可发图，由电脑端识别
**bridge v2.10.0 已实现**：handoffImagesForTextOnlyModel（bridge/attachments.ts:315-360）
—— 模型 inputModalities 不含 image 时，图片落盘工作区 `.dsh-images/`，消息文本留
两行说明（人读行 + `[Image: source: <绝对路径>]` 机器行），桌面 DSH 插件按路径读图。
手机端职责：发图流程不变（已支持）；显示回路靠第 1 条的 image-handoff 取图 +
第 3 条 cwdAbsolute。**本仓无需协议改动**。验收点：对纯文本模型发图，手机端消息气泡
显示交接说明文本；桌面端能按路径读图。

### 9. 应用内检测新版本并下载 APK（国内 Gitee / 国外 GitHub）
新增功能。仓库三远端：gitee 主站 / atomgit 备站 / github 从站（镜像 3h 同步）。
方案：
- 版本源：Gitee Releases API `https://gitee.com/api/v5/repos/westanke/dsh-Chat/releases/latest`
  （国内可达）；GitHub `https://api.github.com/repos/westanke/dsh-Chat/releases/latest`。
- 探测国内外：不 ping，直接先 Gitee（超时短 3s）失败再 GitHub；或按安装时区/语言兜底。
  简单可靠做法：先 Gitee 后 GitHub 自动回落，无需地理判断。
- 下载 APK 用系统浏览器打开 release 页最省事（免文件下载 + 免安装引导），
  或 DownloadManager 拉 asset。一期：检测到新版本弹提示 + 跳浏览器下载。
- 当前版本号来源：package.json/pubspec version + PlatformInfo。

## 工具链（本机已就绪，2026-11-04 报告）
- `source /media/wangke/OFFICE/workspace/tools/env.sh` + `export HOME=/media/wangke/OFFICE/workspace/tools/dsh-home`
  （HOME 必须重指，沙箱只读系统盘会让 flutter 遥测写 /home/wangke 崩）。
- Flutter 3.47.9 / Dart 3.13.7 / JDK 17 / Android SDK 36 全部验证可用；
  `flutter pub get` + `flutter analyze` 已跑，基线 No issues。
- gradle 缓存在 tools/gradle-home（9.3.1-all 预置），APK 构建可行。

## 实现顺序（客户端全部改动，不碰协议）
1. 反馈2（composer 一行逻辑）+ 反馈1（models.dart image part 解析 + items 渲染 +
   REST 取图客户端）——同一批改动耦合最小。
2. 反馈5（history beforeSeq 翻页 + hasMore）。
3. 反馈3（commands 帧 + 命令面板 UI；@ 一期做 cwdAbsolute 注入 + 提示）。
4. 反馈4（模型面板分组收缩）。
5. 反馈6（bash 命令代码块样式）。
6. 反馈7（抽屉「手机会话」分组）。
7. 反馈9（版本检测 + 下载）。
8. 反馈8（验收 + 显示回路依赖 1；无需独立改动）。

每步同提交更新 docs/STRUCTURE.md；提交信息 `<type>(<scope>): 中文摘要`。
