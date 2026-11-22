/// 通知监听：把网关事件翻译成系统通知（对齐 dsh-go 的 chat_alerts + 投递决策）。
///
/// 消费的帧（与 dsh-go 同口径，都在已订阅会话的事件流里）：
/// - `chat.turn.end`  → 回答完成（reason.kind=error 归到失败）
/// - `chat.turn.failed` → 执行失败
/// - `chat.approval.requested` / `chat.userQuestions/requested` → 需要你处理
///
/// 投递规则：偏好关了不发；能不能发看系统权限；**正在看的会话不打扰**
/// （前台 + 同会话 = 跳过，界面里本来就有卡片）。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../bridge/gateway.dart';
import '../bridge/notify.dart';
import 'chat_state.dart';
import 'notify_prefs.dart';

class NotifyWatcher with WidgetsBindingObserver {
  NotifyWatcher(
    this._chat, {
    Future<NotifyStatus> Function()? statusOf,
    Future<bool> Function(NotifyPayload payload)? show,
  }) : _statusOf = statusOf ?? DshNotify.status,
       _show = show ?? DshNotify.show {
    _sub = _chat.gateway.events.listen(_onEvent);
    WidgetsBinding.instance.addObserver(this);
    _foreground = _lifecycleIsForeground();
  }

  final ChatState _chat;

  /// 状态/发送两个副作用点做成可注入的：单测能核对「发了几条、发了什么」，
  /// 不依赖真机系统通知（MethodChannel 在测试里恒不可用）。
  final Future<NotifyStatus> Function() _statusOf;
  final Future<bool> Function(NotifyPayload payload) _show;
  StreamSubscription<GatewayEvent>? _sub;
  bool _foreground = true;

  /// 已经为「这一轮」发过结束类通知的会话。
  ///
  /// 正常路径：`chat.turn.end` 到 → 记一笔并发通知；随后 `chat.session.status`
  /// 的 running=false 只是收尾，不重复打扰。反过来（turn.end 丢了）就靠
  /// status 兜一条，避免「回答结束了但一条通知都没有」。
  final Set<String> _turnNotified = <String>{};

  /// 点击通知后跳会话（由 main 注入，负责切到该会话）。
  void Function(String sessionId)? onOpenSession;

  bool _lifecycleIsForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _onEvent(GatewayEvent e) {
    if (e is TurnFailedEvent) {
      _turnNotified.add(e.sessionId);
      _post(
        kind: NotifyKind.failed,
        attention: false,
        sessionId: e.sessionId,
        key: 'fail:${e.sessionId}',
        title: '执行失败',
        text: _titleOf(e.sessionId, fallback: _clip(e.message)),
      );
    } else if (e is SessionStatusEvent) {
      _onSessionStatus(e);
    } else if (e is TurnEndedEvent) {
      final failed = e.reasonKind == 'error' || e.reasonKind == 'failed';
      final stopped =
          e.reasonKind == 'aborted' || e.reasonKind == 'interrupted';
      if (stopped) return; // 用户自己停的，不打扰
      _turnNotified.add(e.sessionId);
      _post(
        kind: failed ? NotifyKind.failed : NotifyKind.done,
        attention: false,
        sessionId: e.sessionId,
        key: 'turn:${e.sessionId}',
        title: failed ? '执行失败' : '回答已完成',
        text: _titleOf(e.sessionId, fallback: failed ? '本轮执行出错' : '点开查看结果'),
      );
    } else if (e is ApprovalRequestedEvent) {
      final a = e.approval;
      _post(
        kind: NotifyKind.approval,
        attention: true,
        sessionId: a.sessionId,
        key: 'approval:${a.sessionId}:${a.approvalId}',
        title: '需要你确认',
        text: _titleOf(a.sessionId, fallback: '工具 ${a.toolName} 等待批准'),
        eventId: a.approvalId,
      );
    } else if (e is QuestionRequestedEvent) {
      final q = e.question;
      _post(
        kind: NotifyKind.question,
        attention: true,
        sessionId: q.sessionId,
        key: 'question:${q.sessionId}:${q.callId}',
        title: '有新提问',
        text: _titleOf(
          q.sessionId,
          fallback: q.questions.isEmpty
              ? '有提问等你回答'
              : '${q.questions.length} 个问题等你回答',
        ),
        eventId: q.callId,
      );
    }
  }

  /// 轮状态兜底：running=false 但这一轮没发过结束通知 → 补一条「回答已完成」。
  ///
  /// 只补 done，不猜失败/中止（status 不带 reason）；启动新一轮时清掉标记。
  void _onSessionStatus(SessionStatusEvent e) {
    if (e.running) {
      _turnNotified.remove(e.sessionId);
      return;
    }
    if (!_turnNotified.remove(e.sessionId)) {
      _post(
        kind: NotifyKind.done,
        attention: false,
        sessionId: e.sessionId,
        key: 'turn:${e.sessionId}',
        title: '回答已完成',
        text: _titleOf(e.sessionId, fallback: '点开查看结果'),
      );
    }
  }

  Future<void> _post({
    required NotifyKind kind,
    required bool attention,
    required String sessionId,
    required String key,
    required String title,
    required String text,
    String? eventId,
  }) async {
    final prefs = NotifyPrefs.instance;
    final status = await _statusOf();
    final sameSession = _chat.sessionId == sessionId;
    if (!NotifyPrefs.shouldPost(
      allowsKind: prefs.allows(kind),
      canPost: status.canPost,
      foreground: _foreground,
      sameSession: sameSession,
    )) {
      return;
    }
    await _show(
      NotifyPayload(
        title: title,
        text: text,
        key: key,
        attention: attention,
        sessionId: sessionId,
        kind: kind.name,
        eventId: eventId,
      ),
    );
  }

  /// 通知正文优先用会话标题（用户一眼知道是哪个会话），取不到再用兜底文案。
  String _titleOf(String sessionId, {required String fallback}) {
    for (final s in _chat.sessions) {
      if (s.id == sessionId) {
        final t = s.title;
        if (t != null && t.trim().isNotEmpty) return t;
      }
    }
    return fallback;
  }

  String _clip(String s) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 80 ? flat : '${flat.substring(0, 80)}…';
  }
}
