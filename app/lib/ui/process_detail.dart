part of 'process_group.dart';

/// read 结果开窗的默认行数（官方 read.window）。
const int _readWindowLines = 8;

/// diff 详情默认渲染行数，超出收起为「… 其余 N 行」（官方 diff 视图）。
const int _diffMaxLines = 9;

/// 单条工具的完整详情（官方 tool detail 逆向）：
/// - edit/write → 行级差异块（复用 lib/ui/code_diff.dart，默认 9 行 +
///   「… 其余 N 行」展开）+ 结果（失败信息保留）；
/// - commands → BASH 代码块（command 字段）+ 结果正文；
/// - read → 结果正文按行开窗（默认 8 行 + 展开，顶部「显示 N 行中的 M 行」）；
/// - code（run_code）→ code 字段代码块 + 结果；
/// - web_search / web_fetch → 结果正文（完成且无结果 →「未找到结果」）；
/// - questions → 逐问卡 / verdict + 问题列表（官方 AskQuestionRow 特化）；
/// - 其余 → 输入 JSON（美化）+ 输出/错误 + 耗时；完成且无结果 →「无结果」。
class _ToolDetail extends StatelessWidget {
  const _ToolDetail({required this.call, required this.colors, this.answerable});

  final ToolCallInfo call;
  final DsColors colors;

  /// ask_user_question 的 answerable 查询（挂起表里还有同 callId 提问）。
  final bool Function(String callId)? answerable;

  String? _duration() {
    final ms = call.durationMs;
    if (ms == null || ms < 0) return null; // 负值（时钟倒退）不显示
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms ~/ 60000}m${(ms % 60000) ~/ 1000}s';
  }

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

  /// bash / tools.bash 的 command 字段（真机反馈 2026-11-04 第 6 项）。
  String? _bashCommand() {
    if (call.name != 'bash' && call.name != 'tools.bash') return null;
    return _argField('command');
  }

  /// 参数 JSON 里某个字符串字段的值（run_code 的 code / bash 的 command）。
  String? _argField(String key) {
    final raw = call.rawArguments;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        final v = parsed[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Widget _caption(String text) => Text(
    text,
    style: DsTypography.caption.copyWith(color: colors.labelTertiary),
  );

  Widget _captionColored(String text, Color color) =>
      Text(text, style: DsTypography.caption.copyWith(color: color));

  Widget _gap() => const SizedBox(height: DsSpacing.liGap);

  Widget _resultSection(DsColors c, String result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _captionColored(
          call.failed ? '错误' : '输出',
          call.failed ? c.danger : c.labelTertiary,
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
      ],
    );
  }

  Widget _resultSectionOrEmpty(DsColors c) {
    final result = call.resultText;
    if (result != null) return _resultSection(c, result);
    if (!call.failed && call.durationMs != null) return _caption('无结果');
    return const SizedBox.shrink();
  }

  List<Widget> _inputOutput(DsColors c) {
    final out = <Widget>[];
    final args = _prettyArgs();
    if (args != null) {
      out
        ..add(_caption('输入'))
        ..add(const SizedBox(height: 2))
        ..add(
          Text(
            args,
            style: DsTypography.codeBlock.copyWith(color: c.labelSecondary),
          ),
        )
        ..add(_gap());
    }
    out.add(_resultSectionOrEmpty(c));
    return out;
  }

  /// ask_user_question 详情（官方 AskQuestionRow 特化，替换通用 IN/OUT）：
  /// - 已回答（resultText 有 answers）→ 逐问卡：问题文本（主色）+ 答案行
  ///   （selected/custom；无答案 → 灰字「未回答」）；
  /// - 未回答 → verdict 行（pending 且挂起表可答 →「已继续；仍可回答」，
  ///   否则「已关闭」）+ 问题列表；
  /// - 参数不可解析 → 通用 IN/OUT 兜底。
  /// 偏差：答题面板 HitlPanel 常驻消息列表上方（官方是 composer 上方面板 +
  /// reopen 入口），交互保持现状。
  List<Widget> _askSections(DsColors c) {
    final questions = askQuestions(call.rawArguments);
    if (questions == null) return _inputOutput(c);
    final result = askResultOf(call.resultText);
    final answers = result?.answers;
    final out = <Widget>[];
    if (answers != null) {
      for (final q in questions) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.liGap),
            child: Text(
              q.question,
              style: DsTypography.smallStrong.copyWith(color: c.labelPrimary),
            ),
          ),
        );
        final matched = answers.where((a) => a.id == q.id).toList();
        final entry = matched.isEmpty ? null : matched.first;
        if (entry == null || !entry.answered) {
          out.add(
            Padding(padding: const EdgeInsets.only(top: 2), child: _caption('未回答')),
          );
        } else {
          final parts = [...entry.selected];
          final custom = entry.custom?.trim();
          if (custom != null && custom.isNotEmpty) parts.add(custom);
          out.add(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                parts.join('、'),
                style: DsTypography.small.copyWith(color: c.labelSecondary),
              ),
            ),
          );
        }
      }
      return out;
    }
    final pending = result?.pending == true;
    if (pending) {
      final answerable = this.answerable?.call(call.callId) ?? false;
      out.add(
        _captionColored(
          answerable ? '已继续；仍可回答' : '已关闭',
          c.labelTertiary,
        ),
      );
    }
    for (final q in questions) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: DsSpacing.liGap),
          child: Text(
            q.question,
            style: DsTypography.small.copyWith(color: c.labelSecondary),
          ),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final kind = activityKind(call.name);
    final dur = _duration();
    final children = <Widget>[];
    if (dur != null) {
      children.add(
        Padding(padding: const EdgeInsets.only(bottom: 4), child: _caption('耗时 $dur')),
      );
    }
    if (kind == ToolActivityKind.edit || kind == ToolActivityKind.write) {
      final diff = codeDiffOfCall(call.name, call.rawArguments);
      if (diff != null) {
        children
          ..add(_DiffBlock(diff: diff, colors: c))
          ..add(_gap());
        final result = call.resultText;
        if (result != null) children.add(_resultSection(c, result));
      } else {
        children.addAll(_inputOutput(c));
      }
    } else if (kind == ToolActivityKind.commands) {
      final cmd = _bashCommand();
      if (cmd != null) {
        children
          ..add(DsCodeBlock(name: 'BASH', code: cmd, colors: c))
          ..add(_gap());
      } else {
        final args = _prettyArgs();
        if (args != null) {
          children
            ..add(_caption('输入'))
            ..add(const SizedBox(height: 2))
            ..add(
              Text(
                args,
                style: DsTypography.codeBlock.copyWith(color: c.labelSecondary),
              ),
            )
            ..add(_gap());
        }
      }
      children.add(_resultSectionOrEmpty(c));
    } else if (kind == ToolActivityKind.read) {
      final result = call.resultText;
      if (result == null) {
        if (!call.failed && call.durationMs != null) children.add(_caption('无结果'));
      } else if (call.failed) {
        children.add(_resultSection(c, result));
      } else {
        final lines = result.split('\n');
        if (lines.length <= _readWindowLines) {
          children.add(_resultSection(c, result));
        } else {
          children
            ..add(_caption('显示 ${lines.length} 行中的 $_readWindowLines 行'))
            ..add(const SizedBox(height: 2))
            ..add(_ReadLines(lines: lines, shown: _readWindowLines, colors: c));
        }
      }
    } else if (kind == ToolActivityKind.code) {
      final code = _argField('code');
      if (code != null) {
        children
          ..add(DsCodeBlock(name: 'CODE', code: code, colors: c))
          ..add(_gap());
      }
      children.add(_resultSectionOrEmpty(c));
    } else if (kind == ToolActivityKind.webSearch ||
        kind == ToolActivityKind.webFetch) {
      final result = call.resultText;
      if (result != null) {
        children.add(_resultSection(c, result));
      } else if (!isCallRunning(call)) {
        children.add(_caption('未找到结果'));
      }
    } else if (kind == ToolActivityKind.questions) {
      children.addAll(_askSections(c));
    } else {
      children.addAll(_inputOutput(c));
    }
    return Padding(
      padding: const EdgeInsets.only(
        left: DsSpacing.processIconSize + DsSpacing.processIconGap + 3,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// edit/write 的行级差异块（官方 diff 视图）：路径 + +/- 行色
/// （DsColors.diffAdd/diffRemove + diffAddBg/diffRemoveBg 行底），默认
/// [_diffMaxLines] 行，超出收起为「… 其余 N 行」，点击展开全部。
class _DiffBlock extends StatefulWidget {
  const _DiffBlock({required this.diff, required this.colors});

  final CodeDiff diff;
  final DsColors colors;

  @override
  State<_DiffBlock> createState() => _DiffBlockState();
}

class _DiffBlockState extends State<_DiffBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final lines = widget.diff.lines;
    final shown = _expanded ? lines : lines.take(_diffMaxLines).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.diff.path,
          style: DsTypography.caption.copyWith(color: c.labelTertiary),
        ),
        const SizedBox(height: 2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final l in shown) _line(l)],
          ),
        ),
        if (!_expanded && lines.length > _diffMaxLines)
          InkWell(
            onTap: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '… 其余 ${lines.length - _diffMaxLines} 行',
                style: DsTypography.caption.copyWith(color: c.labelSecondary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _line(CodeDiffLine l) {
    final c = widget.colors;
    final (prefix, fg, bg) = switch (l.type) {
      CodeDiffLineType.add => ('+ ', c.diffAdd, c.diffAddBg),
      CodeDiffLineType.del => ('- ', c.diffRemove, c.diffRemoveBg),
      CodeDiffLineType.ctx => ('  ', c.mdCodeBlockText, c.none),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.liGap),
      child: Text(
        prefix + l.text,
        softWrap: false,
        style: DsTypography.codeBlock.copyWith(color: fg),
      ),
    );
  }
}

/// read 结果正文开窗：默认前 [_readWindowLines] 行，「… 其余 N 行」点击展开
/// 全部（官方 read.window + read.expandRest）。
class _ReadLines extends StatefulWidget {
  const _ReadLines({
    required this.lines,
    required this.shown,
    required this.colors,
  });

  final List<String> lines;
  final int shown;
  final DsColors colors;

  @override
  State<_ReadLines> createState() => _ReadLinesState();
}

class _ReadLinesState extends State<_ReadLines> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final lines = widget.lines;
    final visible = _expanded ? lines : lines.take(widget.shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          visible.join('\n'),
          style: DsTypography.codeBlock.copyWith(color: c.labelSecondary),
        ),
        if (!_expanded && lines.length > widget.shown)
          InkWell(
            onTap: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '… 其余 ${lines.length - widget.shown} 行',
                style: DsTypography.caption.copyWith(color: c.labelSecondary),
              ),
            ),
          ),
      ],
    );
  }
}
