/// 侧边会话抽屉：顶部搜索框 + 日期分组 + 纯文字条目 + 底部账号栏。
/// 布局对齐官方 App（docs/design-tokens.md 4.2 节：搜索框 y117..248 逐像素一致）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'session_actions.dart';
import 'session_groups.dart';
import 'session_search.dart';
import 'session_search_section.dart';
import 'sessions_drawer_item.dart';

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({
    super.key,
    required this.state,
    required this.colors,
    required this.onOpenSettings,
    required this.onClose,
    this.width = DsSpacing.drawerWidth,
  });

  final ChatState state;
  final DsColors colors;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉不走 Navigator 路由，条目点选后用这个回调收起抽屉
  /// （原 Scaffold.drawer 方案里是 Navigator.pop，会在 Stack 实现下误弹聊天页）。
  final VoidCallback onClose;

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
                          hintText: '搜索对话内容...',
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
            Expanded(
              child: groups.isEmpty
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
    final rows = searching
        ? g.rows
              .where((r) => r.session.displayTitle.toLowerCase().contains(q))
              .toList()
        : g.rows;
    if (searching && rows.isEmpty) return const [];
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

/// 单条会话：官方是纯文字行（选中态蓝字），无 card、无分割线。
/// 行尾可带状态小字（badge）——「待回答/待审批」，对齐电脑端会话列表
/// status.compact.answer / status.compact.approval 的 trailingLabel。
/// 底部账号栏（真机反馈第三轮 3 + 第五轮）：设置钮+「设置」文字 + 设备名 +
/// 连接状态点 + host:port 地址。整行可点开设置。
/// 点色语义（真机反馈第五轮）：绿点 = 桥连接正常（GatewayState.ready），
/// 红点 = 未连接（connecting/closed/authFailed 等一切非 ready 态）。
class SessionsDrawerFooter extends StatelessWidget {
  const SessionsDrawerFooter({
    super.key,
    required this.colors,
    required this.label,
    required this.connectionLabel,
    required this.connected,
    required this.onOpenSettings,
    required this.onClose,
  });

  final DsColors colors;
  final String label;

  /// 当前连接地址（host:port，来自 ChatState.connectionLabel）。
  final String connectionLabel;

  /// 桥是否连接正常（GatewayState.ready）；false 显示红点。
  final bool connected;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉关闭回调（见 SessionsDrawer.onClose 注释）。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.drawerFooterPadH,
        vertical: DsSpacing.drawerItemPadV,
      ),
      // 整行可点（真机反馈第五轮：点红色区域任何位置都打开设置）；
      // 图标 + 「设置」文字 + 设备名/连接地址同属一个点按目标。
      child: InkWell(
        onTap: () {
          onClose();
          onOpenSettings();
        },
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            // 设置按钮（替代原头像/三点菜单，真机反馈第三轮 3）。
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.drawerSearchFill,
              child: Icon(
                Icons.settings_outlined,
                size: 18,
                color: colors.labelPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '设置',
              style: DsTypography.base.copyWith(color: colors.labelPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.base.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 绿点 = 桥连接正常，红点 = 未连接（真机反馈第五轮）。
                        color: connected
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        connectionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.caption
                            .copyWith(color: colors.labelSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
