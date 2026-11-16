/// 会话抽屉分组 —— 真机反馈 2026-11-16：列表**先按时间、再按工作区**排序，
/// 超过 2 天的会话收进可折叠的「更早」分组。
/// 与鸿蒙 `harmony/entry/src/main/ets/core/SessionGroups.ts` 同语义
/// （PORT-MAP 已记两端差异）；旧版「工作区优先、组内再分日期」实现见 git 历史。
/// 从 chat_state.dart 拆出（宪法 §7 单文件 ≤500 行）：纯函数、无状态。
library;

import '../bridge/models.dart';

/// 抽屉里一行会话：session + 该行上方的工作区小节标题。
class SessionRow {
  const SessionRow(this.session, this.sectionLabel);

  final DshSession session;

  /// 工作区小节标题（同工作区聚簇只在首行显示，「未分组」兜底）；
  /// null = 不显示小节标题。
  final String? sectionLabel;
}

/// 一个时间分组（今天 / 昨天 / 更早）。
class SessionGroup {
  const SessionGroup({
    required this.key,
    required this.label,
    required this.rows,
    required this.collapsible,
  });

  /// 稳定分组键：today / yesterday / earlier（抽屉展开态按它记忆）。
  final String key;

  /// 分组标题。
  final String label;

  /// 组内行（已按时间倒序、工作区聚簇排好）。
  final List<SessionRow> rows;

  /// 「超过 2 天」= true：默认收起，点分组标题展开/收起。
  final bool collapsible;

  /// 组内会话数（折叠态标题右侧显示条数）。
  int get count => rows.length;
}

/// 工作区名（空 → 「未分组」）。
String workspaceLabelOf(DshSession s) {
  final t = s.workspaceTitle;
  return (t == null || t.isEmpty) ? '未分组' : t;
}

/// 一天毫秒数。
const int _dayMs = 86400000;

/// 会话分桶：0=今天，1=昨天，2=更早（按本地日历天算，跨月/跨年都对）。
/// updatedAt<=0 归「更早」（无法判断新旧）。
int dayBucketOf(int updatedAt, DateTime now) {
  if (updatedAt <= 0) return 2;
  final then = DateTime.fromMillisecondsSinceEpoch(updatedAt).toLocal();
  final nowDay = DateTime(now.year, now.month, now.day);
  final thenDay = DateTime(then.year, then.month, then.day);
  final diffDays = ((nowDay.millisecondsSinceEpoch - thenDay.millisecondsSinceEpoch) / _dayMs)
      .round();
  if (diffDays <= 0) return 0;
  return diffDays == 1 ? 1 : 2;
}

/// 会话排序：时间倒序（最新在前），同一时刻按工作区名升序（二次键）。
int _compareSessions(DshSession a, DshSession b) {
  final byTime = b.updatedAt.compareTo(a.updatedAt);
  if (byTime != 0) return byTime;
  return workspaceLabelOf(a).compareTo(workspaceLabelOf(b));
}

/// 桶内按工作区聚成连续小节：工作区按首次出现顺序（= 该组内最新会话的
/// 时间顺序）排列，同工作区保持时间倒序，小节首行带工作区标题。
/// 时间只决定小节顺序：a2/a3 虽比 b1 旧，也要并回 ws-a 小节尾部。
List<SessionRow> _clusterRows(List<DshSession> bucket) {
  final byWs = <String, List<DshSession>>{};
  for (final s in bucket) {
    byWs.putIfAbsent(workspaceLabelOf(s), () => []).add(s);
  }
  return [
    for (final e in byWs.entries)
      for (var i = 0; i < e.value.length; i++)
        SessionRow(e.value[i], i == 0 ? e.key : null),
  ];
}

/// 抽屉分组总入口：先按时间分桶（今天/昨天/更早，空桶不产出，顺序固定），
/// 桶内按工作区聚合。传 [now] 便于单测固定基准时间。
List<SessionGroup> groupSessionsByTime(List<DshSession> sessions, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final buckets = <List<DshSession>>[[], [], []];
  for (final s in sessions) {
    buckets[dayBucketOf(s.updatedAt, base)].add(s);
  }
  for (final b in buckets) {
    b.sort(_compareSessions);
  }
  return [
    if (buckets[0].isNotEmpty)
      SessionGroup(
        key: 'today',
        label: '今天',
        rows: _clusterRows(buckets[0]),
        collapsible: false,
      ),
    if (buckets[1].isNotEmpty)
      SessionGroup(
        key: 'yesterday',
        label: '昨天',
        rows: _clusterRows(buckets[1]),
        collapsible: false,
      ),
    // 超过 2 天的全部归这里，默认收起（用户口径）。
    if (buckets[2].isNotEmpty)
      SessionGroup(
        key: 'earlier',
        label: '更早',
        rows: _clusterRows(buckets[2]),
        collapsible: true,
      ),
  ];
}

/// 展开/收起后实际要渲染的行（收起态把「更早」的行换成 0 行）。
List<SessionRow> visibleRowsOf(SessionGroup group, bool expandedEarlier) {
  if (group.collapsible && !expandedEarlier) return const [];
  return group.rows;
}
