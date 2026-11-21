/// 输入条上方的目标条（对照 dsh-go `ui/chat/dock/goal_bar.dart` +
/// `goal_sheet.dart`）：显示会话的长期目标与状态，点一下弹目标操作面板。
///
/// 数据源是内核 `goal` 投影（history 首屏 `projections.values.goal`，由
/// create_goal / update_goal 工具写），动作走 `goal-edit/pause/resume/clear`
/// 帧（bridge ws-goals.ts，compare-and-set 必须带当前 ref）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/goal.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'window_class.dart';

/// 目标条：`⚑ 目标 把登录迁到新接口… 已暂停 ⋯`；进行中不写状态词。
class GoalDockBar extends StatelessWidget {
  const GoalDockBar({
    super.key,
    required this.goal,
    required this.colors,
    this.onTap,
  });

  final GoalProjection goal;
  final DsColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final blocked = goal.goal.phase == GoalPhase.blocked;
    final stopped = goal.goal.phase == GoalPhase.paused || blocked;
    final state = goalStateLabel(goal);
    final iconColor = blocked
        ? c.chatStatusWarn
        : stopped
        ? c.labelTertiary
        : c.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        DsSpacing.blockGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.bgLayer1,
              borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
              border: Border.all(color: c.borderL2, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: DsSpacing.chipIconSize, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  '目标',
                  style: DsTypography.smallStrong.copyWith(color: c.labelSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goalHeadline(goal.goal.objective),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption.copyWith(
                      color: stopped ? c.labelTertiary : c.labelPrimary,
                    ),
                  ),
                ),
                if (state != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    state,
                    style: DsTypography.caption.copyWith(
                      color: blocked ? c.chatStatusWarn : c.labelTertiary,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.more_horiz, size: DsSpacing.chipIconSize, color: c.labelTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 点目标条：弹操作面板 → 编辑/暂停/继续/清除；失败用 SnackBar 说明。
Future<void> runGoalActions(
  BuildContext context,
  ChatState state,
  DsColors colors,
) async {
  final id = state.sessionId;
  final goal = goalOf(state.projections);
  if (id == null || id.isEmpty || goal == null) return;
  final action = await showModalBottomSheet<GoalAction>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (_) => _GoalSheet(
      goal: goal,
      colors: colors,
      sessionId: id,
      gateway: state.gateway,
    ),
  );
  if (action == null || !context.mounted) return;

  String? problem;
  switch (action) {
    case GoalAction.edit:
      final text = await showDialog<String>(
        context: context,
        builder: (_) => _GoalEditor(initial: goal.goal.objective),
      );
      if (text == null || !context.mounted) return;
      problem = await _mutate(
        () => state.gateway.editGoal(id, goal.ref, objective: text),
        '修改目标失败',
      );
    case GoalAction.pause:
      problem = await _mutate(
        () => state.gateway.pauseGoal(id, goal.ref),
        '暂停目标失败',
      );
    case GoalAction.resume:
      problem = await _mutate(
        () => state.gateway.resumeGoal(id, goal.ref),
        '恢复目标失败',
      );
    case GoalAction.clear:
      if (!await _confirmClear(context, goal, colors)) return;
      problem = await _mutate(
        () => state.gateway.clearGoal(id, goal.ref),
        '清除目标失败',
      );
  }
  if (problem != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(problem)));
    return;
  }
  // 动作成功后投影要重拉：目标正文/阶段/轮次都在投影里，等日志追平。
  await state.reloadHistory();
}

enum GoalAction { edit, pause, resume, clear }

/// 统一跑一次目标写帧：成功返回 null，失败返回一句中文原因。
Future<String?> _mutate(Future<Object?> Function() call, String action) async {
  try {
    await call();
    return null;
  } on RequestException catch (e) {
    return '$action：${goalErrorText(e)}';
  }
}

/// 目标写操作的内核错误 → 人话（对照 dsh-go `goalErrorText`）。
String goalErrorText(RequestException e) => switch (e.code) {
  'GOAL_STALE_REVISION' => '目标刚被改过，请重新打开面板',
  'GOAL_NOT_FOUND' => '目标不存在',
  'GOAL_AGENT_NOT_LIVE' => '这个会话当前不可改目标',
  'GOAL_INVALID_OBJECTIVE' || 'GOAL_INVALID_EDIT' => '目标内容不能为空',
  'unsupported' => '当前网关版本不支持改目标',
  _ => e.message,
};

/// 目标操作面板：完整目标文字 + 状态行（+ activation）+ 编辑/暂停/继续/清除。
class _GoalSheet extends StatefulWidget {
  const _GoalSheet({
    required this.goal,
    required this.colors,
    required this.sessionId,
    required this.gateway,
  });

  final GoalProjection goal;
  final DsColors colors;
  final String sessionId;
  final GatewayClient gateway;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  /// 'armed' / 'disarmed'；null = 老桥没这帧/还没拉回来（不显示该行）。
  String? _activation;

  @override
  void initState() {
    super.initState();
    _loadActivation();
  }

  Future<void> _loadActivation() async {
    if (!widget.gateway.hasCapability('mobile-goal-activation-v1')) return;
    try {
      final activation = await widget.gateway.fetchGoalActivation(
        widget.sessionId,
      );
      if (mounted) setState(() => _activation = activation);
    } on RequestException {
      // 拉不到就不显示 activation 行，不影响暂停/恢复/清除。
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final colors = widget.colors;
    final c = colors;
    final blocked = goal.goal.phase == GoalPhase.blocked;
    final canPause = goalCanPause(goal);
    final canResume = goalCanResume(goal);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '目标',
                    style: DsTypography.h4.copyWith(color: c.labelPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: c.labelTertiary),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.goal.objective,
                    style: DsTypography.base.copyWith(
                      color: c.labelPrimary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        blocked ? Icons.error_outline : Icons.flag_outlined,
                        size: 16,
                        color: blocked ? c.chatStatusWarn : c.labelTertiary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          goalStatusLine(goal),
                          style: DsTypography.caption.copyWith(
                            color: blocked ? c.chatStatusWarn : c.labelTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_activation != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _activation == 'armed' ? '自动续跑：已启用' : '自动续跑：未启用',
                      style: DsTypography.caption.copyWith(color: c.labelTertiary),
                    ),
                  ],
                  if (goal.goal.blockedReason case final reason?) ...[
                    const SizedBox(height: 4),
                    Text(
                      reason.message,
                      style: DsTypography.caption.copyWith(color: c.labelTertiary),
                    ),
                  ],
                ],
              ),
            ),
            _GoalActionTile(
              icon: Icons.edit_outlined,
              title: '编辑目标',
              colors: c,
              onTap: () => Navigator.of(context).pop(GoalAction.edit),
            ),
            if (canPause)
              _GoalActionTile(
                icon: Icons.pause_outlined,
                title: '暂停目标',
                subtitle: '暂停后模型不再自动续跑',
                colors: c,
                onTap: () => Navigator.of(context).pop(GoalAction.pause),
              ),
            if (canResume)
              _GoalActionTile(
                icon: Icons.play_arrow_outlined,
                title: '继续目标',
                subtitle: '让模型接着自动往下做',
                colors: c,
                onTap: () => Navigator.of(context).pop(GoalAction.resume),
              ),
            _GoalActionTile(
              icon: Icons.delete_outline,
              title: '清除目标',
              colors: c,
              danger: true,
              onTap: () => Navigator.of(context).pop(GoalAction.clear),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _GoalActionTile extends StatelessWidget {
  const _GoalActionTile({
    required this.icon,
    required this.title,
    required this.colors,
    this.subtitle,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final DsColors colors;
  final String? subtitle;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final fg = danger ? c.danger : c.labelPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: DsTypography.base.copyWith(color: fg)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: DsTypography.caption.copyWith(
                          color: c.labelTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 编辑目标：多行输入，空白或没改时不能保存。
class _GoalEditor extends StatefulWidget {
  const _GoalEditor({required this.initial});

  final String initial;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection.collapsed(offset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final text = _controller.text.trim();
    return text.isNotEmpty && text != widget.initial.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑目标'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(hintText: '这个会话要完成什么？'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

Future<bool> _confirmClear(
  BuildContext context,
  GoalProjection goal,
  DsColors colors,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('清除目标？'),
      content: Text(
        goal.goal.objective,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: colors.onBrand,
          ),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  return ok == true;
}
