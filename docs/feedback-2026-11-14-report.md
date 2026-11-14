# 交付文件卡落位（2026-11-14）调查报告

反馈（m00002）：「交付的会话中的文件卡，未在结尾位置，而在写入后的位置，不台合理」
—— 即文件卡出现在 present 工具调用的**当场**（过程组与收尾回复之间），
而不是整轮流尾（收尾回复之后）。

调查对象：dsh-remote-bridge v2.10.0（127.0.0.1:3090）、DSH 内核
`@deepseek-ai/dsh`（`~/.dsh-desktop/runtime/node-v24.19.0-linux-x64/lib/node_modules/@deepseek-ai/`）、
官方 Web 参照 `dsh-client-ui-deliverables`、本仓 Flutter 端。

## 证据链

1. **内核在哪里记事件**：`dsh-tool-present/lib/index.js` 的 tools/result 分支——
   present 工具 `tools/result` **成功当场**就 `session.append("deliverables/presented",
   {turn, callId, files})`。此时 assistant 的收尾正文还没产出，所以该事件 seq
   **必然落在收尾回复之前**。
2. **桥怎么转发**：`dsh-remote-bridge/src/host/chat-adapter.ts:1575` 实时把
   `deliverables/presented` 转成 `chat.deliverables.presented`
   （data={sessionId,eventType,seq,files}，无 turn 字段）；REST/WS history
   对该事件**原样透传**（asyncapi.yaml:391-410）。
3. **官方 Web 怎么用**：`dsh-client-ui-deliverables/lib/client.js` 里 deliverables
   是 **Turn-local accumulator**（publishes no view Node）——不直接产出视图节点，
   卡片挂 **turn-tail**（收尾回复之后），聚合整轮 produced+presented。
   这是官方 App 的观感基准：文件卡在**轮流尾**。
4. **Flutter 端错在哪**：`app/lib/bridge/models.dart`（原 445 行附近）HistoryPage.fromEvents
   按**事件 seq 内联**插 role='files' 卡 → 卡片卡在工具过程组与收尾 assistant
   正文之间 = 用户看到的「写入后的位置」。
5. **实时帧缺口**：`app/lib/bridge/gateway.dart` _onEventData 原本没有
   `chat.deliverables.presented` 分支，走 default 被忽略，只靠其它事件的
   800ms 防抖重拉补显示；实时与历史两条路都要修。

## 修复（本仓客户端，不改 bridge/协议）

对齐官方「轮次局部累积器」语义，**延迟落位**：

- `app/lib/bridge/history_page.dart`（fromEvents 装配器）：
  - 新增 `pendingFileCards` 暂存 + `flushFileCards()`（先 flush 未闭合过程组，
    再把暂存卡上屏、清空）；
  - `deliverables/presented` 分支改为 `pendingFileCards.add(...)`，不再按 seq 内联；
  - flush 点三处：**user/message 上屏前**（新一轮开始）、**turn/end case 开头**
    （两轮之间可能没有 user/message——目标续跑、子任务回合，turn/end 是唯一
    稳定轮边界；失败轮错误卡也在 case 内追加，卡自然挂在错误卡之前）、
    **事件流末尾**（最后一轮收口 / 翻页页尾）；
  - 翻页（beforeSeq）旧页在前、新页在后按页装配，页尾 flush 顺序天然正确。
- `app/lib/bridge/gateway.dart`（:277）：新增 `case 'chat.deliverables.presented'`
  → 转 `SessionEventReceived(sessionId, 'deliverables/presented')`；
  `chat_state.dart:456` 既有防抖重拉路径直接吃这个事件。帧里只有 files+seq、
  没有过程组上下文，**不就地插卡**，统一交给重拉后的 projector 按轮尾落位。
- 文件拆分：models.dart 因本次改动超 500 行（宪法 §7），历史装配四件套
  （SessionEvent / DeliverableFile / ChatMessage / HistoryPage）拆出
  `history_page.dart`，models.dart 经 export 继续暴露，既有 import 不受影响。

## 测试

`app/test/projections_test.dart` deliverables 组新增 4 例（期望 role 序列断言）：

1. present 后还有收尾正文 → `[user, assistant, files]`（不内联）；
2. turn/end 收口跨轮 → 卡挂第一轮流尾，不漂到第二轮；
3. 目标续跑轮（两轮间无 user/message）→ turn/end 也要收口；
4. 失败轮 → 卡挂在 error 卡之前（`[user, files, error]`）。

旧用例「文件卡夹在工具过程组中间」语义兼容（页尾 flush 后仍 process→files）。
验证：`flutter analyze` 0 issue；`flutter test` 133 全绿。

## 协议依据（供对照，本仓只消费不修改）

- 事件形状：dsh-remote-bridge asyncapi.yaml:391-410；
- 桥转发：chat-adapter.ts:1575-1591；
- 官方挂尾语义：dsh-client-ui-deliverables/lib/client.js（Turn-local accumulator）。

## 遗留说明

- 实时帧 `chat.deliverables.presented` 无 turn 字段，若未来想在收到帧的**当下**
  就显示（不等防抖重拉），需 bridge 在帧里补 turn —— 按宪法 §5 应去 bridge 仓
  开 issue，本仓不私改协议。
- 内核在 present 成功当场记事件（seq 在收尾正文前）是上游行为，客户端按
  「turn-local」语义消费即可，无需上游改动。
