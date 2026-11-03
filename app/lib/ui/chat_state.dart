/// 会话状态容器：编排 GatewayClient 与 UI（官方聊天页行为对齐）。
/// 数据流：delta 累积流式 → committed 后重拉 history 保证顺序正确。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/app_settings.dart';

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

  /// 当前设备名（抽屉底部账号栏显示，官方是手机号；bridge 侧是设备档案）。
  String get deviceLabel {
    final d = _gateway.device;
    final name = (d?['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'DSH Bridge';
  }

  /// 会话分组：按 updatedAt 归成「今天 / 昨天 / 更早」（官方抽屉的日期分组）。
  Map<String, List<DshSession>> get sessionGroups {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final out = <String, List<DshSession>>{};
    for (final s in sessions) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.updatedAt).toLocal();
      final day = DateTime(t.year, t.month, t.day);
      final label = day == today
          ? '今天'
          : day == yesterday
          ? '昨天'
          : '更早';
      out.putIfAbsent(label, () => []).add(s);
    }
    // 固定顺序，避免 Map 迭代顺序随插入变化
    final ordered = <String, List<DshSession>>{};
    for (final k in const ['今天', '昨天', '更早']) {
      final v = out[k];
      if (v != null && v.isNotEmpty) ordered[k] = v;
    }
    return ordered;
  }

  String? sessionId;
  String? _pendingSessionId;
  List<DshSession> sessions = [];
  List<ChatMessage> messages = [];

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
    _gateway.subscribe(s.id);
    await reloadHistory();
  }

  Future<void> newChat() async {
    sessionId = null;
    messages = [];
    _clearStream();
    _gateway.subscribe(null);
    notifyListeners();
  }

  Future<void> reloadHistory() async {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    try {
      final page = await _gateway.history(id, maxMessages: 200);
      DshLog.w('ui history id=$id items=${page.items.length}');
      messages = page.items;
      notifyListeners();
    } on RequestException catch (e) {
      lastError = '加载历史失败：${e.message}';
      notifyListeners();
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    // 不再因 streaming 直接拒绝：运行中再发由「繁忙发送模式」决定语义
    // （对照 companion ComposerSendPolicy：queue 排队 / steer 插话）。
    if (trimmed.isEmpty) return;
    lastError = null;
    messages = [...messages, ChatMessage(role: 'user', text: trimmed)];
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
      final sid = await _gateway.sendText(
        sessionId: sessionId,
        text: trimmed,
        mode: mode,
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
