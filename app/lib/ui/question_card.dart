/// HITL 交互卡：DSH 向用户提问（userQuestions）与工具审批（approval）。
/// 从 chat_page 拆出的独立 widget（宪法 §7 控行数）。
///
/// 提问卡：每题列选项点选（multiSelect 多选），支持「自定义回答」文本；
/// 提交走 question-answer 帧。审批卡：允许一次 / 拒绝两键（协议无「始终允许」）。
library;

import 'package:flutter/material.dart';

import '../bridge/questions.dart';
import '../design/tokens.dart';
import 'hitl_state.dart';

/// 挂起提问/审批卡列表（放在消息列表上方；无挂起项时不占空间）。
class HitlPanel extends StatelessWidget {
  const HitlPanel({
    super.key,
    required this.state,
    required this.colors,
    required this.onAnswer,
    required this.onDecide,
  });

  final HitlState state;
  final DsColors colors;

  /// 提交一套答案（chat_state.answerQuestion）。
  final void Function(PendingQuestion, List<QuestionAnswerItem>) onAnswer;

  /// 审批决定（chat_state.decideApproval）。
  final void Function(PendingApproval, bool allow) onDecide;

  @override
  Widget build(BuildContext context) {
    final questions = state.pendingQuestions.values.toList();
    final approvals = state.pendingApprovals.values.toList();
    if (questions.isEmpty && approvals.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in approvals)
          _ApprovalCard(
            approval: a,
            colors: colors,
            onDecide: onDecide,
          ),
        for (final q in questions)
          _QuestionCard(question: q, colors: colors, onAnswer: onAnswer),
      ],
    );
  }
}

// ---------- 审批卡 ----------

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.colors,
    required this.onDecide,
  });

  final PendingApproval approval;
  final DsColors colors;
  final void Function(PendingApproval, bool) onDecide;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        DsSpacing.blockGap,
        DsSpacing.contentPadRight,
        0,
      ),
      padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
      decoration: BoxDecoration(
        color: colors.settingsWarnBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gavel,
                size: DsSpacing.processIconSize,
                color: colors.settingsWarnFg,
              ),
              const SizedBox(width: DsSpacing.processIconGap),
              Expanded(
                child: Text(
                  'DSH 请求使用 ${approval.toolName}',
                  style: DsTypography.smallStrong.copyWith(
                    color: colors.settingsWarnFg,
                  ),
                ),
              ),
            ],
          ),
          if (approval.reason != null && approval.reason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.liGap),
              child: Text(
                approval.reason!,
                style: DsTypography.caption.copyWith(
                  color: colors.settingsWarnFg,
                ),
              ),
            ),
          SizedBox(
            height: DsSpacing.composerButtonSize,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => onDecide(approval, false),
                  child: Text(
                    '拒绝',
                    style: DsTypography.small.copyWith(color: colors.danger),
                  ),
                ),
                const SizedBox(width: DsSpacing.chipGap),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.link,
                    foregroundColor: colors.onBrand,
                  ),
                  onPressed: () => onDecide(approval, true),
                  child: const Text('允许一次'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 提问卡 ----------

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    required this.question,
    required this.colors,
    required this.onAnswer,
  });

  final PendingQuestion question;
  final DsColors colors;
  final void Function(PendingQuestion, List<QuestionAnswerItem>) onAnswer;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  /// 每题已选 label 集（key=question.id）。
  final Map<String, Set<String>> _selected = {};

  /// 自定义回答输入框（key=question.id）。
  final Map<String, TextEditingController> _custom = {};

  DsColors get c => widget.colors;

  @override
  void dispose() {
    for (final ctl in _custom.values) {
      ctl.dispose();
    }
    super.dispose();
  }

  /// 能否提交：每题都要有选择（选项或自定义文本）。
  bool get _canSubmit {
    for (final q in widget.question.questions) {
      final picked = _selected[q.id] ?? const {};
      final text = _custom[q.id]?.text.trim() ?? '';
      if (picked.isEmpty && text.isEmpty) return false;
    }
    return true;
  }

  void _submit() {
    final answers = <QuestionAnswerItem>[];
    for (final q in widget.question.questions) {
      final text = _custom[q.id]?.text.trim() ?? '';
      answers.add(
        QuestionAnswerItem(
          id: q.id,
          selected: (_selected[q.id] ?? const {}).toList(),
          custom: text.isEmpty ? null : text,
        ),
      );
    }
    widget.onAnswer(widget.question, answers);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        DsSpacing.blockGap,
        DsSpacing.contentPadRight,
        0,
      ),
      padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
      decoration: BoxDecoration(
        color: c.chipSelectedBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final q in widget.question.questions) _oneQuestion(q),
          const SizedBox(height: DsSpacing.liGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _canSubmit ? c.link : c.drawerGroupLabel,
                foregroundColor: c.onBrand,
              ),
              onPressed: _canSubmit ? _submit : null,
              child: const Text('提交'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oneQuestion(UserQuestion q) {
    final picked = _selected.putIfAbsent(q.id, () => {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (q.header != null && q.header!.isNotEmpty)
          Text(
            q.header!,
            style: DsTypography.caption.copyWith(color: c.drawerGroupLabel),
          ),
        Text(q.question, style: DsTypography.smallStrong),
        if (q.detail != null && q.detail!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.liGap),
            child: Text(
              q.detail!,
              style: DsTypography.caption.copyWith(color: c.labelSecondary),
            ),
          ),
        const SizedBox(height: DsSpacing.chipIconGap),
        if (q.options.isEmpty)
          _customField(q)
        else ...[
          Wrap(
            spacing: DsSpacing.chipIconGap,
            runSpacing: DsSpacing.chipIconGap,
            children: [
              for (final opt in q.options)
                FilterChip(
                  label: Text(opt.label),
                  selected: picked.contains(opt.label),
                  onSelected: (on) => setState(() {
                    if (on) {
                      // 单选题新选一个时清掉旧的（bridge 每题独立 multiSelect）。
                      if (!q.multiSelect) picked.clear();
                      picked.add(opt.label);
                    } else {
                      picked.remove(opt.label);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: DsSpacing.chipIconGap),
          _customField(q),
        ],
        const SizedBox(height: DsSpacing.blockGap),
      ],
    );
  }

  Widget _customField(UserQuestion q) {
    return TextField(
      controller: _custom.putIfAbsent(q.id, TextEditingController.new),
      style: DsTypography.small,
      decoration: const InputDecoration(
        isDense: true,
        hintText: '或输入自定义回答…',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}
