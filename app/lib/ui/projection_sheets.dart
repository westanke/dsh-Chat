/// 三个「本地投影」面板（对照 dsh-companion，全部零网络请求）：
/// - 轨迹 Sheet：ChatState.rawEvents 客户端本地按轮次分组
///   （data/Trajectory.kt:98-127）；
/// - 团队面板 / TODO 面板：读服务端随首屏 history 下发的 projections.values.*
///   （data/AgentTeamProjection.kt、data/ChatPresentation.kt）。
///
/// 约束（bridge API.md:165,167）：projections 可能整个缺席，UI 必须显示
/// 「本会话暂无数据」而不是隐藏入口、更不把它当成「没有这个功能」。
/// 全部样式走 DsColors / DsTypography / DsSpacing（宪法 §4，零裸色）。
library;

import 'package:flutter/material.dart';

import '../bridge/gateway.dart';
import '../bridge/projections.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'subagent_history_page.dart';

// ---------- 公共骨架 ----------

Widget _sheetScaffold({
  required DsColors c,
  required String title,
  required String subtitle,
  required List<Widget> children,
}) {
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        DsSpacing.blockGap,
        DsSpacing.screenPad,
        DsSpacing.blockGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: DsTypography.h4.copyWith(color: c.labelPrimary)),
          const SizedBox(height: DsSpacing.liGap),
          Text(subtitle,
              style: DsTypography.small.copyWith(color: c.labelSecondary)),
          const SizedBox(height: DsSpacing.blockGap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _emptyHint(DsColors c, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
      child: Text(text,
          style: DsTypography.small.copyWith(color: c.labelSecondary)),
    );

Widget _row(DsColors c, String left, String right) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.liGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(left,
                style: DsTypography.small.copyWith(color: c.labelSecondary)),
          ),
          Text(right,
              style: DsTypography.smallStrong.copyWith(color: c.labelPrimary)),
        ],
      ),
    );

// ---------- 轨迹 Sheet ----------

void showTrajectorySheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (context) => _TrajectorySheet(state: state, colors: colors),
  );
}

class _TrajectorySheet extends StatefulWidget {
  const _TrajectorySheet({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  State<_TrajectorySheet> createState() => _TrajectorySheetState();
}

class _TrajectorySheetState extends State<_TrajectorySheet> {
  int? _expandedSeq;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final turns = trajectoryOf(widget.state.rawEvents);
    final children = <Widget>[];
    if (turns.isEmpty) {
      children.add(_emptyHint(c, '这个会话还没有可回溯的历史。'));
    }
    for (final turn in turns) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: DsSpacing.blockGap),
        child: Row(
          children: [
            Icon(Icons.timeline, size: 16, color: c.brand),
            const SizedBox(width: DsSpacing.chipIconGap),
            Text(
              turn.isUnknown ? '轮次之间' : '轮次 ${turn.turn}',
              style: DsTypography.smallStrong.copyWith(color: c.labelPrimary),
            ),
            const SizedBox(width: DsSpacing.chipGap),
            if (turn.toolCalls > 0)
              Text('${turn.toolCalls} 个工具调用',
                  style: DsTypography.caption.copyWith(color: c.labelSecondary)),
            const Spacer(),
            if (turn.durationMillis != null)
              Text('${turn.durationMillis} ms',
                  style: DsTypography.caption.copyWith(color: c.labelTertiary)),
          ],
        ),
      ));
      for (final node in turn.nodes) {
        final expanded = _expandedSeq == node.seq;
        children.add(InkWell(
          onTap: () => setState(() {
            _expandedSeq = expanded ? null : node.seq;
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.thinkHMargin,
              DsSpacing.liGap,
              0,
              DsSpacing.liGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(_nodeIcon(node.kind), size: 14, color: c.labelSecondary),
                    const SizedBox(width: DsSpacing.liGap),
                    Expanded(
                      child: Text(
                        _nodeLabel(node),
                        style: DsTypography.small
                            .copyWith(color: c.labelPrimary),
                      ),
                    ),
                    Text('#${node.seq}',
                        style: DsTypography.caption
                            .copyWith(color: c.labelTertiary)),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: c.labelSecondary,
                    ),
                  ],
                ),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpacing.liGap),
                    child: Container(
                      padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
                      decoration: BoxDecoration(
                        color: c.mdCodeBlockBg,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(DsSpacing.codeBlockRadius),
                        ),
                      ),
                      child: Text(
                        prettyJson(node.raw),
                        style: DsTypography.codeBlock
                            .copyWith(color: c.mdCodeBlockText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
      }
    }
    return _sheetScaffold(
      c: c,
      title: '运行轨迹',
      subtitle: '由当前会话的原始历史事件本地分组，不产生网络请求；点节点展开原始 JSON。',
      children: children,
    );
  }
}

IconData _nodeIcon(TrajectoryNodeKind kind) => switch (kind) {
      TrajectoryNodeKind.user => Icons.person_outline,
      TrajectoryNodeKind.assistant => Icons.smart_toy_outlined,
      TrajectoryNodeKind.tool => Icons.build_outlined,
      TrajectoryNodeKind.deliverable => Icons.attachment_outlined,
      TrajectoryNodeKind.turnEnd => Icons.flag_outlined,
      TrajectoryNodeKind.other => Icons.more_horiz,
    };

String _nodeLabel(TrajectoryNode node) => switch (node.kind) {
      TrajectoryNodeKind.user => '用户消息',
      TrajectoryNodeKind.assistant => '助手回复',
      TrajectoryNodeKind.tool =>
        node.label.isEmpty ? '工具调用' : '工具调用 · ${node.label}',
      TrajectoryNodeKind.deliverable => '交付物',
      TrajectoryNodeKind.turnEnd => '回合结束',
      TrajectoryNodeKind.other => node.type,
    };

// ---------- 团队面板 ----------

void showTeamSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (context) => _TeamSheet(state: state, colors: colors),
  );
}

class _TeamSheet extends StatelessWidget {
  const _TeamSheet({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final team = agentTeamProjectionOf(state.projections);
    final children = <Widget>[];
    if (team == null) {
      children.add(_emptyHint(
          c, '这个会话还没有智能团队数据。\n直接在聊天里发消息让负责人组建团队即可。'));
    } else {
      if (team.failure != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
          child: Text(team.failure!,
              style: DsTypography.small.copyWith(color: c.danger)),
        ));
      }
      children.add(_sectionTitle(c, '成员（${team.members.length}）'));
      if (team.members.isEmpty) {
        children.add(_emptyHint(c, '暂无成员。'));
      } else {
        for (final m in team.members) {
          children.add(_row(c, '${m.name}${m.isLead ? " · 负责人" : ""}',
              '${m.role} · ${m.phase}${m.error.isNotEmpty ? " · ${m.error}" : ""}'));
        }
      }
      children.add(_sectionTitle(
          c, '任务（${team.completedTasks}/${team.tasks.length} 完成）'));
      if (team.tasks.isEmpty) {
        children.add(_emptyHint(c, '暂无任务。'));
      } else {
        for (final t in team.tasks) {
          children.add(_row(
              c,
              '${t.subject.isEmpty ? t.id : t.subject}'
              '${t.ownerName.isNotEmpty ? " · ${t.ownerName}" : ""}',
              t.status));
        }
      }
      children.add(_sectionTitle(c, '子会话（${team.subagents.length}）'));
      if (team.subagents.isEmpty) {
        children.add(_emptyHint(c, '暂无子会话。'));
      } else {
        for (final s in team.subagents) {
          children.add(InkWell(
            // 子会话详情（第四轮反馈 3）：REST 只读窄口拉取后整页查看。
            onTap: () {
              final gateway = state.gateway;
              final leadId = state.sessionId;
              if (leadId == null || leadId.isEmpty) return;
              Navigator.pop(context); // 先收起底部面板再进历史页
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SubagentHistoryPage(
                    gateway: gateway,
                    leadSessionId: leadId,
                    subagent: s,
                    colors: c,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: _row(c, s.label.isEmpty ? s.id : s.label,
                s.mode.isEmpty ? 'subagent' : s.mode),
          ));
        }
      }
      // 底部三枚指挥话术：对照 companion TeamPanelSheet 的 CommandChips。
      // 只是发普通用户消息（无特殊协议），连接未就绪时禁用。
      final canSend = state.connectionState == GatewayState.ready;
      children.add(const SizedBox(height: DsSpacing.blockGap));
      children.add(Wrap(
        spacing: DsSpacing.settingsChipGap,
        runSpacing: DsSpacing.settingsChipGap,
        children: [
          _commandChip(c, '新建成员', '请新建一名团队成员，负责：', canSend),
          _commandChip(c, '分配任务', '请给团队成员分配任务：', canSend),
          _commandChip(c, '问进度', '汇报一下团队当前的成员状态和任务进度。', canSend),
        ],
      ));
    }
    return _sheetScaffold(
      c: c,
      title: '智能团队',
      subtitle: '成员 / 任务 / 子会话来自服务端 projections.values.agentTeam（只读展示）。',
      children: children,
    );
  }

  Widget _commandChip(DsColors c, String label, String text, bool canSend) {
    return Builder(
      builder: (context) => ActionChip(
        label: Text(label,
            style: DsTypography.caption.copyWith(color: c.labelPrimary)),
        backgroundColor: c.chipSelectedBg,
        onPressed: canSend
            ? () {
                Navigator.pop(context);
                state.send(text);
              }
            : null,
      ),
    );
  }
}

Widget _sectionTitle(DsColors c, String text) => Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Text(text,
          style: DsTypography.smallStrong.copyWith(color: c.labelPrimary)),
    );

// ---------- TODO 面板 ----------

void showTodoSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (context) => _TodoSheet(state: state, colors: colors),
  );
}

class _TodoSheet extends StatelessWidget {
  const _TodoSheet({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final todos = todoItems(state.projections);
    final completed = todos.where((t) => t.isCompleted).length;
    final children = <Widget>[];
    if (todos.isEmpty) {
      children.add(_emptyHint(c, '这个会话还没有待办任务。'));
    } else {
      children.add(_row(c, '进度', '已完成 $completed/${todos.length}'));
      for (final t in todos) {
        final color = t.isCompleted
            ? c.brand
            : (t.isInProgress ? c.labelPrimary : c.labelTertiary);
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpacing.liGap),
          child: Row(
            children: [
              Icon(
                t.isCompleted
                    ? Icons.check_circle_outline
                    : (t.isInProgress
                        ? Icons.timelapse
                        : Icons.radio_button_unchecked),
                size: 16,
                color: color,
              ),
              const SizedBox(width: DsSpacing.chipIconGap),
              Expanded(
                child: Text(t.content,
                    style: DsTypography.small.copyWith(color: c.labelPrimary)),
              ),
              const SizedBox(width: DsSpacing.chipGap),
              Text(t.status,
                  style: DsTypography.caption.copyWith(color: color)),
            ],
          ),
        ));
      }
    }
    return _sheetScaffold(
      c: c,
      title: '待办任务',
      subtitle: '列表来自服务端 projections.values.todos（只读展示，可能尚未产生）。',
      children: children,
    );
  }
}
