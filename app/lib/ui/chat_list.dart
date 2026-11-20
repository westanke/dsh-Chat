// 会话列表：居中锚定的两段滚动。
//
// 结构移植自 dsh-go 的 chat_list.dart（app/lib/ui/chat/chat_list.dart）：
// 用 CustomScrollView 的 center + anchor 把列表拆成两段——
//
//   before 段：打开会话时就有的历史，**反向生长**（最新的那行贴着零滚动线，
//              更早的历史往上长）；
//   center 段：这次会话里新来的内容，**正向生长**（往下长）。
//
// 为什么这样切：反向段前插更早的历史时，老内容的「离零滚动线的距离」不变，
// 可见内容不跳位——不用再手写锚点校正。
// 不变量（探针实测，test/chat_list_geometry_test.dart）：
//   before 段的 delegate 下标 i → 行数组 rows[split-1-i]；
//   前插 n 条更早历史时，行数组头部多 n、split 同样多 n，
//   于是老内容的 delegate 下标不变 → 位置不变。
//
// anchor 由「输入条占了多高」推出：零滚动线落在视口底部往上
// (视口高 - 输入条高) 的位置，正文视口的底部因此和输入条上沿对齐。

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'chat_expand_state.dart';
import 'chat_row_gap.dart';
import 'window_class.dart';
import 'chat_row_view.dart';
import 'chat_rows.dart';
import 'chat_state.dart';
import 'scroll_follow.dart';
import 'work_steps.dart';

/// 轮尾行点按：整轮的过程组一起开合。
///
/// 组内任一已展开 → 全部收起；都没展开 → 全部展开。
void toggleTurn(ChatState state, TurnRange turn) {
  final keys = <String>[];
  for (var i = turn.start + 1; i < turn.end; i++) {
    final m = state.messages[i];
    if (m.isProcess) keys.add(processGroupKeyOf(m));
  }
  var anyOpen = false;
  for (final key in keys) {
    if (state.isGroupExpanded(key)) {
      anyOpen = true;
      break;
    }
  }
  for (final key in keys) {
    state.toggleProcessGroup(key, open: !anyOpen);
  }
}

/// 会话列表。
class ChatList extends StatefulWidget {
  const ChatList({
    super.key,
    required this.state,
    required this.colors,
    this.onToggleTurn,
  });

  final ChatState state;
  final DsColors colors;

  /// 轮尾行点按：整轮过程组一起开合。
  final void Function(TurnRange turn)? onToggleTurn;

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final _scroll = ScrollController();

  /// before 段的 sliver key（center 段要指向它，见 CustomScrollView.center）。
  final _beforeKey = GlobalKey();
  final _centerKey = GlobalKey();

  /// 粘性「想贴底」意图：只有用户真拖拽才撤销，滚回底部才恢复。
  /// 对照 companion ChatScrollDiag.kt:254-273：不用瞬时 isAtBottom 当跟随守卫，
  /// 否则流式每 token 重建列表会让 atBottom 翻 false 后永久自锁。
  bool _wantsBottom = kInitialWantsBottom;
  bool _atBottom = true;
  bool _scrolling = false;

  Timer? _settleTimer;
  String? _sessionId;

  /// 派生出的行序列（行模型见 chat_rows.dart）。
  List<ChatRow> _rows = const [];
  Map<String, int> _index = const {};

  /// 行级 widget 缓存：行对象、上方向距、正文列宽都没变就复用同一个 widget。
  /// 行内容来自行自身的才进缓存（ChatRow.cacheable），流式正文不进。
  final Map<String, ({ChatRow row, double gap, double columnMax, Widget widget})>
      _built = {};

  /// 上一批行的主键，用来判「哪些是新行」（新行播入场动画）。
  Set<String> _previousKeys = const {};

  /// 派生输入指纹：变了才重算。
  Object? _rowsSignature;

  /// 上一次派生的输入行数组（用来判前插）。
  List<ChatMessage> _previousMessages = const [];

  /// 视口高度（anchor 要用）。
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.state.sessionId;
    _scroll.addListener(_onScrollPosition);
    widget.state.addListener(_onStateChanged);
    // 初始打开会话：直接滚到底（官方行为，从最新消息开始看）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void didUpdateWidget(covariant ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _resetForSession();
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.state.removeListener(_onStateChanged);
    _scroll.removeListener(_onScrollPosition);
    _scroll.dispose();
    super.dispose();
  }

  void _resetForSession() {
    _sessionId = widget.state.sessionId;
    _wantsBottom = kInitialWantsBottom;
    _atBottom = true;
    _scrolling = false;
    _built.clear();
    _previousKeys = const {};
    _scrollToBottomDeferred(animated: false);
  }

  // ---- 判据入口（全部走 scroll_follow.dart 的可单测纯函数）----

  /// ScrollController 监听：程序滚动与用户滚动都会触发，用同一口径算 atBottom。
  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atBottom = computeAtBottom(
      maxScrollExtent: pos.maxScrollExtent,
      pixels: pos.pixels,
    );
    if (atBottom != _atBottom) {
      final wasAtBottom = _atBottom;
      _atBottom = atBottom;
      // 用户滚回底部 → 恢复粘性意图（唯一恢复通道）。
      if (!wasAtBottom && atBottom) _wantsBottom = true;
      if (mounted) setState(() {});
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    // 只有 DragScrollActivity 发出的通知带 dragDetails（程序滚动为 null）。
    if (isUserScrollGesture(n)) {
      _wantsBottom = false;
    }
    if (n is ScrollStartNotification ||
        n is ScrollUpdateNotification ||
        n is ScrollEndNotification) {
      if (!_scrolling) {
        _scrolling = true;
        if (mounted) setState(() {});
      }
      _restartSettleTimer();
    }
    return false;
  }

  void _restartSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = Timer(DsMotion.freezeSettle, () {
      if (!mounted) return;
      setState(() {
        _scrolling = false;
      });
      // 解冻后若仍想贴底且已偏离，补一次滚底（补偿冻结期间新增内容）。
      if (_wantsBottom && !_atBottom) {
        _scrollToBottomDeferred(animated: false);
      }
    });
  }

  /// ChatState 每次 notifyListeners（流式 delta / 提交 / 会话切换）都到这里。
  void _onStateChanged() {
    final sid = widget.state.sessionId;
    if (sid != _sessionId) _resetForSession();
    _followBottom();
  }

  void _followBottom() {
    // 历史翻页 prepend（第二轮反馈 A）：点「加载更早消息」时用户意图是
    // 向上看旧内容，不是贴底——此时 _wantsBottom 多半仍为 true（还站在
    // 底部点的按钮），prepend 后 maxScrollExtent 暴涨会触发跳底，视觉上
    // 「新消息把旧历史冲没了」。跳过一次跟随。
    if (widget.state.historyPageJustLoaded) {
      widget.state.historyPageJustLoaded = false;
      return;
    }
    final hasItems = widget.state.messages.isNotEmpty || widget.state.streaming;
    if (!shouldAutoFollow(
      wantsBottom: _wantsBottom,
      hasItems: hasItems,
      streaming: widget.state.streaming,
    )) {
      return;
    }
    _scrollToBottomDeferred(
      animated: shouldAnimateFollow(widget.state.streaming),
    );
  }

  void _scrollToBottomDeferred({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scrollToBottom(animated: animated);
    });
  }

  void _scrollToBottom({required bool animated}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = pos.maxScrollExtent;
    if (target - pos.pixels <= kAtBottomTolerance) return;
    if (animated) {
      _scroll.animateTo(
        target,
        duration: DsMotion.scrollSettle,
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  // ---- 行派生与缓存 ----

  /// 重算行序列（输入指纹没变就不重算）。
  void _deriveRows(ChatState state) {
    final input = ChatRowsInput(
      messages: state.messages,
      folded: appSettings.foldedReplies,
      streaming: state.streaming,
      hasMoreHistory: state.historyHasMore,
      historyTruncated: state.historyTruncated,
      streamingProcess: state.streamingProcess,
      maxTokensNotice: state.maxTokensNotice,
      linkError: state.lastError,
    );
    final signature = input.signature;
    if (signature == _rowsSignature) return;
    _rowsSignature = signature;

    final previousKeys = _previousKeys;
    final rows = deriveRows(input);
    _rows = rows;
    _index = {for (var i = 0; i < rows.length; i++) rows[i].key: i};
    _previousKeys = {for (final row in rows) row.key};

    // 前插更早历史：老行的 delegate 下标不变，可见内容不跳位
    // （见文件头的不变量说明），所以这里不需要额外的锚点校正。
    // 但缓存要清：行数组下标变了，缓存里的控件是按行对象记的。
    final previousMessages = _previousMessages;
    _previousMessages = state.messages;
    final prepended = didPrependHistory(previousMessages, state.messages);
    if (prepended) {
      _built.clear();
    } else {
      // 行序列变了：只清掉已经不存在的行。
      _built.removeWhere((key, _) => !_index.containsKey(key));
    }
    // 新行集合：用来播入场动画。
    _freshKeys = {
      for (final row in rows)
        if (!previousKeys.contains(row.key)) row.key,
    };
  }

  /// 本批新出现的主键（新行播入场动画）。
  Set<String> _freshKeys = const {};

  /// 取一行的控件。
  ///
  /// 缓存整行（含行框与间距），见 [_buildRow]：行内容来自行自身的
  /// 才进缓存（ChatRow.cacheable），流式正文每次重建。
  Widget _rowWidget(ChatRow row, ChatState state) {
    return chatRowView(
      row,
      state: state,
      colors: widget.colors,
      onToggleTurn: (turn) => widget.onToggleTurn?.call(turn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = widget.colors;
    _deriveRows(state);

    final showFab = shouldShowFab(atBottom: _atBottom, scrolling: _scrolling);

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.maxHeight;
        // 正文列宽按这一块**实际拿到的宽度**算（§4.16）：抽屉打开时页面被
        // 缩窄，列宽跟着收；用 MediaQuery 的整窗宽会算出比页面还宽的列。
        final columnMax = readableColumnWidth(constraints.maxWidth);
        // 零滚动线落在视口底部往上「输入条占高」的位置。
        // anchor = (视口高 - 底部留白) / 视口高；底部留白 = 渐隐带 + 输入条。
        final bottomPad = DsSpacing.chatListOverlap + DsSpacing.chatVeilFeather;
        final anchor = _viewport <= 0
            ? 1.0
            : ((_viewport - bottomPad) / _viewport).clamp(0.0, 1.0);

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              // SelectionArea（第二轮反馈 E）：长按可选字复制，assistant 的
              // gpt_markdown 内部 SelectableAdapter 注册到最近的 SelectionContainer。
              child: SelectionArea(
                child: CustomScrollView(
                  controller: _scroll,
                  center: _centerKey,
                  anchor: anchor,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  slivers: [
                    // 顶部呼吸空间：正文与顶栏下沿留一点空
                    // （dsh-go 的 topInset + AppSpace.sm；这里顶栏已吃安全区，
                    // 只留间距本身）。
                    const SliverToBoxAdapter(
                      child: SizedBox(height: DsSpacing.chatListTopGap),
                    ),
                    // before 段：反向生长。delegate 下标 i → rows[split-1-i]。
                    SliverList(
                      key: _beforeKey,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildRow(_split - 1 - i, state, columnMax),
                        childCount: _split,
                      ),
                    ),
                    // center 段：正向生长，从零滚动线往下长。
                    SliverList(
                      key: _centerKey,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildRow(_split + i, state, columnMax),
                        childCount: _rows.length - _split,
                      ),
                    ),
                    // 尾部留白：滚到底时最后一条消息停在渐隐带之上，不贴着
                    // 输入条上沿被吃掉一截（dsh-go 的
                    // `SliverToBoxAdapter(SizedBox(height: bottomPad))`；
                    // 与 anchor 用同一个数，两处几何就自洽）。
                    SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
                  ],
                ),
              ),
            ),
            // 跳转最新 FAB：!atBottom && !scrolling 时渐显，点击只滚到底。
            Positioned(
              right: DsSpacing.fabMargin,
              bottom: DsSpacing.fabMargin,
              child: IgnorePointer(
                ignoring: !showFab,
                child: AnimatedOpacity(
                  opacity: showFab ? DsMotion.fabOpacity : 0.0,
                  duration: DsMotion.fabFade,
                  child: _JumpToLatestFab(
                    colors: colors,
                    onTap: () => _scrollToBottom(animated: true),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// before 段与 center 段的分界（行数组下标）。
  ///
  /// 分界选「最后一条稳定行」：用户消息、助手正文、轮尾行——
  /// 这些行以后不会被合并或替换，可以放心当锚点。
  /// 找不到就分界 0（全部在 center 段）。
  int get _split {
    for (var i = _rows.length - 1; i >= 0; i--) {
      if (_rows[i].stable) return i + 1;
    }
    return 0;
  }

  Widget _buildRow(int index, ChatState state, double columnMax) {
    if (index < 0 || index >= _rows.length) return const SizedBox.shrink();
    final row = _rows[index];
    final previous = index > 0 ? _rows[index - 1] : null;
    final gap = chatRowGapBefore(row, previous);
    final fresh = _freshKeys.contains(row.key);
    if (fresh) _freshKeys = {..._freshKeys}..remove(row.key);

    // 行内容来自行自身的才进缓存；间距变了也要重建（间距在行框上）。
    if (row.cacheable) {
      final cached = _built[row.key];
      if (cached != null &&
          identical(cached.row, row) &&
          cached.gap == gap &&
          cached.columnMax == columnMax &&
          !fresh) {
        return cached.widget;
      }
    }

    final body = _rowWidget(row, state);
    // 正文可读列（§4.16）：≤720 用满，更宽按 0.9 缩放；居中对齐。
    final keyed = KeyedSubtree(
      key: ValueKey<String>(row.key),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: columnMax),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              DsSpacing.screenPad,
              gap,
              DsSpacing.screenPad,
              0,
            ),
            child: fresh ? RowFadeIn(child: body) : body,
          ),
        ),
      ),
    );
    if (row.cacheable && !fresh) {
      _built[row.key] = (row: row, gap: gap, columnMax: columnMax, widget: keyed);
    }
    return keyed;
  }
}

/// 跳转最新 FAB（对照 companion ChatDetail.kt:691-717）。
class _JumpToLatestFab extends StatelessWidget {
  const _JumpToLatestFab({required this.colors, required this.onTap});

  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '跳转到最新',
      child: InkResponse(
        onTap: onTap,
        radius: DsSpacing.fabSize / 2,
        child: Container(
          width: DsSpacing.fabSize,
          height: DsSpacing.fabSize,
          decoration: BoxDecoration(
            color: colors.bgLayer2,
            borderRadius: BorderRadius.circular(DsSpacing.fabSize / 2),
            border: Border.all(color: colors.borderL2),
          ),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: DsSpacing.fabIconSize,
            color: colors.brand,
          ),
        ),
      ),
    );
  }
}
