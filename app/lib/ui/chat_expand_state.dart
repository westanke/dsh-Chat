/// 工作步骤组展开态宿主（对照官方 App「通用设置」2026-11-16 批次）。
///
/// - 展开态从 DsProcessGroup 组件内部提升到 ChatState（key=组内首个
///   toolCall.callId，稳定跨历史 reload；无 callId 的组用 'seq<起始seq>'），
///   手动开合在任何展示档位/收起时机下都允许；
/// - 运行中轮的组默认展开（forceOpen，2026-11-17 批次）：用户手动收起过的
///   组记入豁免表，本轮内不再强推展开；
/// - verbose（完全展开）：会话页改为逐条平铺渲染，不再有组折叠行；
///   组级例外表保留用于档位切换的安全兜底；
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
  /// 用户手动展开的组 key 集（verbose 以外档位生效）。
  final Set<String> expandedGroups = <String>{};

  /// 运行中轮的组被 forceOpen 撑开时，用户手动收起过 → 本会话不再强推。
  final Set<String> _forceDismissed = <String>{};

  /// verbose 档的「用户手动收起过」例外（平铺模式下组行不再渲染，仅兜底）。
  final Set<String> _verboseCollapsed = <String>{};

  bool isGroupExpanded(String key) {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) {
      return !_verboseCollapsed.contains(key);
    }
    return expandedGroups.contains(key);
  }

  /// 运行中轮的组是否被用户手动收起过（forceOpen 豁免）。
  bool isForceOpenDismissed(String key) => _forceDismissed.contains(key);

  /// 手动开合以「视觉态」为准：运行中轮的组被 forceOpen 撑开时（[open]=true
  /// 但并不在手动展开表里），点按=收起并记入强推豁免，而不是把底层展开位翻开。
  void toggleProcessGroup(String key, {required bool open}) {
    if (appSettings.workStepsDetail == WorkStepsDetail.verbose) {
      if (!_verboseCollapsed.add(key)) _verboseCollapsed.remove(key);
      notifyListeners();
      return;
    }
    if (open) {
      expandedGroups.remove(key);
      _forceDismissed.add(key);
    } else {
      expandedGroups.add(key);
      _forceDismissed.remove(key);
    }
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
