/// 侧边会话抽屉：工具条 + 搜索框 + 状态筛选 + 日期分组 + 纯文字条目 + 底部主机卡片。
/// 布局对齐官方 App（docs/design-tokens.md 4.2 节：搜索框 y117..248 逐像素一致）；
/// 2026-11-22 按 dsh-go 补了顶部工具条与筛选胶囊（drawer_toolbar /
/// drawer_filter_bar），条目行尾状态点见 sessions_drawer_item。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'drawer_filter_bar.dart';
import 'drawer_toolbar.dart';
import 'session_actions.dart';
import 'session_groups.dart';
import 'session_search.dart';
import 'session_search_section.dart';
import 'sessions_drawer_footer.dart';
import 'sessions_drawer_item.dart';
import 'window_class.dart';

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({
    super.key,
    required this.state,
    required this.colors,
    required this.onOpenSettings,
    required this.onClose,
    this.onSwitchHost,
    this.width = DsSpacing.drawerWidth,
  });

  final ChatState state;
  final DsColors colors;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉不走 Navigator 路由，条目点选后用这个回调收起抽屉
  /// （原 Scaffold.drawer 方案里是 Navigator.pop，会在 Stack 实现下误弹聊天页）。
  final VoidCallback onClose;

  /// 工具条「换主机」：null = 不显示这个圆钮（默认落到设置页的连接区）。
  final VoidCallback? onSwitchHost;

  /// 这一列的宽度：手机 288（屏宽 80% 的官方值），平板/折叠屏 320
  /// （见 docs/design-tokens.md §4.15 与 window_class.dart）。
  final double width;

  @override
  State<SessionsDrawer> createState() => SessionsDrawerState();
}

class SessionsDrawerState extends State<SessionsDrawer> {
  final _search = TextEditingController();

  /// 「更早」分组展开态（默认收起）。真机反馈 2026-11-16：超过 2 天的
  /// 会话收起来，点分组标题展开/收起。
  bool _olderExpanded = false;

  /// 状态筛选（全部 / 运行中 / 待确认）。「未读」暂不做：桥不下发 unread，
  /// 本地记账跨启动不可靠，宁缺不作假（见 docs/FEATURE-PARITY.md 抽屉一行）。
  DrawerFilter _filter = DrawerFilter.all;

  /// 工作区范围：null = 全部对话，否则只显示该工作区的会话。
  String? _scope;

  /// 会话**内容**搜索（内核 `session/search`，走 `dshrb-v1` 通用调用面）。
  ///
  /// 编排逻辑全在 session_search.dart：这里只负责喂输入、画结果。桥不提供这能力时
  /// [SessionSearchController.supported] 为 false，列表仍走原来的标题本地过滤——
  /// 用户感觉不到能力缺失，只是搜不到正文（与接这条之前逐字相同）。
  SessionSearchController? _content;

  @override
  void initState() {
    super.initState();
    _content = SessionSearchController(gateway: widget.state.gateway)..addListener(_onContentSearch);
  }

  void _onContentSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _content?.removeListener(_onContentSearch);
    _content?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = widget.colors;
    // 官方抽屉：顶部搜索框（圆角胶囊灰底）→ 日期分组标题 → 会话条目 → 底部账号栏。
    final groups = state.sessionGroups;
    final q = _search.text.trim().toLowerCase();
    final archived = state.showArchived ? _archivedFor(q) : const <DshSession>[];

    // 内容搜索（正文命中）只在桥提供 dshrb-v1 + 内核装了 session/search 时才有。
    // 不支持时整段不出现，列表照旧按标题本地过滤 —— 这就是「降级」。
    final content = _content;
    final showContent = content != null && content.supported && content.visible;
    return Drawer(
      width: widget.width,
      backgroundColor: c.bgLayer1,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerToolbar(
              colors: c,
              onNewChat: () {
                widget.onClose();
                state.newChat();
              },
              onSwitchHost: widget.onSwitchHost ?? widget.onOpenSettings,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.drawerSearchPadH,
                DsSpacing.drawerSearchPadTop,
                DsSpacing.drawerSearchPadRight,
                0,
              ),
              child: Container(
                height: DsSpacing.drawerSearchHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.drawerSearchInset,
                ),
                decoration: BoxDecoration(
                  color: c.drawerSearchFill,
                  borderRadius: BorderRadius.circular(
                    DsSpacing.drawerSearchRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: c.drawerGroupLabel),
                    const SizedBox(width: DsSpacing.drawerSearchIconGap),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        style: DsTypography.small.copyWith(
                          color: c.labelPrimary,
                        ),
                        cursorColor: c.brand,
                        decoration: InputDecoration(
                          hintText: '搜索对话',
                          hintStyle: DsTypography.small.copyWith(
                            color: c.drawerGroupLabel,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) => _onSearchChanged(v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DrawerFilterBar(
              colors: c,
              filter: _filter,
              onFilter: (f) => setState(() => _filter = f),
              runningCount: groups
                  .expand((g) => g.rows)
                  .where((r) => r.session.running)
                  .length,
              pendingCount: _pendingCount(groups),
              unreadCount: 0,
              scopeLabel: _scope ?? '全部对话',
              onScopeTap: () => _pickScope(context, c),
            ),
            // 归档会话开关：桥只提供 `sessions{archived:true}`（只列归档，
            // 没有恢复接口），所以这里只做「显示/不显示」，不伪造恢复动作。
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.drawerItemPadH,
                0,
                DsSpacing.drawerItemPadH,
                0,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 18,
                    color: c.drawerGroupLabel,
                  ),
                  const SizedBox(width: DsSpacing.drawerSearchIconGap),
                  Expanded(
                    child: Text(
                      '显示已归档',
                      style: DsTypography.small.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    value: state.showArchived,
                    onChanged: (v) {
                      state.setShowArchived(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: groups.isEmpty && archived.isEmpty && !state.showArchived && !showContent
                  ? Center(
                      child: Text(
                        '暂无会话',
                        style: DsTypography.small.copyWith(
                          color: c.drawerGroupLabel,
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        // 正文命中（内容搜索）排在时间分组之前：用户敲的是正文里的词
                        // 时，最想要的往往是「跳到那个会话」，而不是先看标题过滤结果。
                        if (showContent)
                          ...buildContentSearchSection(
                            content: content,
                            colors: c,
                            state: state,
                            onOpen: widget.onClose,
                          ),
                        // 时间分组（今天/昨天/更早），桶内按工作区聚簇；
                        // 渲染拆进 _sectionWidgets（宪法 500 行拆分）。
                        for (final g in groups) ..._sectionWidgets(g, q, c, state),
                        if (state.showArchived) ..._archivedSection(c, state, q),
                      ],
                    ),
            ),
            SessionsDrawerFooter(
              colors: c,
              label: state.deviceLabel,
              connectionLabel: state.connectionLabel,
              connected: state.connectionState == GatewayState.ready,
              onOpenSettings: widget.onOpenSettings,
              onClose: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索框输入：本地标题过滤立刻生效（不必等网络），内容搜索交给防抖控制器。
  void _onSearchChanged(String value) {
    _content?.update(value);
    setState(() {});
  }

  /// 一个时间分组的渲染件：分组标题 + 桶内行（工作区小节标题只在聚簇
  /// 首行显示；「更早」默认收起，搜索时自动展开并按输入过滤、过滤后
  /// 重算小节标题——同工作区只在第一条可见行前显示）。
  List<Widget> _sectionWidgets(SessionGroup g, String q, DsColors c, ChatState state) {
    final searching = q.isNotEmpty;
    final rows = (searching
            ? g.rows.where(
                (r) => r.session.displayTitle.toLowerCase().contains(q),
              )
            : g.rows)
        .where(_visible)
        .toList();
    if (rows.isEmpty) return const [];
    final display = <SessionRow>[];
    if (searching) {
      String? prev;
      for (final r in rows) {
        final w = workspaceLabelOf(r.session);
        display.add(SessionRow(r.session, w == prev ? null : w));
        prev = w;
      }
    } else {
      display.addAll(g.rows);
    }
    return [
      _groupHeader(g, c),
      // 收起态不渲染行；搜索时展开全部组（visibleRowsOf 与分桶语义同源）。
      if (visibleRowsOf(g, _olderExpanded || searching).isNotEmpty)
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
                style: DsTypography.caption.copyWith(color: c.drawerGroupLabel),
              ),
            ),
          SessionsDrawerItem(
            session: r.session,
            selected: r.session.id == state.sessionId,
            // 「待回答/待审批」角标（与电脑端会话列表 status.compact.* 同口径）：
            // 数据来自全连接挂起表（WS replay + REST 合流），按会话 id 派生；
            // hitl 变更经 ChatState.notifyUi 直达本页重建。
            running: r.session.running,
            badge: state.hitlState.pendingQuestionSessionIds.contains(r.session.id)
                ? '待回答'
                : (state.hitlState.pendingApprovalSessionIds.contains(r.session.id)
                      ? '待审批'
                      : null),
            colors: c,
            onTap: () {
              widget.onClose();
              state.openSession(r.session);
            },
            onLongPress: () => openSessionMenu(context, state, r.session, c),
          ),
        ],
    ];
  }

  /// 归档会话按当前搜索/范围/筛选在本地过滤（桥一次只给全量归档列表）。
  List<DshSession> _archivedFor(String q) {
    return widget.state.archivedSessions.where((s) {
      if (_scope != null && (s.workspaceTitle ?? '') != _scope) return false;
      if (q.isNotEmpty && !s.displayTitle.toLowerCase().contains(q)) {
        return false;
      }
      return switch (_filter) {
        DrawerFilter.all => true,
        DrawerFilter.running => s.running,
        DrawerFilter.pending => _pendingIds.contains(s.id),
        DrawerFilter.unread => false,
      };
    }).toList();
  }

  /// 「已归档」区：单独一段放在时间分组之后。桥不支持恢复，条目只可打开。
  List<Widget> _archivedSection(DsColors c, ChatState state, String q) {
    final archived = _archivedFor(q);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.drawerGroupPadH,
          DsSpacing.drawerGroupPadV,
          DsSpacing.drawerGroupPadH,
          DsSpacing.drawerGroupGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已归档',
                style: DsTypography.small.copyWith(color: c.drawerGroupLabel),
              ),
            ),
            Text(
              '${archived.length} 条',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
          ],
        ),
      ),
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
                color: c.brand,
              ),
            ),
          ),
        )
      else if (archived.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.drawerItemPadH,
            DsSpacing.drawerItemPadV,
            DsSpacing.drawerItemPadH,
            DsSpacing.drawerItemPadV,
          ),
          child: Text(
            '暂无已归档会话',
            style: DsTypography.small.copyWith(color: c.drawerGroupLabel),
          ),
        )
      else
        for (final s in archived)
          SessionsDrawerItem(
            session: s,
            selected: s.id == state.sessionId,
            running: s.running,
            colors: c,
            onTap: () {
              widget.onClose();
              state.openSession(s);
            },
          ),
    ];
  }

  /// 这一行是否落在当前的筛选与工作区范围内。
  bool _visible(SessionRow r) {
    final s = r.session;
    if (_scope != null && (s.workspaceTitle ?? '') != _scope) return false;
    return switch (_filter) {
      DrawerFilter.all => true,
      DrawerFilter.running => s.running,
      DrawerFilter.pending => _pendingIds.contains(s.id),
      DrawerFilter.unread => false,
    };
  }

  /// 待回答 / 待审批的会话 id（与行尾角标同源：全连接挂起表）。
  Set<String> get _pendingIds => {
    ...widget.state.hitlState.pendingQuestionSessionIds,
    ...widget.state.hitlState.pendingApprovalSessionIds,
  };

  int _pendingCount(List<SessionGroup> groups) {
    final ids = _pendingIds;
    return groups
        .expand((g) => g.rows)
        .where((r) => ids.contains(r.session.id))
        .length;
  }

  /// 「全部对话」那一行点开的范围选择：全部 + 各工作区（按会话现存的去重）。
  Future<void> _pickScope(BuildContext context, DsColors c) async {
    final names = <String>{};
    for (final g in widget.state.sessionGroups) {
      for (final r in g.rows) {
        final w = r.session.workspaceTitle;
        if (w != null && w.isNotEmpty) names.add(w);
      }
    }
    final picked = await showModalBottomSheet<String?>(
      context: context,
      constraints: modalSheetConstraints(context),
      backgroundColor: c.bgLayer1,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                '选择范围',
                style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
              ),
            ),
            for (final w in [null, ...names])
              ListTile(
                title: Text(
                  w ?? '全部对话',
                  style: DsTypography.base.copyWith(color: c.labelPrimary),
                ),
                trailing: (w == _scope)
                    ? Icon(Icons.check, size: 20, color: c.brand)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(w ?? ''),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _scope = picked.isEmpty ? null : picked);
  }

  /// 分组标题行：「更早」右侧显示「N 条 · 展开/收起」并整行可点切换；
  /// 普通分组保持官方 tune 图标样式。
  Widget _groupHeader(SessionGroup g, DsColors c) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            g.label,
            style: DsTypography.small.copyWith(color: c.drawerGroupLabel),
          ),
        ),
        if (g.collapsible)
          Text(
            '${g.count} 条 · ${_olderExpanded ? '收起' : '展开'}',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
          )
        else
          Icon(Icons.tune, size: 16, color: c.drawerGroupLabel),
      ],
    );
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupPadV,
        DsSpacing.drawerGroupPadH,
        DsSpacing.drawerGroupGap,
      ),
      child: row,
    );
    if (!g.collapsible) return padded;
    return InkWell(
      onTap: () => setState(() => _olderExpanded = !_olderExpanded),
      child: padded,
    );
  }
}
