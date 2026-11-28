/// 会话信息面板（对照 dsh-Go `ui/session/conversation_overview.dart` 与
/// `session_detail_page.dart` 的 SessionHero：顶部「信息 | 插件」分段、
/// 会话标题、「共 N 轮」、三元大数字、工作区/模型/主机三行）。
///
/// 只借结构与文案，配色/字号/间距全部走本仓 token。数据口径（不造数，
/// 每一列都能指到真实来源）：
/// - 轮数：`turnsOf(messages)`，每条 user 消息开启一轮；
/// - 步骤：消息里 `toolCalls` 的条数之和（流式中的过程组也算）；
/// - 用时：已完成轮的 `turnStartedAt/turnFinishedAt`，缺时退回轮内过程组
///   首尾；一轮都取不到真实起止时**整列不显示**；
/// - 改动文件：非 failed 的 edit/write 调用里出现过的不同路径数；
/// - 模型：`gateway.sessionModels(sid)` → `SessionModels.current`，读不到
///   就不显示这一行（老桥没有 models 帧是常态，不是错误）；
/// - 工作区：当前会话的 `workspaceTitle`，为空就不显示这一行；
/// - 主机：`deviceLabel`（与顶栏 hostLabel 同源）+ 连接方式。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/models_view.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'model_sheet.dart';
import 'plugins_panel.dart';
import 'session_info_stats.dart';
import 'window_class.dart';

/// 弹出会话信息面板。[onShare] 由入口（顶栏菜单）提供：面板本身不持有
/// 导出逻辑，避免与 chat_overflow_menu.dart 互相 import 成环。
Future<void> showSessionInfoSheet(
  BuildContext context,
  ChatState state,
  DsColors colors, {
  Future<void> Function()? onShare,
}) {
  return showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (_) => SessionInfoContent(
      state: state,
      colors: colors,
      onShare: onShare,
    ),
  );
}

class SessionInfoContent extends StatefulWidget {
  const SessionInfoContent({super.key, 
    required this.state,
    required this.colors,
    this.onShare,
  });

  final ChatState state;
  final DsColors colors;
  final Future<void> Function()? onShare;

  @override
  State<SessionInfoContent> createState() => _SessionInfoSheetState();
}

class _SessionInfoSheetState extends State<SessionInfoContent> {
  bool _plugins = false;

  /// models 帧的当前选择；null = 还没读到（或读不到，行直接消失）。
  ModelSelection? _model;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    final sid = widget.state.sessionId;
    if (sid == null || sid.isEmpty) return;
    try {
      final models = SessionModels.parse(
        await widget.state.gateway.sessionModels(sid),
      );
      if (!mounted) return;
      setState(() => _model = models.current);
    } on RequestException {
      // 老桥没有 models 帧是常态：不报错，不显示模型行。
      if (!mounted) return;
      setState(() => _model = null);
    }
  }

  Future<void> _openModelSheet() async {
    final sid = widget.state.sessionId;
    if (sid == null || sid.isEmpty) return;
    // 返回服务端确认后的 selected（问题2：面板不只回「变了没有」）。
    final selection = await showModelSheet(
      context,
      colors: widget.colors,
      gateway: widget.state.gateway,
      sessionId: sid,
    );
    if (selection == null) return;
    await widget.state.reloadHistory();
    await _loadModel();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return SafeArea(
      child: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpacing.screenPad,
              DsSpacing.liGap,
              DsSpacing.screenPad,
              DsSpacing.blockGap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(c),
                const SizedBox(height: DsSpacing.blockGap),
                if (_plugins) _pluginsBody(c) else _infoBody(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(DsColors c) {
    return SizedBox(
      height: DsSpacing.topBarHeight,
      child: Row(
        children: [
          _tab(
            '信息',
            selected: !_plugins,
            c: c,
            onTap: () => setState(() => _plugins = false),
          ),
          const SizedBox(width: DsSpacing.chipIconGap),
          _tab(
            '插件',
            selected: _plugins,
            c: c,
            onTap: () => setState(() => _plugins = true),
          ),
          const Spacer(),
          if (widget.onShare != null)
            Tooltip(
              message: '分享会话',
              child: InkWell(
                onTap: widget.onShare,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(DsSpacing.cellPadV),
                  child: Icon(
                    Icons.share_outlined,
                    size: DsSpacing.fabIconSize,
                    color: c.labelSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    required DsColors c,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.cellPadH,
          vertical: DsSpacing.nestedListGap,
        ),
        decoration: BoxDecoration(
          color: selected ? c.chipSelectedBg : null,
          borderRadius: BorderRadius.circular(DsSpacing.chipRadius),
        ),
        child: Text(
          label,
          style: (selected ? DsTypography.smallStrong : DsTypography.small)
              .copyWith(color: selected ? c.chipSelectedFg : c.labelSecondary),
        ),
      ),
    );
  }

  Widget _infoBody(DsColors c) {
    final state = widget.state;
    final stats = sessionInfoStatsOf(
      state.messages,
      streaming: state.streaming,
    );
    final title = state.sessionTitle;
    final session = _currentSession(state);
    final workspace = (session?.workspaceTitle ?? '').trim();
    final model = _model;
    final modelName = model?.model.trim() ?? '';
    final effort = modelName.isEmpty
        ? ''
        : reasoningEffortLabel(model!.reasoningEffort ?? '');
    final cells = <_Stat>[
      if (stats.elapsedMs != null)
        _Stat(value: _formatElapsed(stats.elapsedMs!), label: '用时'),
      _Stat(value: '${stats.steps}', label: '步骤'),
      if (stats.changedFiles != null)
        _Stat(value: '${stats.changedFiles}', label: '改动文件'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: DsTypography.h4.copyWith(color: c.labelPrimary),
          ),
          const SizedBox(height: DsSpacing.liGap),
        ],
        Text(
          stats.turns == 0
              ? '还没有完整的一轮'
              : '共 ${stats.turns} 轮${stats.running ? ' · 进行中' : ''}',
          style: DsTypography.small.copyWith(color: c.labelSecondary),
        ),
        const SizedBox(height: DsSpacing.blockGap),
        _statsCard(cells, c),
        const SizedBox(height: DsSpacing.blockGap),
        _infoRows(c, workspace: workspace, modelName: modelName, effort: effort),
      ],
    );
  }

  Widget _statsCard(List<_Stat> cells, DsColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: DsSpacing.blockGap,
        horizontal: DsSpacing.cellPadH,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: c.borderL1),
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      ),
      child: Row(
        children: [
          for (final cell in cells)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cell.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.h3.copyWith(
                      color: c.labelPrimary,
                      fontFamily: DsTypography.codeFamily,
                    ),
                  ),
                  const SizedBox(height: DsSpacing.nestedListGap),
                  Text(
                    cell.label,
                    style: DsTypography.caption.copyWith(
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

  Widget _infoRows(
    DsColors c, {
    required String workspace,
    required String modelName,
    required String effort,
  }) {
    final rows = <Widget>[
      if (workspace.isNotEmpty)
        _InfoRow(
          icon: Icons.folder_outlined,
          label: '工作区',
          value: workspace,
          colors: c,
        ),
      if (modelName.isNotEmpty)
        _InfoRow(
          icon: Icons.memory,
          label: '模型',
          value: effort.isEmpty ? modelName : '$modelName · $effort',
          colors: c,
          onTap: _openModelSheet,
        ),
      _InfoRow(
        icon: Icons.dns_outlined,
        label: '主机',
        value: _hostValue(widget.state),
        colors: c,
      ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.borderL1),
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: DsSpacing.cellPadV,
                indent: DsSpacing.cellPadH,
                endIndent: DsSpacing.cellPadH,
                color: c.borderL1,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _pluginsBody(DsColors c) =>
      PluginsPanel(state: widget.state, colors: c);
}

/// 三元统计里的一格。
class _Stat {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final DsColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DsSpacing.settingsRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpacing.cellPadH),
          child: Row(
            children: [
              Icon(icon, size: DsSpacing.actionIconSize, color: c.labelTertiary),
              const SizedBox(width: DsSpacing.settingsIconGap),
              Text(
                label,
                style: DsTypography.small.copyWith(color: c.labelSecondary),
              ),
              const SizedBox(width: DsSpacing.settingsIconGap),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: DsTypography.smallStrong.copyWith(
                    color: c.labelPrimary,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: DsSpacing.nestedListGap),
                Icon(
                  Icons.chevron_right,
                  size: DsSpacing.actionIconSize,
                  color: c.labelTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前会话（sessions 是抽屉列表，按 id 找当前这条）。
DshSession? _currentSession(ChatState state) {
  final sid = state.sessionId;
  if (sid == null || sid.isEmpty) return null;
  for (final s in state.sessions) {
    if (s.id == sid) return s;
  }
  return null;
}

/// 主机行：设备名（顶栏 hostLabel 同源）+ 连接方式。客户端始终连的是
/// 另一台机器上的桥，所以「远程」是事实；地址以 127.0.0.1/localhost
/// 出现时（adb reverse）标「本机」。
String _hostValue(ChatState state) {
  final name = state.deviceLabel.trim();
  final addr = state.connectionLabel;
  final local =
      addr.startsWith('127.0.0.1') ||
      addr.startsWith('localhost') ||
      addr.startsWith('[::1]');
  final kind = local ? '本机' : '远程';
  return name.isEmpty ? kind : '$name · $kind';
}

/// 用时格式化：一小时以内 `mm:ss`，以上 `h:mm:ss`（与 dsh-Go formatClock 同形）。
String _formatElapsed(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
