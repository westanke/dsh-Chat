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
import 'process_group.dart';
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

class _ChatPageState extends State<ChatPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  ChatState get st => widget.state;
  DsColors get c => widget.colors;

  @override
  void initState() {
    super.initState();
    st.addListener(_onChange);
    st.loadSessions();
  }

  @override
  void dispose() {
    st.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.bgBase,
      drawerScrimColor: c.drawerScrim,
      drawer: SessionsDrawer(
        state: st,
        colors: c,
        onOpenSettings: widget.onOpenSettings,
      ),
      appBar: _TopBar(
        colors: c,
        title: st.sessionTitle,
        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
        onNewChat: () => st.newChat(),
        onStats: () => showChatStatsSheet(context, st, c),
        connected: st.connectionState == GatewayState.ready,
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
    required this.onStats,
    required this.connected,
  });

  final DsColors colors;
  final String title;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;
  final VoidCallback onStats;
  final bool connected;

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
            // 官方静音图标是纯展示；这里接成「会话统计」入口
            // （对照 companion ChatHeader ⋯ 菜单里的「会话统计」Sheet）。
            Tooltip(
              message: '会话统计',
              child: InkResponse(
                onTap: onStats,
                radius: 20,
                child: Icon(
                  Icons.volume_off_outlined,
                  size: 22,
                  color: connected
                      ? colors.labelPrimary
                      : colors.labelTertiary,
                ),
              ),
            ),
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
            const SizedBox(width: DsSpacing.screenPad),
          ],
        ),
      ),
    );
  }
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
