/// 会话侧栏：把原来散在「更多」菜单里的几个面板收进一个可左右滑动的 TAB 容器
/// （2026-11-22 用户要求：集合到一个窗口里多个 TAB，支持左右滑动查看）。
///
/// 每个 TAB 直接复用既有面板的身体类，不复制逻辑：
/// 会话信息 / 会话统计 / 运行轨迹（代码工作视图按设置出现）。团队与待办
/// 已有顶栏成员图标与底部待办条入口，这里不再重复放 TAB。
library;

import 'package:material_ui/material_ui.dart';

import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'projection_sheets.dart';
import 'session_info_sheet.dart';
import 'stats_sheet.dart';
import 'window_class.dart';
import 'work_view_sheet.dart';

/// 一个 TAB 的声明：标签 + 图标 + 内容构造器。
class SessionTab {
  const SessionTab({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final Widget Function(BuildContext context, ChatState state, DsColors colors)
  builder;
}

/// 当前会话可用的 TAB（按显示顺序）。
List<SessionTab> sessionTabsOf({Future<void> Function()? onShare}) {
  return <SessionTab>[
    SessionTab(
      label: '信息',
      icon: Icons.info_outline,
      builder: (context, state, colors) => SessionInfoContent(
        state: state,
        colors: colors,
        onShare: onShare,
      ),
    ),
    SessionTab(
      label: '统计',
      icon: Icons.bar_chart,
      builder: (context, state, colors) =>
          StatsBody(state: state, colors: colors),
    ),
    SessionTab(
      label: '轨迹',
      icon: Icons.timeline,
      builder: (context, state, colors) =>
          TrajectoryBody(state: state, colors: colors),
    ),
    if (appSettings.codeWorkView)
      SessionTab(
        label: '代码',
        icon: Icons.difference_outlined,
        builder: (context, state, colors) =>
            WorkViewContent(state: state, colors: colors),
      ),
  ];
}

/// 打开会话侧栏。`initial` 是打开时落在第几个 TAB。
Future<void> showSessionTabsSheet(
  BuildContext context,
  ChatState state,
  DsColors colors, {
  int initial = 0,
  Future<void> Function()? onShare,
}) {
  final tabs = sessionTabsOf(onShare: onShare);
  final start = initial.clamp(0, tabs.length - 1);
  return showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (_) => SessionTabsSheet(
      state: state,
      colors: colors,
      tabs: tabs,
      initial: start,
    ),
  );
}

/// TAB 容器本体：顶部横滑标签 + 下方 PageView（左右滑动切页）。
class SessionTabsSheet extends StatefulWidget {
  const SessionTabsSheet({
    super.key,
    required this.state,
    required this.colors,
    required this.tabs,
    this.initial = 0,
    this.embedded = false,
    this.onClose,
  });

  /// 嵌进侧栏时的关闭回调（点顶部把手 / 下拖 / 右滑）。
  final VoidCallback? onClose;

  /// 嵌进侧栏（左滑推出）时撑满可用高度；作为 bottom sheet 时留 88% 高。
  final bool embedded;

  final ChatState state;
  final DsColors colors;
  final List<SessionTab> tabs;
  final int initial;

  @override
  State<SessionTabsSheet> createState() => _SessionTabsSheetState();
}

class _SessionTabsSheetState extends State<SessionTabsSheet> {
  late final PageController _controller = PageController(
    initialPage: widget.initial,
  );
  late int _index = widget.initial;

  /// 把手上的横向累计位移：侧栏从右滑出，向右滑回即收起。
  double _handleDx = 0;
  final GlobalKey<_TabBarState> _tabKey = GlobalKey<_TabBarState>();

  @override
  void initState() {
    super.initState();
    // 手指拖 PageView 时头栏跟着走（不只在翻页完成时跳一下）。
    _controller.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    final page = _controller.page;
    if (page == null) return;
    _tabKey.currentState?.follow(page);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPageScroll);
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final height = MediaQuery.sizeOf(context).height;
    final box = SafeArea(
      child: SizedBox(
        height: widget.embedded ? null : height * 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _handle(c),
            _TabBar(
              key: _tabKey,
              colors: c,
              tabs: widget.tabs,
              index: _index,
              onPick: _go,
            ),
            const SizedBox(height: DsSpacing.composerKeyGap),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.tabs.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    DsSpacing.screenPad,
                    0,
                    DsSpacing.screenPad,
                    DsSpacing.screenPad,
                  ),
                  child: widget.tabs[i].builder(
                    context,
                    widget.state,
                    c,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.embedded) return box;
    return Material(
      color: c.bgLayer1,
      child: SizedBox.expand(child: box),
    );
  }

  Widget _handle(DsColors c) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onClose,
    onVerticalDragEnd: (d) {
      if ((d.primaryVelocity ?? 0) > 200) widget.onClose?.call();
    },
    onHorizontalDragStart: (_) => _handleDx = 0,
    onHorizontalDragUpdate: (d) => _handleDx += d.delta.dx,
    onHorizontalDragEnd: (d) {
      // 侧栏从右滑出，向右滑回即收起（面板头部的把手区域）。
      if (_handleDx > 60 || (d.primaryVelocity ?? 0) > 300) {
        widget.onClose?.call();
      }
    },
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: c.borderL1,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}

class _TabBar extends StatefulWidget {
  const _TabBar({
    super.key,
    required this.colors,
    required this.tabs,
    required this.index,
    required this.onPick,
  });

  final DsColors colors;
  final List<SessionTab> tabs;
  final int index;
  final ValueChanged<int> onPick;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  final ScrollController _ctrl = ScrollController();
  late List<GlobalKey> _keys;
  int _followed = -1;

  @override
  void initState() {
    super.initState();
    _keys = List<GlobalKey>.generate(widget.tabs.length, (_) => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.index));
  }

  @override
  void didUpdateWidget(_TabBar old) {
    super.didUpdateWidget(old);
    if (_keys.length != widget.tabs.length) {
      _keys = List<GlobalKey>.generate(widget.tabs.length, (_) => GlobalKey());
    }
    // 翻页后把当前项滚到正中：滑到哪页，头就跟到哪页。
    if (old.index != widget.index) _center(widget.index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 拖动 PageView 时每帧调用：跨过半页就把头滚到对应项（不带动画，跟手）。
  void follow(double page) {
    final i = page.round().clamp(0, widget.tabs.length - 1);
    if (i == _followed) return;
    _followed = i;
    _scrollTo(i, animate: false);
  }

  void _center(int i) {
    _followed = i;
    _scrollTo(i, animate: true);
  }

  /// 第 i 项居中所需的偏移。
  ///
  /// chip 等宽、两端各留半屏 padding，所以目标就是 `i * (chip + gap)`；
  /// 不去测 RenderBox —— 翻页动画中间态会把测量结果带偏，实测停不稳。
  void _scrollTo(int i, {required bool animate}) {
    if (i < 0 || i >= widget.tabs.length) return;
    if (!_ctrl.hasClients) return;
    const step = DsSpacing.tabChipWidth + DsSpacing.tabChipGap;
    final target = (i * step).clamp(0.0, _ctrl.position.maxScrollExtent);
    if ((_ctrl.offset - target).abs() < 0.5) return;
    if (animate) {
      _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _ctrl.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    const chipW = DsSpacing.tabChipWidth;
    return SizedBox(
      height: 36,
      child: LayoutBuilder(
        builder: (context, box) {
          // 两端各留半屏：第一项与最后一项也能滚到正中，
          // 不会像普通 ListView 那样被 maxScrollExtent 卡在边上。
          final edge = ((box.maxWidth - chipW) / 2);
          return ListView.separated(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: edge < 0 ? 0 : edge),
            itemCount: widget.tabs.length,
            separatorBuilder: (context, i) =>
                const SizedBox(width: DsSpacing.tabChipGap),
            itemBuilder: (context, i) {
              final on = i == widget.index;
              final t = widget.tabs[i];
              return KeyedSubtree(
                key: _keys[i],
                child: SizedBox(
                  width: chipW,
                  child: Material(
                    color: on ? c.chipSelectedBg : c.drawerSearchFill,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onPick(i),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            t.icon,
                            size: 16,
                            color: on ? c.chipSelectedFg : c.labelSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              t.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: DsTypography.smallStrong.copyWith(
                                color:
                                    on ? c.chipSelectedFg : c.labelSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
