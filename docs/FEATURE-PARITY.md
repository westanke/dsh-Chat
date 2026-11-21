# 会话页功能对照（dsh-Go → dsh-Chat）

> 对照对象：`/media/wangke/OFFICE/workspace/dsh-go-src/dsh-Go`（HEAD `0bfa417`）的聊天/会话面
> 与本仓 `app/lib`（2026-11-21，提交 `a96a212` 之后）。
> 目的：给「还差什么」一张可排期的表，不是逐像素复刻清单。
> 结论标记：**✅ 对齐** / **◐ 部分** / **❌ 缺**。

## 一、总表（按会话页从上到下）

| 功能 | dsh-Go 做法（文件） | dsh-Chat 现状 | 结论 |
|---|---|---|---|
| 顶栏标题胶囊 | 可点进会话详情（`ui/chat/chat_header.dart`） | 标题 + 状态行，无详情页（`ui/chat_top_bar.dart`） | ◐ |
| 顶栏状态机 | 生成中/停止中/同步中/重连中/待审批/已结束结果（`chat_screen.dart:2403`） | 连接态 + 生成 + 待审批/回答（`chat_header_status.dart`） | ◐ 缺「同步中/停止中」 |
| 模型胶囊 | 标题旁胶囊，点开模型 + 推理强度（`ui/chat/model_sheet.dart`） | ⋯ 菜单里选模型，不显示当前模型（`ui/model_sheet.dart`） | ◐ |
| ＋ 新建对话 | 顶栏 ＋，首次发送才建会话 | ✅ 同口径（`chat_state.dart:215`） | ✅ |
| 定时任务入口 | 标题胶囊时钟 + 小 sheet（`header_schedule.dart`） | 无 | ❌ |
| 会话抽屉分组 | 文件夹分组 + 运行点 + 待确认/未读（`ui/shell/sessions_drawer.dart`） | 今天/昨天/更早 + 待回答/待审批角标 | ◐ 无文件夹/置顶/未读 |
| 会话长按菜单 | 置顶/重命名/移动/分享/多选/归档/删除（`sessions_drawer.dart:535`） | **✅ 重命名 + 归档（2026-11-21）**；无置顶/移动/分享/多选 | ◐ |
| 会话正文搜索 | 标题本地匹配 + 服务端正文命中（`session_search_page.dart`） | ✅ kernel-call `session/search`，老桥降级 | ✅ |
| 空态建议卡 | 一组建议 prompt 卡（`empty_state.dart`） | 只有问候 + 目录 chip（`chat_page.dart:411`） | ❌ |
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
| 输入条直接回答提问 | 单问 + 纯文本时发送即回答（`chat_screen.dart:693`） | 无 | ❌ |
| 后台任务卡/列表 | `tool-jobs` 消息卡 + jobs 页（`background_task_notice.dart`、`jobs_page.dart`） | 只有工具行文字 | ❌ |
| dsh-ui 交互块 | 图表/表单/选择块 + 回复 chip（`ui/chat/dsh_ui/`） | 无 | ❌ |
| 消息菜单 | 复制/选中/引用/分享/朗读/重答/分叉/编辑（`message_menu.dart`） | 复制/点赞/朗读/分享/重新生成（`message_actions.dart`） | ◐ 无分叉/编辑 |
| 分叉 / 编辑重发 | 一律开新会话（`session/fork`）；残留队列清掉 | 会话长按「分叉到新会话」已接 `fork` 帧并自动打开；「重新生成」仍是重发最后一条 | ◐ 编辑重发缺 |
| 分享面板 | 范围 + 隐私项 → 链接/图片/文件/文本（`share_panel.dart`） | 单条消息系统分享 | ◐ |
| 对话回放 | `.dshgo` 只读回放（`replay_page.dart`） | 无 | ❌ |
| 玻璃输入条 | 1–6 行、Enter 发送 / Esc 打断（`ui/chat/composer.dart`） | ✅ 1–5 行、发送/停止三态（`composer_bar.dart`） | ✅ 无 Esc（移动端） |
| 运行中发送语义 | 默认**插话**，长按选「插话/停止后排队/排队」（`chat_state.dart:1313`） | 设置里二选一排队/插话，默认排队（`settings_sections.dart:274`） | ◐ |
| 排队气泡 + 动作 | 七种状态标签；`inboxId` 到手后可编辑/立即发送/改插话/撤回（`chat_list.dart:1130`、`session/updateQueue`） | **只有「排队中」标签**（本轮新增）；不可撤回/改插话 | ◐ 队列读写需桥补帧 |
| 停止本轮 | `session/cancel`；停后把 inbox 末条放回唤醒（`chat_state.dart:1700`） | ✅ `session-cancel` + 清流式 | ◐ 无「放回唤醒」 |
| 上下文环 + 用量 | 22dp 环 + 用量/余额 sheet（`usage_sheet.dart`） | 输入条上方 `ContextUsageBar`：18dp 环 + 「上下文 42% · 61k / 1M」，点开列占用/预估/窗口；80% 警示；老桥或窗口缺失不占位 | ✅ |
| 目标条 | ⚑ 目标 + 首行 + 暂停/受阻状态（`dock/goal_bar.dart`） | **✅ 本轮实现**（`ui/goal_dock.dart`） | ✅ |
| 目标编辑/暂停/恢复/清除 | sheet + CAS + 单飞 + 墓碑（`dock/goal_sheet.dart`、`goal_dock_state.dart`） | **✅ 编辑/暂停/恢复/清除（CAS ref，失败译人话）**；无 activation 维度/墓碑 | ◐ |
| 待办条 | 「3/7 · 正在：…」原地展开（`dock/todo_bar.dart`） | ✅ 同口径（`todo_dock.dart`） | ✅ |
| 活动胶囊 | 鲸尾 + 此刻状态 + 用时（`activity_strip.dart`） | 无 | ❌ |
| 底部卡片叠 | 待办/目标/活动/插件折成一副牌（`dock_stack.dart`） | 待办与目标上下两张，不折 | ◐ |
| 斜杠面板 | 应用级 + 宿主 + 技能（`slash_palette.dart`） | ✅ 命令匹配 + ↑↓（`composer_panels.dart`） | ✅ |
| @ 提及 | 文件/文件夹/子代理/会话（`mention_picker.dart`） | ✅ 文件/目录/会话（`composer_panels.dart:105`） | ◐ 无子代理 |
| 引用追问 | 引文片拼 Markdown 引用块（`quote_chip.dart`） | 无 | ❌ |
| 附件面板 | 相册/拍照/文件/生成 + 权限/计划（`plus_panel.dart`） | ✅ 相册多图（最多 6） | ◐ 无拍照/文件选择 |
| 语音听写 | 云识别 → 引擎 → 系统三级回退（`voice_controller.dart`） | 无（hint「按住说话」名不副实） | ❌ |
| 草稿按会话保存 | 每会话一份文本+附件（`draft_store.dart`） | 无 | ❌ |
| 断线/同步恢复 | syncing 横幅 + 超时降级「需要同步」（`chat_state.dart:726`） | 连接态 + 自动重连；无 syncing 横幅 | ◐ |
| 只读子会话 | 输入条换只读玻璃条（`read_only_bar.dart`） | ✅ 子会话历史页无输入条（`subagent_history_page.dart`） | ✅ |

## 二、本轮已落地

1. **目标（goal）整条链路**：`bridge/goal.dart`（投影模型 + 口径）→ `gateway_api` 的 `fetchGoal/editGoal/pauseGoal/resumeGoal/clearGoal`（`goal` / `goal-edit` / `goal-pause` / `goal-resume` / `goal-clear` 帧，CAS `ref:{id,revision}`）→ `ui/goal_dock.dart`（目标条 + 操作面板 + 编辑对话框 + 清除确认 + 错误翻译）→ `chat_page.dart` 输入条上方接入；投影来自 history 首屏 `projections.values.goal`，动作成功后 `reloadHistory()` 追平。
2. **排队可见性**：运行中以排队模式再发时，用户气泡上方显示「排队中 · 本轮结束后发送」（UI 派生：`isUser && seq<0 && streaming && busySendMode==queue`），落库即消失。

## 三、下一批候选（按价值/成本）

| 优先级 | 事项 | 说明 | 成本 |
|---|---|---|---|
| P0 | 队列真管理（撤回/改插话/立即发送） | 等桥 issue IKX1ZM（`session-queues`/`queue-update`/`queue-item-updated` + `mobile-queue-v1`）；App 侧排队提示已上 | 桥 12–30h |
| P1 | 后台任务面板 | 桥无 `job/list`/`job/kill` 帧（asyncapi 客户端 enum 无 job 系列），需另开 issue | 桥 |
| P1 | 会话 fork | ✅ 会话长按「分叉到新会话」（`fork` 帧，自动打开新会话） | 已完成 |
| P1 | 上下文用量环 | ✅ 输入条上方 `ContextUsageBar`（环 + 用量 sheet） | 已完成 |
| P1 | 自动允许胶囊 | 批量放行挂起审批，需确认协议是否支持 | 小 |
| P2 | 输入条直接回答提问 | 单问 + 纯文本发送即答案 | 小 |
| P2 | 会话导出（md/json） | ✅ 顶栏 ⋯「复制/分享对话（Markdown）」 | 已完成 |
| P2 | 语音输入 | 依赖原生 ASR 通道，工作量最大 | 大 |
| P3 | 文件夹/置顶/未读 | 抽屉信息架构升级 | 中 |
| P3 | 分叉/编辑重发 | 与「会话不可变」模型绑定，需先接 fork | 中 |
