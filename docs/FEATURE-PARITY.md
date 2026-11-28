# 会话页功能对照（dsh-Go → dsh-Chat）

> 对照对象：`/media/wangke/OFFICE/workspace/dsh-go-src/dsh-Go`（HEAD `0bfa417`）的聊天/会话面
> 与本仓 `app/lib`（2026-11-27，提交 `1b6143f` 之后；各行的「2026-11-2x」注记为当轮核对结果）。
> 目的：给「还差什么」一张可排期的表，不是逐像素复刻清单。
> 结论标记：**✅ 对齐** / **◐ 部分** / **❌ 缺**。

## 一、总表（按会话页从上到下）

| 功能 | dsh-Go 做法（文件） | dsh-Chat 现状 | 结论 |
|---|---|---|---|
| 顶栏标题胶囊 | 可点进会话详情（`ui/chat/chat_header.dart`） | 标题 + 状态行，无详情页（`ui/chat_top_bar.dart`） | ◐ |
| 顶栏状态机 | 生成中/停止中/同步中/重连中/待审批/已结束结果（`chat_screen.dart:2403`） | 连接态 + 生成 + 待审批/回答（`chat_header_status.dart`） | ◐ 缺「同步中/停止中」 |
| 模型胶囊 | 标题旁胶囊，点开模型 + 推理强度（`ui/chat/model_sheet.dart`） | ⋯ 菜单里选模型，不显示当前模型（`ui/model_sheet.dart`） | ◐ |
| ＋ 新建对话 | 顶栏 ＋，首次发送才建会话 | ✅ 同口径（`chat_state.dart:215`） | ✅ |
| 定时任务入口 | 标题胶囊时钟 + 小 sheet（`header_schedule.dart`） | **✅ 2026-11-27**：标题胶囊尾端时钟按钮（能力位 `chat-schedules-v1` 才渲染，`chat_top_bar.dart`）→ 底部 sheet 列表/启停/立即运行/删除/详情（`schedule_sheet.dart`、`schedule_detail.dart`、`bridge/gateway_schedule.dart`）；启停走 `schedule-edit` 的 `patch.active` + CAS；新建/编辑表单与历史分页未做 | ◐ 无新建/编辑表单 |
| 会话抽屉分组 | 文件夹分组 + 运行点 + 待确认/未读（`ui/shell/sessions_drawer.dart`） | 今天/昨天/更早 + 待回答/待审批角标 | ◐ 无文件夹/置顶/未读 |
| 会话长按菜单 | 置顶/重命名/移动/分享/多选/归档/删除（`sessions_drawer.dart:535`） | **✅ 重命名 + 归档（2026-11-21）**；**✅ 2026-11-27 抽屉「显示已归档」开关**（`archived:true` 帧、底部「已归档 · N 条」，`sessions_drawer.dart`）；无置顶/移动/分享/多选/恢复 | ◐ |
| 会话正文搜索 | 标题本地匹配 + 服务端正文命中（`session_search_page.dart`） | ✅ kernel-call `session/search`，老桥降级 | ✅ |
| 空态建议卡 | 一组建议 prompt 卡（`empty_state.dart`） | **✅ 2026-11-25**：`empty_suggestions.dart` + `EmptyGreeting` 已接入（此前表格记错为 ❌） | ✅ |
| 新对话选项 | 文件夹/预设/权限预先挂起（`new_chat_options.dart`） | 只有工作目录（`session_location_sheet.dart`） | ◐ |
| 消息列表锚定 | center 锚点两段 sliver，上翻不抢滚动（`ui/chat/chat_list.dart`） | 贴底跟随 + FAB（`scroll_follow.dart`） | ◐ |
| 用户气泡 | 软气泡 + 附件缩略 + 发送状态标签（`user_bubble.dart`） | 气泡 + 历史图 + **本轮新增「排队中」提示** | ◐ |
| 助手 Markdown | 代码/表格/mermaid/公式/ANSI（`render/markdown_body.dart`） | 代码/表格/任务列表/思考；无 mermaid/公式 | ◐ |
| 思考折叠 | 流式「最新在写什么」三行 + 点开全文（`thinking_pill.dart`） | ✅ 同口径（`chat_thinking.dart`） | ✅ |
| 工具行 | 单行图标 + 摘要，点开详情（`tool_row.dart`） | ✅ 四档过程组 + 详情（`process_group.dart`） | ✅ |
| 整轮折叠 | 「✓ 已完成 · 7 次工具」+ 左侧细线（`turn_process.dart`） | 轮尾行 + 过程组折叠 | ◐ 无统一轮折叠 |
| 回合脚注 | 时长/步数/花费/tokens，窄屏依次省（`turn_footnote.dart`） | 轮尾「已完成，用时 X」 | ◐ 无花费/步数 |
| 运行轨迹 | 瀑布图 + 步骤详情页（`trajectory_sheet.dart`） | 本地事件轨迹 JSON 面板（`projection_sheets.dart`） | ◐ |
| 改动卡 → diff 页 | 文件 chip + 行号 + 换行开关（`diff_page.dart`） | **✅ 左右滑切文件**（`chat_diff_page.dart`，本轮问题 5） | ✅ |
| 产物卡/预览 | 缩略图 + PDF/Office 转图 + CSV 表格（`artifact_preview.dart`） | 文件卡打开/分享；md 全屏渲染 | ◐ |
| 命令记录行 | 等宽命令行 + 宿主结果（`command_row.dart`） | ✅ 命令卡（`role=='command'`） | ✅ |
| 审批卡 | 主键「拒绝/允许本次」，都允许降级文字按钮（`approval_card.dart`） | ✅ 允许一次/拒绝（`question_card.dart`） | ✅ 无「本对话都允许」（协议也不支持） |
| 自动允许胶囊 | 常驻可见、一点即关（`auto_approve_pill.dart`） | 无 | ❌ |
| 完全权限胶囊 | 常驻输入条上方警示（`permission_pill.dart`） | 权限 chip 在输入条（`composer_bar.dart`） | ◐ |
| 提问卡 | 选项 + 提交 + 可拒绝（`question_card.dart`） | ✅ 单选/多选/自定义（`question_card.dart`） | ✅ |
| 输入条直接回答提问 | 单问 + 纯文本时发送即回答（`chat_screen.dart:693`） | **✅ 2026-11-21**：`singleOpenQuestion` + send() 拦截走 question-answer custom；hint 切「直接回答上面的提问…」 | ✅ |
| 后台任务卡/列表 | `tool-jobs` 消息卡 + jobs 页（`background_task_notice.dart`、`jobs_page.dart`） | 只有工具行文字 | ❌ |
| dsh-ui 交互块 | 图表/表单/选择块 + 回复 chip（`ui/chat/dsh_ui/`） | 无 | ❌ |
| 消息菜单 | 复制/选中/引用/分享/朗读/重答/分叉/编辑（`message_menu.dart`） | 复制/点赞/朗读/分享/重新生成/**从此消息分叉**（`message_actions.dart`） | ◐ 无选中/引用/编辑 |
| 分叉 / 编辑重发 | 一律开新会话（`session/fork`）；残留队列清掉 | 会话长按「分叉到新会话」+ **消息级 `fork atSeq`（2026-11-27，仅 seq>=0）**已接 `fork` 帧并自动打开；「重新生成」仍是重发最后一条 | ◐ 编辑重发缺 |
| 分享面板 | 范围 + 隐私项 → 链接/图片/文件/文本（`share_panel.dart`） | 单条消息系统分享 | ◐ |
| 对话回放 | `.dshgo` 只读回放（`replay_page.dart`） | 无 | ❌ |
| 玻璃输入条 | 1–6 行、Enter 发送 / Esc 打断（`ui/chat/composer.dart`） | **✅ 2026-11-27**：空输入单行收起、有文字/待发图 280ms 展开双行（`composer_rows.dart`）；可见 2–6 行按键盘上方高度算（`_maxLines`），超出行数出现「展开编辑」全屏弹层（`composer_editor.dart`）；发送/停止三态 | ✅ 无 Esc（移动端） |
| 运行中发送语义 | 默认**插话**，长按选「插话/停止后排队/排队」（`chat_state.dart:1313`） | 设置里二选一排队/插话，默认排队（`settings_sections.dart:274`） | ◐ |
| 排队气泡 + 动作 | 七种状态标签；`inboxId` 到手后可编辑/立即发送/改插话/撤回（`chat_list.dart:1130`、`session/updateQueue`） | **✅ 2026-11-21 真管理**：队列条 + 面板撤回/改插话/改写（`session-queues`/`queue-update`/`queue-item-updated`，mobile-queue-v1）；本地「排队中」标签保留 | ✅ |
| 停止本轮 | `session/cancel`；停后把 inbox 末条放回唤醒（`chat_state.dart:1700`） | ✅ `session-cancel` + 清流式 | ◐ 无「放回唤醒」 |
| 上下文环 + 用量 | 22dp 环 + 用量/余额 sheet（`usage_sheet.dart`） | 输入条上方 `ContextUsageBar`：18dp 环 + 「上下文 42% · 61k / 1M」，点开列占用/预估/窗口；80% 警示；老桥或窗口缺失不占位 | ✅ |
| 目标条 | ⚑ 目标 + 首行 + 暂停/受阻状态（`dock/goal_bar.dart`） | **✅ 本轮实现**（`ui/goal_dock.dart`） | ✅ |
| 目标编辑/暂停/恢复/清除 | sheet + CAS + 单飞 + 墓碑（`dock/goal_sheet.dart`、`goal_dock_state.dart`） | **✅ 编辑/暂停/恢复/清除（CAS ref，失败译人话）+ activation（`goals-get` 显示自动续跑已启用/未启用）**；无单飞/墓碑 | ◐ |
| 待办条 | 「3/7 · 正在：…」原地展开（`dock/todo_bar.dart`） | ✅ 同口径（`todo_dock.dart`） | ✅ |
| 活动胶囊 | 鲸尾 + 此刻状态 + 用时（`activity_strip.dart`） | **◐ 2026-11-27 复核：已上线**——`ui/activity_strip.dart`（思考/工具/命令图标 + 标题 + 一行细节 + 实时秒表），`chat_page.dart:415-418` 在 streaming 时有活动才占位；`liveActivityOf()` 从最后过程组取 live 调用、组内无 live 但仍在生成时退化为「思考中」。与 dsh-go 的差异只在左侧图形（工具图标 vs 鲸尾） | ◐ 图形差异 |
| 底部卡片叠 | 待办/目标/活动/插件折成一副牌（`dock_stack.dart`） | 待办与目标上下两张，不折 | ◐ |
| 斜杠面板 | 应用级 + 宿主 + 技能（`slash_palette.dart`，dsh-go `commands_state.dart` 同口径） | **✅ 2026-11-21 全对齐**：①中文——first-party 按 `definitionId` 换上官方 zh 字典的 label/描述/参数占位（此前只透传内核英文）；②四条客户端功能命令 new/model/export/features（本地执行，`/features` 落设置页）；③会话技能行（内核 `skills/list`，经 `dshrb-v1` kernel-call，需桥 `KERNEL_ALLOWLIST` 放行——桥 v2.14.x 起）；④面板 `中文名 /name 参数` 三列 + 按 name/label 四档过滤 + 中文名精确解析；⑤三态（候选/参数提示/不显示）与点选语义（无参命令点一下直接执行、有参插入 `'/name '`、技能与带后缀一律插入、光标按插入点定位）；⑥发送分流（裸 `/` 吃掉回车、技能整行当消息、名字不全先选首行）；⑦关闭语义（点面板外 / 返回键 / Esc 只关面板，文本不变不重弹，重敲裸 `/` 才重开）；⑧视觉逐值对齐（容器圆角 28、行圆角 22、行高 52、图标槽 32/20、选中底 6%、⏎ 仅首行显形、空态「没有匹配的指令，按普通消息发送」）；数据面 `bridge/slash_commands.dart`、渲染 `ui/composer_palette.dart`、状态 `ui/composer_slash.dart` | ✅（真机已验：V2080A 上 13 条——4 客户端 + 4 宿主中文化（compact 当前会话未提供、export 按 dsh-go 口径隐藏）+ 5 技能行；`/features` 开设置页、`/export` 复制 Markdown 均实测生效）|
| @ 提及 | 文件/文件夹/子代理/会话（`mention_picker.dart`） | ✅ 文件/目录/会话（`composer_panels.dart:105`） | ◐ 无子代理 |
| 引用追问 | 引文片拼 Markdown 引用块（`quote_chip.dart`） | 无 | ❌ |
| 附件面板 | 相册/拍照/文件/生成 + 权限/计划（`plus_panel.dart`） | ✅ 相册多图（最多 6） | ◐ 无拍照/文件选择 |
| 语音听写 | 云识别 → 引擎 → 系统三级回退（`voice_controller.dart`） | 无（hint「按住说话」名不副实） | ❌ |
| 草稿按会话保存 | 每会话一份文本+附件（`draft_store.dart`） | **✅ 2026-11-25**：`ui/composer_drafts.dart` 按 sessionId 存文本+图片（null 键 = 新对话），切会话自动存/取，发送成功清草稿 | ✅ |
| 模型重试提示 | 内核 `llm/retry` → 桌面端折叠行「已重试模型请求（1/5）· 1s」（`client.js` RetryItem） | **✅ 2026-11-25**：装配 `llm/retry`/`llm/retry-started` → `RetryRow` + 折叠明细（重试延迟/失败原因），此前整条丢弃 | ✅ |
| 流式等待指示 | 三个跳动的点（chat-demo `.waiting`/`.waitingDot`） | **✅ 2026-11-25**：`ui/waiting_dots.dart`（6px、错峰 0.1/0.2s、0.3→1） | ✅ |
| 断线/同步恢复 | syncing 横幅 + 超时降级「需要同步」（`chat_state.dart:726`） | 连接态 + 自动重连；无 syncing 横幅 | ◐ |
| 只读子会话 | 输入条换只读玻璃条（`read_only_bar.dart`） | ✅ 子会话历史页无输入条（`subagent_history_page.dart`） | ✅ |

## 二、本轮已落地

1. **目标（goal）整条链路**：`bridge/goal.dart`（投影模型 + 口径）→ `gateway_api` 的 `fetchGoal/editGoal/pauseGoal/resumeGoal/clearGoal`（`goal` / `goal-edit` / `goal-pause` / `goal-resume` / `goal-clear` 帧，CAS `ref:{id,revision}`）→ `ui/goal_dock.dart`（目标条 + 操作面板 + 编辑对话框 + 清除确认 + 错误翻译）→ `chat_page.dart` 输入条上方接入；投影来自 history 首屏 `projections.values.goal`，动作成功后 `reloadHistory()` 追平。
2. **排队可见性**：运行中以排队模式再发时，用户气泡上方显示「排队中 · 本轮结束后发送」（UI 派生：`isUser && seq<0 && streaming && busySendMode==queue`），落库即消失。
3. **2026-11-25 本批（对照 `.dsh-mobile/chat-demo/` 官方 demo）**：
   - **按会话保存草稿**：`ui/composer_drafts.dart`（`ComposerDraftStore`，键 = sessionId，null = 新对话）；输入文字与待发送图片都随会话存草稿，切会话自动存旧取新，发送成功后清掉该会话草稿；测试 `test/composer_drafts_test.dart`。
   - **模型重试提示**：内核 `llm/retry` / `llm/retry-started` 事件原先被装配器整条丢弃（桌面端有「已重试模型请求（1/5）· 1s」，手机端无任何提示）。现在 `bridge/history_page.dart` 装配出 `role='retry'` 消息（`ModelRetryInfo`：retryId/retry/maxRetries/delayMs/failure/started/cancelled），`ui/chat_rows.dart` 派生 `RetryRow`，`ui/chat_row_view.dart` 渲染可折叠的「已重试模型请求（n/m）· Xs」+「重试延迟：N毫秒 / 失败原因：…」。测试 `test/model_retry_test.dart`。
   - **流式等待指示**：模型已接收请求但还没有任何输出时显示三个跳动的点（官方 `.waiting`/`.waitingDot`：6px、错峰 0.1/0.2s、透明度 0.3→1）；此前这段完全空白。`ui/waiting_dots.dart`。

## 三、下一批候选（按价值/成本）

| 优先级 | 事项 | 说明 | 成本 |
|---|---|---|---|
| P0 | ~~队列真管理~~ | **✅ 已接 IKX2AE**（桥 22a5223）：撤回/改插话/改写；真机四步回归待做 | 已完成 |
| P1 | 后台任务面板 | 桥已补 `job-list`/`job-output`/`job-kill` 帧与 `chat.job.*` 事件（2026-11-27，待合并验收）；客户端 UI 未做 | 中 |
| P1 | 会话 fork | ✅ 会话长按「分叉到新会话」（`fork` 帧，自动打开新会话） | 已完成 |
| P1 | 上下文用量环 | ✅ 输入条上方 `ContextUsageBar`（环 + 用量 sheet） | 已完成 |
| P1 | 协议卫生 | **✅ 2026-11-27**：`hello.maxFrameBytes` 预检 + `PAYLOAD_TOO_LARGE`、1009/1013 人话提示、`error.retryable/details` 与 429 重试（`gateway.dart`、`chat_state.dart`、`LinkErrorRow`）。**✅ 2026-11-28**：预检之后不能只是报错——整帧超上限的消息改走 REST 大消息通道（`content.messageFrameBytes` 估帧 + `gateway_rest.gatewaySendMessage`，12 MB body，按体积一开始就选通道，对齐 companion issue #15），相册原图（base64 2.5–9 MB）可发 | 已完成 |
| P1 | 自动允许胶囊 | 批量放行挂起审批，需确认协议是否支持 | 小 |
| P2 | ~~输入条直接回答提问~~ | **✅ 已完成**（`singleOpenQuestion` + send 拦截） | 已完成 |
| P2 | 会话导出（md/json） | ✅ 顶栏 ⋯「复制/分享对话（Markdown）」 | 已完成 |
| P2 | 语音输入 | 依赖原生 ASR 通道，工作量最大 | 大 |
| P3 | 文件夹/置顶/未读 | 抽屉信息架构升级 | 中 |
| P3 | 分叉/编辑重发 | 与「会话不可变」模型绑定，需先接 fork | 中 |
| P3 | 思考胶囊扫光 | dsh-Go `thinking_pill.dart` 的 shimmer（lead 600ms / sweep 1s / period 4s）；只影响进行中思考行的装饰 | 小 |
| P3 | 思考胶囊翻译 chip | 同文件里的翻译 chip（高 26、padding 10、`StadiumBorder`）；本仓无翻译通道，需先定数据来源 | 中 |
