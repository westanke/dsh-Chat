/// 会话状态容器：编排 GatewayClient 与 UI（官方聊天页行为对齐）。
/// 数据流：delta 累积流式 → committed 后重拉 history 保证顺序正确。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/queue.dart';
import '../design/app_settings.dart';
import 'hitl_state.dart';
import 'chat_command_actions.dart';
import 'chat_history_actions.dart';
import 'chat_queue_actions.dart';
import 'chat_expand_state.dart';
import 'chat_hitl_actions.dart';
import 'chat_setup_state.dart';
import 'mobile_workspace.dart';
import 'session_groups.dart';
import 'streaming_tools.dart';

export 'hitl_state.dart';

part 'chat_state_events.dart';

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

class ChatState extends ChangeNotifier
    with GroupExpandState, ChatSetupState {
  ChatState(this._gateway) {
    _sub = _gateway.events.listen((event) => _onGatewayEvent(this, event));
    _stateSub = _gateway.state.listen(_onGatewayState);
    // HITL 卡片要自己驱动重建：hitl 表变更（含 replay/REST 合流）直达 UI，
    // 不依赖 reloadHistory「碰巧」触发（2026-11-16 真机：replay 晚于 reloadHistory 时提问卡永不出现）。
    hitl.addListener(notifyUi);
    appSettings.addListener(notifyUi); // 通用设置变更直达会话页（列表读 appSettings）
  }

  final GatewayClient _gateway;
  StreamSubscription<GatewayEvent>? _sub;
  StreamSubscription<GatewayState>? _stateSub;

  GatewayState get connectionState => _gateway.currentState;

  /// 权限档位 chip 需要：底层网关（发 permission-options / permission 帧）。
  @override
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

  /// HITL 挂起表（question_card.dart 渲染；事件转发见 chat_state_events.dart）。
  HitlState get hitlState => hitl;

  /// 唯一一条单题提问：输入条文字直接当答案（一个请求 + 一题；有审批不抢答）。
  PendingQuestion? get singleOpenQuestion {
    final list = hitl.sessionQuestions(sessionId);
    if (list.length != 1) return null;
    final request = list.single;
    if (request.questions.length != 1) return null;
    if (hitl.sessionApprovals(sessionId).isNotEmpty) return null;
    return request;
  }

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
  /// 真机反馈 2026-11-16：时间优先分桶（今天/昨天/更早），超 2 天折叠。
  List<SessionGroup> get sessionGroups => groupSessionsByTime(sessions);

  @override
  String? sessionId;
  String? _pendingSessionId;
  @override
  List<DshSession> sessions = [];
  List<ChatMessage> messages = [];

  /// 命令卡（role=='command'，seq=-1）**按会话归属**保存：服务端历史里没有这类
  /// 本地回执，reloadHistory 重建 messages 时要拼回尾部。必须按会话 id 归属：
  /// 只存在 messages 里的话，切会话时 merge 会把上一会话的卡片当本地消息保留，
  /// 于是「A 执行的命令结果挂在所有会话尾巴上，重进才消」（真机 2026-11-23）。
  final Map<String, List<ChatMessage>> commandCards = {};

  /// 待发送队列（mobile-queue-v1；老桥恒空；身份用 inboxId）。
  List<QueueEntry> queue = const [];

  bool get queueSupported => _gateway.hasCapability(queueCapability);

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

  /// 服务端按字节预算裁掉了最旧端事件（history 应答 `truncated`，
  /// bridge history-byte-budget-v1）。列表头显示一次「部分历史未显示」。
  bool historyTruncated = false;

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
  @override
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

  /// 按 id 打开会话（通知点击用）：先查已加载列表，没命中就重拉一次；
  /// 还找不到就按最小会话对象打开（bridge 会补齐投影/历史）。
  Future<void> openSessionById(String id) async {
    if (id.isEmpty || id == sessionId) return;
    for (final s in sessions) {
      if (s.id == id) return openSession(s);
    }
    await loadSessions();
    for (final s in sessions) {
      if (s.id == id) return openSession(s);
    }
    await openSession(
      DshSession(id: id, rootId: '', updatedAt: 0, running: false, blank: false),
    );
  }

  Future<void> openSession(DshSession s) async {
    // 命令卡只活在执行它的那一次会话里：进会话即清，切走也不带走
    // （真机 2026-11-23：命令结果卡跨会话串台，只有重进会话才消失）。
    commandCards.remove(s.id);
    sessionId = s.id;
    // 切会话先清空原始事件/投影：防止上一会话的团队/TODO 串台
    // （reloadHistory 里 projections 缺席时会保留上一份）。
    rawEvents = [];
    projections = null;
    historyHasMore = false;
    loadingOlder = historyPageJustLoaded = historyTruncated = false;
    queue = const [];
    // 流式缓冲一并清（2026-11-15 反馈）：A 会话执行中切到 B，残留的
    // streamReasoning/streamText 会以流式正文挂在 B 页
    // 尾部——「深度思考未按照对应会话显示」正是这个残留；若 B 也在执行，
    // B 的 delta 追加在 A 残留后面，两段内容混在一起。切回 A 时缓冲从零
    // 累积，与 reloadHistory 拉回的落库内容衔接、不重复。
    // newChat() 一直有 _clearStream()，openSession 漏了。
    streaming = false;
    _clearStream();
    // 先用清空态渲染新会话页（history 网络往返期间不显示旧会话残留）。
    notifyListeners();
    _gateway.subscribe(s.id);
    // REST 兜底拉一次挂起提问（含内核 continued）：WS replay 只补本桥前台
    // 挂起表，内核 continued（限时提问）只有 REST 看得到。fire-and-forget，
    // 失败静默（打断换会话的代价大于漏一张兜底卡）。
    unawaited(_refreshPendingQuestions(s.id));
    await reloadHistory();
    unawaited(loadChatQueue(this));
    // 模型 chip 的文案跟着会话走（服务端 models 帧的 current.model）。
    await refreshModelLabel();
  }

  /// REST 拉会话挂起提问并合流进 hitl 表（见 GatewayApi.fetchQuestions）。
  Future<void> _refreshPendingQuestions(String sessionId) async {
    try {
      hitl.mergeQuestions(await _gateway.fetchQuestions(sessionId));
    } on RequestException catch (e) {
      DshLog.w('ui pending-questions refresh failed sid=$sessionId ${e.code}');
    }
  }

  Future<void> newChat() async {
    sessionId = null;
    streaming = false; // 生成中标记属于上一会话，不清会带成新会话的空「生成中」
    messages = [];
    commandCards.clear(); // 新对话不继承上一会话的命令卡
    queue = const [];
    rawEvents = [];
    projections = null;
    historyHasMore = false;
    loadingOlder = false;
    historyPageJustLoaded = false;
    historyTruncated = false;
    // 目录选择随新会话重置回「手机会话」默认（不沿用上次选择）。
    pendingLocation = null;
    // 模型 chip 的文案属于上一个会话：清掉（草稿保留 —— 那是给「接下来这个
    // 新会话」选的配置，newChat 不该把它丢掉）。
    modelLabel = null;
    _clearStream();
    _gateway.subscribe(null);
    notifyListeners();
  }

  Future<void> reloadHistory() => reloadChatHistory(this); // 实现见 chat_history_actions.dart

  Future<void> loadOlder() => loadOlderMessages(this);

  /// 带图发送（真机反馈 2026-11-04 第 2 项 / 2026-11-21 多图）：每张图一个
  /// PromptPart.image（base64 内联，mediaType 白名单），文本可空。
  Future<void> sendWithImages(String text, List<PromptPart> images) =>
      send(text, imageParts: images);

  Future<void> send(String text, {List<PromptPart>? imageParts}) async {
    final trimmed = text.trim();
    // 纯图无文字也允许发（图片是完整消息内容）；两者都空才忽略。
    if (trimmed.isEmpty && (imageParts == null || imageParts.isEmpty)) return;
    // 单题提问挂着且无图片：这段文字就是答案，不再发成新一轮提问。
    final pendingQuestion = imageParts == null || imageParts.isEmpty
        ? singleOpenQuestion
        : null;
    if (pendingQuestion != null && trimmed.isNotEmpty) {
      await _answerSingleQuestion(pendingQuestion, trimmed);
      return;
    }
    // 不再因 streaming 直接拒绝：运行中再发由「繁忙发送模式」决定语义
    // （对照 companion ComposerSendPolicy：queue 排队 / steer 插话）。
    lastError = null;
    final userText = trimmed.isEmpty ? '[图片]' : trimmed;
    messages = [...messages, ChatMessage(role: 'user', text: userText)];
    // 收起时机 = 下次有新消息时：发送即收起（verbose 档永不自动收起）。
    collapseOnNewInput();
    // 繁忙发送模式（对照 companion ComposerSendPolicy）：运行中再发消息时，
    // queue = 排队等当前回合结束，steer = 立即打断。设置页偏好在这里落地。
    final mode =
        appSettings.busySendMode == BusySendMode.steer ? 'steer' : 'queue';
    // steer 会打断当前回合：清掉流式缓冲；queue 保留当前流式显示继续跑。
    // 注意：queue 时首回合 committed 会短暂置 streaming=false，随后次回合
    // delta 再置回 true（本版本不做多回合队列跟踪，属已知简化）。
    if (!streaming || mode == 'steer') _clearStream();
    streaming = true;
    maxTokensNotice = false;
    notifyListeners();
    try {
      DshLog.w('ui send start sid=$sessionId mode=$mode');
      // 建会话通道：选了目录走 session-create{rootId,cwd}；否则落手机工作区。
      // 模式（Agent 预设）随 session-create 的 agentPreset 字段下发
      // （bridge ws-sessions.ts:49-95 支持该字段）。
      if (sessionId == null && pendingLocation != null) {
        final loc = pendingLocation!;
        final sid = await _gateway.createSessionAt(
          rootId: loc.rootId,
          cwd: loc.cwd,
          agentPreset: setup.agentPresetId,
        );
        DshLog.w('ui pre-created session $sid at ${loc.cwd}');
        sessionId = sid;
        _pendingSessionId = sid;
        pendingLocation = null; // 目录已定死，随会话落位。
        await applySetupTo(sid);
      } else if (sessionId == null) {
        final wsId = await ensureMobileWorkspace(_gateway, _mobileWorkspaceId);
        if (wsId != null) {
          try {
            final sid = await _gateway.createSessionInWorkspace(
              wsId,
              agentPreset: setup.agentPresetId,
            );
            DshLog.w('ui pre-created session $sid in workspace $wsId');
            _mobileWorkspaceId = wsId;
            sessionId = sid;
            _pendingSessionId = sid;
            await applySetupTo(sid);
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
        contentParts: imageParts == null || imageParts.isEmpty
            ? null
            : imageParts,
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

  /// 把输入条文字作为自定义答案提交（question-answer 帧；成功即本地摘卡）。
  Future<void> _answerSingleQuestion(
    PendingQuestion question,
    String text,
  ) async {
    lastError = null;
    try {
      await hitl.answerQuestion(_gateway, question, [
        QuestionAnswerItem(id: question.questions.single.id, custom: text),
      ]);
    } on RequestException catch (e) {
      lastError = '提交回答失败：${e.message}';
    }
    notifyListeners();
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

  /// 确保当前有会话可挂（IKX5MV：斜杠命令必须带 sessionId 才能派发）。
  ///
  /// 新对话（sessionId 为空）里发 `/tunnel` 之类宿主命令时先建会话，路径与
  /// send() 的预建通道一致：选了目录 → session-create{rootId,cwd}；否则
  /// 手机工作区 → session-create{workspaceId}；老桥没工作区 → 未分组兜底。
  /// 返回建好/已有的会话 id；建不出来返回 null（调用方给错误卡，别静默）。
  Future<String?> ensureSessionOpen() async {
    final existing = sessionId;
    if (existing != null && existing.isNotEmpty) return existing;
    String? sid;
    try {
      if (pendingLocation != null) {
        final loc = pendingLocation!;
        sid = await _gateway.createSessionAt(
          rootId: loc.rootId,
          cwd: loc.cwd,
          agentPreset: setup.agentPresetId,
        );
        pendingLocation = null; // 目录已定死，随会话落位。
      } else {
        final wsId = await ensureMobileWorkspace(_gateway, _mobileWorkspaceId);
        if (wsId != null) {
          sid = await _gateway.createSessionInWorkspace(
            wsId,
            agentPreset: setup.agentPresetId,
          );
          _mobileWorkspaceId = wsId;
        } else {
          // 老桥没有工作区概念：建到默认位置（未分组），不阻挠命令派发。
          sid = await _gateway.createSessionAt(agentPreset: setup.agentPresetId);
        }
      }
    } on RequestException catch (e) {
      DshLog.w('ui ensure-session FAIL ${e.code}');
      lastError = '建立会话失败：${e.message}';
      notifyListeners();
      return null;
    }
    if (sid.isEmpty) return null;
    sessionId = sid;
    _pendingSessionId = sid;
    _gateway.subscribe(sid);
    notifyListeners();
    unawaited(loadSessions());
    await applySetupTo(sid);
    return sid;
  }

  /// 执行斜杠命令（实现见 chat_command_actions.dart）。
  Future<void> runCommand(String line) => runChatCommand(this, line);

  /// 「重新生成」：重发上一条用户正文（实现见 chat_command_actions.dart）。
  Future<void> regenerateAt(int index) => regenerateChatAt(this, index);

  Future<void> retryLast() => retryChatLast(this);

  /// 工具调用实时缓冲（桥 fdb85da 工具帧 → preparing/running/结果三态；
  /// committed 后由 reloadHistory 的持久化过程组覆盖，_clearStream 清空）。
  final StreamingToolBuffer _toolBuffer = StreamingToolBuffer();

  /// 流式工具合成过程组（空缓冲回 null；列表装配层据此插流式过程组）。
  ChatMessage? get streamingProcess => _toolBuffer.processMessage;

  /// 「回答被截断」提示（官方：轮结束 reason=max-tokens 时置位，列表装配
  /// 层渲染提示行；新轮 turn.start 或 send() 复位）。
  bool maxTokensNotice = false;

  /// 只清正文流式缓冲，不动工具行缓冲——中途 committed（正文已落库）时
  /// 工具仍在转（内核先提交无正文消息，工具跑完才出最终正文）。
  void clearStreamText() {
    streamText = '';
    streamReasoning = '';
  }

  /// reloadHistory 后按 callId 去掉已持久化的流式工具行，防止同一工具
  /// 「流式行 + 持久过程组」双份渲染（缓冲清空后 streamingProcess 为 null）。
  void dropPersistedToolRows() {
    final ids = <String>{
      for (final m in messages)
        for (final c in m.toolCalls)
          if (c.callId.isNotEmpty) c.callId,
    };
    _persistedCallIds = ids;
    _toolBuffer.dropPersisted(ids);
  }

  /// 已持久化的工具 callId（reloadHistory 后由持久过程组承载的集合）：
  /// 内核先提交无正文消息再执行工具，随后 tool/call 帧才到——缓冲行已被
  /// dropPersisted 清掉，迟到帧若重建行会出现「持久组 + 流式组」双份。
  Set<String> _persistedCallIds = const {};

  /// 该 callId 是否已由持久化消息承载（持久过程组渲染，缓冲不再重复建行）。
  bool isPersistedToolCall(String callId) =>
      callId.isNotEmpty && _persistedCallIds.contains(callId);

  /// 网关事件分派（chat_state_events.dart）用的 notifyListeners 转发——
  /// 顶层函数调用 ChangeNotifier.protected 成员会触发 lint，收进实例方法。
  void _notify() => notifyListeners();

  void _clearStream() {
    clearStreamText();
    _toolBuffer.clear();
  }

  /// 服务端统计投影（`session-stats` 帧：sessionStats/tokenUsage/contextPressure）。
  /// null = 没拉过，或桥太老（< 2.12 没有这一帧，回 UNKNOWN_TYPE）。
  Map<String, dynamic>? serverStats;

  /// 拉服务端统计（统计 Sheet 打开时调；失败静默回落本地估算）。
  Future<void> loadServerStats() async {
    final id = sessionId;
    if (id == null || id.isEmpty) return;
    try {
      serverStats = await _gateway.sessionStats(id);
      notifyListeners();
    } on RequestException catch (e) {
      DshLog.w('ui session-stats failed ${e.code}');
      notifyListeners();
    }
  }

  void _onGatewayState(GatewayState s) {
    if (s == GatewayState.authFailed) {
      // 4001 吊销 / 令牌失效：只有重新配对能恢复，别让用户干等重连。
      lastError = '连接鉴权失败：设备可能已被吊销，请重新配对';
    }
    if (s == GatewayState.ready) {
      // 断线重连成功：重拉会话与当前历史（resync 兜底）。
      loadSessions();
      reloadHistory();
    }
    notifyListeners();
  }

  // ---- HITL 动作（问答 / 审批；实现见 chat_hitl_actions.dart）----

  Future<void> answerQuestion(
    PendingQuestion question,
    List<QuestionAnswerItem> answers,
  ) => submitChatAnswer(this, question, answers);

  Future<void> cancelQuestion(PendingQuestion question) =>
      skipChatQuestion(this, question);

  Future<void> decideApproval(PendingApproval approval, bool allow) =>
      decideChatApproval(this, approval, allow);

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
    appSettings.removeListener(notifyUi);
    super.dispose();
  }
}
