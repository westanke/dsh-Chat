/// 定时任务面板（顶栏时钟入口 → 底部 sheet）。
///
/// 交互口径参考 dsh-go `app/lib/ui/chat/header_schedule.dart`：入口只挂在标题胶囊
/// 尾端、图标按钮；面板先列任务，单条任务可看详情。差异是本仓桥侧支持
/// `patch.active`，所以列表行直接给启用开关（dsh-go 官方记录没有 paused 态）。
///
/// 依赖的帧全部走 [GatewaySchedule]（app/lib/bridge/gateway_schedule.dart）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/gateway_schedule.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'schedule_detail.dart';
import 'schedule_form.dart';
import 'window_class.dart';

/// 顶栏时钟入口是否可见：必须在会话内，且桥 hello 声明了能力位。
bool scheduleEntryVisible(ChatState state) {
  final sid = state.sessionId;
  return sid != null &&
      sid.isNotEmpty &&
      state.gateway.hasCapability(scheduleCapability);
}

/// 打开定时任务面板。
Future<void> showScheduleSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  return showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (_) => ScheduleSheet(state: state, colors: colors),
  );
}

/// 面板本体（公开给测试直接 pump）。
class ScheduleSheet extends StatefulWidget {
  const ScheduleSheet({super.key, required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  State<ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<ScheduleSheet> {
  List<ScheduleTask>? _tasks;
  String? _error;
  bool _loading = false;
  bool _busy = false;
  ScheduleTask? _detail;

  DsColors get _c => widget.colors;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final sid = widget.state.sessionId;
    if (sid == null || sid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _tasks = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final tasks = await widget.state.gateway.scheduleList(sid);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _error = null;
        _loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = scheduleErrorMessage(e.code, e.message);
        _loading = false;
      });
    }
  }

  Future<void> _runTask(ScheduleTask task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.state.gateway.scheduleRun(task.id);
      _snack('已触发「${task.title}」');
      await _load();
    } on RequestException catch (e) {
      _snack(scheduleErrorMessage(e.code, e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleTask(ScheduleTask task, bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.state.gateway.setScheduleEnabled(task, enabled);
      await _load();
      _snack(enabled ? '已启用「${task.title}」' : '已暂停「${task.title}」');
    } on RequestException catch (e) {
      _snack(scheduleErrorMessage(e.code, e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTask(ScheduleTask task) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _c.bgLayer1,
        title: Text(
          '删除定时任务？',
          style: DsTypography.h4.copyWith(color: _c.labelPrimary),
        ),
        content: Text(
          '「${task.title}」将不再运行，历史记录保留。',
          style: DsTypography.small.copyWith(color: _c.labelSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('删除', style: TextStyle(color: _c.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final sid = widget.state.sessionId;
    if (sid == null || sid.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.state.gateway.deleteSchedule(sid, task.id);
      _snack('已删除「${task.title}」');
      await _load();
    } on RequestException catch (e) {
      _snack(scheduleErrorMessage(e.code, e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTask() async {
    if (_busy) return;
    final created = await showScheduleForm(context, widget.state, _c);
    if (created == true) await _load();
  }

  Future<void> _editTask(ScheduleTask task) async {
    if (_busy) return;
    final saved = await showScheduleForm(
      context,
      widget.state,
      _c,
      task: task,
    );
    if (saved != true) return;
    await _load();
    if (!mounted) return;
    ScheduleTask? refreshed;
    for (final item in _tasks ?? const <ScheduleTask>[]) {
      if (item.id == task.id) {
        refreshed = item;
        break;
      }
    }
    setState(() => _detail = refreshed);
  }

  void _snack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final detail = _detail;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.screenPad,
          DsSpacing.liGap,
          DsSpacing.screenPad,
          DsSpacing.blockGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(detail),
            const SizedBox(height: DsSpacing.liGap),
            if (detail != null)
              ScheduleDetailView(task: detail, state: widget.state, colors: c)
            else ...[
              if (_error != null && _tasks != null) _refreshBanner(),
              if (_tasks == null && _error == null)
                _loadingBox()
              else if (_tasks == null)
                _errorBox()
              else if (_tasks!.isEmpty)
                _emptyBox()
              else
                for (final task in _tasks!)
                  ScheduleRow(
                    task: task,
                    colors: c,
                    busy: _busy,
                    onToggle: (value) => unawaited(_toggleTask(task, value)),
                    onRun: () => unawaited(_runTask(task)),
                    onDetail: () => setState(() => _detail = task),
                    onDelete: () => unawaited(_deleteTask(task)),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(ScheduleTask? detail) {
    final c = _c;
    return SizedBox(
      height: DsSpacing.topBarHeight,
      child: Row(
        children: [
          if (detail != null)
            IconButton(
              tooltip: '返回任务列表',
              icon: const Icon(Icons.arrow_back),
              color: c.labelPrimary,
              onPressed: () => setState(() => _detail = null),
            )
          else ...[
            Icon(
              Icons.schedule,
              size: DsSpacing.chipIconSize + 4,
              color: c.labelSecondary,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              detail?.title ?? '定时任务',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.h4.copyWith(color: c.labelPrimary),
            ),
          ),
          if (detail == null)
            Text(
              '${_tasks?.length ?? 0} 个',
              style: DsTypography.small.copyWith(color: c.labelTertiary),
            ),
          if (detail == null)
            IconButton(
              tooltip: '新建定时任务',
              icon: const Icon(Icons.add),
              color: c.labelSecondary,
              onPressed: _busy ? null : () => unawaited(_createTask()),
            ),
          if (detail == null)
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              color: c.labelSecondary,
              onPressed: _busy || _loading ? null : () => unawaited(_load()),
            ),
          if (detail != null)
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined),
              color: c.labelSecondary,
              onPressed: _busy ? null : () => unawaited(_editTask(detail)),
            ),
        ],
      ),
    );
  }

  Widget _loadingBox() {
    return SizedBox(
      height: 120,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: _c.brand),
        ),
      ),
    );
  }

  Widget _errorBox() {
    final c = _c;
    return Container(
      padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
      decoration: BoxDecoration(
        color: c.settingsWarnBg,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      ),
      child: Column(
        children: [
          Text(
            _error ?? '定时任务加载失败',
            textAlign: TextAlign.center,
            style: DsTypography.small.copyWith(color: c.settingsWarnFg),
          ),
          const SizedBox(height: DsSpacing.liGap),
          TextButton(
            onPressed: () => unawaited(_load()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _refreshBanner() {
    final c = _c;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
      child: Material(
        color: c.settingsWarnBg,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
          onTap: () => unawaited(_load()),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.settingsCardPadH,
              vertical: DsSpacing.settingsCardPadV,
            ),
            child: Text(
              '刷新失败：$_error（点此重试）',
              style: DsTypography.small.copyWith(color: c.settingsWarnFg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyBox() {
    final c = _c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
      child: Column(
        children: [
          Icon(Icons.schedule_outlined, size: 36, color: c.labelTertiary),
          const SizedBox(height: 8),
          Text(
            '这个会话还没有定时任务',
            style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '定时任务在桥端按时触发，不依赖 App 在线。',
            textAlign: TextAlign.center,
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          ),
        ],
      ),
    );
  }
}
