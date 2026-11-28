# 调查报告：对照 dsh-go 与 ds-harness-remote，dsh-Chat / dsh-remote-bridge 的能力与界面提升面

- 日期：2026-11-28
- 对象与基线：
  - `dsh-Chat`：Flutter 客户端，`1.0.39+40`，HEAD `878846c`（git status 干净）
  - `dsh-remote-bridge`：Node/TS 桥，`2.18.1`，HEAD `e8870c6`（git status 干净）
  - `dsh-go`：上游源码副本 `dsh-go-src/dsh-Go`，`1.2.0+1`，AGPL-3.0
  - `ds-harness-remote`：上游源码副本 `ds-harness-remote-main`，`0.6.7`，MIT
- 方法：只读源码与仓库内文档；按「能力位 → 端点/帧 → 客户端调用点」三层核对；每条结论给出证据文件与行号；不跑真机、不改代码。
- 口径说明：文中「已实现」指仓库内存在可调用实现与文档，不等于真机验收通过；工作量为含单测、不含发版的人日估算。

---

## 0. 结论

### 0.1 一句话判断

桥已经「有面」，客户端还没「上桌」：`dsh-remote-bridge` 把后台任务、文件、语音、插件、置顶、反馈、定时任务新建这些面都备好了，`dsh-Chat` 大部分还没有入口。下一步的主要矛盾不是加协议，而是把桥已备好的能力做成手机界面。

### 0.2 五个结论

1. **桥的能力面领先客户端一个身位。** `job-list/job-output/job-kill` 三帧（`src/host/capabilities.ts:110`）、分块附件上传（`:116`）、语音转写（`:118`）、文件浏览/写/回收站（`:57`）、插件清单与启停（`:80`）、置顶与消息反馈（`src/host/bridge/kernel-allowlist.ts:128-129` 等）都已在桥侧；客户端对 `pluginInventory/pluginManager`、`pinSession`、`messageFeedback`、`speech` 的检索是零命中；`jobs` 只有 `tool_titles.dart` 里的工具行文案，没有功能接入；插件面板还是占位（`app/lib/ui/session_info_sheet.dart:369`）。
2. **客户端会话正文区已接近 dsh-go 的水平，差距集中在三块外围。** 正文区已有过程组四档、改动卡→diff、命令卡、审批/提问卡、队列/目标/待办/活动条、上下文环、会话搜索、归档、定时任务列表、消息级分叉；缺的是「外围页面」（后台任务、文件、插件）、「组织能力」（置顶、未读、多选、文件夹）、「输入与消息动作」（语音、引用、编辑重发）。
3. **两个参照产品走的是两条不同的轴。** dsh-go 是「本机引擎 + 手机原生全栈」：App 内装 Ubuntu/Node/DSH，终端、文件树、子代理谱系、团队、分享、回放、桌宠全原生；ds-harness-remote 是「接入基础设施 + 多后端」：账号/设备配对、Noise E2EE、LAN→P2P→TURN→Relay 自适应、DSH Web 票据交接、CodeX/ACP。dsh-Chat 的合理定位是第三条：**远程 DSH 的最佳手机客户端**，不追本机引擎、终端、桌宠。
4. **最高 ROI 的四个 P0 都在客户端，不动协议：** 后台任务面板、产物卡打开/分享、抽屉组织能力、顶栏信息架构。桥对应的帧/端点已经存在，缺的是 UI 与状态管理。
5. **桥侧近期该做的是「契约收口」，不是继续铺面：** 能力位→客户端消费矩阵、`pin/feedback/unread` 的专用帧（现在只能走 `kernel-call`）、定时任务新建/编辑的客户端契约样例、附件上传进度语义。分享、终端、DSH Web 交接属于架构级，需要单独立项，不宜混进本轮。

### 0.3 建议先做的四项

| 顺序 | 项目 | 为什么现在做 | 估算 |
|---|---|---|---|
| 1 | 后台任务面板 + 顶栏胶囊 | 桥三帧 + 推送已就绪；用户「发出去就不管了」的痛点最直接 | 3–4 人日 |
| 2 | 产物卡打开/预览/分享 | 已有 `DeliverablesCard` 的完整打开链可复用，`ArtifactCard` 却只能复制路径 | 2–3 人日 |
| 3 | 抽屉组织：置顶/未读/多选归档 | 置顶走 `kernel-call` 已可达；未读可纯客户端推导 | 3–4 人日 |
| 4 | 顶栏信息架构 | 标题可点、模型/上下文/任务/子代理胶囊，都是纯 UI | 2–3 人日 |

---

## 1. 两个参照产品在做什么

### 1.1 dsh-go：把 DSH 做成手机原生 App

- **本机引擎**：App 内装 Ubuntu/Node/DSH，无需 Root/Termux；也可 SSH 或经 DS Harvest Remote 连远程。这是它和纯客户端产品最大的区别。
- **会话页全栈**（`docs/official-parity.md` 自述「几乎全部原生」）：
  - 后台任务：顶栏「N 个后台任务」，`job/list`、`job/follow`、`job/kill`（`:43`）
  - 子代理目录与谱系：顶栏胶囊、详情谱系树、点开续聊、一次性只读（`:44`）
  - 工作区文件树与文档预览：文本/图片/PDF/表格，Office 由主机转 PDF（`:48`）
  - 终端：多标签、快捷键行、离开继续跑（`:49`）
  - 智能体团队：成员/任务板/消息（`:53`）
  - 会话长按：置顶、重命名、移到文件夹、分享、多选、归档（`:54`）
  - 未读完成提醒：行尾小圆点 + 「未读」筛选（`:57`）
  - 引用追问：长按回复/选中文字 › 引用，引文在输入框上方（`:118`）
  - @ 引用文件/对话/子代理（`:25`）；思考过程机器翻译（`:33`）；语音输入（`:34`，待真机验证）
  - 分享码：链接/二维码/`.dshgo`（`:113`）；系统集成：分享进来、桌面快捷方式、快速设置磁贴（`:120`）
- **App 自有能力**：分享面板、回放、主题/字号、桌宠、社区/论坛、DS Bot、订阅账号；插件市场与插件配置页；自动化任务的新建/编辑/运行记录。
- **它的代价**：能力随 Host 与连接方式不同；经 DS Harvest Remote 只支持图片附件、不能 App 内开网页版、插件管理仅开关、不支持 DS Bot 与对话日志导出（README 自述）。这正好说明「全栈原生」在远程连接下会打折。

### 1.2 ds-harness-remote：把远程接入做成基础设施

- **接入层**：同账号设备发现、身份固定（key 变化 fail closed）、Noise IK 端到端加密、LAN→P2P→TURN→Relay 自适应、RPC/流按连接隔离；Remote Server 可 Docker 自部署。
- **多后端**：Harness 官方会话优先，另接 CodeX App Server 与 ACP（Cursor/Antigravity/Pi/OpenCode/Claude/Hermes），独立数据面（`docs/design/PRODUCT.md:17`）。
- **外围**：只读工作区文件 + 交互终端 + 授权本机开发服务预览（`PRODUCT.md:18`）；DSH Web 票据交接（0.6.7，`docs/CHANGELOG.md:11`）；跨机器复制会话历史（0.6.6）。
- **手机端体验**（0.6.3–0.6.7 累积）：后台任务日志与终止、Mermaid、自动化任务管理与表单创建、锁屏实时任务通知 + 会话深链、工作区分组/会话手动排序、消息全屏编辑、选词引用、拍照/视频/二进制文件、LAN 大文件独立 WS、离线草稿、reduced motion、11 语言、浅/深色（`docs/CHANGELOG.md:139-140`、`:162`、`:86-92`）。
- **设计原则**（`docs/design/DESIGN.md`）：会话优先；复用官方契约；只显示上游确认的模型/effort/权限；审批单次允许或拒绝；Host 侧校验路径/归属/身份；错误给可执行恢复步骤；文件预览只读、不执行 Host HTML/SVG/PDF 脚本；终端关闭释放订阅、重连恢复有界屏幕不重放输入。

### 1.3 两条轴对 dsh-Chat 的含义

| 维度 | dsh-go | ds-harness-remote | 对 dsh-Chat 的含义 |
|---|---|---|---|
| 核心卖点 | 手机即主机 | 任何网络下安全接入 | 我们做「远程 DSH 的最佳手机客户端」 |
| 能力重心 | 会话页 + 本机工具链 | 连接/身份/多后端 | 先把会话页外围补齐，再谈接入增强 |
| 不做什么 | 不做多后端 | 不做本机引擎 | 终端/回放/桌宠/社区都不跟 |
| 可借鉴 | 任务/文件/子代理/消息动作的交互密度 | 能力真实呈现、错误恢复、只读边界 | 两者都借，但不背它们的架构包袱 |

---

## 2. 能力对照矩阵

图例：✅ 已实现；◐ 部分/只读/有入口不完整；❌ 无；— 不适用。

### 2.1 会话与消息

| 能力 | dsh-go | ds-harness-remote | 桥 | dsh-Chat | 判断 |
|---|---|---|---|---|---|
| 会话列表/搜索/归档 | ✅ | ✅ | ✅ | ✅ | 已对齐 |
| 会话置顶 | ✅ | ◐ 收藏/最近 | ◐ 仅 `kernel-call` | ❌ | 客户端可做，建议桥补专用帧 |
| 会话文件夹/分组 | ✅ | ◐ 工作区分组 | ❌ | ❌ | 低优先 |
| 未读/运行中/待确认筛选 | ✅ | ◐ | ◐ 无 unread | ◐ 三档有、未读恒 0 | 客户端可本地推导未读 |
| 多选批量归档 | ✅ | ❌ | ❌ 单条 | ❌ | 客户端循环调用即可 |
| 消息复制/点赞/朗读/分享/分叉/重生成 | ✅ | ◐ | ✅ 反馈可写 | ◐ 点赞仅本地、分享仅文本 | 反馈落库是桥已备好的 |
| 引用追问 | ✅ | ✅ 选词引用 | 无需新端点 | ❌ | 纯客户端 |
| 编辑重发/多选 | ✅ | ✅ 全屏编辑 | 分叉已支持 | ❌ | 纯客户端 |
| 每轮用量/花费/步数 | ✅ | ✅ | ✅ stats | ◐ 仅会话统计 | 小项 |
| 长工具输出头尾折叠 + 查看全部页 | ✅ | ✅ | n/a | ◐ 仅 24 行截断 | 小项 |
| 子代理谱系/续聊 | ✅ | ◐ 折叠活动区 | ✅ history 帧 | ◐ 只读历史页 | 补谱系与续聊 |
| 智能体团队 | ✅ 成员/任务/消息 | ◐ 折叠活动区 | ✅ 只读投影 | ◐ 只读 TAB | 写操作需评估 |
| 后台任务 | ✅ | ✅ 日志/终止 | ✅ 三帧 + 推送 | ❌ | **P0** |
| 定时任务 | ✅ 列表/新建/编辑/历史 | ✅ 管理 + 表单 | ✅ REST 四条 + 十帧 | ◐ 列表/运行/开关/删除 | 补新建/编辑 |
| 插件管理 | ✅ 市场/配置/实验开关 | ✅ 插件弹窗 | ✅ 清单/启停 + kernel-call | ❌ 占位 | **P1** |
| 分享/回放/分享码 | ✅ | ❌ | ❌ | ◐ 文本分享 | 不建议追 |

### 2.2 文件、终端与 Web

| 能力 | dsh-go | ds-harness-remote | 桥 | dsh-Chat | 判断 |
|---|---|---|---|---|---|
| 工作区文件浏览 | ✅ 树 + 预览 | ✅ 只读 | ✅ roots/entries/content | ❌ | **P1** |
| 单文件打开 | ✅ 系统/内置 | ✅ 内置受限 renderer | ✅ content | ◐ 交付卡可开、产物卡不可 | **P0 统一** |
| PDF/Office/表格预览 | ✅ Office 转 PDF | ✅ 本地 renderer | n/a | ❌ | 先系统打开，内置后置 |
| 附件发送（任意文件/大图） | ◐ 经 Remote 仅图片 | ✅ 分块/拍照/视频 | ✅ 分块上传 256 MiB | ◐ 大图走 REST 大消息 | 走附件路径 |
| 终端 | ✅ | ✅ | ❌ 设计拒绝 | ❌ | 不做 |
| Host DSH Web | ✅ 网页模式 | ✅ 票据交接 | ❌ | ❌ | 架构级，后置 |
| 本机开发服务预览 | ❌ | ✅ | ❌ | ❌ | 不做 |

### 2.3 输入、通知与外观

| 能力 | dsh-go | ds-harness-remote | 桥 | dsh-Chat | 判断 |
|---|---|---|---|---|---|
| 语音输入 | ✅ 系统/引擎两路 | ❌ | ✅ 8 帧 + PCM16 | ❌ | **P1**，需原生录音 |
| 语音朗读 | ✅ | ❌ | n/a | ✅ 系统 TTS | 已对齐 |
| 拍照 | ◐ 相册/图片（对照表未见相机） | ✅ 0.6.5 | ✅ 附件上传 | ❌ | 需原生 CameraX |
| 通知 | ✅ 完成/待确认 | ✅ 锁屏实时任务 + 深链 | n/a | ◐ 完成/待确认，无操作按钮 | P2 升级 |
| 浅色主题 | ✅ | ✅ | n/a | ❌ 仅深色 | P2 |
| 多语言 | ◐ 引擎设置语言 | ✅ 11 语言 | n/a | ❌ 仅中文 | P2 |
| 无障碍/大字号/reduced motion | ◐ | ✅ 目标/部分 | n/a | ◐ 仅字号 | P2 |
| 宽屏三栏 | ✅ ≥840dp | ✅ 条件三栏 | n/a | ❌ 刻意不做（`window_class.dart:8`） | 保持 |

### 2.4 接入与安全

| 能力 | dsh-go | ds-harness-remote | 桥 | dsh-Chat | 判断 |
|---|---|---|---|---|---|
| 配对/设备身份 | ✅ 二维码 | ✅ 账号 + 设备 + 固定身份 | ✅ 配对码/令牌 | ✅ | 已对齐 |
| 端到端加密 | ✅ 经 SSH/Remote | ✅ Noise IK | ❌ 文档未见 E2EE | ❌ | 架构级，单独立项 |
| 多客户端并行 | ◐ | ✅ | ◐ 多连接 | ◐ | 够用 |
| 多后端（CodeX/ACP） | ❌ | ✅ | ❌ | ❌ | 不做 |
| 断线重连/续传 | ✅ | ✅ | ✅ | ✅ 重连 + 快照 | 已对齐 |

---

## 3. dsh-Chat 提升清单

> 排序原则：桥已就绪且用户高频 → P0；需要少量原生/桥配合 → P1；大改或生态向 → P2。
> 每项给出「现状 / 证据 / 参照 / 改法 / 验收 / 估算」。

### P0-1 后台任务面板 + 顶栏胶囊

**现状**：只能在过程组里看到「job_list/job_output/job_kill」的工具行（`app/lib/ui/tool_titles.dart:68-70`），没有「当前有哪些后台任务、跑到哪、要不要停」的入口；活动条只反映当前轮（`app/lib/ui/activity_strip.dart:1-10`）。

**证据**：客户端 `jobs` 除工具行文案外零命中（`tool_titles.dart:68-70` 只是标题，没有数据层）；桥已有 `job-list`/`job-output`/`job-kill` 三帧与 `chat.job.updated|finished` 事件（`docs/project/API.md:1056-1058`、`:1113`），并有 REST `GET …/jobs` 兜底；断线重连先 `job-list` 拉基线（`src/host/ws-jobs.ts:18`）。

**参照**：dsh-go 顶栏「N 个后台任务」+ 进行中/已结束 + 实时输出 + 停止（`official-parity.md:43`）；ds-harness-remote 后台任务日志/终止（`CHANGELOG.md:139-140`）。

**改法**：
1. `GatewayClient` 增 `jobList/jobOutput/jobKill`（WS 优先，REST 兜底）；订阅 `chat.job.*` 事件更新本地表。
2. 新增 `ui/jobs_sheet.dart`：进行中/已结束两段，行内显示命令、耗时、末行输出；点开增量拉 `job-output`（带 cursor），底部「停止」调 `job-kill`。
3. 顶栏标题胶囊尾端加任务胶囊（与定时任务胶囊同位置，`chat_top_bar.dart:197`），显示运行中数量；点击开 sheet。
4. 会话切走/断线时保留基线，重连后以 `job-list` 覆盖，不做乐观合并。

**验收**：跑一个 `sleep 60` 的后台命令 → 顶栏出现 1；进 sheet 能看到输出增长；停止后状态变「已终止」；断线重连后列表仍在；退出会话再进不丢。

**估算**：3–4 人日。

### P0-2 产物卡打开/预览/分享（统一到交付卡链路）

**现状**：`ArtifactCard`（「生成了 N 个文件」）只有缩略图、文件名、类型说明；点行只弹「复制路径 / 分享」，分享还是「分享暂不可用」（`app/lib/ui/chat_artifact_card.dart:117-156`）。图片缩略图不可点开。相比之下，`DeliverablesCard`（交付文件卡）已经能：`.md` 进全屏渲染页，其他类型 `resolve + readContent + DshPlatform.openFile`，失败回退系统分享（`app/lib/ui/chat_message_items.dart:380-430`）。

**证据**：`DshPlatform.openFile` 已存在（`app/lib/bridge/platform.dart:185-205`，FileProvider + ACTION_VIEW）；`gatewayResolvePath/gatewayReadFileBytes` 已存在；产物卡没有复用。

**参照**：dsh-go 产物卡「预览/打开/分享/存下载」；ds-harness-remote 文件卡点击进只读预览（`DESIGN.md:42-46`）。

**改法**：
1. 把 `DeliverablesCard` 的打开链抽成 `openWorkspaceFile(context, gateway, path, name, mime)`，两卡共用。
2. 产物行整行可点；图片/文本/Markdown 走内置，PDF/Office 先系统打开；长按菜单：打开、复制路径、分享。
3. 分享改为「先写缓存再 `ACTION_SEND` 带 `content://`」；需要给 `DshPlatform.share` 增加 `shareFile(name, bytes, mime)` 原生方法（Android 现有 FileProvider 可复用，鸿蒙需对应实现）。
4. 图片缩略图点开 `openImageViewer`，查看器补「保存到相册/分享」。

**验收**：产物卡里 PNG 点开大图；`.md` 进渲染页；`.pdf` 调起系统查看器；分享面板出现文件而不是路径字符串；无查看器时提示而不是死点。

**估算**：2–3 人日（不含鸿蒙原生分享）。

### P0-3 抽屉组织能力：置顶 / 未读 / 多选归档

**现状**：抽屉有四档筛选胶囊（全部/运行中/待确认/未读，`drawer_filter_bar.dart:13-17`），但「未读」恒为 0，代码注释写明「桥不下发 unread」（`sessions_drawer.dart:60`、`:174`）；长按菜单只有重命名/分叉/归档（`session_actions.dart:1-60`），无置顶、无文件夹、无多选、无「删除已归档」。

**证据**：桥的 `workspace/pinSession|unpinSession` 在通用内核白名单里（`kernel-allowlist.ts:128-129`），本地 workspace 清单已带 `pinnedSessionIds`（`kernel-local.ts:334/348`）；客户端 `pinSession|pinned` 零命中。`messageFeedback/*` 同样在 allowlist（`kernel-allowlist.ts`），客户端零命中。

**参照**：dsh-go 长按「置顶、重命名、移到文件夹、分享、多选、归档」（`official-parity.md:54`），未读圆点 + 筛选（`:57`）；ds-harness-remote 工作区分组、会话手动排序、收藏/最近。

**改法**：
1. **置顶**：走 `kernelCall('workspace/pinSession', {sessionId})`（客户端已有 `gateway_kernel.dart:185` 调用面；`kernel-call-v1` 不可用时隐藏入口）；列表读 `pinnedSessionIds`，置顶区固定在最上，长按菜单加「置顶/取消置顶」。
2. **未读**：不依赖桥。客户端为每个会话记录「最后查看时的事件序号/时间」到本地偏好；收到 `chat.*` 事件且会话不在前台时标未读；进会话清除。dsh-go 也是本地口径。
3. **多选**：抽屉顶部进入选择态，批量归档（循环单条 `archive`，或桥后续补批量端点）；归档区补「删除」需桥先有删除端点，暂不做。
4. 置顶/未读都做「失败回滚 + SnackBar」，不乐观改服务端真值。

**验收**：置顶三个会话后重进 App 顺序不变；未读圆点在新回复后出现、进会话消失；多选归档 5 条后列表同步缩减；`kernel-call-v1` 关闭时置顶入口不出现。

**估算**：3–4 人日。

### P0-4 顶栏信息架构

**现状**：顶栏是「标题胶囊（标题 + 状态行）+ 定时任务胶囊」（`chat_top_bar.dart:1`、`:76-81`、`:197`）；没有模型 chip、上下文环、后台任务/子代理胶囊；模型入口在输入条 chip 与更多菜单（`chat_page.dart:470-472`）。

**参照**：dsh-go `chat_header.dart` 的标题/模型/任务/子代理胶囊；ds-harness-remote 聊天标题栏的 Trajectory 入口与 session-tools-panel。

**改法**：
1. 标题胶囊点击 → 打开 `session_tabs_sheet`（信息/统计/轨迹/团队/任务）。
2. 状态行右侧加三个轻量胶囊：模型短名（点击切模型）、上下文百分比（点击看用量）、后台任务数（点击开 jobs）。
3. 子代理运行中时加「N 个子代理」胶囊，点击进谱系页（见 P1-5）。
4. 胶囊总宽超限时按优先级折叠进「更多」，不做横向滚动。

**验收**：375dp 宽不换行不裁切；点标题进会话面板；模型胶囊切完刷新历史；上下文百分比与 `context_usage_bar` 同源。

**估算**：2–3 人日。

### P1-5 子代理谱系 + 续聊

**现状**：`subagentCatalog` 已解析（`app/lib/bridge/projections.dart:292`），`subagentHistory` 已封装（`gateway_api.dart:357`），但 UI 只有 `subagent_history_page.dart` 的只读历史，没有谱系树、没有「点开续聊」。

**参照**：dsh-go 顶栏胶囊 → 谱系树 → 点开续聊（`official-parity.md:44`）。

**改法**：团队 TAB 下加「谱系」子页，按 parentId 建树；节点点开进现有历史页；「续聊」用 `fork`/`send` 到子会话（桥若不允许对子会话发消息，则只做只读 + 复制任务描述）。先确认内核契约再决定是否做续聊。

**验收**：三层子代理树正确缩进；节点显示状态/耗时；历史可分页；续聊不可用时按钮禁用并说明原因。

**估算**：3–5 人日（取决于续聊契约）。

### P1-6 消息动作：引用追问 / 编辑重发 / 多选

**现状**：助手消息操作条只有复制/喜欢（本地）/朗读/分享（文本）/分叉/重新生成（`message_actions.dart:5-16`、`:98-130`）；用户消息没有「引用」「编辑重发」；没有多选。

**参照**：dsh-go 引用追问（`official-parity.md:118`）、从消息分叉、多选；ds-harness-remote 选词引用、全屏编辑、消息操作（`CHANGELOG.md:162`）。

**改法**：
1. **引用**：长按/选中文字 → 记录 `{sessionId, seq, 摘录}` → 输入条上方显示引用条 → 发送时拼成 `> 摘录\n\n` 前缀（纯客户端，协议不变）。
2. **编辑重发**：用户消息长按「编辑」→ 预填输入条 → 发送时新建一轮；若要替换原轮，用 `fork(atSeq)` 从该消息前分叉（已有 `chat_state.dart:672-684`）。
3. **多选**：进入选择态，支持批量复制 Markdown、批量收藏（本地）。转发/分享到其他会话先不做。

**验收**：引用条可删除；编辑后分叉会话带上历史；多选复制内容含角色与时间。

**估算**：3–4 人日。

### P1-7 定时任务新建/编辑表单

**现状**：`schedule_sheet.dart` 只有列表、立即运行、启用开关、删除；详情页看 `schedule-view` 与投递历史；没有新建/编辑表单（`gateway_schedule.dart:227-300` 只有 list/view/run/setEnabled/delete/history）。

**证据**：桥有 `schedule-create` 与 `schedule-edit` 帧（`src/host/ws-schedule.ts:39-41`），REST 也支持 `POST /chat/schedules`、`PATCH /chat/schedules/{id}`（`API.md:1197-1200`）。

**参照**：dsh-go 新建交给模型 + 表单编辑重复规则/时区/cron；ds-harness-remote 表单创建 + 编辑（`CHANGELOG.md:162`）。

**改法**：加「新建」按钮 → 表单（指令、cron 或可视化重复、时区、目标：当前会话/新会话）→ `schedule-create`；详情页加「编辑」→ `schedule-edit`（只传变化字段，带 `expectedUpdatedAt` 做 CAS）。cron 解析失败在本地先拦。

**验收**：新建后列表出现且下次运行时间正确；编辑后旧值被覆盖且不误改其他字段；多端同时编辑时冲突提示。

**估算**：3–4 人日。

### P1-8 插件面板

**现状**：会话信息里的「插件」TAB 是占位：「当前客户端还没有接入插件面板。」（`session_info_sheet.dart:369`）。

**证据**：桥有 `plugin-inventory-v1`（`capabilities.ts:80`，`GET /settings/plugins`）与 `plugin-toggle-v1`；通用白名单还有 `pluginManager/listBundles|inspect|installBundle|removeBundle|updateBundle|setBundleEnabled` 与 `pluginMarket/search|readEntryDetail`（`kernel-allowlist.ts`）。

**参照**：dsh-go 插件市场/已安装/实验开关/配置页（`official-parity.md:88-89`）；ds-harness-remote plugins-modal。

**改法**：分两步——先做「已安装清单 + 启停 + 版本 + 详情」（REST 为主，无需 kernel-call）；市场/安装/更新后置（需要 kernel-call 且要确认 bundle 安装的权限边界）。不做插件配置的 Cordis 网页。

**验收**：清单与 Host 设置页一致；启停后状态持久；安装失败给出桥的错误码文案。

**估算**：4–6 人日。

### P1-9 语音输入

**现状**：零接入；输入条没有麦克风；`plus_panel` 明确不放开语音（`plus_panel.dart:4-6`）。

**证据**：桥有 8 条 speech 帧，`speech-transcribe` 收 16k PCM16 WAV Base64（`src/host/ws-speech.ts`），能力位 `speech-transcription-v1`（`capabilities.ts:118`）；客户端需原生录音 + 16k 重采样 + WAV 头。

**参照**：dsh-go 输入框麦克风（系统识别/引擎插件两路，`official-parity.md:34`，待真机验证）。

**改法**：Android 用 `AudioRecord`（16k/mono/PCM16）→ 本地切 10–20s 段 → 组 WAV → `speech-transcribe`；鸿蒙用对应录音 API；录音时输入条显示波形/计时，可取消。先做「按住说话、松手转写」，不做实时流式。

**验收**：30s 中文语音转写成功率与延迟可接受；取消不残留；无麦克风权限时引导设置；桥无 speech 服务时隐藏入口。

**估算**：5–8 人日（含三端原生）。

### P1-10 通知升级

**现状**：两条通道 `done`/`attention`，只在用户看不到该会话时发；点击回推 `tap`，冷启动 `takeLaunchTap`（`app/lib/bridge/notify.dart:5-6`、`:45-73`）；没有操作按钮、没有「进行中任务」常驻通知。

**参照**：ds-harness-remote 锁屏实时任务通知 + 会话深链；dsh-go 未读/待确认提醒。

**改法**：先做「后台任务进行中」常驻通知（配合 P0-1，显示任务数/末行输出，点开进 jobs），再做审批/提问的操作按钮（允许/拒绝/回答）——后者需要原生通知 action + 回传桥，工作量更大。

**验收**：任务运行期间通知常驻、结束自动撤；点通知进对应会话/jobs；Android 13 权限拒绝时不崩。

**估算**：3–5 人日（仅常驻通知）；带操作按钮再加 4–6 人日。

### P2-11 浅色主题 / 多语言 / 无障碍

**现状**：设置页注释明确「语言三档 / 配色四套……本版本未做，不摆空开关」（`settings_page.dart:8`）；只有深色 token、只有中文；有字号设置。

**参照**：ds-harness-remote 11 语言、浅/深色、reduced motion、TalkBack 目标；dsh-go 主题/字号。

**改法**：先把 `DsColors` 抽成 light/dark 两套并跑通全部页面（不要只换背景）；i18n 用 `flutter_localizations` + ARB，先中英两语；无障碍补语义标签与 48dp 触达。这是长尾工程，不要和功能项混在一个迭代。

**估算**：主题 5–8 人日；i18n 8–12 人日；无障碍 3–5 人日。

### P2-12 分享面板 / 分享链接 / 图片保存

**现状**：只有系统文本分享（`DshPlatform.share(String)`，`platform.dart:90`）与「复制对话 Markdown」；图片查看器无保存/分享（`image_viewer.dart:1-20`）；桥没有 share 端点，`liveshareShares` 在禁命名空间（`kernel-allowlist.ts:86-114`）。

**参照**：dsh-go 分享链接/图片/文件/文字、分享码、`.dshgo`；ds-harness-remote 消息附件预览/下载。

**改法**：客户端先做「图片保存相册 + 文件 ACTION_SEND」（不依赖桥）；分享链接需要桥新增 `share-create/share-revoke` 或复用内核 liveshare（当前被禁），属单独立项。`.dshgo` 回放不做。

**验收**：图片保存后相册可见；文件分享面板出现文件；无新端点时「分享链接」入口不出现。

**估算**：客户端 2–3 人日；桥分享端点 5–8 人日 + 安全评审。

### P2-13 Host DSH Web 交接

**现状**：客户端没有打开 Host DSH Web 的入口；桥没有票据/交接端点（文档未见 `dsh.web.*` 之类）。

**参照**：ds-harness-remote 0.6.7「从主机详情经局域网打开主机 DSH Web」，跨网走一次性 browserGrant + 顶层 POST 换 Cookie（`docs/dsh-web-client.zh.md`）；dsh-go 的「聊天 + 网页模式」。

**改法**：桥新增 `POST /chat/web-ticket`（短时、单次、绑定设备与 Host），客户端 WebView 顶层 POST 换 Cookie；关闭时撤销。必须做同源限制、禁止外部 URL、禁 JS 注入。属架构级，先出设计再排期。

**验收**：票据 60s 过期、二次兑换失败、换 Host 失效、断线不泄露 Cookie。

**估算**：桥 6–10 人日 + 客户端 3–5 人日（含安全评审）。

### P2-14 工作区管理

**现状**：抽屉可按工作区筛选（`sessions_drawer.dart:64-65`、`:439-481`），`mobile_workspace.dart` 会自动建 `.dsh-mobile`；没有新建/重命名/删除/分组/排序入口。

**证据**：桥有 `workspaces` 帧、`workspace-create` 帧、REST `POST/PATCH/DELETE /chat/workspaces`（`API.md:30`、`:74`、`:290-292`）。

**参照**：dsh-go 工作区添加/切换/分组/置顶；ds-harness-remote 工作区列表/建改删排序/收藏。

**改法**：抽屉「全部对话」范围面板加「管理工作区」：新建（选授权根 + 相对路径）、重命名、删除登记（不删目录）、排序（本地）。分组后置。

**验收**：新建后出现在范围选择；重命名同步会话小节标题；删除只移除登记。

**估算**：3–4 人日。

### P2-15 团队写操作

**现状**：团队 TAB 只读展示成员/任务/子会话 + 三枚指挥话术（`projection_sheets.dart:263-354`）；没有成员详情、消息流、任务指派。

**证据**：桥把 `agentTeams` 列入禁命名空间（`kernel-allowlist.ts:86-114`），通用面够不到；只读投影来自 `projections.values.agentTeam`。

**判断**：不建议本轮做。要做需先评估内核 `agentTeams` 的写契约与权限边界；否则容易做成「看起来能指挥、实际发不出去」。

### 不建议做（明确边界）

| 项目 | 理由 |
|---|---|
| 终端 | 桥按设计拒绝 `terminal`/`sandbox`（`kernel-allowlist.ts:88`、`API.md:960`）；与「手机客户端」定位不符 |
| `.dshgo` 回放 / 分享码 | 容器格式与托管端未定；桥无端点 |
| 桌宠 / 主题商店 / 社区 / 酒馆 / DS Bot | dsh-go 的生态向能力，维护成本高，与远程客户端定位无关 |
| 本机引擎安装 | 需要 App 内 Linux 运行时，和现有架构冲突 |
| 拍照 | 原生只有 `pickImage`、无 CameraX 通路（`plus_panel.dart:4-6`）；需要新原生模块，优先级低于附件 |
| 自动允许胶囊 | 内核只有 `allowed-once|rejected`，没有 always（历史报告已确认） |
| 宽屏常驻三栏 | 真机反馈明确不要（`window_class.dart:8`），保持抽屉 |

---

## 4. dsh-remote-bridge 提升清单

桥的整体判断：**能力位不缺，缺的是「客户端可发现、可消费、可验证」的收口。** 近期不应继续铺新面。

### P0 契约收口

1. **能力位 → 客户端消费矩阵**：在 `docs/project/` 增加一张表，逐位标注「哪个客户端页面在用、哪个没用、没用的原因」。现在 `capabilities.ts` 有 30+ 位，客户端只对 `approvals/questions/session-archive-list` 三项分支（历史结论），其余是「对外声明」。这张表能防止「桥做了、客户端不知道」继续发生。
2. **`pin/feedback` 专用帧或 REST 化**：现在只能走 `kernel-call`（`kernel-allowlist.ts:128-129`），而 `kernel-call-v1` 是可选子协议，客户端要处理「能力位不可用就隐藏入口」。若置顶是高频，建议加 `session-pin` 帧（或 `PATCH /chat/sessions/{id}` 带 `pinned`），比让每个客户端重复实现 kernel-call 更稳。
3. **定时任务新建/编辑的客户端契约样例**：`schedule-create`/`schedule-edit` 已存在（`ws-schedule.ts:39-41`），但 `API.md` 的帧表只写了列表/历史/更新/删除，新建/编辑的请求形状与错误码需要补一段「客户端接入示例」，否则客户端只能读源码。
4. **附件上传进度语义**：分块上传已有 `GET …/uploads/{uploadId}` 进度（`API.md:1160`），但没有「上传中」事件；客户端只能轮询。建议明确轮询建议间隔与 `alreadyReceived` 的并发语义，或加 `attachment-upload-progress` 事件（可选）。
5. **jobs 重连语义写进客户端指南**：`chat.job.*` 是变化通知、没有回放，重连必须先 `job-list` 拉基线（`API.md:1113`、`ws-jobs.ts:18`）。这段现在只在 API.md 的角落，建议进 `PROTOCOL-BEHAVIOR.md` 的「重连检查清单」。

### P1 能力补齐（按价值）

1. **分享端点**：`share-create`/`share-revoke`（或明确「不做」并在能力位文档写死）。当前 `liveshareShares` 被禁（`kernel-allowlist.ts:86-114`），客户端无法做分享链接；如果短期不做，应在客户端隐藏入口并在文档标注。
2. **未读语义**：桥目前不发 unread。两个选择：客户端本地推导（推荐，零协议成本），或桥在 `sessions` 帧带 `lastReadSeq/lastEventSeq`。先做前者，文档写清口径。
3. **文件预览辅助**：若客户端要做 Office 预览，桥可提供「Office → PDF」转换端点（dsh-go 是主机转 PDF）；否则客户端只能系统打开。建议先不做，等真机反馈。
4. **团队只读 → 受限写**：仅当产品确定要做「给成员发消息/指派任务」时，再评估开放 `agentTeams` 的只读+发消息子集；否则保持只读投影。

### P2 架构级（单独立项）

1. **DSH Web 交接票据**（见 P2-13）。
2. **传输加密**：桥当前以设备令牌 + 部署层（局域网/隧道 TLS）为边界；在 `API.md`/`SECURITY.md` 中未见 Noise/E2EE 层（`SECURITY.md:532` 讲的是令牌用 Keystore 加密落盘）。若要对标 ds-harness-remote 的「Relay 只见密文」，需要 Noise/应用层加密，工作量大，先出威胁模型。
3. **协议 3.0.0 去 REST**：ROADMAP 的 `PROTO-001` 已 planned；在客户端还有 REST 依赖（大图、文件、设置）时不要切，先把 REST 依赖清单列全。
4. **多语言错误文案**：桥的错误 `message` 目前以中文/英文混排；客户端若要 i18n，需要桥给稳定 `code`（已有）并让客户端自己映射，不要再依赖 `message` 文案。

### 不做

- 终端/沙箱：按设计拒绝，保持。
- 账号体系/多租户：与「单 Host 单用户」定位冲突。
- 多后端 ACP：不是桥的职责。

---

## 5. 建议落地顺序

### 第 1 周（客户端为主，桥只补文档）

| 天 | 客户端 | 桥 |
|---|---|---|
| 1–2 | jobs 数据层 + `jobs_sheet` 骨架 | 补 jobs 重连说明到 `PROTOCOL-BEHAVIOR.md` |
| 2–3 | jobs 顶栏胶囊 + 事件订阅 | — |
| 3–4 | 产物卡统一打开链 + 图片保存 | — |
| 4–5 | 抽屉置顶 + 未读本地推导 | 补 `pin` 客户端接入示例 |

### 第 2 周

| 天 | 客户端 | 桥 |
|---|---|---|
| 1–2 | 多选归档 + 顶栏信息架构 | — |
| 2–4 | 子代理谱系页（只读） | 确认子会话续聊契约 |
| 4–5 | 引用/编辑重发 | — |

### 第 3–4 周

| 客户端 | 桥 |
|---|---|
| 定时任务新建/编辑表单 | schedule 帧表示例 |
| 插件清单/启停 | 能力位消费矩阵 |
| 语音输入（Android 先行） | speech 真机联调 |
| 通知常驻任务 | jobs 事件联调 |

### 之后（单独立项）

主题/i18n/无障碍、分享端点、DSH Web 交接、工作区管理、团队写操作。

### 版本映射建议

- 客户端 `1.0.40`：P0 四项（jobs、产物卡、抽屉组织、顶栏）。
- 客户端 `1.1.0`：P1 五项（子代理谱系、消息动作、定时任务表单、插件面板、语音）。
- 客户端 `1.2.x`：P2 中可独立交付的项（工作区管理、图片保存/文件分享、通知常驻）。
- 桥 `2.18.x`：只做文档与契约收口，不改帧语义；`2.19` 再考虑 pin/反馈专用帧与分享端点设计。

---

## 6. 验收与风险

### 6.1 每项的通用验收

- 单测：新增数据层/状态机必须有测试；客户端 `flutter test` 全绿、`flutter analyze` 无 issue；桥 `pnpm check` 四门全绿。
- 断线：WS 断开/重连后列表、游标、未读状态不丢不重。
- 权限：`kernel-call-v1`/`speech-transcription-v1` 不可用时入口隐藏，不出现「点了必然失败」的按钮。
- 帧上限：附件/大输出不再撞 1 MiB；错误按 `retryable` 与 `details` 分支。
- 小屏：375dp 宽、键盘弹出、字号 1.15 倍下不裁切。
- 平板：保持抽屉，不出现「半截三栏」。

### 6.2 主要风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 鸿蒙三端共用，新增插件必须带 ohos 实现 | 语音/文件选择/分享可能只能 Android 先行 | 优先用已有原生通道；新能力做平台能力探测，缺失时隐藏 |
| `kernel-call-v1` 是可选子协议 | 置顶/反馈/插件市场在旧桥不可用 | 以能力位分支 + 隐藏入口；关键能力（置顶）考虑桥补专用帧 |
| 未读本地推导与多端不一致 | 换设备后未读错乱 | 文档写明「未读是本机口径」；不进服务端真值 |
| 产物卡统一打开链依赖 FileProvider/鸿蒙对应实现 | 分享/打开在鸿蒙失败 | 先做「打开」，分享后置；失败回退提示 |
| 后台任务事件无回放 | 断线期间状态丢失 | 重连先 `job-list` 拉基线，UI 不做增量合并 |
| 真机未验收 | 语音/通知/大文件在真机可能翻车 | 每项排真机验收；语音先做 Android 单端 |

### 6.3 与现有版本的关系

- 客户端 `1.0.39+40` 已把「大图走 REST 大消息」修好；P0-2 的附件路径是它的下一步，不冲突。
- 桥 `2.18.1` 的 jobs/attachment/speech/plugin 帧都已稳定；本轮桥侧只做文档与少量契约补齐，不改协议语义。
- 两仓当前提交均未 push（历史记录），落地前先确认远端状态，避免把新改动叠在未推送提交上。

---

## 附录 A 证据索引

### 客户端（dsh-Chat）

| 事实 | 位置 |
|---|---|
| 插件面板占位文案 | `app/lib/ui/session_info_sheet.dart:369` |
| 产物卡只有复制/分享，分享暂不可用 | `app/lib/ui/chat_artifact_card.dart:117-156` |
| 交付卡已有完整打开链 | `app/lib/ui/chat_message_items.dart:380-430` |
| 原生 openFile 已存在 | `app/lib/bridge/platform.dart:185-205` |
| 顶栏只有标题 + 定时任务胶囊 | `app/lib/ui/chat_top_bar.dart:1`、`:76-81`、`:197` |
| 模型入口在输入条/更多菜单 | `app/lib/ui/chat_page.dart:470-472` |
| 活动条只反映当前轮 | `app/lib/ui/activity_strip.dart:1-10` |
| 未读恒 0、桥不下发 | `app/lib/ui/sessions_drawer.dart:60`、`:174` |
| 抽屉四档筛选 | `app/lib/ui/drawer_filter_bar.dart:13-17` |
| 会话长按只有重命名/分叉/归档 | `app/lib/ui/session_actions.dart:1-60`、`:50` |
| 消息操作条 | `app/lib/ui/message_actions.dart:5-16`、`:98-130` |
| 通知两条通道、无操作按钮 | `app/lib/bridge/notify.dart:5-6`、`:45-73` |
| 定时任务只有 list/view/run/开关/删/历史 | `app/lib/bridge/gateway_schedule.dart:227-300` |
| kernel-call 调用面已存在 | `app/lib/bridge/gateway_kernel.dart:185-228` |
| 设置页不做主题/语言 | `app/lib/ui/settings_page.dart:8` |
| 图片查看器无保存/分享 | `app/lib/ui/image_viewer.dart:1-20` |
| 宽屏不常驻侧栏 | `app/lib/ui/window_class.dart:8` |
| 拍照/语音明确不放 | `app/lib/ui/plus_panel.dart:4-6` |
| 子代理目录已解析 | `app/lib/bridge/projections.dart:292` |
| 子代理历史已封装 | `app/lib/bridge/gateway_api.dart:357` |

### 桥（dsh-remote-bridge）

| 事实 | 位置 |
|---|---|
| jobs 能力位 | `src/host/capabilities.ts:110` |
| 附件分块上传能力位 | `src/host/capabilities.ts:116` |
| 定时任务能力位 | `src/host/capabilities.ts:117` |
| 语音转写能力位 | `src/host/capabilities.ts:118` |
| 文件浏览能力位 | `src/host/capabilities.ts:57` |
| 插件清单能力位 | `src/host/capabilities.ts:80` |
| 能力位→服务映射 | `src/host/capabilities.ts:186-204` |
| jobs 三帧 | `src/host/ws-jobs.ts:5-7` |
| jobs 首帧只建 baseline | `src/host/ws-jobs.ts:18` |
| jobs 帧与事件、无回放 | `docs/project/API.md:1056-1058`、`:1113` |
| 定时任务 REST 四条 | `docs/project/API.md:1197-1200` |
| 分块上传六端点 | `docs/project/API.md:1158-1163` |
| hello 带 maxFrameBytes | `docs/project/API.md:982`、`:987` |
| error.retryable/details | `docs/project/API.md:722-739` |
| 剩余缺口（子会话历史只走 REST 等） | `docs/project/API.md:1285` |
| 禁命名空间（分享/团队/终端等） | `src/host/bridge/kernel-allowlist.ts:86-114` |
| 置顶端点 | `src/host/bridge/kernel-allowlist.ts:128-129` |
| pinnedSessionIds 已透出 | `src/host/bridge/kernel-local.ts:334/348` |
| schedule-create/edit 帧 | `src/host/ws-schedule.ts:39-41` |
| speech 帧与 PCM16 | `src/host/ws-speech.ts` |
| 令牌落盘（无 E2EE 声明） | `docs/project/SECURITY.md:532` |

### 参照产品

| 事实 | 位置 |
|---|---|
| dsh-go 后台任务 | `dsh-go-src/dsh-Go/docs/official-parity.md:43` |
| dsh-go 子代理谱系 | 同上 `:44` |
| dsh-go 文件树/文档预览 | 同上 `:48` |
| dsh-go 终端 | 同上 `:49` |
| dsh-go 智能体团队 | 同上 `:53` |
| dsh-go 会话长按 | 同上 `:54` |
| dsh-go 未读 | 同上 `:57` |
| dsh-go 分享码 | 同上 `:113` |
| dsh-go 引用追问 | 同上 `:118` |
| dsh-go 系统集成 | 同上 `:120` |
| dsh-go 语音输入 | 同上 `:34` |
| ds-harness-remote 文件/终端 | `ds-harness-remote-main/docs/design/DESIGN.md:42-46` |
| ds-harness-remote 多后端 | `ds-harness-remote-main/docs/design/PRODUCT.md:17` |
| ds-harness-remote 只读文件/终端 | 同上 `:18` |
| ds-harness-remote DSH Web 交接 | `ds-harness-remote-main/docs/CHANGELOG.md:11` |
| ds-harness-remote 自动化/通知/分组 | 同上 `:162`、`:139-140` |
| ds-harness-remote 拍照/大文件 | 同上 `:86-92` |
| ds-harness-remote ACP | 同上 `:42-43` |

---

## 附录 B 本次未覆盖

- 真机验收：语音、通知、大文件、鸿蒙三端差异均未跑真机。
- 鸿蒙构建：未验证新增原生依赖（录音/文件分享）在 ohos 的可用性。
- 未读语义：未与 dsh-go 的具体实现逐行对照，本报告只给「本地推导」的方案。
- 分享/终端/Web 交接：只做能力判断，未做协议设计与安全评审。
- 测试基线：客户端 616 例、桥 1112 例为 2026-11-27 夜间记录，本次未重跑。
