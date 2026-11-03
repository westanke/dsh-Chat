# STRUCTURE — dsh-Chat

> 宪法 §8 要求：lib/ 下文件增删与结构变更，**同提交**更新本表。

## docs/（平铺）

| 文件 | 用途 |
|---|---|
| `design-tokens.md` | 设计基准（官方 Web token + App 实测像素），token 单一事实来源 |
| `STRUCTURE.md` | 本文件 |

## app/lib/

| 文件 | 用途 | 状态 |
|---|---|---|
| `main.dart` | 入口：DshLog 初始化、主题装配（三档 / 字号缩放由 `AppSettings` 驱动）、自动连接（凭证持久化）、路由（连接页 ⇄ 聊天页 ⇄ 设置页） | ✅ 装机验证 |
| `design/tokens.dart` | DsPalette / DsColors / DsTypography / DsSpacing —— 全部样式值唯一出口（§4.4 设置页 token） | ✅ |
| `design/app_settings.dart` | 本地偏好 `AppSettings`（界面风格三档 / 字号缩放 / 跟随系统 / 繁忙发送模式 / 诊断日志）+ `AppFontScaler`（与系统字号相乘的 TextScaler）；枚举按 name 持久化，凭据分库 | ✅ 单测覆盖 |
| `bridge/models.dart` | SessionEvent / ChatMessage / DshSession / DshWorkspace / PromptPart / MessageDelta / MessageCommitted / HistoryPage（含 `turn/end` 失败解析）；re-export `tool_call.dart` | ✅ 单测覆盖 |
| `bridge/tool_call.dart` | ToolCallInfo + 工具措辞表 `toolPhrases` + 摘要 `toolSummary` + `RawToolCall` / `extractToolCalls`（从 models.dart 拆出，控行数） | ✅ 单测覆盖 |
| `bridge/gateway.dart` | WS `/ws/mobile`：子协议 `dsh-mobile-v1`、hello.protocol=3、requestId（**data 内回显**）、退避重连 1→2→4→8→16s、心跳 25s；`cancelTurn()` 发 `session-cancel` 帧 | ✅ 装机验证 |
| `bridge/credentials.dart` | shared_preferences 持久化 `{baseUrl, token}`，实现「一次配对，此后自动连接」 | ✅ |
| `bridge/device.dart` | MethodChannel `dsh/device#ianaZone` → IANA 时区（clientTimeZone 必需 `Area/Location`） | ✅ |
| `bridge/dlog.dart` | 文件日志 `/data/data/<pkg>/files/dsh.log`（vivo 过滤 flutter 日志，只能落文件）；`enabled` 开关 + `read()` 供设置页诊断日志区 | ✅ |
| `ui/chat_page.dart` | 聊天主页：顶栏（会话名 + 静音→会话统计 + 新对话，加号接 `newChat`） / 空态问候 / 消息列表（自动滚底 + 双击复制整条）/ 流式项 / 思考流折叠 / 消息操作条（重新生成接线）/ 设置页入口 | ✅ 装机验证 |
| `ui/chat_state.dart` | ChangeNotifier：会话列表 / 打开会话 / 发送（按偏好携带 `mode: queue\|steer`）/ `cancelTurn()` 停止回合 / `regenerateAt()` 重新生成 / `retryLast()` 失败重试 / 流式累积 / 推送分发 | ✅ 装机验证 |
| `ui/stats_sheet.dart` | 会话统计 Sheet：`chatStatsOf()` 由已加载消息本地计算（消息/工具/思考/错误数），零网络请求；对照 companion ChatStatsSheet | ✅ 单测覆盖 |
| `ui/settings_page.dart` | 设置页主文件：Scaffold + 分区骨架（`settings_sections.dart` / `settings_widgets.dart` 是同库 `part`，共享私有成员，宪法 §7 控行数） | ✅ 单测覆盖 |
| `ui/settings_sections.dart` | 设置页分区：连接与设备信息（hello 只读）/ 界面风格三档 / 字号缩放与跟随系统 / 繁忙发送模式 / 诊断日志 / 关于 / 断开连接；不摆无授权的服务端开关 | ✅ 单测覆盖 |
| `ui/settings_widgets.dart` | 设置页通用组件：`_Section` / `_InfoRow` / `_ActionRow` / `_SwitchRow` / `_SegmentedRow` / `_ScopeChip` / `_WarningBanner` | ✅ 单测覆盖 |
| `ui/composer.dart` | 输入条：白浮层圆角容器 + 输入框 + 深度思考 / 智能搜索 chips + 发送键三态（发送/停止/占位，对照 companion ComposerSendPolicy）+ 底部免责提示 | ✅ 装机验证 |
| `ui/connect_page.dart` | 配对页：bridge 地址 + 配对码 | ✅ 装机验证 |
| `ui/md_view.dart` | GptMarkdown 定制：官方 token 全量映射、任务列表预处理、codeBuilder/tableBuilder 接线 | ✅ 装机验证 |
| `ui/md_code_block.dart` | 自绘代码块：Atom One Light（ValTheme 自定义）+ banner「语言名 / 复制」 | ✅ 装机验证 |
| `ui/md_table.dart` | 自绘表格：banner「表格 + 复制/下载/展开」+ 官方 #fafafa 底 + #dcdcdc 线 | ✅ 装机验证 |
| `ui/message_actions.dart` | 助手消息操作条：复制 / 喜欢 / 不喜欢 / 朗读 / 分享（无协议能力时明确提示「暂不支持」，不摆空开关）+ 右侧重新生成接线 | ✅ 装机验证 |
| `ui/process_group.dart` | 工具调用折叠组：折叠一行「执行了命令，读取了文件…」，点开展开逐条明细 | ✅ 装机验证 |
| `ui/sessions_drawer.dart` | 侧边会话抽屉：胶囊搜索框 + 日期分组（今天/昨天/更早）+ 纯文字条目 + 底部账号栏（三点接设置页入口） | ✅ 装机验证 |
| `ui/brand_mark.dart` | 空态品牌标记 DsBrandMark（`_WhalePainter` 原创 Path 绘制：圆身 + 双瓣尾鳍 + 月牙腹部 + 眼睛），不引用官方素材 | ✅ 装机验证 |

## 平台侧（框架通道与清单）

| 文件 | 用途 |
|---|---|
| `app/android/app/src/main/kotlin/.../MainActivity.kt` | MethodChannel `dsh/device#ianaZone`（Android IANA 时区） |
| `app/android/app/src/main/AndroidManifest.xml` | `INTERNET` 权限 + `usesCleartextTraffic`（bridge 走 ws:// 明文） |
| `app/ios/Runner/AppDelegate.swift` | 同款 `dsh/device#ianaZone` 通道（iOS `TimeZone.current.identifier`） |
| `app/ios/Runner/Info.plist` | 显示名 DSH Chat + ATS 放行明文 + 本地网络用途说明 |

## app/test/

| 文件 | 覆盖 |
|---|---|
| `app_settings_test.dart` | `normalizeFontScale`（NaN/Inf/越界夹取）、`AppFontScaler` 与系统字号相乘、`AppSettings` 默认值与 `effectiveFontScale` |
| `settings_page_test.dart` | 设置页渲染：界面风格三档 / 繁忙发送模式两档 / 字号滑块与跟随系统 / 诊断日志开关均真实生效 |
| `chat_actions_test.dart` | `chatStatsOf()` 本地统计、`Composer` 发送键三态、`ChatState.regenerateAt/retryLast` 重发用户消息 |
| `models_test.dart` | 协议模型 round-trip、`data.message.content` 提取、注入上下文过滤（`source.kind != user`）、displayTitle 兜底、工具调用措辞表 / 摘要 / 过程组合并去重与耗时、`turn/end` 失败 → `role=error` |
| `md_view_test.dart` | MD 全家福 / 超长表格**不溢出**（360dp 宽，断言 `takeException() == null`） |
| `widget_test.dart` | 冷启动进连接页 |
| `brand_mark_test.dart` | 空态品牌标记尺寸 = token |
| `render_mark_test.dart` | 离屏导出品牌标记 PNG（`ref/mark-preview.png`） |
| `render_md_test.dart` | 离屏导出 MD 全家福 PNG（`ref/md-preview.png`） |

## app/tool/

| 文件 | 用途 |
|---|---|
| `tool/verify_groups.dart` | 宿主侧校验脚本：读 `ref/hist-demo.json` 跑 `HistoryPage.fromEvents`，打印用户/过程组/助手三段结构 |
| `tool/verify_err.dart` | 宿主侧校验脚本：读 `ref/hist-err.json`，确认 `turn/end` 失败被解析成 `role=error` 消息 |

## bridge 协议引用

- 消费对象：`dsh-remote-bridge` v2.10.0，协议 `dsh-mobile-v1`，hello.protocol=3。
- 事实来源：`/media/wangke/OFFICE/workspace/dsh-remote-bridge/docs/api/`（openapi/asyncapi）
  + `docs/project/API.md` §客户端→服务端帧。
- 用到的帧：`ping/subscribe/unsubscribe/message/workspaces/sessions/history/hello`
  （`message.mode` 由本地偏好取 `queue` 或 `steer`，对照 companion 的繁忙发送策略）；
  `session-cancel`（停止当前回合，应答 `session-cancelled` 会回显 requestId，可 await）；
  推送：`event(chat.message.delta|chat.message.committed|chat.turn.failed)`、
  `connection-resync-required`、`question-requested`。

### 踩过的协议坑（勿重犯）

1. **requestId 在 `data` 里，不在帧顶层** —— `ws-protocol.ts:611` 的 `withRequestIdEcho`
   返回 `{...frame, data:{...record, requestId}}`。只读 `frame['requestId']` 会导致
   所有 `request()` 永不 resolve（30s 超时），但消息本身已送达。
2. **`subscribed` 帧不回显 requestId**（在 `REQUEST_ID_ECHO_EXCLUDED_KINDS` 排除表里）→
   `subscribe` 必须 fire-and-forget，不能 await。
3. **空态会收到别的会话的推送**（bridge「连接即重放」活跃会话）→ 必须用
   `sessionId != null && (sid == sessionId || sid == pendingSessionId)` 过滤，否则串台。
4. **`clientTimeZone` 必须是 IANA `Area/Location`**（正则要求带 `/`），Dart 的
   `timeZoneName` 在 Android 返回 `CST` → 走 MethodChannel 取 `TimeZone.getDefault().id`。
5. **`user/message` 带 `data.source.kind`**（`user` / `runtime-context` / `skill-catalog` /
   `time-context`），注入上下文也记成 user/message → 只显示 `kind == 'user'`。
6. **`assistant/message` 的 content 在 `data.message.content`**，`user/message` 在
   `data.content`。
