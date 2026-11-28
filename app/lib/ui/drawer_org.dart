/// 会话抽屉的组织能力：置顶分组、未读小圆点、多选勾选与批量归档操作条。
///
/// 拆出原因：sessions_drawer.dart 已到宪法 §7 的 500 行上限，且这几块由
/// 「置顶 / 未读 / 多选」三个能力共用。纯逻辑（可见性、置顶排序、归档过滤）
/// 放在文件顶部，单测直接 import；行/标题组件见 drawer_org_widgets.dart，
/// 本文件只留分组编排与筛选口径。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'drawer_filter_bar.dart';
import 'drawer_org_widgets.dart';
import 'session_groups.dart';

/// 这一行是否落在当前的「工作区范围 + 状态筛选」内。
///
/// `pendingIds` = 待回答 ∪ 待审批；`unreadIds` = ChatState 的本地未读记账。
/// 置顶分组与时间分组、归档区共用这一口径，避免三处各写一份 switch。
bool drawerSessionVisible(
  DshSession session, {
  required DrawerFilter filter,
  required Set<String> pendingIds,
  required Set<String> unreadIds,
  String? scope,
}) {
  if (scope != null && (session.workspaceTitle ?? '') != scope) return false;
  return switch (filter) {
    DrawerFilter.all => true,
    DrawerFilter.running => session.running,
    DrawerFilter.pending => pendingIds.contains(session.id),
    DrawerFilter.unread => unreadIds.contains(session.id),
  };
}

/// 置顶会话，按内核 `pinnedSessionIds` 的顺序（最近置顶在前）。
///
/// 清单里的 id 可能已被别的端取消置顶/归档（集合比会话列表旧），
/// 只保留仍在 [sessions] 里的，不伪造条目。
List<DshSession> pinnedSessionsOf(
  List<DshSession> sessions,
  Set<String> pinnedIds,
) {
  if (pinnedIds.isEmpty) return const <DshSession>[];
  final order = <String, int>{};
  var rank = 0;
  for (final id in pinnedIds) {
    order[id] = rank++;
  }
  final out = sessions.where((s) => order.containsKey(s.id)).toList();
  out.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  return out;
}

/// 归档区按当前搜索 / 范围 / 筛选在本地过滤（桥一次只给全量归档列表）。
List<DshSession> filterArchivedSessions(
  List<DshSession> archived, {
  required String query,
  required String? scope,
  required DrawerFilter filter,
  required Set<String> pendingIds,
  required Set<String> unreadIds,
}) {
  return archived.where((s) {
    if (query.isNotEmpty && !s.displayTitle.toLowerCase().contains(query)) {
      return false;
    }
    return drawerSessionVisible(
      s,
      filter: filter,
      pendingIds: pendingIds,
      unreadIds: unreadIds,
      scope: scope,
    );
  }).toList();
}

/// 多选集合的点击语义：已选则移除，未选则加入（返回新集合，便于 setState 比较）。
Set<String> toggledSelection(Set<String> selected, String sessionId) {
  final next = Set<String>.of(selected);
  if (!next.remove(sessionId)) next.add(sessionId);
  return next;
}

/// 抽屉列表主体：内容搜索结果（leading）→ 置顶分组 → 时间分组 → 已归档。
///
/// 状态（筛选/范围/未读/多选）由 SessionsDrawerState 持有，这里只读快照、
/// 把动作回传；这样单测可以绕开整棵树，直接测上面的纯函数。
class DrawerOrgBody extends StatelessWidget {
  const DrawerOrgBody({
    super.key,
    required this.state,
    required this.colors,
    required this.groups,
    required this.query,
    required this.filter,
    required this.scope,
    required this.olderExpanded,
    required this.showArchived,
    required this.archived,
    required this.leading,
    required this.selecting,
    required this.selected,
    required this.onToggleOlder,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggleSelected,
  });

  final ChatState state;
  final DsColors colors;
  final List<SessionGroup> groups;
  final String query;
  final DrawerFilter filter;
  final String? scope;
  final bool olderExpanded;
  final bool showArchived;
  final List<DshSession> archived;

  /// 内容搜索（正文命中）块：由 sessions_drawer 生成后插到列表最前。
  final List<Widget> leading;
  final bool selecting;
  final Set<String> selected;
  final VoidCallback onToggleOlder;
  final ValueChanged<DshSession> onOpen;
  final ValueChanged<DshSession> onLongPress;
  final ValueChanged<String> onToggleSelected;

  Set<String> get _pendingIds => {
    ...state.hitlState.pendingQuestionSessionIds,
    ...state.hitlState.pendingApprovalSessionIds,
  };

  bool _visible(DshSession s) {
    // 置顶行由顶部「置顶」分组单独渲染，时间分组里不再重复。
    if (state.pinnedSessionIds.contains(s.id)) return false;
    if (query.isNotEmpty && !s.displayTitle.toLowerCase().contains(query)) {
      return false;
    }
    return drawerSessionVisible(
      s,
      filter: filter,
      pendingIds: _pendingIds,
      unreadIds: state.unreadSessionIds,
      scope: scope,
    );
  }

  bool _pinnedVisible(DshSession s) {
    if (query.isNotEmpty && !s.displayTitle.toLowerCase().contains(query)) {
      return false;
    }
    return drawerSessionVisible(
      s,
      filter: filter,
      pendingIds: _pendingIds,
      unreadIds: state.unreadSessionIds,
      scope: scope,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = pinnedSessionsOf(
      state.sessions,
      state.pinnedSessionIds,
    ).where(_pinnedVisible).toList();
    final visibleArchived = showArchived
        ? filterArchivedSessions(
            archived,
            query: query,
            scope: scope,
            filter: filter,
            pendingIds: _pendingIds,
            unreadIds: state.unreadSessionIds,
          )
        : const <DshSession>[];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 正文命中（内容搜索）排在时间分组之前：用户敲的是正文里的词时，
        // 最想要的往往是「跳到那个会话」，而不是先看标题过滤结果。
        ...leading,
        if (pinned.isNotEmpty) ...[
          DrawerOrgHeader(
            label: '置顶',
            count: pinned.length,
            colors: colors,
            icon: Icons.push_pin_outlined,
          ),
          for (final s in pinned) _row(s, selectable: true),
        ],
        for (final g in groups) ..._groupWidgets(g),
        if (showArchived) ..._archivedWidgets(visibleArchived),
      ],
    );
  }

  /// 一个时间分组：标题 + 过滤后的行（工作区小节标题按过滤后的首行重算，
  /// 修掉旧实现「筛选只隐藏整组、组内行照旧渲染」的错位）。
  List<Widget> _groupWidgets(SessionGroup g) {
    final rows = g.rows.where((r) => _visible(r.session)).toList();
    if (rows.isEmpty) return const [];
    final display = <SessionRow>[];
    String? prev;
    for (final r in rows) {
      final w = workspaceLabelOf(r.session);
      display.add(SessionRow(r.session, w == prev ? null : w));
      prev = w;
    }
    final expanded = olderExpanded || query.isNotEmpty;
    // 标题条数按过滤/置顶后的实际行数算：置顶行已经移到顶部，不再算进时间分组。
    final effective = SessionGroup(
      key: g.key,
      label: g.label,
      rows: rows,
      collapsible: g.collapsible,
    );
    return [
      DrawerGroupHeader(
        group: effective,
        colors: colors,
        expanded: expanded,
        onToggle: onToggleOlder,
      ),
      // 收起态不渲染行；搜索时展开全部组（visibleRowsOf 与分桶语义同源）。
      if (visibleRowsOf(effective, expanded).isNotEmpty)
        for (final r in display) ...[
          if (r.sectionLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.drawerItemPadH,
                DsSpacing.drawerSectionPadTop,
                DsSpacing.drawerItemPadH,
                DsSpacing.drawerSectionPadBottom,
              ),
              child: Text(
                r.sectionLabel!,
                style: DsTypography.caption.copyWith(
                  color: colors.drawerGroupLabel,
                ),
              ),
            ),
          _row(r.session, selectable: true),
        ],
    ];
  }

  List<Widget> _archivedWidgets(List<DshSession> visible) {
    return [
      DrawerOrgHeader(label: '已归档', count: visible.length, colors: colors),
      if (state.loadingArchived)
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: DsSpacing.drawerItemPadV,
          ),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.brand,
              ),
            ),
          ),
        )
      else if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.drawerItemPadH,
            DsSpacing.drawerItemPadV,
            DsSpacing.drawerItemPadH,
            DsSpacing.drawerItemPadV,
          ),
          child: Text(
            '暂无已归档会话',
            style: DsTypography.small.copyWith(color: colors.drawerGroupLabel),
          ),
        )
      else
        for (final s in visible) _row(s, selectable: false),
    ];
  }

  Widget _row(DshSession s, {required bool selectable}) {
    final hitl = state.hitlState;
    // 「待回答/待审批」角标（与电脑端会话列表 status.compact.* 同口径）：
    // 数据来自全连接挂起表（WS replay + REST 合流），按会话 id 派生。
    final badge = hitl.pendingQuestionSessionIds.contains(s.id)
        ? '待回答'
        : (hitl.pendingApprovalSessionIds.contains(s.id) ? '待审批' : null);
    final selectingHere = selecting && selectable;
    return SessionOrgRow(
      session: s,
      selected: s.id == state.sessionId,
      running: s.running,
      badge: badge,
      // 未读圆点优先级最低：有角标或正在运行时行尾已经被占用，不再叠一个点。
      unread:
          badge == null && !s.running && state.unreadSessionIds.contains(s.id),
      colors: colors,
      selecting: selectingHere,
      checked: selectingHere && selected.contains(s.id),
      onTap: () {
        if (selectingHere) {
          onToggleSelected(s.id);
          return;
        }
        onOpen(s);
      },
      onLongPress: selecting ? null : () => onLongPress(s),
    );
  }
}
