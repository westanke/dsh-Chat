/// 侧边会话抽屉：工具条 + 搜索框 + 状态筛选 + 日期分组 + 纯文字条目 + 底部主机卡片。
/// 布局对齐官方 App（docs/design-tokens.md 4.2 节：搜索框 y117..248 逐像素一致）；
/// 2026-11-22 按 dsh-go 补了顶部工具条与筛选胶囊（drawer_toolbar /
/// drawer_filter_bar），条目行尾状态点见 sessions_drawer_item。
///
/// 2026-11-28：置顶分组 / 未读圆点 / 多选批量归档拆进 drawer_org.dart
/// （宪法 §7 单文件 500 行上限），本文件只留抽屉骨架与多选动作。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'drawer_filter_bar.dart';
import 'drawer_org.dart';
import 'drawer_org_widgets.dart';
import 'drawer_toolbar.dart';
import 'session_actions.dart';
import 'session_groups.dart';
import 'session_search.dart';
import 'session_search_section.dart';
import 'sessions_drawer_footer.dart';
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

  /// 状态筛选（全部 / 运行中 / 待确认 / 未读）。「未读」是本地记账：
  /// 非当前会话的回合正常结束/失败时由 ChatState 标未读，打开即清。
  DrawerFilter _filter = DrawerFilter.all;

  /// 工作区范围：null = 全部对话，否则只显示该工作区的会话。
  String? _scope;

  /// 多选：进入后行首出勾选框，底部操作条换成批量归档。
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _archiving = false;

  /// 会话**内容**搜索（内核 `session/search`，走 `dshrb-v1` 通用调用面）。
  ///
  /// 编排逻辑全在 session_search.dart：这里只负责喂输入、画结果。桥不提供这能力时
  /// [SessionSearchController.supported] 为 false，列表仍走原来的标题本地过滤——
  /// 用户感觉不到能力缺失，只是搜不到正文（与接这条之前逐字相同）。
  SessionSearchController? _content;

  @override
  void initState() {
    super.initState();
    _content = SessionSearchController(gateway: widget.state.gateway)
      ..addListener(_onContentSearch);
    // 置顶集合是内核全局状态：抽屉一出来就拉一次 workspace 清单对齐
    // （失败静默，不影响本地列表；成功后 notifyUi 会触发重建）。
    unawaited(widget.state.refreshPinnedSessions());
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
              runningCount: _countWhere(groups, (s) => s.running),
              pendingCount: _countWhere(
                groups,
                (s) => _pendingIds.contains(s.id),
              ),
              unreadCount: _countWhere(
                groups,
                (s) => state.unreadSessionIds.contains(s.id),
              ),
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
                  TextButton(
                    onPressed: _toggleSelecting,
                    child: Text(
                      _selecting ? '完成' : '多选',
                      style: DsTypography.small.copyWith(
                        color: _selecting ? c.brand : c.labelSecondary,
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
              child: groups.isEmpty && !state.showArchived && !showContent
                  ? Center(
                      child: Text(
                        '暂无会话',
                        style: DsTypography.small.copyWith(
                          color: c.drawerGroupLabel,
                        ),
                      ),
                    )
                  : DrawerOrgBody(
                      state: state,
                      colors: c,
                      groups: groups,
                      query: q,
                      filter: _filter,
                      scope: _scope,
                      olderExpanded: _olderExpanded,
                      showArchived: state.showArchived,
                      archived: state.archivedSessions,
                      leading: showContent
                          ? buildContentSearchSection(
                              content: content,
                              colors: c,
                              state: state,
                              onOpen: widget.onClose,
                            )
                          : const <Widget>[],
                      selecting: _selecting,
                      selected: _selected,
                      onToggleOlder: () =>
                          setState(() => _olderExpanded = !_olderExpanded),
                      onOpen: (s) {
                        widget.onClose();
                        state.openSession(s);
                      },
                      onLongPress: (s) => openSessionMenu(context, state, s, c),
                      onToggleSelected: _toggleSelected,
                    ),
            ),
            _selecting
                ? DrawerSelectionBar(
                    colors: c,
                    count: _selected.length,
                    busy: _archiving,
                    onCancel: _toggleSelecting,
                    onArchive: _archiveSelected,
                  )
                : SessionsDrawerFooter(
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

  int _countWhere(List<SessionGroup> groups, bool Function(DshSession) test) =>
      groups.expand((g) => g.rows).where((r) => test(r.session)).length;

  /// 待回答 / 待审批的会话 id（与行尾角标同源：全连接挂起表）。
  Set<String> get _pendingIds => {
    ...widget.state.hitlState.pendingQuestionSessionIds,
    ...widget.state.hitlState.pendingApprovalSessionIds,
  };

  /// 进/出多选态：退出时清空已选（需求：退出多选清理选择）。
  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      final next = toggledSelection(_selected, id);
      _selected
        ..clear()
        ..addAll(next);
    });
  }

  /// 批量归档：逐条调既有单条归档（桥没有批量接口），部分失败要报数。
  Future<void> _archiveSelected() async {
    if (_selected.isEmpty || _archiving) return;
    final ids = List<String>.of(_selected);
    setState(() => _archiving = true);
    BatchArchiveResult? result;
    Object? failure;
    try {
      result = await widget.state.archiveSessions(ids);
    } on Exception catch (e) {
      failure = e;
    } finally {
      if (mounted) {
        setState(() {
          _archiving = false;
          _selecting = false;
          _selected.clear();
        });
      }
    }
    if (!mounted) return;
    final String text;
    if (failure != null) {
      final reason = failure is RequestException ? failure.message : '$failure';
      text = '归档失败：$reason';
    } else if (result!.failed == 0) {
      text = '已归档 ${result.archived} 项';
    } else {
      text = '已归档 ${result.archived} 项，${result.failed} 项失败';
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
}
