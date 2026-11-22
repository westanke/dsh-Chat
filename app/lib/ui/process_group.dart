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
import 'ask_present.dart';
import 'code_diff.dart';
import 'md_code_block.dart';
import 'thinking_ticker.dart';
import 'tool_glyph.dart';
import 'tool_present.dart';
import 'tool_titles.dart';

part 'process_detail.dart';

/// 过程组要渲染的行序列：优先用装配层给的到达顺序，回退到「先思考后工具」。
List<ToolCallInfo> _rowsOf(ChatMessage group) => group.processRows.isNotEmpty
    ? group.processRows
    : <ToolCallInfo>[...group.thoughts, ...group.toolCalls];

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
    final canExpand = detail != WorkStepsDetail.concise &&
        (calls.isNotEmpty || group.thoughts.isNotEmpty);
    final open = expanded || forceOpen;
    final title = processGroupTitle(
      group,
      liveDetail: detail.liveProcessDetail,
      reasoningHint: reasoningHint,
    );

    // 行间距由列表行框统一给（chat_row_gap.dart），这里不再自带顶距。
    return Column(
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
                  child: ToolGlyph(
                    colors: c,
                    kind: _groupActivityKind(group),
                  ),
                ),
                // 官方 ProcessGroupHeader：chevron 紧跟图标、都在标题左侧。
                if (canExpand)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: DsSpacing.chipIconGap,
                    ),
                    child: Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 16,
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
                // 思考与工具**按到达顺序混排**（dsh-go 折叠列表就是这么排的）。
                // processRows 为空时（老装配路径/纯工具组）退回「先思考后工具」。
                for (final t in _rowsOf(group))
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
    );
  }
}

/// 单条工具调用行（官方 ToolRow 逐项对齐）：
/// [kind 图标] + [标题] + 2px 圆点 + [摘要] + [diff 增删统计] + [退出徽标]
/// + [展开箭头]。
/// - run-state（正在准备调用/运行中/失败/已停止）只作文案进 Semantics，
///   官方把它放在 visuallyHidden 里，行上不显示文字；
/// - running：TextShimmer（未做动画，仅色弱化）+ 摘要显示已到的参数；
/// - failed：图标红色，无 exit 标记时摘要换成结果首行红字（官方 error 态）；
/// - ok：无任何状态提示。
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

  /// 行 hover 态：官方 diff 增删统计只在展开或 hover 时显色。
  bool _hover = false;

  /// 读屏文案（官方 visuallyHidden 的 stateStatus）：标题 + 状态词 + 展开提示。
  String _a11yLabel(
    ToolCallInfo call,
    ToolRowState state,
    bool Function(String callId) answerable,
  ) {
    final kind = activityKind(call.name);
    final buffer = StringBuffer(toolTitle(call.name));
    switch (state) {
      case ToolRowState.preparing:
        buffer.write('，正在准备调用');
      case ToolRowState.running:
        buffer.write('，运行中');
      case ToolRowState.stopped:
        buffer.write('，已停止');
      case ToolRowState.failed:
        buffer.write('，失败');
      case ToolRowState.cancelled:
      case ToolRowState.ok:
        break;
    }
    if (kind == ToolActivityKind.questions) {
      final ask = askSummary(call, answerable);
      if (ask != null) buffer.write('，$ask');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final call = widget.call;
    final kind = activityKind(call.name);
    final rowState = toolRowStateOf(call);
    final expandable =
        widget.allowDetail &&
        (call.resultText != null || call.rawArguments != null);
    final diff = kind == ToolActivityKind.edit || kind == ToolActivityKind.write
        ? codeDiffOfCall(call.name, call.rawArguments)
        : null;
    // 摘要：按 kind 键序取参；ask 工具换成状态机摘要；失败态换结果正文——
    // 官方语义：error 态**无 exitLabel 时** summary 才换 errorSummary（结果
    // 首行红字），带 exit 标记时保持参数摘要、退出状态交给行尾徽标。
    final exit = parseExitStatus(call.resultText);
    final hasResult = call.resultText?.trim().isNotEmpty ?? false;
    String? summary;
    Color summaryColor = c.labelTertiary;
    if (call.failed && hasResult) {
      if (exit != null) {
        summary = summarizeArgs(kind, call.rawArguments) ?? call.summary;
      } else {
        summary = call.resultText!.split('\n').first.trim();
        summaryColor = c.danger;
      }
    } else if (kind == ToolActivityKind.questions) {
      summary =
          askSummary(call, widget.answerable ?? (_) => false) ??
          summarizeArgs(kind, call.rawArguments);
    } else {
      final base = summarizeArgs(kind, call.rawArguments) ?? call.summary;
      // 官方 toolRowModel：generic 工具（未注册名）摘要带原工具名前缀
      // [toolName, base].join(' · ')。
      summary = isGenericTool(call.name) && base != null && base.isNotEmpty
          ? '${bareToolName(call.name)} · $base'
          : base;
    }
    // 行尾退出状态徽标（exit code 不是协议字段，从结果文本尾部解析；
    // 非 0 / signal 红色，exit 0 用弱化色）。
    final badge = exitBadgeLabel(exit);
    final badgeColor = exitBadgeIsError(exit) ? c.danger : c.labelTertiary;
    // 官方 diff 增删统计只在行展开或 hover 时显色（折叠继承行色）。
    final highlighted = _detail || _hover;

    // 进行中的思考行用多行滚动预览（dsh-go thinking_pill 的 ticker）。
    final liveThought =
        kind == ToolActivityKind.thinking &&
        isToolRowLive(call) &&
        (call.resultText ?? '').trim().isNotEmpty;
    // dsh-go StreamRow：整行最小高 32（24 图标 + 上下各 4），左右各 8 内衬。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DsSpacing.streamMinHeight),
      child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.streamBleed,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            // 官方 visuallyHidden 状态文案（读屏可用，屏幕上不显示）。
            label: _a11yLabel(
              call,
              rowState,
              widget.answerable ?? (_) => false,
            ),
            button: expandable,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: InkWell(
                onTap: expandable
                    ? () => setState(() => _detail = !_detail)
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 图形列固定 24 宽、图标在其中居中（streamLead）。
                    SizedBox(
                      width: DsSpacing.streamLead,
                      child: Center(
                        child: ToolGlyph(
                          colors: c,
                          kind: kind,
                          failed: call.failed,
                          // 进行中的思考行底块呼吸（dsh-go ThinkingOrb）。
                          pulsing:
                              kind == ToolActivityKind.thinking &&
                              isToolRowLive(call),
                        ),
                      ),
                    ),
                    const SizedBox(width: DsSpacing.streamGap),
                    Expanded(
                      child: liveThought
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  toolTitle(call.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DsTypography.small.copyWith(
                                    fontSize: 14,
                                    height: 1.3,
                                    color: c.labelSecondary,
                                  ),
                                ),
                                // 思考进行中：多行滚动预览（dsh-go ticker）。
                                ThinkingTicker(
                                  colors: c,
                                  text: call.resultText ?? '',
                                ),
                              ],
                            )
                          : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: toolTitle(call.name),
                              style: DsTypography.small.copyWith(
                                fontSize: 14,
                                height: 1.3,
                                color: c.labelSecondary,
                              ),
                            ),
                            // 标题与摘要之间的 2px 圆点分隔（官方 .sep，
                            // 色 label-caption → 近似 labelTertiary）。
                            if (summary != null && summary.isNotEmpty) ...[
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Container(
                                  width: DsSpacing.sepDot,
                                  height: DsSpacing.sepDot,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: DsSpacing.sepGap,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.labelTertiary,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: summary,
                                // dsh-go thinking_pill：思考预览是常规体
                                // bodySmall 13 / 1.3 / textTertiary，不是等宽体；
                                // 工具行摘要仍用等宽体。
                                style: kind == ToolActivityKind.thinking
                                    ? DsTypography.small.copyWith(
                                        fontSize: 13,
                                        height: 1.3,
                                        color: summaryColor,
                                      )
                                    : DsTypography.codeBlockLabel.copyWith(
                                        color: summaryColor,
                                      ),
                              ),
                            ],
                            // diff 增删统计：官方只在展开或 hover 时显色
                            //（折叠态继承行色）。
                            if (diff != null) ...[
                              const TextSpan(text: '  '),
                              TextSpan(
                                text:
                                    '+${_countDiff(diff, CodeDiffLineType.add)}',
                                style: DsTypography.codeBlockLabel.copyWith(
                                  color: highlighted
                                      ? c.diffAdd
                                      : c.labelTertiary,
                                ),
                              ),
                              const TextSpan(text: ' '),
                              TextSpan(
                                text:
                                    '-${_countDiff(diff, CodeDiffLineType.del)}',
                                style: DsTypography.codeBlockLabel.copyWith(
                                  color: highlighted
                                      ? c.diffRemove
                                      : c.labelTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 行尾退出徽标（官方 ExitCodeBadge：红点恒红 + 标签）。
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: DsSpacing.exitBadgeGapLeft,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: DsSpacing.exitBadgeDot,
                              height: DsSpacing.exitBadgeDot,
                              decoration: BoxDecoration(
                                color: c.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: DsSpacing.exitBadgeGap),
                            Text(
                              badge,
                              style: DsTypography.codeBlockLabel.copyWith(
                                color: badgeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 官方 ToolRow：run-state 文案走 visuallyHidden，只给读屏
                    // 引擎，行上不渲染「运行中/失败/已停止」文字（状态靠图标
                    // 色彩、TextShimmer、摘要红字表达）。
                    // dsh-go StreamChevron：16 号箭头，280ms 旋转半圈表示展开。
                    if (expandable) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _detail ? 0.5 : 0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        child: Icon(
                          Icons.expand_more,
                          size: 16,
                          color: c.labelTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_detail && widget.allowDetail)
            _ToolDetail(call: call, colors: c, answerable: widget.answerable),
        ],
      ),
      ),
    );
  }
}

/// 过程组图标的活动类型：运行中取最新 live 调用（官方 live.activity），
/// 完成组取首类（官方 counts[0].kind 的近似），空组按 thinking。
ToolActivityKind _groupActivityKind(ChatMessage group) {
  // 思考段也是组内活动：dsh-go 的运行中组头会显示思考图标。
  for (final call in [...group.thoughts, ...group.toolCalls]) {
    if (isToolRowLive(call)) return activityKind(call.name);
  }
  if (group.toolCalls.isEmpty) return ToolActivityKind.thinking;
  return activityKind(group.toolCalls.first.name);
}

int _countDiff(CodeDiff diff, CodeDiffLineType type) =>
    diff.lines.where((l) => l.type == type).length;
