/// 工具调用过程组：折叠成一行（「修改了文件，执行了命令」），点开展开逐条明细。
///
/// 为什么需要它：一次工具密集的回合会在会话里留下十几条 `tool/call`，把助手正文
/// 冲得七零八落。DSH 桌面端与官方 App 的做法一致 —— 连续的工具调用收成**一行**
/// 摘要，正文始终是主角。
///
/// 措辞（修改了文件 / 执行了命令 / 读取了文件…）来自 lib/bridge/models.dart 的
/// toolPhrases，与 dsh-companion 的 ChatToolPresentation 同源。
library;

import 'package:flutter/material.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';

class DsProcessGroup extends StatefulWidget {
  const DsProcessGroup({super.key, required this.group, required this.colors});

  final ChatMessage group; // role == 'process'
  final DsColors colors;

  @override
  State<DsProcessGroup> createState() => _DsProcessGroupState();
}

class _DsProcessGroupState extends State<DsProcessGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final calls = widget.group.toolCalls;
    final failed = calls.any((t) => t.failed);
    final headColor = failed ? c.labelTertiary : c.labelSecondary;

    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: calls.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
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
                      widget.group.phraseText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.small.copyWith(color: headColor),
                    ),
                  ),
                  if (calls.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: headColor,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final t in calls) _ToolRow(call: t, colors: c)],
              ),
            ),
        ],
      ),
    );
  }
}

/// 展开后的单条工具调用：图标 + 动作短语 + 参数摘要（+ 失败标记）。
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.call, required this.colors});

  final ToolCallInfo call;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final summary = call.summary;
    final color = call.failed ? c.labelTertiary : c.labelSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 3,
              right: DsSpacing.processIconGap,
            ),
            child: Icon(
              call.failed ? Icons.error_outline : Icons.check_circle_outline,
              size: DsSpacing.processIconSize,
              color: color,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.phrases.join('，'),
                  style: DsTypography.small.copyWith(color: color),
                ),
                if (summary != null)
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.codeBlockLabel.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
