/// 主聊天页：顶栏 / 消息列表 / 输入条 / 侧栏抽屉。
/// 布局对齐官方 App（docs/design-tokens.md 布局节：内容 x30dp 起、顶栏 44dp）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../bridge/gateway.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'brand_mark.dart';
import 'chat_header_status.dart';
import 'chat_image.dart';
import 'chat_list.dart';
import 'chat_message_items.dart';
import 'chat_shell.dart';
import 'chat_state.dart';
import 'chat_top_bar.dart';
import 'composer.dart';
import 'model_sheet.dart';
import 'projection_sheets.dart';
import 'question_card.dart';
import 'session_location_sheet.dart';
import 'sessions_drawer.dart';
import 'stats_sheet.dart';
import 'window_class.dart';
import 'work_view_sheet.dart';

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
      MessageItem.imageFetcher = gatewayImageFetcher(st.gateway, sid0);
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
      MessageItem.imageFetcher = gatewayImageFetcher(st.gateway, sid);
    }
    if (mounted) setState(() {});
  }

  void _openDrawer() => _drawerCtrl.forward();

  void _closeDrawer() => _drawerCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    // 三种窗口都用同一套抽屉（真机反馈 2026-11-20：平板横屏也不要常驻侧栏——
    // 抽屉式够方便，只要别把会话页整个推出屏外）。尺寸类只决定抽屉多宽、
    // 页面让出多少：推挤距离跟抽屉宽走，宽窗右边永远留着整页会话。
    final cls = windowClassOf(context);
    final width = MediaQuery.sizeOf(context).width;
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
    // 抽屉打开时页面怎么让路：手机上整页推走（官方残条观感），宽窗上**缩窄**
    // 到右边剩余宽度——推走会让顶栏的 ⊕/⋮ 越出右缘被裁掉（真机反馈 2026-11-20）。
    final reflow = cls != DsWindowClass.compact;
    final page = AnimatedBuilder(
      animation: _drawerShift,
      builder: (context, child) {
        final inset = cls.pageInsetFor(width) * _drawerShift.value;
        return reflow
            ? Padding(padding: EdgeInsets.only(left: inset), child: child)
            : Transform.translate(offset: Offset(inset, 0), child: child);
      },
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
          width: cls.sidebarWidth,
          child: SessionsDrawer(
            state: st,
            colors: c,
            onOpenSettings: widget.onOpenSettings,
            onClose: _closeDrawer,
            width: cls.sidebarWidth,
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
        // 抽屉开着时，返回先收起抽屉（宽窗和手机上一样）。
        if (_drawerShift.value > 0) {
          _closeDrawer();
          return;
        }
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
      // 外壳自绘（dsh-go 的分槽布局）：顶栏 / 正文 / 输入条 / 渐隐带四槽。
      // Scaffold 不再放 appBar，顶部安全区由顶栏自己吃掉。
      body: ChatShell(
        colors: c,
        header: ChatTopBar(
          colors: c,
          title: st.sessionTitle,
          status: _headerStatus,
          onMenu: _openDrawer,
          onNewChat: () => st.newChat(),
          trailing: _OverflowMenu(colors: c, state: st),
        ),
        body: Column(
          children: [
            // HITL 问答/审批卡（DSH 向用户提问；无挂起项时不占空间）。
            HitlPanel(
              state: st.hitlState,
              sessionId: st.sessionId,
              colors: c,
              onAnswer: st.answerQuestion,
              onDecide: st.decideApproval,
            ),
            Expanded(
              child: st.isEmpty
                  ? _Greeting(colors: c, state: st)
                  : ChatList(
                      state: st,
                      colors: c,
                      onToggleTurn: (turn) => toggleTurn(st, turn),
                    ),
            ),
          ],
        ),
        composer: Composer(
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
      ),
    );
  }

  /// 顶栏状态：连接态 + 生成态 + 等待审批/回答（dsh-go 的顶栏状态机）。
  ChatHeaderStatus get _headerStatus => chatHeaderStatus(
        connection: st.connectionState,
        streaming: st.streaming,
        waitingApproval: st.hitl.sessionApprovals(st.sessionId).isNotEmpty,
        waitingAnswer: st.hitl.sessionQuestions(st.sessionId).isNotEmpty,
        hostLabel: st.deviceLabel,
      );
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
          case 'workview':
            showWorkViewSheet(context, state, c);
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
        // D 项：设置「显示代码工作视图」开启后才出现（官方通用设置）。
        if (appSettings.codeWorkView)
          _menuItem('workview', Icons.difference_outlined, '代码工作视图'),
        _menuItem('team', Icons.groups_outlined, '智能团队'),
        _menuItem('todo', Icons.checklist_outlined, '任务'),
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
  const _Greeting({required this.colors, required this.state});

  final DsColors colors;
  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final loc = state.pendingLocation;
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
          // 工作目录选择（2026-11-15 反馈）：新建会话默认「手机会话」，
          // 发首条消息前可在此换成授权根下的指定目录。选中后 label 显示
          // 在 chip 上；会话建好后随 sessionId 定死（本组件只在空态显示）。
          const SizedBox(height: DsSpacing.liGap),
          InkWell(
            onTap: () => showSessionLocationSheet(context, state, colors),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: colors.bgLayer1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.inputBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    loc == null ? Icons.smartphone : Icons.folder,
                    size: 15,
                    color: colors.brand,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '工作目录：${loc == null ? '手机会话（默认）' : loc.label}',
                    style: DsTypography.small.copyWith(
                      color: colors.labelPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more,
                    size: 15,
                    color: colors.labelTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 消息列表已拆到 chat_list.dart（居中锚定的两段滚动）；
// 消息项拆到 chat_message_items.dart；行渲染层拆到 chat_row_view.dart。
