// ---------- 行渲染层：一行 → 一个控件 ----------
//
// 列表只认行（chat_rows.dart），这里只负责把行画出来。
// 行级 widget 缓存命中与否看行对象是否 identical（见 chat_rows.dart 的
// ChatRowsCache），所以这里的返回对象要尽量稳定。

library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'chat_expand_state.dart';
import 'chat_message_items.dart';
import 'chat_rows.dart';
import 'chat_state.dart';
import 'chat_thinking.dart';
import 'md_view.dart';
import 'process_group.dart';
import 'turn_process_row.dart';
import 'work_steps.dart';

/// 行 → 控件。
///
/// 依赖可变状态（过程组的展开态、轮尾的聚合态）的行包一层
/// ListenableBuilder：状态一变就自己重建，不必让整张列表缓存失效。
Widget chatRowView(
  ChatRow row, {
  required ChatState state,
  required DsColors colors,
  required void Function(TurnRange turn) onToggleTurn,
}) {
  switch (row) {
    case final UserRow r:
      return MessageItem(
        message: r.message,
        colors: colors,
        index: r.index,
        state: state,
      );
    case final AssistantRow r:
      return MessageItem(
        message: r.message,
        colors: colors,
        index: r.index,
        state: state,
      );
    case final ProcessRow r:
      return ListenableBuilder(
        listenable: state,
        builder: (context, _) => MessageItem(
          message: r.message,
          colors: colors,
          index: r.index,
          state: state,
        ),
      );
    case final ErrorRow r:
      return MessageItem(
        message: r.message,
        colors: colors,
        index: r.index,
        state: state,
      );
    case final FilesRow r:
      return MessageItem(
        message: r.message,
        colors: colors,
        index: r.index,
        state: state,
      );
    case final CommandRow r:
      return MessageItem(
        message: r.message,
        colors: colors,
        index: r.index,
        state: state,
      );
    case final TurnEndRow r:
      return ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final info = turnEndInfoOf(
            state.messages,
            r.turn,
            canCollapse: appSettings.workStepsDetail.foldCompletedTurns,
            isGroupExpanded: state.isGroupExpanded,
          );
          if (info == null) return const SizedBox.shrink();
          return TurnProcessRow(
            info: info,
            colors: colors,
            onToggle: info.canCollapse ? () => onToggleTurn(r.turn) : null,
          );
        },
      );
    case HistoryMoreRow():
      return _HistoryMoreButton(state: state, colors: colors);
    case HistoryTruncatedRow():
      return _HistoryTruncatedNotice(colors: colors);
    case final StreamingProcessRow r:
      return _StreamingProcessGroup(state: state, colors: colors, group: r.group);
    case StreamingTextRow():
      return _StreamingText(state: state, colors: colors);
    case MaxTokensRow():
      return _MaxTokensNotice(colors: colors);
    case final LinkErrorRow r:
      // 行间距由列表行框统一给，这里不再自带顶距。
      return Text(
        r.message,
        style: DsTypography.small.copyWith(color: colors.labelTertiary),
      );
  }
}

/// 新行入场淡入（token rowFadeIn）。只对新行播，老行不重播。
class RowFadeIn extends StatefulWidget {
  const RowFadeIn({super.key, required this.child});

  final Widget child;

  @override
  State<RowFadeIn> createState() => _RowFadeInState();
}

class _RowFadeInState extends State<RowFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DsMotion.rowFadeIn,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: widget.child,
    );
  }
}

/// 「加载更早消息」入口：服务端还有更早事件时的显式入口
/// （真机反馈 2026-11-04 第 5 项：上滑触发不可靠）。
class _HistoryMoreButton extends StatelessWidget {
  const _HistoryMoreButton({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: DsSpacing.blockGap),
        child: state.loadingOlder
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton.icon(
                onPressed: state.loadOlder,
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('加载更早消息'),
              ),
      ),
    );
  }
}

/// 「会话过长，更早的部分未显示」提示行：服务端按字节预算裁剪过历史
/// （history-byte-budget-v1），最新的一屏也可能不全，必须明说。
class _HistoryTruncatedNotice extends StatelessWidget {
  const _HistoryTruncatedNotice({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.blockGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 14, color: colors.labelSecondary),
          const SizedBox(width: DsSpacing.liGap),
          Flexible(
            child: Text(
              '会话过长，更早的部分未显示',
              style: DsTypography.small.copyWith(color: colors.labelSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流式过程组（工具调用实时缓冲的合成组）：官方行为对齐——工具行在流式
/// 正文上方，组恒展开（用户手动收起过则尊重 _forceDismissed）；标题走
/// processGroupTitle 的 preparing 词表（「正在准备…」）。
class _StreamingProcessGroup extends StatelessWidget {
  const _StreamingProcessGroup({
    required this.state,
    required this.colors,
    required this.group,
  });

  final ChatState state;
  final DsColors colors;
  final ChatMessage group;

  @override
  Widget build(BuildContext context) {
    final detail = appSettings.workStepsDetail;
    final key = processGroupKeyOf(group);
    final forceOpen = !state.isForceOpenDismissed(key);
    bool answerable(String callId) =>
        state.hitl.sessionQuestions(state.sessionId).any(
          (q) => q.callId == callId,
        );
    return DsProcessGroup(
      group: group,
      colors: colors,
      detail: detail,
      expanded: state.isGroupExpanded(key),
      forceOpen: forceOpen,
      onToggle: () => state.toggleProcessGroup(
        key,
        open: state.isGroupExpanded(key) || forceOpen,
      ),
      // reasoning 兜底不接：流式思考在 _StreamingText 的 ThinkingRow 展示。
      answerable: answerable,
    );
  }
}

/// 流式正文（正在生成的助手回复）。
class _StreamingText extends StatelessWidget {
  const _StreamingText({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.streamReasoning.isNotEmpty)
          ThinkingRow(
            text: state.streamReasoning,
            colors: colors,
            streaming: true,
            // 正文还没开始就是「思考中」；正文一旦出来，实时窗口收成一行摘要。
            answerStarted: state.streamText.isNotEmpty,
          ),
        DsMarkdownView(
          text: state.streamText,
          colors: colors,
          streaming: true,
        ),
      ],
    );
  }
}

/// 「回答被截断」提示行（官方 client.js:6707 文案逐字）：轮结束
/// reason=max-tokens 时置位，新轮 turn.start / send() 复位。
class _MaxTokensNotice extends StatelessWidget {
  const _MaxTokensNotice({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.thinkHMargin,
        DsSpacing.liGap,
        DsSpacing.thinkHMargin,
        DsSpacing.liGap,
      ),
      decoration: BoxDecoration(
        color: c.settingsWarnBg,
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      ),
      child: Text(
        '回答被截断，已有输出保留在对话中。发送“继续”可让模型接着输出。',
        style: DsTypography.small.copyWith(color: c.labelTertiary),
      ),
    );
  }
}
