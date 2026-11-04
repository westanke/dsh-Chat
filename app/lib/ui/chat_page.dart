/// 主聊天页：顶栏 / 消息列表 / 输入条 / 侧栏抽屉。
/// 布局对齐官方 App（docs/design-tokens.md 布局节：内容 x30dp 起、顶栏 44dp）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'brand_mark.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'md_view.dart';
import 'message_actions.dart';
import 'model_sheet.dart';
import 'process_group.dart';
import 'projection_sheets.dart';
import 'scroll_follow.dart';
import 'sessions_drawer.dart';
import 'stats_sheet.dart';

part 'chat_message_items.dart';
part 'chat_message_list.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.state,
    required this.colors,
    required this.onOpenSettings,
  });

  final ChatState state;
  final DsColors colors;
  final VoidCallback onOpenSettings;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _drawerCtrl;
  // 抽屉打开时，官方是把聊天页整体推出屏外（推挤式），不是 Scaffold.drawer
  // 的覆盖式。曲线/时长登记在 docs/design-tokens.md §4.2 与 DsMotion。
  late final Animation<double> _drawerShift;

  ChatState get st => widget.state;
  DsColors get c => widget.colors;

  @override
  void initState() {
    super.initState();
    st.addListener(_onChange);
    st.loadSessions();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: DsMotion.drawerShift,
      value: 0,
    );
    _drawerShift = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    st.removeListener(_onChange);
    _drawerCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _openDrawer() => _drawerCtrl.forward();

  void _closeDrawer() => _drawerCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    // 深色保留淡遮罩（drawerScrim 深色 0x50000000）；浅色官方无灰幕（全透明），
    // 页面被推走本身就是「打开中」的视觉反馈。
    final scrim = AnimatedBuilder(
      animation: _drawerShift,
      builder: (context, _) => _drawerShift.value == 0
          ? const SizedBox.shrink()
          : Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDrawer,
                child: ColoredBox(
                  color: Color.lerp(
                    c.none,
                    c.drawerScrim,
                    _drawerShift.value,
                  )!,
                ),
              ),
            ),
    );
    final page = AnimatedBuilder(
      animation: _drawerShift,
      builder: (context, child) => Transform.translate(
        offset: Offset(DsSpacing.drawerPageShift * _drawerShift.value, 0),
        child: child,
      ),
      child: _buildChatScaffold(context),
    );
    final drawer = ClipRect(
      child: AnimatedBuilder(
        animation: _drawerShift,
        builder: (context, child) => Align(
          alignment: Alignment.centerLeft,
          widthFactor: _drawerShift.value,
          child: child,
        ),
        child: SizedBox(
          width: DsSpacing.drawerWidth,
          child: SessionsDrawer(
            state: st,
            colors: c,
            onOpenSettings: widget.onOpenSettings,
            onClose: _closeDrawer,
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: page),
        // 抽屉关闭时给左缘留一条手势热区，可像官方一样从边缘拖出/点按呼出。
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _drawerShift.value == 0 ? DsSpacing.drawerEdgeDragWidth : 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openDrawer,
            child: const SizedBox.shrink(),
          ),
        ),
        scrim,
        drawer,
      ],
    );
  }

  Widget _buildChatScaffold(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.bgBase,
      appBar: _TopBar(
        colors: c,
        title: st.sessionTitle,
        onMenu: _openDrawer,
        onNewChat: () => st.newChat(),
        connected: st.connectionState == GatewayState.ready,
        state: st,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: st.isEmpty
                  ? _Greeting(colors: c)
                  : _MessageList(state: st, colors: c),
            ),
            Composer(
              colors: c,
              enabled: st.connectionState == GatewayState.ready,
              onSend: st.send,
              onCancel: st.cancelTurn,
              streaming: st.streaming,
              sessionId: st.sessionId,
              gateway: st.gateway,
              currentPermission: st.currentPermission,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 顶栏 ----------

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.colors,
    required this.title,
    required this.onMenu,
    required this.onNewChat,
    required this.connected,
    required this.state,
  });

  final DsColors colors;
  final String title;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final bool connected;
  final ChatState state;

  @override
  Size get preferredSize => const Size.fromHeight(DsSpacing.topBarHeight);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: DsSpacing.topBarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.menu),
              color: colors.labelPrimary,
              onPressed: onMenu,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.pageTitle.copyWith(
                  color: colors.labelPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 18),
            // 官方「新建对话」加号：此前是纯展示 Icon，onNewChat 参数没接上（死交互）。
            Tooltip(
              message: '新建对话',
              child: InkResponse(
                onTap: onNewChat,
                radius: 20,
                child: Icon(
                  Icons.add_circle_outline,
                  size: 24,
                  color: colors.labelPrimary,
                ),
              ),
            ),
            // 溢出菜单收纳三个「本地投影」面板与会话统计
            // （对照 companion ChatHeader 的 ⋯ 菜单：轨迹 / 团队 / 统计 /
            // 后台任务 …；TODO 面板在 companion 是消息区内嵌，这里收进同一菜单）。
            _OverflowMenu(colors: colors, state: state),
            const SizedBox(width: DsSpacing.screenPad),
          ],
        ),
      ),
    );
  }
}

// ---------- 顶栏溢出菜单（本地投影面板入口） ----------

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.colors, required this.state});

  final DsColors colors;
  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: Icon(Icons.more_vert, size: 22, color: c.labelPrimary),
      color: c.settingsSurface,
      onSelected: (value) async {
        switch (value) {
          case 'stats':
            showChatStatsSheet(context, state, c);
          case 'trajectory':
            showTrajectorySheet(context, state, c);
          case 'team':
            showTeamSheet(context, state, c);
          case 'todo':
            showTodoSheet(context, state, c);
          case 'model':
            final sid = state.sessionId;
            if (sid == null || sid.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先打开一个会话再调整模型')),
              );
              return;
            }
            final changed = await showModelSheet(
              context,
              colors: c,
              gateway: state.gateway,
              sessionId: sid,
            );
            if (changed) await state.reloadHistory();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        _menuItem('stats', Icons.bar_chart, '会话统计'),
        _menuItem('trajectory', Icons.timeline, '运行轨迹'),
        _menuItem('team', Icons.groups_outlined, '智能团队'),
        _menuItem('todo', Icons.checklist_outlined, '待办任务'),
        _menuItem('model', Icons.tune, '调整模型'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.labelSecondary),
            const SizedBox(width: DsSpacing.chipIconGap),
            Text(label,
                style: DsTypography.small
                    .copyWith(color: colors.labelPrimary)),
          ],
        ),
      );
}

// ---------- 空态问候 ----------

class _Greeting extends StatelessWidget {
  const _Greeting({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsBrandMark(
            color: colors.brandMark,
            bellyColor: colors.bgBase,
            width: DsSpacing.brandMarkWidth,
            height: DsSpacing.brandMarkHeight,
          ),
          const SizedBox(height: DsSpacing.brandMarkGap),
          Text(
            '嗨！今天想聊些什么？',
            style: DsTypography.greeting.copyWith(color: colors.labelPrimary),
          ),
        ],
      ),
    );
  }
}

// 消息列表（含滚动冻结 / 贴底跟随 / 跳转最新 FAB）已拆到
// chat_message_list.dart（本库 part）；消息项拆到 chat_message_items.dart。
