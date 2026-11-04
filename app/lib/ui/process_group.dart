/// 工具调用过程组：折叠成一行（「修改了文件，执行了命令」），点开展开逐条明细，
/// 再点单条看完整参数与结果（真机反馈 2026-11-04：执行了命令要点开能查看）。
///
/// 为什么需要它：一次工具密集的回合会在会话里留下十几条 `tool/call`，把助手正文
/// 冲得七零八落。DSH 桌面端与官方 App 的做法一致 —— 连续的工具调用收成**一行**
/// 摘要，正文始终是主角。
///
/// 措辞（修改了文件 / 执行了命令 / 读取了图片…）来自 lib/bridge/tool_call.dart 的
/// toolPhrases，与 dsh-companion 的 ChatToolPresentation 同源；详情布局参考
/// companion 的 ChatToolBlocks/ChatToolDetail（参数 JSON + 结果正文 + 耗时）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'md_code_block.dart';

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

/// 展开后的单条工具调用：图标 + 动作短语 + 参数摘要（+ 失败标记）；
/// 点击整行再展开完整详情（参数 JSON + 结果正文 + 耗时）。
class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.call, required this.colors});

  final ToolCallInfo call;
  final DsColors colors;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _detail = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final call = widget.call;
    final summary = call.summary;
    final color = call.failed ? c.labelTertiary : c.labelSecondary;
    final hasDetail =
        call.resultText != null ||
        call.durationMs != null ||
        _rawArgs() != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasDetail ? () => setState(() => _detail = !_detail) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: 3,
                    right: DsSpacing.processIconGap,
                  ),
                  child: Icon(
                    call.failed
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
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
                if (hasDetail)
                  Icon(
                    _detail ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: c.labelTertiary,
                  ),
              ],
            ),
          ),
          if (_detail) _ToolDetail(call: call, colors: c),
        ],
      ),
    );
  }

  /// arguments 原串（JSON 字符串），详情里直接解析。
  String? _rawArgs() => widget.call.rawArguments;
}

/// 单条工具的完整详情：参数 JSON（美化）+ 结果正文 + 耗时。
class _ToolDetail extends StatelessWidget {
  const _ToolDetail({required this.call, required this.colors});

  final ToolCallInfo call;
  final DsColors colors;

  String? _prettyArgs() {
    final raw = call.rawArguments;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        final out = <String>[];
        parsed.forEach((k, v) {
          var vText = '$v';
          if (vText.length > 200) vText = '${vText.substring(0, 200)}…';
          out.add('$k: $vText');
        });
        return out.isEmpty ? null : out.join('\n');
      }
    } on FormatException {
      return raw;
    }
    return raw;
  }

  /// bash 命令原文（真机反馈 2026-11-04 第 6 项）：name 为 bash / tools.bash
  /// 时从 arguments 里取 command 字段，按 BASH 代码块渲染（DsCodeBlock）。
  String? _bashCommand() {
    if (call.name != 'bash' && call.name != 'tools.bash') return null;
    final raw = call.rawArguments;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        final cmd = parsed['command'];
        if (cmd is String && cmd.trim().isNotEmpty) return cmd;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _duration() {
    final ms = call.durationMs;
    if (ms == null || ms < 0) return null; // 负值（时钟倒退）不显示
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms ~/ 60000}m${(ms % 60000) ~/ 1000}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final bash = _bashCommand();
    final args = bash == null ? _prettyArgs() : null;
    final result = call.resultText;
    final dur = _duration();
    return Padding(
      padding: const EdgeInsets.only(
        left: DsSpacing.processIconSize + DsSpacing.processIconGap + 3,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dur != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '耗时 $dur',
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ),
          // bash 命令按 BASH 代码块样式（语法高亮 + 复制按钮 + 语言名头）。
          if (bash != null) ...[
            DsCodeBlock(name: 'BASH', code: bash, colors: c),
            const SizedBox(height: 6),
          ] else if (args != null) ...[
            Text(
              '输入',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
            const SizedBox(height: 2),
            Text(
              args,
              style: DsTypography.codeBlock.copyWith(
                color: c.labelSecondary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (result != null) ...[
            Text(
              call.failed ? '错误' : '输出',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
            const SizedBox(height: 2),
            Text(
              result,
              maxLines: 24,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.codeBlock.copyWith(
                color: call.failed ? c.danger : c.labelSecondary,
              ),
            ),
          ] else if (!call.failed && call.durationMs != null)
            Text(
              '结果为空',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
        ],
      ),
    );
  }
}