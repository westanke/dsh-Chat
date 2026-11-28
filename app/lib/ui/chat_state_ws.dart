part of 'chat_state.dart';

/// ChatState 的 WS 新通道：权威 todos（tasks 帧）、session.snapshot 基线、
/// compact history 预取。
///
/// 拆成 part 文件：chat_state.dart 已超宪法 §7 的 500 行存量上限，新逻辑不再往里堆。
extension ChatStateWs on ChatState {
  /// 拉当前会话的权威 todos 投影（WS `tasks` 帧，能力位 `mobile-tasks-v1`）。
  ///
  /// 失败/老桥不支持时**静默回退**：不动 [projections]，页面继续用本地推导
  /// （不能把面板清空，也不能把错误弹到聊天页）。成功时把 todos 合并回
  /// [projections] 的 `values.todos`，现有 `todoItems(projections)` 照常读到。
  Future<void> refreshSessionTasks(String sessionId) async {
    if (!_gateway.hasFrame('tasks')) return;
    try {
      final tasks = await _gateway.sessionTasks(sessionId);
      _tasksRefreshedAt[sessionId] = DateTime.now();
      // 期间切走了：结果只属于旧会话，不能写进当前页（切回时会重拉）。
      if (sessionId != this.sessionId) return;
      sessionTasks = tasks;
      projections = projectionsWithTodos(projections, tasks);
      // extension 里不能直接调 protected 的 notifyListeners；走公开转发。
      notifyUi();
    } on RequestException catch (e) {
      DshLog.w('ui tasks failed sid=$sessionId ${e.code}');
      // 回退：保留 projections 里的本地推导，不清、不报错。
    }
  }

  /// history 重拉后顺手刷新权威 todos（节流 3s；缺能力位时整体跳过）。
  void maybeRefreshSessionTasks() {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    if (!_gateway.hasFrame('tasks')) return;
    final now = DateTime.now();
    final last = _tasksRefreshedAt[id];
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _tasksRefreshedAt[id] = now;
    unawaited(refreshSessionTasks(id));
  }

  /// 记录 `chat.session.snapshot`（按会话；baseline 只记第一次）。
  void recordSessionSnapshot(SessionSnapshot snapshot) {
    if (snapshot.sessionId.isEmpty) return;
    sessionSnapshotBaselines.putIfAbsent(snapshot.sessionId, () => snapshot);
    sessionSnapshots[snapshot.sessionId] = snapshot;
  }

  /// resync 后能否跳过整页重拉：判定可单测；**当前接入仍保守重拉**
  /// （chat_state_events.dart 的 ResyncEvent 分支只记日志，不真的跳过）。
  bool shouldSkipResyncReload(String id) => shouldSkipSessionResync(
    sessionSnapshotBaselines[id],
    sessionSnapshots[id],
  );

  /// 紧凑历史预取入口（能力位 `history-compact-v1`；供首次加载长会话 /
  /// 后台预取使用）。本版本不被首屏调用，首屏默认仍走全文。
  ///
  /// 只接受服务端明确回 `compact:true` 的应答：老桥可能忽略参数回全文，
  /// 那种结果不能当摘要缓存（会把截断标记误用到全文上）。
  Future<HistoryPage?> prefetchCompactHistory(
    String sessionId, {
    int maxMessages = 200,
  }) async {
    if (!_gateway.hasFrame('history')) return null;
    try {
      final page = await _gateway.history(
        sessionId,
        maxMessages: maxMessages,
        compact: true,
      );
      if (!page.compact) {
        DshLog.w('ui compact-history 应答未标 compact sid=$sessionId');
        return null;
      }
      compactHistoryPrefetch = page;
      DshLog.w('ui compact-history sid=$sessionId items=${page.items.length}');
      return page;
    } on RequestException catch (e) {
      DshLog.w('ui compact-history failed sid=$sessionId ${e.code}');
      return null;
    }
  }
}
