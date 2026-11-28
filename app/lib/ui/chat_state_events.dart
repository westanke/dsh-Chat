// ChatState 的网关事件分派（从 chat_state.dart 拆出：宪法 §7 单文件 ≤500 行）。
//
// delta 三路分派（桥 fdb85da 起 kind 扩展）：'text'→streamText、
// 'reasoning'→streamReasoning、'tool-call'/'tool-call-end'→流式工具缓冲；
// **未知 kind 忽略**（官方契约：老客户端不得把未知帧当正文渲染）。
// 工具帧（chat.tool.call / chat.tool.result）喂数据给 _toolBuffer；
// committed 后 reloadHistory 用持久化过程组覆盖缓冲。
part of 'chat_state.dart';

/// 网关事件总分派（ChatState 构造时 `_gateway.events.listen` 挂入）。
void _onGatewayEvent(ChatState state, GatewayEvent event) {
  switch (event) {
    case DeltaEvent(:final delta):
      // 逐条 delta 不写诊断日志：流式期间每帧一条同步写盘会拖死 UI 线程（真机 ANR）。
      if (!state._isCurrent(delta.sessionId)) return;
      switch (delta.kind) {
        case 'text':
          state.streamText += delta.text;
        case 'reasoning':
          state.streamReasoning += delta.text;
        case 'tool-call':
          state._toolBuffer.handleDelta(delta);
        case 'tool-call-end':
          state._toolBuffer.handleEnd(delta);
        default:
          // 未知 kind：忽略，不得当文本渲染（老客户端契约）。
          break;
      }
      state.streaming = true;
      state._notify();
    case CommittedEvent(:final committed):
      DshLog.w(
        'ui committed role=${committed.role} sid=${committed.sessionId} '
        'hasBody=${committed.hasReplyContent}',
      );
      if (!state._isCurrent(committed.sessionId)) return;
      // committed = 一条消息落库。内核在工具执行前会先提交一条只含
      // tool-call 块、无正文的 assistant 消息（hasReplyContent=false，桥
      // e08b6b5）——不能把它当「回答已结束」：不清 streaming、不清工具
      // 缓冲、不收起；正文提交了才清正文流式缓冲（工具行继续跑）。
      if (committed.role == 'assistant') {
        if (committed.hasReplyContent) state.clearStreamText();
        state.reloadHistory();
      } else {
        // 用户消息落库：可能是本端发的（本地已乐观上屏），也可能是别的端
        // /REST 外部写入。统一做一次防抖重拉，保证外部写入也能看到。
        state._scheduleToolRefresh();
      }
    case TurnStartedEvent(:final sessionId):
      // 新一轮开始：恢复流式态并复位截断提示（官方轮状态判据）。
      if (!state._isCurrent(sessionId)) return;
      state.streaming = true;
      state.maxTokensNotice = false;
      state._notify();
    case TurnEndedEvent(:final sessionId, :final reasonKind):
      // 轮真结束才停流式并清缓冲；「回答结束后」收起时机挂在这里——
      // abort 类结束（aborted/interrupted/error）不收起；max-tokens 置
      // 截断提示。TurnFailed（桥失败轮替代 turn.end）另有分支。
      if (!state._isCurrent(sessionId)) return;
      state.streaming = false;
      state._clearStream();
      const abortKinds = {'aborted', 'interrupted', 'error'};
      if (!abortKinds.contains(reasonKind)) {
        state.collapseOnAssistantCommitted(state.messages);
      }
      if (reasonKind == 'max-tokens') state.maxTokensNotice = true;
      state.reloadHistory();
    case TurnFailedEvent(:final sessionId, :final message):
      if (!state._isCurrent(sessionId)) return;
      state.streaming = false;
      state.maxTokensNotice = false;
      state._clearStream();
      state.lastError = message;
      state._notify();
    case GatewayErrorEvent(:final error):
      // 没有 requestId / requestType 可归属的错误帧：retryable 与 details
      // 之前在这一层就丢了，UI 既不知道能不能重试，也不知道限流要等多久。
      state.reportError(
        error.rateLimited ? '请求过于频繁' : '请求失败',
        error,
        retry: error.retryable && !error.rateLimited
            ? () => state.retryLast()
            : null,
      );
      state._notify();
    case SessionStatusEvent(:final sessionId, :final running):
      // 兜底：turn/end 走跟随流，丢了就永远「生成中」（桥 v2.16.1 已修根因，
      // 老桥仍可能丢）。chat.session.status 走 host 流，不依赖那次跟随。
      // 正常收尾时 turn.end 先到、streaming 已落，这里直接 no-op，不重复重拉。
      if (!state._isCurrent(sessionId)) return;
      if (running) {
        state.streaming = true;
        state._notify();
        return;
      }
      if (!state.streaming) return;
      state.streaming = false;
      state._clearStream();
      state.reloadHistory();
    case SessionSnapshotEvent(:final snapshot):
      // `chat.session.snapshot`（能力位 session-snapshot-v1）：只记每个会话的
      // cursor 切点，不改消息/投影，也不需要重建（不 notify）。
      state.recordSessionSnapshot(snapshot);
    case ResyncEvent():
      // 背压丢帧：走 WS 重拉当前历史。
      // 能力位 session-snapshot-v1 下已有 cursor 基线时，这里先记一条
      // 「能否跳过整页重拉」的判定（可单测），但**仍重拉**——判定接入刻意保守，
      // 避免 cursor 语义在旧桥/边界情况下误跳过真实断档。
      final resyncSid = state.sessionId;
      if (resyncSid != null && resyncSid.isNotEmpty) {
        DshLog.w(
          'ui resync sid=$resyncSid '
          'skip=${state.shouldSkipResyncReload(resyncSid)}',
        );
      }
      state.reloadHistory();
    case ToolCallEvent(:final call):
      // 工具开始执行：参数定稿覆盖 preparing 行（streaming 标记由 delta 流
      // 置位；committed 前后到达都只刷缓冲）。
      if (!state._isCurrent(call.sessionId)) return;
      if (state.isPersistedToolCall(call.callId)) {
        // 该工具行已在持久过程组里：不往缓冲重复建行，防抖重拉让持久组
        // 刷新状态（迟到帧 + dropPersisted 组合防「持久组+流式组」双份）。
        state._scheduleToolRefresh();
        return;
      }
      state._toolBuffer.handleCall(call);
      state._notify();
    case ToolResultEvent(:final result):
      // 工具结果：error.code 分派（已停止/已取消/失败）+ 结果正文落行。
      if (!state._isCurrent(result.sessionId)) return;
      if (state.isPersistedToolCall(result.callId)) {
        state._scheduleToolRefresh();
        return;
      }
      state._toolBuffer.handleResult(result);
      state._notify();
    case SessionEventReceived(:final sessionId):
      // 实时流只有 eventType（无事件体）：低频事件与老桥（工具调用还没有
      // 独立帧的版本）靠防抖重拉 history 拿完整明细，800ms 防抖限流。
      if (!state._isCurrent(sessionId)) return;
      state._scheduleToolRefresh();
    case QuestionRequestedEvent(:final question):
      // HITL 提问（含 replay 补推）：按 callId 去重入表（全连接）。
      DshLog.w(
        'ui question requested callId=${question.callId} '
        'sid=${question.sessionId} n=${question.questions.length}',
      );
      state.hitl.onQuestionRequested(question);
    case QuestionResolvedEvent(:final sessionId, :final callId):
      DshLog.w('ui question settled callId=$callId sid=$sessionId');
      state.hitl.onQuestionResolved(callId);
    case ApprovalRequestedEvent(:final approval):
      DshLog.w('ui approval requested id=${approval.approvalId}');
      state.hitl.onApprovalRequested(approval);
    case ApprovalResolvedEvent(:final sessionId, :final approvalId):
      DshLog.w('ui approval resolved id=$approvalId sid=$sessionId');
      state.hitl.onApprovalResolved(approvalId);
    case LinkClosedEvent(:final code, :final reason):
      // 语义化 close（协议对齐）：4001 = 设备吊销/鉴权失败（重连无意义），
      // 1009 = 单帧超过 hello 下发的 maxFrameBytes，1013 = 服务端连接数满。
      // 上限不再硬编码 1 MiB：用事件里带的本次连接实际上限（老桥才回退默认值）。
      DshLog.w('ui link closed code=$code reason=$reason');
      if (event.revoked) {
        state.lastError = '设备已被吊销（close 4001），请重新配对';
      } else if (event.frameTooLarge) {
        final limit = event.limitBytes ?? state.gateway.frameLimitBytes;
        state.lastError = '${frameLimitHint(limit)}；连接已重置';
      } else if (event.serverBusy) {
        state.lastError = '服务端连接数已满，请稍后再试';
      }
      state._notify();
    case QueueUpdatedEvent(:final sessionId, :final queue):
      // 队列整份快照（bridge 22a5223）：直接替换；推送可能被反压丢弃，
      // 丢了靠下次读帧/轮末快照补（IKX2AE 客户端约束 1）。
      if (!state._isCurrent(sessionId)) return;
      applyChatQueue(state, queue);
    case ModelsUpdatedEvent():
      // 模型目录推送（桥 v2.11.0，issue #1）：模型面板打开时必重拉
      // models 帧，这里无需处理；显式 case 保 switch 穷尽并留扩展点。
      break;
  }
}
