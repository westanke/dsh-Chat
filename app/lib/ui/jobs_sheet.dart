/// 后台任务面板：打开拉 job-list，点条目拉 job-output，运行中任务确认后
/// 发 job-kill。数据来自 [JobsController]，配色只用 Ds token（宪法 §4）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/jobs.dart';
import '../design/tokens.dart';
import 'window_class.dart';

/// 打开后台任务面板。
Future<void> showJobsSheet(
  BuildContext context,
  JobsController controller,
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
    builder: (_) => JobsSheet(controller: controller, colors: colors),
  );
}

/// 面板本体（公开给测试直接 pump）。
class JobsSheet extends StatefulWidget {
  const JobsSheet({super.key, required this.controller, required this.colors});

  final JobsController controller;
  final DsColors colors;

  @override
  State<JobsSheet> createState() => _JobsSheetState();
}

class _JobsSheetState extends State<JobsSheet> {
  String? _detailId;
  JobOutput? _output;
  String? _outputError;
  bool _outputLoading = false;
  bool _busy = false;

  DsColors get _c => widget.colors;
  JobsController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    // 每次打开都重拉：桥侧推送没有回放，缓存可能是上一个连接留下的。
    unawaited(_ctrl.refresh());
  }

  Future<void> _open(JobInfo job) async {
    setState(() {
      _detailId = job.id;
      _output = null;
    });
    await _loadOutput(job.id);
  }

  Future<void> _loadOutput(String jobId) async {
    if (!mounted) return;
    setState(() {
      _outputLoading = true;
      _outputError = null;
    });
    try {
      final out = await _ctrl.output(jobId);
      if (!mounted || _detailId != jobId) return;
      setState(() {
        _output = out;
        _outputLoading = false;
      });
    } on RequestException catch (e) {
      if (!mounted || _detailId != jobId) return;
      setState(() {
        _outputError = jobErrorMessage(e);
        _outputLoading = false;
      });
    }
  }

  Future<void> _stop(JobInfo job) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _c.bgLayer1,
        title: Text(
          '停止后台任务？',
          style: DsTypography.h4.copyWith(color: _c.labelPrimary),
        ),
        content: Text(
          '「${job.label}」将被终止，已产生的输出会保留。',
          style: DsTypography.small.copyWith(color: _c.labelSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('job-confirm-stop'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('停止', style: TextStyle(color: _c.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final killed = await _ctrl.kill(job.id);
      _snack(killed ? '已发送停止请求' : '任务已经结束');
    } on RequestException catch (e) {
      _snack(jobErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _closeDetail() => setState(() {
    _detailId = null;
    _output = null;
    _outputError = null;
  });

  @override
  Widget build(BuildContext context) {
    // 固定 72% 屏高：任务列表可能很长，面板自己滚，不随内容跳高。
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final id = _detailId;
            final detail = id == null ? null : _ctrl.jobById(id);
            return Column(
              children: [
                _header(detail),
                Expanded(
                  child: detail == null ? _listBody() : _detailBody(detail),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(JobInfo? detail) {
    final c = _c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.screenPad),
      child: SizedBox(
        height: DsSpacing.topBarHeight,
        child: Row(
          children: [
            if (detail != null)
              IconButton(
                tooltip: '返回任务列表',
                icon: const Icon(Icons.arrow_back),
                color: c.labelPrimary,
                onPressed: _closeDetail,
              ),
            Expanded(
              child: Text(
                detail?.label ?? '后台任务',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.h4.copyWith(color: c.labelPrimary),
              ),
            ),
            IconButton(
              tooltip: '刷新任务列表',
              icon: const Icon(Icons.refresh),
              color: c.labelSecondary,
              onPressed: _ctrl.loading
                  ? null
                  : () => unawaited(_ctrl.refresh()),
            ),
            if (detail != null) _statusChip(detail),
          ],
        ),
      ),
    );
  }

  Widget _listBody() {
    final error = _ctrl.error;
    if (!_ctrl.isLoaded) {
      return error == null ? _loading() : _message(error, retry: _ctrl.refresh);
    }
    final jobs = _ctrl.jobs;
    if (jobs.isEmpty && error == null) return _emptyBox();
    final running = _ctrl.runningJobs;
    final finished = _ctrl.finishedJobs;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        0,
        DsSpacing.screenPad,
        DsSpacing.blockGap,
      ),
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
            child: Text(
              '刷新失败：$error',
              style: DsTypography.small.copyWith(color: _c.settingsWarnFg),
            ),
          ),
        if (running.isNotEmpty) _sectionTitle('运行中', running.length),
        for (final job in running)
          _row(job, onStop: () => unawaited(_stop(job))),
        if (finished.isNotEmpty) _sectionTitle('已结束', finished.length),
        for (final job in finished) _row(job),
      ],
    );
  }

  Widget _detailBody(JobInfo job) {
    final meta = <String>[
      '${job.kind} · 开始于 ${formatJobTime(job.startedAt)}',
      if (job.owner?.isNotEmpty ?? false) '发起者：${job.owner}',
      if (job.detail?.isNotEmpty ?? false) '结束原因：${job.detail}',
    ].join('\n');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.screenPad,
            0,
            DsSpacing.screenPad,
            DsSpacing.liGap,
          ),
          child: Text(
            meta,
            style: DsTypography.caption.copyWith(color: _c.labelTertiary),
          ),
        ),
        Expanded(child: _outputBody(job)),
      ],
    );
  }

  Widget _outputBody(JobInfo job) {
    final c = _c;
    if (_outputLoading) return _loading();
    final error = _outputError;
    if (error != null) {
      return _message(error, retry: () => unawaited(_loadOutput(job.id)));
    }
    final output = _output;
    if (output == null || output.isEmpty) {
      return _message('这个任务还没有产生输出');
    }
    final warn = output.truncated;
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: DsSpacing.screenPad),
            padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
            decoration: BoxDecoration(
              color: c.mdCodeBlockBg,
              borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                output.output,
                style: DsTypography.codeBlock.copyWith(
                  fontFamily: DsTypography.codeFamily,
                  color: c.mdCodeBlockText,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(DsSpacing.liGap),
          child: Row(
            children: [
              Icon(
                warn ? Icons.info_outline : Icons.notes,
                size: DsSpacing.chipIconSize,
                color: warn ? c.settingsWarnFg : c.labelTertiary,
              ),
              const SizedBox(width: DsSpacing.chipIconGap),
              Expanded(
                child: Text(
                  warn
                      ? '输出较长，较早的部分已被桥端裁剪，无法再取回'
                      : '输出 ${output.output.length} 字符',
                  style: DsTypography.caption.copyWith(
                    color: warn ? c.settingsWarnFg : c.labelTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(
        top: DsSpacing.blockGap,
        bottom: DsSpacing.liGap,
      ),
      child: Text(
        '$title · $count',
        style: DsTypography.caption.copyWith(color: _c.labelTertiary),
      ),
    );
  }

  Widget _loading() => Center(
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: _c.brand),
    ),
  );

  Widget _message(String text, {VoidCallback? retry}) {
    final c = _c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.screenPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: DsTypography.small.copyWith(
                color: retry == null ? c.labelTertiary : c.settingsWarnFg,
              ),
            ),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox() {
    final c = _c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.screenPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 36, color: c.labelTertiary),
            const SizedBox(height: 8),
            Text(
              '这个会话没有后台任务',
              style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '任务由工具在后台启动，运行中的任务会显示在这里。',
              style: DsTypography.small.copyWith(color: c.labelTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(JobInfo job, {VoidCallback? onStop}) {
    final c = _c;
    final progress = job.progressLine;
    final start = formatJobTime(job.startedAt);
    final end = job.finishedAt;
    return Material(
      color: c.none,
      child: InkWell(
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
        onTap: () => unawaited(_open(job)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _jobIcon(job.kind),
                size: DsSpacing.menuIconSize,
                color: job.isLive ? c.brand : c.labelTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            job.label.isEmpty ? job.id : job.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.smallStrong.copyWith(
                              color: c.labelPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(job),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      end == null ? start : '$start — ${formatJobTime(end)}',
                      style: DsTypography.caption.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                    if (progress.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        progress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.caption.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onStop != null) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: ValueKey('job-stop-${job.id}'),
                  onPressed: _busy ? null : onStop,
                  child: Text('停止', style: TextStyle(color: c.danger)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(JobInfo job) {
    final c = _c;
    final (Color bg, Color fg) = switch (job.phase) {
      JobPhase.running => (c.chipSelectedBg, c.chipSelectedFg),
      JobPhase.failed => (c.settingsWarnBg, c.danger),
      JobPhase.finished => (c.bgOverlay, c.labelTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.chipPadH,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
      ),
      child: Text(
        job.status.label,
        style: DsTypography.caption.copyWith(color: fg),
      ),
    );
  }

  static IconData _jobIcon(String kind) => switch (kind) {
    'subagent' => Icons.smart_toy_outlined,
    'bash' || 'shell' || 'command' => Icons.terminal,
    _ => Icons.bolt,
  };
}
