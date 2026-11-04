/// 会话抽屉分组（真机反馈 2026-11-04 第 7 项）。
/// 从 chat_state.dart 拆出（宪法 §7 单文件 ≤500 行）：纯函数、无状态。
library;

import '../bridge/models.dart';

/// 顶层按工作区分——「手机会话」（title 含「手机」的工作区）排最前，
/// 其余工作区用其 title，无工作区的落「未分组」；组内再按 updatedAt
/// 归「今天 / 昨天 / 更早」。单工作区单日期时组名退化为纯日期（与官方一致）。
Map<String, List<DshSession>> groupSessionsByWorkspace(
  List<DshSession> sessions,
) {
  /// 会话分组（真机反馈 2026-11-04 第 7 项）：顶层按工作区分——
  /// 「手机会话」（title 含「手机」的工作区）排最前，其余工作区用其 title，
  /// 无工作区的落「未分组」；组内再按 updatedAt 归「今天 / 昨天 / 更早」。

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String dayLabel(DshSession s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.updatedAt).toLocal();
      final day = DateTime(t.year, t.month, t.day);
      return day == today ? '今天' : day == yesterday ? '昨天' : '更早';
    }

    // 顶层：工作区桶（保持 sessions 原顺序，手机工作区置顶）。
    final byWs = <String, List<DshSession>>{};
    for (final s in sessions) {
      final key = (s.workspaceTitle != null && s.workspaceTitle!.isNotEmpty)
          ? s.workspaceTitle!
          : '未分组';
      byWs.putIfAbsent(key, () => []).add(s);
    }
    final out = <String, List<DshSession>>{};
    void emit(String wsKey) {
      final bucket = byWs.remove(wsKey);
      if (bucket == null || bucket.isEmpty) return;
      // 单工作区不套两层组名；多组时组名 = 工作区名 · 日期。
      final days = <String, List<DshSession>>{};
      for (final s in bucket) {
        days.putIfAbsent(dayLabel(s), () => []).add(s);
      }
      final single = byWs.isEmpty && out.isEmpty && days.length == 1;
      for (final e in days.entries) {
        out[single ? e.key : '$wsKey · ${e.key}'] = e.value;
      }
    }

    emit('手机会话');
    for (final k in byWs.keys.toList()) {
      if (k != '未分组') emit(k);
    }
    emit('未分组');
    return out;
}
