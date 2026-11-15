# 双会话并行时深度思考串台（2026-11-15）调查报告

反馈：「同时有两个会话在执行的时候，深度思考 未按照对应会话显示」。

## 复现路径与机制

1. 会话 A 在执行：`ChatState.streaming = true`，`streamReasoning` 累积 A 的
   深度思考（流式缓冲是 ChatState 上的**全局单一缓冲**，不分会话）。
2. 用户切到会话 B：`openSession(B)`（chat_state.dart）清了 rawEvents/projections/
   翻页状态，**但没清流式缓冲**（对比 `newChat()` 一直有 `_clearStream()`）。
3. B 页渲染：`_StreamingItem`（chat_message_items.dart:204）读全局
   `state.streamReasoning`/`streamText` + `state.streaming` → **B 页尾部挂着
   A 的深度思考气泡**；若 B 也在执行，B 的新 delta（`_isCurrent` 放行）
   追加在 A 残留后面，两段内容混在一起——「未按照对应会话显示」。
4. 切回 A：缓冲仍是「切走前的旧 A 内容」，与 reloadHistory 拉回的落库内容
   **重叠**（同一段思考显示两份），直到 committed 清空。

## 修复

`app/lib/ui/chat_state.dart` `openSession()`：切会话时
`streaming = false; _clearStream(); notifyListeners();` —— 与 newChat() 对齐；
notify 提前到 reloadHistory 之前，history 网络往返期间 B 页先渲染清空态，
不显示旧会话残留。切回 A 时缓冲从零累积，与落库历史衔接、不重复。

回补单测：`app/test/chat_actions_test.dart`（真实 `GatewayClient` 指向
`http://127.0.0.1:1` 不连接 + 手工灌残留状态 → openSession → 断言清空）。

## 「同时两个会话执行」的两种读法

- **切会话看另一会话 → 残留串台**：本报告修复项。
- **停在 A 只看 A 的流**：设计内行为。`_isCurrent()`（chat_state.dart:531）
  按 sessionId 过滤全部推送（delta/committed/turn-failed/session-event），
  未选会话时空态兜底也过滤（bridge「连接即重放」其它会话活跃事件不串台）；
  B 的流式进度切过去时由 reloadHistory + 后续 delta 续上。官方 App 同为
  「当前会话只显示当前会话的流」。

## 验证

`flutter analyze` 0 issue；`flutter test` 134 全绿（新增 1）。

## 遗留

- **断线重连**（`_onGatewayState(ready)`）不清流式缓冲：A 执行中断网重连后
  reloadHistory 拉落库内容，旧缓冲未清可能短暂重复。同类残留、用户未报、
  且 bridge 重连会重放当前订阅会话的活跃 delta（缓冲会续上）——单独评估，
  不混入本次提交。
- 实时帧 `chat.message.delta` 带 sessionId（MessageDelta.from 已解析），
  路由本身没有协议缺口，无需 bridge 改动。
