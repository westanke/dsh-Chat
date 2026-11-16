/// 工作步骤组展开态宿主（对照官方 App「通用设置」2026-11-16 批次）。
///
/// - 展开态从 DsProcessGroup 组件内部提升到 ChatState（key=组内首个
///   toolCall.callId，稳定跨历史 reload；无 callId 的组用 'seq<起始seq>'），
///   手动开合在任何展示档位/收起时机下都允许；
/// - verbose（完全展开）默认全展开：单独记「用户手动收起过」的例外表，
///   与手动展开表分开，切档互不污染、也无需监听设置变更清状态；
/// - 收起时机：completion=assistant committed 时收起最后一轮内展开的组；
///   next-input=send() 时收起全部展开的组。verbose 永不自动收起。
library;

import 'package:flutter/foundation.dart';

import '../bridge/models.dart';
import '../design/app_settings.dart';
import 'work_steps.dart';

/// 组展开态的稳定 key：组内首个 toolCall.callId；无 callId 用 'seq' 拼组内起始 seq。
String processGroupKeyOf(ChatMessage group) {
  final calls = group.toolCalls;
  if (calls.isNotEmpty && calls.first.callId.isNotEmpty) {
    return calls.first.callId;
  }
  return 'seq${group.seq}';
}

mixin GroupExpandState on ChangeNotifier {
  /// 用户手动展开的组 key 集（非 verbose 档生效）。
  final Set<String> expandedGroups = <String>{};

  /// verbose 档默认全展开，这里记「用户手动收起过」的例外。
  final Set<String> _verboseCollapsed = <String>{};

  bool isGroupExpanded(String key) {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) {
      return !_verboseCollapsed.contains(key);
    }
    return expandedGroups.contains(key);
  }

  void toggleGroup(String key) {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) {
      // verbose 的「收起」是往例外表里记；与手动展开表互不污染。
      if (!_verboseCollapsed.add(key)) _verboseCollapsed.remove(key);
      notifyListeners();
      return;
    }
    if (!expandedGroups.add(key)) expandedGroups.remove(key);
    notifyListeners();
  }

  /// 「回答结束后」收起时机：assistant committed 时收起最后一轮（最后一条
  /// user 之后）内展开的组。verbose 与其他时机直接返回。
  void collapseOnAssistantCommitted(List<ChatMessage> messages) {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) return;
    if (appSettings.collapseTiming != CollapseTiming.completion) return;
    final turn = lastTurnOf(messages);
    if (turn == null) return;
    var changed = false;
    for (var i = turn.start + 1; i < turn.end; i++) {
      final m = messages[i];
      if (m.isProcess) changed = expandedGroups.remove(processGroupKeyOf(m)) || changed;
    }
    if (changed) notifyListeners();
  }

  /// 「下次有新消息时」收起时机：send() 时收起全部展开的组。
  void collapseOnNewInput() {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) return;
    if (appSettings.collapseTiming != CollapseTiming.nextInput) return;
    if (expandedGroups.isEmpty) return;
    expandedGroups.clear();
    notifyListeners();
  }
}
