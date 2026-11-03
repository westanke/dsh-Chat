part of 'chat_page.dart';

// ---------- 消息列表（含滚动冻结 / 贴底跟随 / 跳转最新 FAB） ----------
// 对照 companion 三处实现：ChatDetail.kt:443-450 / :691-717（atBottom 与 FAB）、
// ChatScrollDiag.kt:254-273（wantsBottom 粘性意图）、
// ChatScrollFreeze.kt:42-82（滚动冻结快照）。判据抽到 scroll_follow.dart 可单测。

class _MessageList extends StatefulWidget {
  const _MessageList({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();

  /// 粘性「想贴底」意图：只有用户真拖拽才撤销，滚回底部才恢复。
  /// 对照 companion `ChatScrollDiag.kt:254-273`：不用瞬时 isAtBottom 当跟随守卫，
  /// 否则流式每 token 重建列表会让 atBottom 翻 false 后永久自锁
  ///（`PITFALLS.md:574-616`）。
  bool _wantsBottom = kInitialWantsBottom;
  bool _atBottom = true;
  bool _scrolling = false;

  /// 滚动期间冻结的子项快照，对照 `ChatScrollFreeze.kt:42-82`：
  /// 流式每 token 重建 ListView 会卡顿，用户滚动时复用冻结快照。
  /// 空列表不冻结（companion 固化空表 → 位置归零 → atBottom 永久 false 事故）。
  List<Widget>? _frozenChildren;
  List<Widget> _lastChildren = const <Widget>[];

  Timer? _settleTimer;
  String? _sessionId;

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
  void didUpdateWidget(covariant _MessageList oldWidget) {
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
    _frozenChildren = null;
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
      if (n is ScrollStartNotification) _freezeChildren();
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

  void _freezeChildren() {
    if (_frozenChildren != null) return;
    // 空表返回 null，不冻结（companion 事故防线）。
    final snap = freezeSnapshot(_lastChildren);
    if (snap == null) return;
    _frozenChildren = snap;
  }

  void _restartSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = Timer(DsMotion.freezeSettle, () {
      if (!mounted) return;
      setState(() {
        _scrolling = false;
        _frozenChildren = null;
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
    final hasItems =
        widget.state.messages.isNotEmpty || widget.state.streaming;
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

  List<Widget> _buildChildren(ChatState state, DsColors colors) {
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
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = widget.colors;
    final List<Widget> children;
    if (_frozenChildren != null) {
      children = _frozenChildren!;
    } else {
      children = _buildChildren(state, colors);
      _lastChildren = children;
    }
    final showFab = shouldShowFab(atBottom: _atBottom, scrolling: _scrolling);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.screenPad,
              0,
              DsSpacing.contentPadRight,
              DsSpacing.hMarginBottom,
            ),
            children: children,
          ),
        ),
        // 跳转最新 FAB：对照 companion ChatDetail.kt:691-717，
        // !atBottom && !scrolling 时渐显，点击只滚到底不手写状态。
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
  }
}

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
