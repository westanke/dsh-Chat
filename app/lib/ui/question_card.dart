/// HITL 交互卡：DSH 向用户提问（userQuestions）与工具审批（approval）。
/// 从 chat_page 拆出的独立 widget（宪法 §7 控行数）。
///
/// 提问卡：每题列选项点选（multiSelect 多选），支持「自定义回答」文本；
/// 提交走 question-answer 帧。审批卡：允许一次 / 拒绝两键（协议无「始终允许」）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/questions.dart';
import '../design/tokens.dart';
import 'hitl_state.dart';
import 'window_class.dart';

/// 挂起提问/审批卡列表（放在消息列表上方；无挂起项时不占空间）。
class HitlPanel extends StatelessWidget {
  const HitlPanel({
    super.key,
    required this.state,
    required this.sessionId,
    required this.colors,
    required this.onAnswer,
    required this.onDecide,
  });

  final HitlState state;

  /// 只渲染当前会话的卡：挂起表是全连接的（含其它会话），不过滤会把别的
  /// 会话的提问/审批渲染进当前页（2026-11-16 真机反馈）。
  final String? sessionId;
  final DsColors colors;

  /// 提交一套答案（chat_state.answerQuestion）。
  final void Function(PendingQuestion, List<QuestionAnswerItem>) onAnswer;

  /// 审批决定（chat_state.decideApproval）。
  final void Function(PendingApproval, bool allow) onDecide;

  @override
  Widget build(BuildContext context) {
    final questions = state.sessionQuestions(sessionId);
    final approvals = state.sessionApprovals(sessionId);
    if (questions.isEmpty && approvals.isEmpty) return const SizedBox.shrink();
    // 限高 + 整面板滚动：题目/选项过多时提交按钮会被撑出屏幕外
    // （2026-11-15 用户反馈），故面板最大占屏高一半，超出可上下滑动。
    final maxH =
        MediaQuery.sizeOf(context).height * DsSpacing.hitlPanelMaxFraction;
    // 宽窗把卡片收在会话页读宽上（§4.16）：手机是无穷大，卡片照旧铺满正文列；
    // 平板横屏若不收，一张审批卡会被拉成 1181dp 的横幅。
    final maxW = windowClassOf(context).hitlMaxWidth;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      // heightFactor: 1 —— 按内容的高度收缩，不吃满 maxH（否则半屏空白留在
      // 列表顶上），横向才居中限宽。
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in approvals)
                  _ApprovalCard(
                    approval: a,
                    colors: colors,
                    onDecide: onDecide,
                  ),
                for (final q in questions)
                  _QuestionCard(
                    question: q,
                    colors: colors,
                    onAnswer: onAnswer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 审批卡 ----------

/// 审批卡（官方 approval 包语义）：
/// - 顶部 strip 状态条（小圆点 + 「等待审批」），决定提交后按钮全禁用
///   （官方 answered 态 disabled + aria-busy）；
/// - full-access 越权标题「工具 {toolName} 请求越权执行」，standard 保持
///   「DSH 请求使用 {toolName}」；
/// - reason 用代码等宽字体（官方 detail 是 command 代码字体）；
/// - 只有「拒绝」「允许一次」两键（协议 decideApproval 只收 allow bool，
///   官方亦无「始终允许」第三键）。
class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({
    required this.approval,
    required this.colors,
    required this.onDecide,
  });

  final PendingApproval approval;
  final DsColors colors;
  final void Function(PendingApproval, bool) onDecide;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  /// 本地 answered 态：决定已提交（等待 resolved 摘表）期间按钮全禁用。
  bool _answered = false;

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    final c = widget.colors;
    final title = approval.risk == 'full-access'
        ? '工具 ${approval.toolName} 请求越权执行'
        : 'DSH 请求使用 ${approval.toolName}';
    final reason = approval.reason;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        DsSpacing.screenPad,
        DsSpacing.blockGap,
        DsSpacing.contentPadRight,
        0,
      ),
      padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
      decoration: BoxDecoration(
        color: c.settingsWarnBg,
        borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: DsSpacing.liGap,
                height: DsSpacing.liGap,
                decoration: BoxDecoration(
                  color: c.settingsWarnFg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: DsSpacing.chipIconGap),
              Text(
                '等待审批',
                style: DsTypography.caption.copyWith(color: c.settingsWarnFg),
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.liGap),
          Row(
            children: [
              Icon(
                Icons.gavel,
                size: DsSpacing.processIconSize,
                color: c.settingsWarnFg,
              ),
              const SizedBox(width: DsSpacing.processIconGap),
              Expanded(
                child: Text(
                  title,
                  style: DsTypography.smallStrong.copyWith(
                    color: c.settingsWarnFg,
                  ),
                ),
              ),
            ],
          ),
          if (reason != null && reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.liGap),
              child: Text(
                reason,
                // 官方 detail 用代码等宽字体展示命令文本。
                style: DsTypography.codeBlockLabel.copyWith(
                  color: c.settingsWarnFg,
                ),
              ),
            ),
          // detail = 关联 tool/call 的命令预览（bridge redactApprovalText 截
          // 1200；官方 ApprovalFlow body：等宽代码字体 break-all）。与 reason
          // 同字体，超长命令靠 Flutter 默认按字符换行兜住。
          if (approval.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.liGap),
              child: Text(
                approval.detail!,
                style: DsTypography.codeBlockLabel.copyWith(
                  color: c.settingsWarnFg,
                ),
              ),
            ),
          SizedBox(
            height: DsSpacing.composerButtonSize,
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: _answered
                      ? null
                      : () {
                          setState(() => _answered = true);
                          widget.onDecide(approval, false);
                        },
                  child: Text(
                    '拒绝',
                    style: DsTypography.small.copyWith(
                      color: _answered ? c.labelTertiary : c.danger,
                    ),
                  ),
                ),
                const SizedBox(width: DsSpacing.chipGap),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.link,
                    foregroundColor: c.onBrand,
                  ),
                  onPressed: _answered
                      ? null
                      : () {
                          setState(() => _answered = true);
                          widget.onDecide(approval, true);
                        },
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
