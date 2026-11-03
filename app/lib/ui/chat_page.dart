/// 主聊天页：顶栏 / 消息列表 / 输入条 / 侧栏抽屉。
/// 布局对齐官方 App（docs/design-tokens.md 布局节：内容 x30dp 起、顶栏 44dp）。
library;

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
import 'sessions_drawer.dart';
import 'stats_sheet.dart';

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

// ---------- 消息列表 ----------

class _MessageList extends StatefulWidget {
  const _MessageList({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();

  // 官方行为：新消息/流式更新时若用户已在底部附近则自动跟随滚底。
  void _followBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent - _scroll.offset < 400) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // 初始打开会话：直接滚到底（官方行为，从最新消息开始看）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    widget.state.addListener(_followBottom);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_followBottom);
      widget.state.addListener(_followBottom);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_followBottom);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = widget.colors;
    final items = <Widget>[];
    for (var i = 0; i < state.messages.length; i++) {
      items.add(
        _MessageItem(
          message: state.messages[i],
          colors: colors,
          index: i,
          state: state,
        ),
      );
    }
    if (state.streaming) {
      items.add(_StreamingItem(state: state, colors: colors));
    }
    if (state.lastError != null) {
      items.add(
        Padding(
          padding: const EdgeInsets.all(DsSpacing.screenPad),
          child: Text(
            state.lastError!,
            style: DsTypography.small.copyWith(color: colors.labelTertiary),
          ),
        ),
      );
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        0,
        DsSpacing.contentPadRight,
        DsSpacing.hMarginBottom,
      ),
      children: items,
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({
    required this.message,
    required this.colors,
    required this.index,
    required this.state,
  });

  final ChatMessage message;
  final DsColors colors;
  final int index;
  final ChatState state;

  /// 双击复制整条消息（对照 companion ChatMessageItems.kt 的
  /// combinedClickable onDoubleClick + ClipboardManager）。
  Future<void> _copyAll(BuildContext context) async {
    if (message.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制整条消息')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 工具调用过程组：折叠成一行，点开展开明细。
    if (message.isProcess) {
      return DsProcessGroup(group: message, colors: colors);
    }
    // 一轮 turn 失败（模型限流 / 额度 / 网关报错）：官方是红色错误提示，
    // 这里同样用 danger 色块呈现，而不是静默什么都不显示。
    if (message.isError) {
      return Container(
        margin: const EdgeInsets.only(top: DsSpacing.blockGap),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        ),
        child: Text(
          message.text,
          style: DsTypography.small.copyWith(color: colors.danger),
        ),
      );
    }
    // 双击复制：包在气泡/正文外，不挂 onLongPress（否则选词手柄出不来）。
    final bubble = message.role == 'user'
        ? Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(
                top: DsSpacing.blockGap,
                left: DsSpacing.hMargin,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: colors.userBubble,
                borderRadius: BorderRadius.circular(DsSpacing.bubbleRadius),
              ),
              child: Text(
                message.text,
                style: DsTypography.base.copyWith(
                  color: colors.userBubbleText,
                  height: 24 / 16,
                ),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: DsSpacing.blockGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.reasoning.isNotEmpty)
                  _ThinkBlock(text: message.reasoning, colors: colors),
                DsMarkdownView(text: message.text, colors: colors),
                DsMessageActions(
                  colors: colors,
                  text: message.text,
                  onRegenerate: () => state.regenerateAt(index),
                ),
              ],
            ),
          );
    return GestureDetector(
      onDoubleTap: () => _copyAll(context),
      child: bubble,
    );
  }
}

class _StreamingItem extends StatelessWidget {
  const _StreamingItem({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.streamReasoning.isNotEmpty)
            _ThinkBlock(text: state.streamReasoning, colors: colors),
          DsMarkdownView(
            text: state.streamText,
            colors: colors,
            streaming: true,
          ),
        ],
      ),
    );
  }
}

/// 思考流：官方「已深度思考」可折叠小字块。
class _ThinkBlock extends StatefulWidget {
  const _ThinkBlock({required this.text, required this.colors});

  final String text;
  final DsColors colors;

  @override
  State<_ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<_ThinkBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.thinkHMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 14,
                    color: c.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? '收起深度思考' : '已深度思考',
                    style: DsTypography.smallStrong.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: c.labelSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: DsSpacing.thinkHMargin),
              child: DsMarkdownView(text: widget.text, colors: c, small: true),
            ),
        ],
      ),
    );
  }
}

// ---------- 侧栏会话列表 ----------
