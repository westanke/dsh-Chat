/// 工具调用过程组：折叠成一行聚合标题（官方 Web 工具调用展示对齐 ·
/// 2026-11-17 批次），点开展开逐条明细，再点单条看完整参数与结果。
///
/// 标题不再用短语拼接（tool_call.dart 的 phraseText），改为
/// lib/ui/tool_present.dart 的 processGroupTitle：
/// - 进行中：「正在读取文件 · <运行细节>」（细节按官方 LIVE_TOOL_DETAIL_KEYS
///   取参，缺失回退最近思考流末段）；
/// - 完成：「已读取文件并写入文件」（kind 聚合，前 3 类，>3 类加「等」）。
///
/// 「通用设置 · 工作步骤展示」四档：
/// - concise 简洁：只渲染折叠行，不可展开、无展开箭头；
/// - standard 标准：可展开，工具行（标题+摘要）不带详情；
/// - detailed 详细：工具行 + 点开详情（diff/BASH/结果开窗/逐问卡）；
/// - verbose 完全展开：不聚合，会话页逐条平铺 DsToolRow（组行不渲染）。
///
/// 运行中轮的组由上层 forceOpen 撑开（官方 alwaysOpen 语义）；展开态托管在
/// ChatState（key=组内首个 callId），跨历史 reload 稳定。详情区拆在
/// process_detail.dart（part，宪法 §7 单文件 ≤500 行）。
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'code_diff.dart';
import 'md_code_block.dart';
import 'tool_present.dart';

part 'process_detail.dart';
class DsProcessGroup extends StatelessWidget {
  const DsProcessGroup({
    super.key,
    required this.group,
    required this.colors,
    required this.detail,
    required this.expanded,
    this.forceOpen = false,
    required this.onToggle,
    this.reasoningHint,
    this.answerable,
  });

  final ChatMessage group; // role == 'process'
  final DsColors colors;
  final WorkStepsDetail detail;

  /// 展开态（父层托管）；verbose 平铺不渲染本组件、concise 恒折叠。
  final bool expanded;

  /// 运行中轮的组恒展开（官方 alwaysOpen）；用户收起过则上层传 false。
  final bool forceOpen;
  final VoidCallback? onToggle;

  /// 运行中组无参数细节时的思考流兜底（上层取最近助手 reasoning 末段）。
  final String? reasoningHint;

  /// ask_user_question 的 answerable 查询（HITL 挂起表里有同 callId 提问）。
  final bool Function(String callId)? answerable;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final calls = group.toolCalls;
    final failed = calls.any((t) => t.failed);
    final running = calls.any(isCallRunning);
    // 运行中标题弱化（官方弱化色；无 shimmer 组件不新增大组件）。
    final headColor = failed || running ? c.labelTertiary : c.labelSecondary;
    final canExpand = detail != WorkStepsDetail.concise && calls.isNotEmpty;
    final open = expanded || forceOpen;
    final title = processGroupTitle(
      group,
      liveDetail: detail.liveProcessDetail,
      reasoningHint: reasoningHint,
    );

    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canExpand ? onToggle : null,
            child: SizedBox(
              height: DsSpacing.processRowHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      right: DsSpacing.processIconGap,
                    ),
                    child: Icon(
                      Icons.build_outlined,
                      size: DsSpacing.processIconSize,
                      color: headColor,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.small.copyWith(color: headColor),
                    ),
                  ),
                  if (canExpand)
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: headColor,
                    ),
                ],
              ),
            ),
          ),
          if (canExpand && open)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in calls)
                    DsToolRow(
                      call: t,
                      colors: c,
                      // standard 只到工具行（标题+摘要），不渲染详情。
                      allowDetail: detail != WorkStepsDetail.standard,
                      answerable: answerable,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条工具调用行（官方 tool row 五态结构）：
/// [kind 图标] + [标题] + [参数摘要] + [diff 增删统计] + [状态字] + [展开箭头]。
/// - running：右侧「运行中」（摘要仍显示已到的参数）；
/// - failed：图标/状态字红色，摘要槽位换成结果首行（官方 error 态）；
/// - ok：无状态字。
/// 点击整行展开详情（[allowDetail]=false 时 standard 档只显示行本体）；
/// 可展开 = 有结果或有参数（running 也可展开）。
class DsToolRow extends StatefulWidget {
  const DsToolRow({
    super.key,
    required this.call,
    required this.colors,
    required this.allowDetail,
    this.answerable,
  });

  final ToolCallInfo call;
  final DsColors colors;
  final bool allowDetail;
  final bool Function(String callId)? answerable;

  @override
  State<DsToolRow> createState() => _DsToolRowState();
}

class _DsToolRowState extends State<DsToolRow> {
  bool _detail = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final call = widget.call;
    final kind = activityKind(call.name);
    final running = isCallRunning(call);
    final expandable =
        widget.allowDetail && (call.resultText != null || call.rawArguments != null);
    final diff =
        kind == ToolActivityKind.edit || kind == ToolActivityKind.write
            ? codeDiffOfCall(call.name, call.rawArguments)
            : null;
    // 摘要：按 kind 键序取参；ask 工具换成状态机摘要；失败态换成结果首行红字
    // （官方 error 态），结果为空回退参数摘要。
    String? summary;
    Color summaryColor = c.labelTertiary;
    if (call.failed && (call.resultText?.trim().isNotEmpty ?? false)) {
      summary = call.resultText!.split('\n').first.trim();
      summaryColor = c.danger;
    } else if (kind == ToolActivityKind.questions) {
      summary = askSummary(call, widget.answerable ?? (_) => false) ??
          summarizeArgs(kind, call.rawArguments);
    } else {
      summary = summarizeArgs(kind, call.rawArguments) ?? call.summary;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _detail = !_detail) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: 3,
                    right: DsSpacing.processIconGap,
                  ),
                  child: Icon(
                    call.failed ? Icons.error_outline : toolIcon(kind),
                    size: DsSpacing.processIconSize,
                    color: call.failed ? c.danger : c.labelSecondary,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: toolTitle(call.name),
                          style: DsTypography.small.copyWith(
                            color: c.labelPrimary,
                          ),
                        ),
                        if (summary != null && summary.isNotEmpty)
                          TextSpan(
                            text: '  $summary',
                            style: DsTypography.codeBlockLabel.copyWith(
                              color: summaryColor,
                            ),
                          ),
                        if (diff != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text:
                                '+${_countDiff(diff, CodeDiffLineType.add)}',
                            style: DsTypography.codeBlockLabel.copyWith(
                              color: c.diffAdd,
                            ),
                          ),
                          const TextSpan(text: ' '),
                          TextSpan(
                            text:
                                '-${_countDiff(diff, CodeDiffLineType.del)}',
                            style: DsTypography.codeBlockLabel.copyWith(
                              color: c.diffRemove,
                            ),
                          ),
                        ],
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (running)
                  Padding(
                    padding: const EdgeInsets.only(left: DsSpacing.chipIconGap),
                    child: Text(
                      '运行中',
                      style: DsTypography.caption.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                  ),
                if (call.failed)
                  Padding(
                    padding: const EdgeInsets.only(left: DsSpacing.chipIconGap),
                    child: Text(
                      '失败',
                      style: DsTypography.caption.copyWith(color: c.danger),
                    ),
                  ),
                if (expandable)
                  Icon(
                    _detail ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: c.labelTertiary,
                  ),
              ],
            ),
          ),
          if (_detail && widget.allowDetail)
            _ToolDetail(
              call: call,
              colors: c,
              answerable: widget.answerable,
            ),
        ],
      ),
    );
  }
}

int _countDiff(CodeDiff diff, CodeDiffLineType type) =>
    diff.lines.where((l) => l.type == type).length;
