/// 主聊天页：顶栏 / 消息列表 / 输入条 / 侧栏抽屉。
/// 布局对齐官方 App（docs/design-tokens.md 布局节：内容 x30dp 起、顶栏 44dp）。
library;

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../bridge/goal.dart';
import '../bridge/jobs.dart';
import '../bridge/projections.dart';
import '../design/tokens.dart';
import 'chat_header_status.dart';
import 'chat_image.dart';
import 'chat_list.dart';
import 'chat_message_items.dart';
import 'chat_overflow_menu.dart';
import 'chat_side_rails.dart';
import 'chat_shell.dart';
import 'chat_state.dart';
import 'goal_dock.dart';
import 'jobs_sheet.dart';
import 'agent_lineage.dart';
import 'queue_dock.dart';
import 'chat_top_bar.dart';
import 'projection_sheets.dart';
import 'composer.dart';
import 'chat_page_composer.dart';
import 'chat_setup.dart';
import 'question_card.dart';
import 'session_tabs_sheet.dart';
import 'sessions_drawer.dart';
import 'activity_strip.dart';
import 'empty_greeting.dart';
import 'todo_dock.dart';
import 'window_class.dart';

/// 屏内右滑是否足以呼出会话抽屉：位移够远，或已越过最小行程且甩得够快。
/// 纯函数便于单测（阈值在 design_tokens_layout.dart）。
bool drawerSwipeOpens(double dx, double velocity) =>
    dx >= DsSpacing.drawerSwipeOpenDistance ||
    (dx > DsSpacing.drawerSwipeMinTravel &&
        velocity >= DsSpacing.drawerSwipeOpenVelocity);

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
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _drawerCtrl;
  // 抽屉打开时，官方是把聊天页整体推出屏外（推挤式），不是 Scaffold.drawer
  // 的覆盖式。曲线/时长登记在 docs/design-tokens.md §4.2 与 DsMotion。
  late final Animation<double> _drawerShift;

  /// 右侧「会话面板」侧栏（左滑推出，会话页同时向左让位）。
  late final AnimationController _panelCtrl;
  late final Animation<double> _panelShift;

  ChatState get st => widget.state;
  DsColors get c => widget.colors;

  /// 后台任务控制器：跟当前会话绑定，负责基线拉取与推送归并。
  late final JobsController _jobs;

  @override
  void initState() {
    super.initState();
    st.addListener(_onChange);
    _jobs = JobsController(gateway: st.gateway, sessionId: st.sessionId)
      ..addListener(_onJobsChange);
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
    _panelCtrl = AnimationController(
      vsync: this,
      duration: DsMotion.drawerShift,
      value: 0,
    );
    _panelShift = CurvedAnimation(
      parent: _panelCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    st.removeListener(_onChange);
    _jobs
      ..removeListener(_onJobsChange)
      ..dispose();
    _drawerCtrl.dispose();
    _panelCtrl.dispose();
    super.dispose();
  }

  /// 已经为哪个新会话补拉过一次清单（防止服务端清单不含当前会话时无限重拉）。
  String? _listRefreshFor;

  void _onJobsChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openJobs() async {
    await _jobs.refresh();
    if (!mounted) return;
    await showJobsSheet(context, _jobs, c);
  }

  void _onChange() {
    // 后台任务按会话隔离：换会话就换基线，旧会话的推送不再归并。
    if (_jobs.sessionId != st.sessionId) _jobs.bind(st.sessionId);
    // 图片下载器要跟当前会话走：attachments 接口必填 sessionId query
    // （内核按会话事件校验引用），换会话就换下载器。
    final sid = st.sessionId;
    if (sid != null && sid.isNotEmpty) {
      MessageItem.imageFetcher = gatewayImageFetcher(st.gateway, sid);
      // 新建会话（问题 2）：send() 预建/首帧建好会话后 sessions 里还没有它，
      // 这里补拉一次；每个 sid 只补一次，服务端清单缺当前会话也不会死循环。
      if (_listRefreshFor != sid && !st.sessions.any((s) => s.id == sid)) {
        _listRefreshFor = sid;
        unawaited(st.loadSessions());
      }
    }
    if (mounted) setState(() {});
  }

  void _openDrawer() {
    // 每次打开都顺手重拉会话清单：别的地方（另一台设备/网页）新建的会话
    // 也能出现在抽屉里，同时兜住「新建后列表不刷新」（问题 2）。
    unawaited(st.loadSessions());
    _drawerCtrl.forward();
  }

  void _closeDrawer() => _drawerCtrl.reverse();

  void _openPanels() {
    if (_panelCtrl.value == 1) return;
    _panelCtrl.forward();
  }

  void _closePanels() => _panelCtrl.reverse();

  /// 屏内右滑的累计位移（逻辑像素）。
  double _swipeDx = 0;

  /// 抽屉本体上的左滑累计位移：滑出方向相反即可收起。
  double _drawerSwipeDx = 0;

  /// 右侧面板上的原始指针位移：PageView 会吃掉横向手势，这里用 Listener
  /// 兜一层，向右滑回即可收起。
  double _panelPointerDx = 0;
  double? _panelPointerStartX;

  void _onSwipeStart(DragStartDetails _) => _swipeDx = 0;

  void _onSwipeUpdate(DragUpdateDetails d) => _swipeDx += d.delta.dx;

  void _onSwipeEnd(DragEndDetails d) {
    final intent = swipeIntent(
      dx: _swipeDx,
      velocity: d.primaryVelocity ?? 0,
      drawerOpen: _drawerShift.value > 0,
      panelOpen: _panelShift.value > 0,
    );
    switch (intent) {
      case SwipeIntent.openDrawer:
        _openDrawer();
      case SwipeIntent.closeDrawer:
        _closeDrawer();
      case SwipeIntent.closePanel:
        _closePanels();
      case SwipeIntent.openPanel:
        _openPanels();
      case SwipeIntent.none:
        break;
    }
  }

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
      animation: Listenable.merge([_drawerShift, _panelShift]),
      builder: (context, _) {
        final v = _drawerShift.value > _panelShift.value
            ? _drawerShift.value
            : _panelShift.value;
        if (v == 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _drawerShift.value > 0 ? _closeDrawer : _closePanels,
            child: ColoredBox(color: Color.lerp(c.none, c.drawerScrim, v)!),
          ),
        );
      },
    );
    // 抽屉打开时页面怎么让路：手机上整页推走（官方残条观感），宽窗上**缩窄**
    // 到右边剩余宽度——推走会让顶栏的 ⊕/⋮ 越出右缘被裁掉（真机反馈 2026-11-20）。
    final reflow = cls != DsWindowClass.compact;
    final page = GestureDetector(
      // 屏内从左往右滑一次即可呼出会话列表（问题 3）。整页接水平拖动：
      // 表格横向滚动、消息列表纵向滚动这些子级手势会在竞技场里先胜出，
      // 所以正常滚动不会被误判成开抽屉。
      onHorizontalDragStart: _onSwipeStart,
      onHorizontalDragUpdate: _onSwipeUpdate,
      onHorizontalDragEnd: _onSwipeEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_drawerShift, _panelShift]),
        builder: (context, child) {
          final step = cls.pageInsetFor(width);
          final inset = step * _drawerShift.value - step * _panelShift.value;
          return reflow
              ? Padding(
                  padding: EdgeInsets.only(
                    left: inset > 0 ? inset : 0,
                    right: inset < 0 ? -inset : 0,
                  ),
                  child: child,
                )
              : Transform.translate(offset: Offset(inset, 0), child: child);
        },
        child: _buildChatScaffold(context),
      ),
    );
    final drawer = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _drawerSwipeDx = 0,
      onHorizontalDragUpdate: (d) => _drawerSwipeDx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        // 抽屉从左滑出，向左滑回即收起；纵向列表滚动不受影响。
        if (_drawerSwipeDx < -60 || (d.primaryVelocity ?? 0) < -300) {
          _closeDrawer();
        }
      },
      child: sideRail(
        shift: _drawerShift,
        alignment: Alignment.centerLeft,
        width: cls.sidebarWidth,
        child: SessionsDrawer(
          state: st,
          colors: c,
          onOpenSettings: widget.onOpenSettings,
          onClose: _closeDrawer,
          width: cls.sidebarWidth,
        ),
      ),
    );
    // 右侧「会话面板」：把原来散在「更多」菜单里的几个面板收成一个可左右滑
    // 的 TAB 容器（用户 2026-11-22 要求）。左滑推出，会话页同时向左让位。
    final panels = sideRail(
      shift: _panelShift,
      alignment: Alignment.centerRight,
      width: cls.sidebarWidth,
      child: SessionTabsSheet(
        state: st,
        colors: c,
        tabs: sessionTabsOf(
          onShare: () async => _runAppCommand('export'),
        ),
        embedded: true,
        onClose: _closePanels,
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
        // 右侧面板开着时同理。
        if (_panelShift.value > 0) {
          _closePanels();
          return;
        }
        // 斜杠面板开着时，返回只收面板（dsh-go PopScope 同口径）：不退页面。
        final composer = _composerKey.currentState;
        if (composer != null && composer.paletteOpen) {
          composer.dismissPalette();
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
          // 铺一层底色：侧栏展开时页外露出的区域不能是黑的。
          Positioned.fill(child: ColoredBox(color: c.bgBase)),
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
          // 右侧面板必须钉在右缘：Stack 的非定位子级默认从左上开始排。
          // PageView 会赢得横向手势竞技场，用原始指针再兜一层「右滑收起」。
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Listener(
              onPointerDown: (e) {
                _panelPointerStartX = e.position.dx;
                _panelPointerDx = 0;
              },
              onPointerMove: (e) {
                final start = _panelPointerStartX;
                if (start != null) _panelPointerDx = e.position.dx - start;
              },
              onPointerUp: (_) {
                if (_panelPointerDx > 100) _closePanels();
                _panelPointerStartX = null;
                _panelPointerDx = 0;
              },
              onPointerCancel: (_) {
                _panelPointerStartX = null;
                _panelPointerDx = 0;
              },
              child: panels,
            ),
          ),
        ],
      ),
    );
  }

  /// 退出 APP 双击确认的时间窗（主页 PopScope 回调读写）。
  int? _lastExitAt;

  /// 输入框（斜杠面板）状态：返回键要先关面板再谈退出（dsh-go 同口径）。
  final GlobalKey<ComposerState> _composerKey = GlobalKey<ComposerState>();

  Widget _buildChatScaffold(BuildContext context) {
    // 当前活动（dsh-go runActivityOf 的同口径本地版）：不在跑就是 null。
    final activity = liveActivityOf(
      messages: st.messages,
      streaming: st.streaming,
    );
    // 任务条摘要（dsh-go TodoDock 同口径）：没有清单时为 null，不占位。
    final todoDock = TodoDockSummary.of(
      todoItems(st.projections),
      running: st.streaming,
    );
    // 目标条（dsh-go GoalBar 移植）：进行中/暂停/受阻的目标常驻输入条上方。
    final goal = goalOf(st.projections);
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
          state: st,
          onMenu: _openDrawer,
          onNewChat: () => st.newChat(),
          // 成员圆钮（dsh-go chat_header 同位置）：复用「更多」菜单里的团队面板。
          onOpenTeam: st.sessionId == null
              ? null
              : () => showTeamSheet(context, st, c),
          onPickModel: _pickModel,
          jobsRunning: _jobs.runningCount,
          onOpenJobs: () => unawaited(_openJobs()),
          subagentCount:
              agentTeamProjectionOf(st.projections)?.subagents.length ?? 0,
          onOpenSubagents: st.sessionId == null
              ? null
              : () => showAgentLineage(context, st, c),
          trailing: ChatOverflowMenu(colors: c, state: st),
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
              child: st.loadingHistory && st.messages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 12),
                          Text('正在加载会话…'),
                        ],
                      ),
                    )
                  : st.isEmpty
                      ? EmptyGreeting(
                          colors: c,
                          state: st,
                          onPickSuggestion: (text) =>
                              _composerKey.currentState?.fillDraft(text),
                        )
                      : ChatList(
                          state: st,
                          colors: c,
                          onToggleTurn: (turn) => toggleTurn(st, turn),
                        ),
            ),
          ],
        ),
        composer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 排队管理（mobile-queue-v1）：有排队项才占位。
            if (st.queue.isNotEmpty)
              QueueDockBar(
                entries: st.queue,
                colors: c,
                onManage: () => runQueueActions(context, st, c),
              ),
            // 上下文用量条 2026-11-22 移除：dsh-go 输入框上方没有这条横条，
            // 用量只在输入条右侧的小环里（composer_status.dart 的
            // ComposerUsageRing），点环看明细走同一个 showContextUsageSheet。
            // 目标条（dsh-go GoalBar 移植）：有未完成的目标时常驻。
            if (goal != null && goal.goal.phase != GoalPhase.complete)
              GoalDockBar(
                goal: goal,
                colors: c,
                onTap: () => runGoalActions(context, st, c),
              ),
            // 当前活动条（dsh-go ActivityStrip 移植）：这一轮在跑时显示
            // 「思考中 / 正在调用工具 + 细节 + 实时秒表」，不跑就不占位。
            if (activity != null)
              ActivityStrip(activity: activity, colors: c),
            // 输入条上方的任务条（dsh-go TodoDock 移植）：没有清单时不占位。
            if (todoDock != null)
              TodoDockBar(
                summary: todoDock,
                todos: todoItems(st.projections),
                colors: c,
                topGap: activity != null
                    ? DsSpacing.activityStripGap
                    : DsSpacing.blockGap,
              ),
            _buildComposer(
              context: context,
              activity: activity,
              todoDock: todoDock,
            ),
          ],
        ),
      ),
    );
  }

  /// 输入条（从 chat_page.dart 拆出，见 chat_page_composer.dart）：
  /// 参数多、注释多，单独成文件守 §7 行数。
  Widget _buildComposer({
    required BuildContext context,
    Object? activity,
    Object? todoDock,
  }) =>
      buildChatComposer(
        context: context,
        state: st,
        colors: c,
        composerKey: _composerKey,
        activity: activity,
        todoDock: todoDock,
        onAppCommand: _runAppCommand,
        onPickModel: _pickModel,
      );

  /// 顶栏状态：连接态 + 生成态 + 等待审批/回答（dsh-go 的顶栏状态机）。
  ChatHeaderStatus get _headerStatus => chatHeaderStatus(
    connection: st.connectionState,
    streaming: st.streaming,
    waitingApproval: st.hitl.sessionApprovals(st.sessionId).isNotEmpty,
    waitingAnswer: st.hitl.sessionQuestions(st.sessionId).isNotEmpty,
    hostLabel: st.deviceLabel,
  );

  /// 斜杠面板里的客户端功能命令（bridge/slash_commands.dart 的 appSlashCommands）。
  ///
  /// 这些名字桥不认识（服务端只有内核命令），所以必须在本地落到已有界面上：
  /// new→清空会话、model→模型面板、export→复制 Markdown、features→设置页。
  /// 输入条模型 chip → 模型选择（成功后刷新历史，与「更多 → 模型」同口径）。
  Future<void> _pickModel() => _runAppCommand('model');

  Future<void> _runAppCommand(String name) async {
    switch (name) {
      case 'new':
        await st.newChat();
      case 'model':
        // 有会话 → 切当前会话的模型；没有会话 → 选一个「接下来要用的模型」
        // （存草稿，建会话后补应用，见 chat_setup.dart）。
        final selection = await pickSessionModel(context, st, c);
        if (selection) await st.reloadHistory();
      case 'export':
        final body = sessionMarkdown(st);
        if (body.trim().isEmpty) return;
        await Clipboard.setData(ClipboardData(text: body));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('已复制 Markdown')));
      case 'features':
        widget.onOpenSettings();
    }
  }
}

// ---------- 空态问候 ----------

// 消息列表已拆到 chat_list.dart（居中锚定的两段滚动）；
// 消息项拆到 chat_message_items.dart；行渲染层拆到 chat_row_view.dart。
