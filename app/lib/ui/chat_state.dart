/// 会话状态容器：编排 GatewayClient 与 UI（官方聊天页行为对齐）。
/// 数据流：delta 累积流式 → committed 后重拉 history 保证顺序正确。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/app_settings.dart';
import 'hitl_state.dart';
import 'chat_history_actions.dart';
import 'mobile_workspace.dart';
import 'session_groups.dart';

export 'hitl_state.dart';

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

  /// HITL 挂起表（question_card.dart 渲染；事件转发见 _onEvent）。
  HitlState get hitlState => hitl;

  /// 当前设备名（抽屉底部账号栏显示，官方是手机号；bridge 侧是设备档案）。
  String get deviceLabel {
    final d = _gateway.device;
    final name = (d?['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'DSH Bridge';
  }

  /// 当前连接地址（抽屉底部绿点旁显示，真机反馈第三轮 3）：
  /// baseUrl 去掉协议前缀，只留 host[:port]。
  String get connectionLabel {
    final raw = _gateway.baseUrl;
    final stripped = raw.replaceFirst(RegExp(r'^https?://'), '');
    return stripped.isEmpty ? raw : stripped;
  }

  /// 会话分组：实现在 session_groups.dart（顶层纯函数，宪法 500 行拆分）。
  Map<String, List<DshSession>> get sessionGroups =>
      groupSessionsByWorkspace(sessions);

  String? sessionId;
  String? _pendingSessionId;
  List<DshSession> sessions = [];
  List<ChatMessage> messages = [];

  /// 新建会话的待定工作目录（2026-11-15 反馈）：null = 默认「手机会话」
  /// 工作区；非空时 send() 首条消息走 session-create{rootId,cwd}，
  /// 会话建好即清；newChat() 也清（不沿用上次选择）。
  SessionLocation? pendingLocation;

  /// 目录 sheet 的写入入口（含通知；别直接赋值）。
  void setPendingLocation(SessionLocation? loc) {
    pendingLocation = loc;
    notifyListeners();
  }

  /// 顶层动作文件的对外通知入口（notifyListeners 是 protected）。
  void notifyUi() => notifyListeners();

  /// 历史翻页（真机反馈 2026-11-04 第 5 项）：
  /// [historyHasMore] 服务端还有更早事件（history 应答 hasMore）；
  /// [loadingOlder] 翻页请求进行中（按钮转圈/防重复点击）。
  String? _mobileWorkspaceId; // 本连接内已知的手机工作区（mobile_workspace.dart）

  bool historyHasMore = false;
  bool loadingOlder = false;

  /// 翻页刚 prepend 过更早消息（第二轮反馈 A）：列表层消费后清零，
  /// 用于跳过一次贴底跟随，保住用户阅读位置。
  bool historyPageJustLoaded = false;

  /// 已加载的最小 seq（下一页 beforeSeq）；-1 = 流式中的临时消息，跳过。
  /// 当前会话的原始历史事件（轨迹 Sheet 本地分组用，零网络请求）。
  /// 形状：[{type, seq, time, data}]，data 为原样 Map。
  List<Map<String, dynamic>> rawEvents = [];

  /// 服务端算好的投影（团队 / TODO / 权限等）。可能为 null：内核没给基线时
  /// 整个字段缺席，且只在 history 首屏带、翻页不带（API.md:165,766）。
  /// 面板必须容忍缺席，不能把「读不到」渲染成「功能不存在」。
  Map<String, dynamic>? projections;

  // ---- HITL 问答 / 审批（真机反馈补充：DSH 向用户提问）----
  // 状态与动作在 hitl_state.dart（宪法 §7 拆分）；这里组合并转发事件。

  final HitlState hitl = HitlState();

  List<PendingQuestion> get sessionQuestions =>
      hitl.sessionQuestions(sessionId);

  List<PendingApproval> get sessionApprovals =>
      hitl.sessionApprovals(sessionId);

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
    historyPageJustLoaded = false;
    // 流式缓冲一并清（2026-11-15 反馈）：A 会话执行中切到 B，残留的
    // streamReasoning/streamText 会以流式气泡（_StreamingItem）挂在 B 页
    // 尾部——「深度思考未按照对应会话显示」正是这个残留；若 B 也在执行，
    // B 的 delta 追加在 A 残留后面，两段内容混在一起。切回 A 时缓冲从零
    // 累积，与 reloadHistory 拉回的落库内容衔接、不重复。
    // newChat() 一直有 _clearStream()，openSession 漏了。
    streaming = false;
    _clearStream();
    // 先用清空态渲染新会话页（history 网络往返期间不显示旧会话残留）。
    notifyListeners();
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
    historyPageJustLoaded = false;
    // 目录选择随新会话重置回「手机会话」默认（不沿用上次选择）。
    pendingLocation = null;
    _clearStream();
    _gateway.subscribe(null);
    notifyListeners();
  }

  Future<void> reloadHistory() => reloadChatHistory(this); // 实现见 chat_history_actions.dart

  Future<void> loadOlder() => loadOlderMessages(this);

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
      // 建会话通道：选了目录走 session-create{rootId,cwd}；否则落手机工作区。
      if (sessionId == null && pendingLocation != null) {
        final loc = pendingLocation!;
        final sid = await _gateway.createSessionAt(
          rootId: loc.rootId,
          cwd: loc.cwd,
        );
        DshLog.w('ui pre-created session $sid at ${loc.cwd}');
        sessionId = sid;
        _pendingSessionId = sid;
        pendingLocation = null; // 目录已定死，随会话落位。
      } else if (sessionId == null) {
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
  /// 第六轮反馈 m03878：执行回执以本地「命令卡」消息注入会话流——
  /// 成功显示命令行 + 结果摘要（kind），失败显示错误文本；重拉历史后
  /// 本地卡保留（seq=-1 不参与去重/排序），直到下次 reloadHistory 重建。
  Future<void> runCommand(String line) async {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    lastError = null;
    final card = ChatMessage(
      role: 'command',
      text: line,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    messages = [...messages, card];
    notifyListeners();
    try {
      final r = await _gateway.executeCommand(sessionId: id, line: line);
      final result = r['result'];
      final kind = result is Map ? (result['kind'] ?? '') as String : '';
      if (kind == 'error') {
        final text = result is Map && result['text'] is String
            ? result['text'] as String
            : '命令执行失败';
        card.text = '$line\n✗ $text';
        lastError = text;
        notifyListeners();
        return;
      }
      final detail = result is Map && result['text'] is String
          ? (result['text'] as String).trim()
          : '';
      card.text = detail.isEmpty
          ? '$line\n✓ 已执行'
          : '$line\n✓ $detail';
      // 成功的命令大多自带落盘事件（如 /model 走 session 事件）；保险起见
      // 重拉一次历史，把命令效果落到 UI。
      await reloadHistory();
      notifyListeners();
    } on RequestException catch (e) {
      card.text = '$line\n✗ ${e.message}';
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
      case QuestionRequestedEvent(:final question):
        // HITL 提问（含 replay 补推）：按 callId 去重入表（全连接）。
        DshLog.w(
          'ui question requested callId=${question.callId} '
          'sid=${question.sessionId} n=${question.questions.length}',
        );
        hitl.onQuestionRequested(question);
      case QuestionResolvedEvent(:final sessionId, :final callId):
        DshLog.w('ui question settled callId=$callId sid=$sessionId');
        hitl.onQuestionResolved(callId);
      case ApprovalRequestedEvent(:final approval):
        DshLog.w('ui approval requested id=${approval.approvalId}');
        hitl.onApprovalRequested(approval);
      case ApprovalResolvedEvent(:final sessionId, :final approvalId):
        DshLog.w('ui approval resolved id=$approvalId sid=$sessionId');
        hitl.onApprovalResolved(approvalId);
    }
  }

  // ---- HITL 动作（问答 / 审批；失败落 lastError）----

  /// 提交一套答案（question-answer 帧）。成功即本地摘卡。
  Future<void> answerQuestion(
    PendingQuestion question,
    List<QuestionAnswerItem> answers,
  ) async {
    lastError = null;
    try {
      await hitl.answerQuestion(_gateway, question, answers);
    } on RequestException catch (e) {
      lastError = '提交回答失败：${e.message}';
    }
    notifyListeners();
  }

  /// 放弃一条提问（question-cancel）；continued 态取消不了会提示。
  Future<void> cancelQuestion(PendingQuestion question) async {
    lastError = null;
    try {
      await hitl.cancelQuestion(_gateway, question);
    } on RequestException catch (e) {
      lastError = '无法跳过该提问：${e.message}';
    }
    notifyListeners();
  }

  /// 审批决定（allowed-once / rejected）。成功即本地摘卡。
  Future<void> decideApproval(PendingApproval approval, bool allow) async {
    lastError = null;
    try {
      await hitl.decideApproval(_gateway, approval, allow);
    } on RequestException catch (e) {
      lastError = '审批操作失败：${e.message}';
    }
    notifyListeners();
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
