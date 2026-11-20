/// 「代码工作视图」抽屉（对照官方 App「通用设置 · 显示代码工作视图」· D 项）。
///
/// 入口：聊天页 ⋯ 菜单（`appSettings.codeWorkView` 开启时出现）。
/// 三段：
/// 1. 运行轨迹 —— 复用 projection_sheets.dart 的 [TrajectoryBody]，不复制逻辑；
/// 2. 本轮代码差异 —— codeDiffsOfTurn 取当前轮 edit/write 工具参数，
///    渲染 +/- 行色代码块（diffAdd/diffRemove，docs/design-tokens.md §4.9）；
/// 3. Agent 预设 —— REST GET /chat/agent-presets 列表，空白会话可切换
///    （PUT /chat/sessions/{sid}/agent-preset，409=预设已锁）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'code_diff.dart';
import 'projection_sheets.dart';
import 'window_class.dart';

/// 单个差异块最多渲染的行数（write 大文件保护；超出截断并提示总行数）。
const int _maxDiffLines = 400;

void showWorkViewSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (context) => _WorkViewSheet(state: state, colors: colors),
  );
}

/// 从会话清单里找当前会话（抽屉/顶栏同款查找方式）。
DshSession? _currentSessionOf(ChatState state) {
  final sid = state.sessionId;
  if (sid == null || sid.isEmpty) return null;
  for (final s in state.sessions) {
    if (s.id == sid) return s;
  }
  return null;
}

class _WorkViewSheet extends StatefulWidget {
  const _WorkViewSheet({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  State<_WorkViewSheet> createState() => _WorkViewSheetState();
}

class _WorkViewSheetState extends State<_WorkViewSheet> {
  List<GatewayAgentPreset>? _presets;
  String? _presetsError;
  String? _switchError;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      final items = await widget.state.gateway.agentPresets();
      if (!mounted) return;
      setState(() {
        _presets = items;
        _presetsError = null;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() => _presetsError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _presetsError = '预设列表加载失败');
    }
  }

  Future<void> _selectPreset(GatewayAgentPreset preset) async {
    final state = widget.state;
    final sid = state.sessionId;
    if (sid == null || _switching) return;
    setState(() {
      _switching = true;
      _switchError = null;
    });
    try {
      await state.gateway.selectAgentPreset(sid, preset.id);
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换 Agent 预设：${preset.name}')),
      );
      // 会话清单里的 agentPreset 字段随桥端视图更新（抽屉/下次打开同步）。
      await state.loadSessions();
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _switching = false;
        // 409 = AGENT_PRESET_LOCKED：会话非 blank 已锁定。
        _switchError = e.code == 'HTTP_409' ? '已锁定，仅空白会话可切换' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _switching = false;
        _switchError = '切换失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final state = widget.state;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.screenPad,
          DsSpacing.blockGap,
          DsSpacing.screenPad,
          DsSpacing.blockGap,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('代码工作视图', style: DsTypography.h4),
                const SizedBox(height: DsSpacing.liGap),
                Text(
                  '运行轨迹、本轮代码差异与 Agent 预设（本地与桥端汇总）。',
                  style: DsTypography.small.copyWith(color: c.labelSecondary),
                ),
                const SizedBox(height: DsSpacing.blockGap),
                _sectionTitle(c, '运行轨迹'),
                Text(
                  '按轮次查看消息、工具调用、耗时和 Token 等运行记录。',
                  style: DsTypography.caption.copyWith(color: c.labelTertiary),
                ),
                const SizedBox(height: DsSpacing.liGap),
                TrajectoryBody(state: state, colors: c),
                _sectionTitle(c, '本轮代码差异'),
                ..._diffSection(state, c),
                _sectionTitle(c, 'Agent 预设'),
                ..._presetSection(state, c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(DsColors c, String text) => Padding(
        padding: const EdgeInsets.only(
          top: DsSpacing.blockGap,
          bottom: DsSpacing.liGap,
        ),
        child: Text(text, style: DsTypography.smallStrong.copyWith(color: c.labelSecondary)),
      );

  List<Widget> _diffSection(ChatState state, DsColors c) {
    final diffs = codeDiffsOfTurn(state.messages);
    if (diffs.isEmpty) {
      return [_hint(c, '本轮没有代码改动。')];
    }
    return [for (final d in diffs) _diffBlock(d, c)];
  }

  Widget _diffBlock(CodeDiff diff, DsColors c) {
    final truncated = diff.lines.length > _maxDiffLines;
    final lines = truncated ? diff.lines.sublist(0, _maxDiffLines) : diff.lines;
    return Container(
      margin: const EdgeInsets.only(top: DsSpacing.liGap),
      padding: const EdgeInsets.all(DsSpacing.codeBlockPad),
      decoration: BoxDecoration(
        color: c.mdCodeBlockBg,
        borderRadius: const BorderRadius.all(
          Radius.circular(DsSpacing.codeBlockRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.difference_outlined, size: 14, color: c.labelTertiary),
              const SizedBox(width: DsSpacing.liGap),
              Expanded(
                child: Text(
                  diff.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.codeBlockLabel.copyWith(color: c.labelPrimary),
                ),
              ),
              Text(
                diff.kind == 'edit' ? '修改' : '写入',
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.liGap),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines) _diffLine(line, c),
              ],
            ),
          ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.liGap),
              child: Text(
                '… 其余 ${diff.lines.length - _maxDiffLines} 行',
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _diffLine(CodeDiffLine line, DsColors c) {
    final (prefix, color, bg) = switch (line.type) {
      CodeDiffLineType.add => ('+ ', c.diffAdd, c.diffAddBg),
      CodeDiffLineType.del => ('- ', c.diffRemove, c.diffRemoveBg),
      CodeDiffLineType.ctx => ('  ', c.mdCodeBlockText, c.none),
    };
    return Container(
      color: bg,
      child: Text(
        '$prefix${line.text}',
        style: DsTypography.codeBlock.copyWith(color: color),
      ),
    );
  }

  List<Widget> _presetSection(ChatState state, DsColors c) {
    final session = _currentSessionOf(state);
    final sid = state.sessionId;
    if (sid == null || sid.isEmpty) {
      return [_hint(c, '请先打开一个会话再选择 Agent 预设。')];
    }
    // 锁定判定：messages 非空或桥端标记非 blank（openapi：首条消息后锁定）。
    final locked = state.messages.isNotEmpty || (session?.blank == false);
    final error = _presetsError;
    final presets = _presets;
    final currentId = session?.agentPreset;
    if (error != null) {
      return [_hint(c, error, danger: true)];
    }
    if (presets == null) {
      return [
        const Padding(
          padding: EdgeInsets.all(DsSpacing.liGap),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (presets.isEmpty) {
      return [_hint(c, '桥端暂无可用预设。')];
    }
    return [
      if (locked)
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
          child: Text(
            '首条消息后锁定，仅空白会话可切换。',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ),
      if (_switchError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
          child: Text(
            _switchError!,
            style: DsTypography.caption.copyWith(color: c.danger),
          ),
        ),
      for (final p in presets) _presetRow(p, c, currentId, locked),
    ];
  }

  Widget _presetRow(
    GatewayAgentPreset preset,
    DsColors c,
    String? currentId,
    bool locked,
  ) {
    final isCurrent = preset.id == currentId;
    final selectable = !locked && preset.available && !_switching;
    final labelColor = selectable ? c.labelPrimary : c.labelTertiary;
    return InkWell(
      onTap: selectable ? () => _selectPreset(preset) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DsSpacing.liGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: DsSpacing.chipIconGap),
              child: Icon(
                isCurrent ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isCurrent ? c.brand : c.labelTertiary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          preset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsTypography.base.copyWith(color: labelColor),
                        ),
                      ),
                      if (preset.isDefault)
                        Padding(
                          padding: const EdgeInsets.only(left: DsSpacing.liGap),
                          child: Text(
                            '默认',
                            style: DsTypography.caption.copyWith(color: c.brand),
                          ),
                        ),
                    ],
                  ),
                  if (preset.description != null &&
                      preset.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        preset.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.caption.copyWith(color: c.labelTertiary),
                      ),
                    ),
                  if (!preset.available)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '当前不可用',
                        style: DsTypography.caption.copyWith(color: c.labelTertiary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(DsColors c, String text, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(top: DsSpacing.liGap, bottom: DsSpacing.liGap),
        child: Text(
          text,
          style: DsTypography.small.copyWith(
            color: danger ? c.danger : c.labelTertiary,
          ),
        ),
      );
}
