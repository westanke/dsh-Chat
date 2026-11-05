/// 主聊天页：顶栏 / 消息列表 / 输入条 / 侧栏抽屉。
/// 布局对齐官方 App（docs/design-tokens.md 布局节：内容 x30dp 起、顶栏 44dp）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/platform.dart';
import '../design/tokens.dart';
import 'brand_mark.dart';
import 'chat_image.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'md_view.dart';
import 'md_viewer.dart';
import 'message_actions.dart';
import 'model_sheet.dart';
import 'process_group.dart';
import 'projection_sheets.dart';
import 'question_card.dart';
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
    // 历史图片下载器（真机反馈 2026-11-04 第 1 项）：attachment / image-handoff
    // 都走 REST，token 从 gateway 拿；sessionId 在 _onChange 里随会话刷新。
    final sid0 = st.sessionId;
    if (sid0 != null && sid0.isNotEmpty) {
      _MessageItem._imageFetcher = gatewayImageFetcher(st.gateway, sid0);
    }
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
    // 图片下载器要跟当前会话走：attachments 接口必填 sessionId query
    // （内核按会话事件校验引用），换会话就换下载器。
    final sid = st.sessionId;
    if (sid != null && sid.isNotEmpty) {
      _MessageItem._imageFetcher = gatewayImageFetcher(st.gateway, sid);
    }
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
    return PopScope(
      // 退出 APP 二次确认（真机反馈第五轮勘误：上一版错装在设置页——
      // 用户原意是「在主页按返回退出 APP 要两次且有提示」防误触）。
      // 首次返回提示「再按一次退出 DSH」，2 秒内再按放行（系统默认退到桌面）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastExitAt != null && now - _lastExitAt! < 2000) {
          // 第二次按返回：不拦截，让系统路由正常出栈/退出。
          SystemNavigator.pop();
          return;
        }
        _lastExitAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再按一次退出 DSH'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Stack(
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
      ),
    );
  }

  /// 退出 APP 双击确认的时间窗（主页 PopScope 回调读写）。
  int? _lastExitAt;

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
            // HITL 问答/审批卡（DSH 向用户提问；无挂起项时不占空间）。
            HitlPanel(
              state: st.hitlState,
              colors: c,
              onAnswer: st.answerQuestion,
              onDecide: st.decideApproval,
            ),
            Expanded(
              child: st.isEmpty
                  ? _Greeting(colors: c)
                  : _MessageList(state: st, colors: c),
            ),
            Composer(
              colors: c,
              enabled: st.connectionState == GatewayState.ready,
              onSend: st.send,
              onSendWithImage: st.sendWithImage,
              onCancel: st.cancelTurn,
              onCommand: st.runCommand,
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
