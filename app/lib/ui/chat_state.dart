/// 会话状态容器：编排 GatewayClient 与 UI（官方聊天页行为对齐）。
/// 数据流：delta 累积流式 → committed 后重拉 history 保证顺序正确。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/app_settings.dart';
import 'mobile_workspace.dart';
import 'session_groups.dart';

/// 纯函数：取 [0..end] 区间里最后一条有正文的用户消息文本
/// （对照 companion ChatRetry.kt：排除只有图片 / 空正文的用户消息）。
/// 抽成顶层函数便于单测，协议没有 regenerate 帧，重新生成=重新提问。
String? lastUserTextBefore(List<ChatMessage> messages, int end) {
  if (messages.isEmpty) return null;
  String? last;
  final stop = end.clamp(0, messages.length - 1);
  for (var i = 0; i <= stop; i++) {
    final m = messages[i];
    if (m.role == 'user' && m.text.trim().isNotEmpty) last = m.text;
  }
  return last;
}

class ChatState extends ChangeNotifier {
  ChatState(this._gateway) {
    _sub = _gateway.events.listen(_onEvent);
    _stateSub = _gateway.state.listen(_onGatewayState);
  }

  final GatewayClient _gateway;
  StreamSubscription<GatewayEvent>? _sub;
  StreamSubscription<GatewayState>? _stateSub;

  GatewayState get connectionState => _gateway.currentState;

  /// 权限档位 chip 需要：底层网关（发 permission-options / permission 帧）。
  GatewayClient get gateway => _gateway;

  /// 当前会话权限档位 value（projections.values.permissions.currentValue；
  /// 投影缺席/没有该条时为 null，UI 显示「权限」并可拉 permission-options）。
  String? get currentPermission {
    final values = projections?['values'];
    if (values is! Map) return null;
    final p = values['permissions'];
    if (p is! Map) return null;
    final v = p['currentValue'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// 当前设备名（抽屉底部账号栏显示，官方是手机号；bridge 侧是设备档案）。
  String get deviceLabel {
    final d = _gateway.device;
    final name = (d?['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'DSH Bridge';
  }

  /// 会话分组：实现在 session_groups.dart（顶层纯函数，宪法 500 行拆分）。
  Map<String, List<DshSession>> get sessionGroups =>
      groupSessionsByWorkspace(sessions);

  String? sessionId;
  String? _pendingSessionId;
  List<DshSession> sessions = [];
  List<ChatMessage> messages = [];

  /// 历史翻页（真机反馈 2026-11-04 第 5 项）：
  /// [historyHasMore] 服务端还有更早事件（history 应答 hasMore）；
  /// [loadingOlder] 翻页请求进行中（按钮转圈/防重复点击）。
  String? _mobileWorkspaceId; // 本连接内已知的手机工作区（mobile_workspace.dart）

  bool historyHasMore = false;
  bool loadingOlder = false;

  /// 已加载的最小 seq（下一页 beforeSeq）；-1 = 流式中的临时消息，跳过。
  int? get oldestSeq {
    for (final m in messages) {
      if (m.seq >= 0) return m.seq;
    }
    return null;
  }

  /// 当前会话的原始历史事件（轨迹 Sheet 本地分组用，零网络请求）。
  /// 形状：[{type, seq, time, data}]，data 为原样 Map。
  List<Map<String, dynamic>> rawEvents = [];

  /// 服务端算好的投影（团队 / TODO / 权限等）。可能为 null：内核没给基线时
  /// 整个字段缺席，且只在 history 首屏带、翻页不带（API.md:165,766）。
  /// 面板必须容忍缺席，不能把「读不到」渲染成「功能不存在」。
  Map<String, dynamic>? projections;

  /// 当前会话标题（顶栏居中显示，官方行为：会话名 + 新对话无标题）。
  String get sessionTitle {
    final id = sessionId;
    if (id == null || id.isEmpty) return '';
    for (final s in sessions) {
      if (s.id == id) return s.displayTitle;
    }
    return '';
  }

  /// 流式缓冲（text / reasoning 分开累积）。
  String streamText = '';
  String streamReasoning = '';
  bool streaming = false;
  String? lastError;

  bool get isEmpty => !streaming && messages.isEmpty;

  // ---- 对外动作 ----

  Future<void> loadSessions() async {
    try {
      sessions = await _gateway.sessions();
      notifyListeners();
    } on RequestException catch (e) {
      lastError = '加载会话失败：${e.message}';
      notifyListeners();
    }
  }

  Future<void> openSession(DshSession s) async {
    sessionId = s.id;
    // 切会话先清空原始事件/投影：防止上一会话的团队/TODO 串台
    // （reloadHistory 里 projections 缺席时会保留上一份）。
    rawEvents = [];
    projections = null;
    historyHasMore = false;
    loadingOlder = false;
    _gateway.subscribe(s.id);
    await reloadHistory();
  }

  Future<void> newChat() async {
    sessionId = null;
    messages = [];
    rawEvents = [];
    projections = null;
    historyHasMore = false;
    loadingOlder = false;
    _clearStream();
    _gateway.subscribe(null);
    notifyListeners();
  }

  Future<void> reloadHistory() async {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    try {
      final page = await _gateway.history(id, maxMessages: 200);
      DshLog.w('ui history id=$id items=${page.items.length} '
          'raw=${page.rawEvents.length} '
          'projections=${page.projections != null} '
          'hasMore=${page.hasMore}');
      messages = page.items;
      rawEvents = page.rawEvents;
      historyHasMore = page.hasMore;
      // 翻页/刷新时 projections 可能缺席：保留上一份（同会话），避免面板闪空。
      // 切会话时 newChat()/openSession() 会先清空，不会串台。
      projections = page.projections ?? projections;
      notifyListeners();
    } on RequestException catch (e) {
      lastError = '加载历史失败：${e.message}';
      notifyListeners();
    }
  }

  /// 向上翻页加载更早消息（真机反馈 2026-11-04 第 5 项）：
  /// beforeSeq = 当前已加载的最小 seq，返回的更早事件 prepend 到头部并按
  /// seq 去重（防刷新窗口内重叠）。翻页应答不带 projections（API.md:766）。
  Future<void> loadOlder() async {
    final id = sessionId;
    if (id == null || id.isEmpty || loadingOlder || !historyHasMore) return;
    final before = oldestSeq;
    if (before == null || before <= 0) return;
    loadingOlder = true;
    notifyListeners();
    try {
      final page = await _gateway.history(
        id,
        maxMessages: 200,
        beforeSeq: before,
      );
      DshLog.w('ui history-older id=$id before=$before '
          'items=${page.items.length} hasMore=${page.hasMore}');
      if (id != sessionId) return; // 翻页期间切了会话：丢弃
      final known = messages
          .where((m) => m.seq >= 0)
          .map((m) => m.seq)
          .toSet();
      final fresh = page.items
          .where((m) => m.seq < 0 || !known.contains(m.seq))
          .toList();
      messages = [...fresh, ...messages];
      rawEvents = [...page.rawEvents, ...rawEvents];
      historyHasMore = page.hasMore;
      notifyListeners();
    } on RequestException catch (e) {
      lastError = '加载更早消息失败：${e.message}';
      notifyListeners();
    } finally {
      loadingOlder = false;
      if (id == sessionId) notifyListeners();
    }
  }

  /// 带图发送（真机反馈 2026-11-04 第 2 项）：图片走 PromptPart.image
  /// （base64 内联，mediaType 白名单），文本可空。
  Future<void> sendWithImage(String text, PromptPart image) =>
      send(text, imagePart: image);

  Future<void> send(String text, {PromptPart? imagePart}) async {
    final trimmed = text.trim();
    // 纯图无文字也允许发（图片是完整消息内容）；两者都空才忽略。
    if (trimmed.isEmpty && imagePart == null) return;
    // 不再因 streaming 直接拒绝：运行中再发由「繁忙发送模式」决定语义
    // （对照 companion ComposerSendPolicy：queue 排队 / steer 插话）。
    lastError = null;
    messages = [
      ...messages,
      ChatMessage(role: 'user', text: trimmed.isEmpty ? '[图片]' : trimmed),
    ];
    // 繁忙发送模式（对照 companion ComposerSendPolicy）：运行中再发消息时，
    // queue = 排队等当前回合结束，steer = 立即打断。设置页偏好在这里落地。
    final mode = appSettings.busySendMode == BusySendMode.steer
        ? 'steer'
        : 'queue';
    // steer 会打断当前回合：清掉流式缓冲；queue 保留当前流式显示继续跑。
    // 注意：queue 时首回合 committed 会短暂置 streaming=false，随后次回合
    // delta 再置回 true（本版本不做多回合队列跟踪，属已知简化）。
    if (!streaming || mode == 'steer') _clearStream();
    streaming = true;
    notifyListeners();
    try {
      DshLog.w('ui send start sid=$sessionId mode=$mode');
      // 新会话落「手机会话」分组（真机反馈 2026-11-04 第 7 项）：
      // message 帧自动建会话不带 workspaceId（ws-basic.ts:39-47，落未分组），
      // 所以首条消息前先 session-create{workspaceId} 显式建到手机工作区。
      if (sessionId == null) {
        final wsId = await ensureMobileWorkspace(_gateway, _mobileWorkspaceId);
        if (wsId != null) {
          try {
            final sid = await _gateway.createSessionInWorkspace(wsId);
            DshLog.w('ui pre-created session $sid in workspace $wsId');
            _mobileWorkspaceId = wsId;
            sessionId = sid;
            _pendingSessionId = sid;
          } on RequestException catch (e) {
            // 建会话失败不阻断发消息：退回 message 帧自动建（落未分组）。
            DshLog.w('ui pre-create session FAIL ${e.code}');
          }
        }
      }
      final sid = await _gateway.sendText(
        sessionId: sessionId,
        text: trimmed,
        mode: mode,
        contentParts: imagePart == null ? null : [imagePart],
      );
      DshLog.w('ui send done sid=$sid');
      if (sessionId == null && sid != null) {
        sessionId = sid;
        _pendingSessionId = sid;
      }
      _gateway.subscribe(sessionId);
      DshLog.w('ui subscribed sid=$sessionId');
    } on RequestException catch (e) {
      DshLog.w('ui send FAIL ${e.code} ${e.message}');
      streaming = false;
      lastError = '发送失败：${e.message}';
      notifyListeners();
    }
  }

  /// 停止当前回合（对照 companion ChatHeader 的「停止运行」）：
  /// 发 session-cancel 帧，立即收起流式显示，再重拉历史拿落库的最终状态。
  Future<void> cancelTurn() async {
    final id = sessionId;
    if (!streaming || id == null || id.isEmpty) return;
    streaming = false;
    _clearStream();
    lastError = null;
    notifyListeners();
    try {
      await _gateway.cancelTurn(id);
      await reloadHistory();
    } on RequestException catch (e) {
      lastError = '停止失败：${e.message}';
      notifyListeners();
    }
  }

  /// 执行斜杠命令（真机反馈 2026-11-04 第 3 项）：`/xxx args` 整行走
  /// command-execute 帧，不出现在用户气泡里（bridge 端命令不入 chat 历史）。
  Future<void> runCommand(String line) async {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    lastError = null;
    try {
      final r = await _gateway.executeCommand(sessionId: id, line: line);
      final result = r['result'];
      final kind = result is Map ? (result['kind'] ?? '') as String : '';
      if (kind == 'error') {
        final text = result is Map && result['text'] is String
            ? result['text'] as String
            : '命令执行失败';
        lastError = text;
        notifyListeners();
        return;
      }
      // 成功的命令大多自带落盘事件（如 /model 走 session 事件）；保险起见
      // 重拉一次历史，把命令效果落到 UI。
      await reloadHistory();
    } on RequestException catch (e) {
      lastError = '命令执行失败：${e.message}';
      notifyListeners();
    }
  }

  /// 「重新生成」：重发指定助手消息之前（含）最后一条有正文的用户消息。
  /// 协议没有 regenerate 帧、本版本也未接 fork，因此采用「重新提问」语义
  /// （对照 companion ChatRetry.kt：排除只有图片/空正文的用户消息）。
  Future<void> regenerateAt(int index) async {
    if (streaming) return;
    final last = lastUserTextBefore(messages, index);
    if (last == null) return;
    await send(last);
  }

  /// 失败重试：重发历史里最后一条有正文的用户消息。
  Future<void> retryLast() => regenerateAt(messages.length - 1);

  void _clearStream() {
    streamText = '';
    streamReasoning = '';
  }

  // ---- 网关事件 ----

  void _onGatewayState(GatewayState s) {
    if (s == GatewayState.ready) {
      // 断线重连成功：重拉会话与当前历史（resync 兜底）。
      loadSessions();
      reloadHistory();
    }
    notifyListeners();
  }

  void _onEvent(GatewayEvent event) {
    switch (event) {
      case DeltaEvent(:final delta):
        DshLog.w(
          'ui delta kind=${delta.kind} len=${delta.text.length} sid=${delta.sessionId}',
        );
        if (!_isCurrent(delta.sessionId)) return;
        if (delta.kind == 'reasoning') {
          streamReasoning += delta.text;
        } else {
          streamText += delta.text;
        }
        streaming = true;
        notifyListeners();
      case CommittedEvent(:final committed):
        DshLog.w(
          'ui committed role=${committed.role} sid=${committed.sessionId}',
        );
        if (!_isCurrent(committed.sessionId)) return;
        // committed = 一条消息落库；重拉历史拿最终顺序与完整内容。
        if (committed.role == 'assistant') {
          streaming = false;
          _clearStream();
          reloadHistory();
        } else {
          // 用户消息落库：可能是本端发的（本地已乐观上屏），也可能是别的端
          // /REST 外部写入。统一做一次防抖重拉，保证外部写入也能看到。
          _scheduleToolRefresh();
        }
      case TurnFailedEvent(:final sessionId, :final message):
        if (!_isCurrent(sessionId)) return;
        streaming = false;
        _clearStream();
        lastError = message;
        notifyListeners();
      case ResyncEvent():
        // 背压丢帧：走 REST/WS 重拉当前历史。
        reloadHistory();
      case SessionEventReceived(:final sessionId):
        // 实时流只有 eventType（无事件体）：工具名/参数、外部端（REST）写入的
        // 正文都只能靠重拉 history 拿到。一轮 turn 事件很密，800ms 防抖限流。
        if (!_isCurrent(sessionId)) return;
        _scheduleToolRefresh();
    }
  }

  Timer? _toolRefreshTimer;

  void _scheduleToolRefresh() {
    if (_toolRefreshTimer?.isActive ?? false) return;
    _toolRefreshTimer = Timer(const Duration(milliseconds: 800), () {
      _toolRefreshTimer = null;
      reloadHistory();
    });
  }

  /// 未选会话（空态）时忽略一切推送——否则 bridge「连接即重放」其它会话的
  /// 活跃事件会串台到手机 UI（官方空态也不显示任何进行中的流）。
  /// 已选会话时：等于当前会话，或等于发送中待确认的会话（sent 应答前的 delta）。
  bool _isCurrent(String sid) =>
      (sessionId != null && sessionId!.isNotEmpty) &&
      (sid == sessionId || sid == _pendingSessionId);

  @override
  void dispose() {
    _toolRefreshTimer?.cancel();
    _sub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
