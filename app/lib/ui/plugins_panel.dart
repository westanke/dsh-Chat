/// 会话信息面板里的「插件」页：列表、开关与说明文档。
///
/// 不带 Scaffold / 弹层外壳，直接嵌进 `SessionInfoContent` 的滚动 Column；
/// 数据与错误文案全部由 [PluginCenter] 提供。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/plugin_center.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'window_class.dart';

/// 插件管理面板。
///
/// 用法（接进 session_info_sheet 的插件 TAB）：
/// ```dart
/// PluginsPanel(state: widget.state, colors: widget.colors)
/// ```
class PluginsPanel extends StatefulWidget {
  const PluginsPanel({
    super.key,
    required this.state,
    required this.colors,
    this.center,
  });

  final ChatState state;
  final DsColors colors;

  /// 测试注入用；为空时用 [ChatState.gateway] 创建 [PluginCenter]。
  final PluginCenter? center;

  @override
  State<PluginsPanel> createState() => _PluginsPanelState();
}

class _PluginsPanelState extends State<PluginsPanel> {
  late PluginCenter _center;
  bool _loading = true;
  bool _unsupported = false;
  String? _error;
  List<PluginBundle> _plugins = const <PluginBundle>[];

  /// 正在切换开关的插件（内核 bundle name），用于防连点。
  final Set<String> _busy = <String>{};

  /// 请求序号：重试时丢弃过期应答。
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _center = widget.center ?? PluginCenter(widget.state.gateway);
    if (_center.available) {
      unawaited(_load());
    } else {
      _loading = false;
      _unsupported = true;
    }
  }

  Future<void> _load() async {
    final seq = ++_request;
    if (!_center.available) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unsupported = true;
        _error = null;
        _plugins = const <PluginBundle>[];
      });
      return;
    }
    setState(() {
      _loading = true;
      _unsupported = false;
      _error = null;
    });
    try {
      final plugins = await _center.listPlugins();
      if (!mounted || seq != _request) return;
      setState(() {
        _plugins = plugins;
        _loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted || seq != _request) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || seq != _request) return;
      setState(() {
        _loading = false;
        _error = '插件列表加载失败，请重试';
      });
    }
  }

  Future<void> _toggle(PluginBundle bundle, bool enabled) async {
    if (_busy.contains(bundle.id)) return;
    setState(() => _busy.add(bundle.id));
    try {
      final effective = await _center.setPluginEnabled(bundle.id, enabled);
      if (!mounted) return;
      setState(() {
        _plugins = <PluginBundle>[
          for (final plugin in _plugins)
            if (plugin.id == bundle.id)
              plugin.copyWith(enabled: effective)
            else
              plugin,
        ];
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      _toast('插件开关失败，请重试');
    } finally {
      if (mounted) setState(() => _busy.remove(bundle.id));
    }
  }

  Future<void> _openDetail(PluginBundle bundle) async {
    final colors = widget.colors;
    await showModalBottomSheet<void>(
      context: context,
      constraints: modalSheetConstraints(context),
      backgroundColor: colors.bgLayer1,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.settingsCardRadius),
        ),
      ),
      builder: (_) => _PluginDetailSheet(
        bundle: bundle,
        detail: _center.pluginDetail(bundle.id),
        colors: colors,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    if (_loading) {
      return SizedBox(
        height: DsSpacing.settingsRowMinHeight * 2,
        child: Center(
          child: SizedBox(
            width: DsSpacing.fabIconSize,
            height: DsSpacing.fabIconSize,
            child: CircularProgressIndicator(
              strokeWidth: DsSpacing.quoteBarWidth,
              color: c.brand,
            ),
          ),
        ),
      );
    }
    if (_unsupported) {
      return _messageBox(
        c,
        icon: Icons.extension_off_outlined,
        title: '当前连接不支持插件管理',
        body: '需要主机启用 kernel-call-v1，并开放 pluginManager 端点。',
        retryLabel: '重试',
        onRetry: () => unawaited(_load()),
      );
    }
    if (_error != null) {
      return _messageBox(
        c,
        icon: Icons.error_outline,
        title: '插件列表加载失败',
        body: _error!,
        retryLabel: '重试',
        onRetry: () => unawaited(_load()),
      );
    }
    if (_plugins.isEmpty) {
      return _messageBox(
        c,
        icon: Icons.extension_outlined,
        title: '还没有安装插件',
        body: '连接的主机没有可管理的插件包。',
        retryLabel: '刷新',
        onRetry: () => unawaited(_load()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < _plugins.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: DsSpacing.liGap),
          _PluginRow(
            bundle: _plugins[i],
            colors: c,
            busy: _busy.contains(_plugins[i].id),
            onOpen: () => unawaited(_openDetail(_plugins[i])),
            onToggle: (value) => unawaited(_toggle(_plugins[i], value)),
          ),
        ],
      ],
    );
  }

  Widget _messageBox(
    DsColors c, {
    required IconData icon,
    required String title,
    required String body,
    required String retryLabel,
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
      child: Column(
        children: <Widget>[
          Icon(icon, size: DsSpacing.fabSize, color: c.labelTertiary),
          const SizedBox(height: DsSpacing.liGap),
          Text(
            title,
            textAlign: TextAlign.center,
            style: DsTypography.baseStrong.copyWith(color: c.labelPrimary),
          ),
          const SizedBox(height: DsSpacing.nestedListGap),
          Text(
            body,
            textAlign: TextAlign.center,
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          ),
          const SizedBox(height: DsSpacing.liGap),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({
    required this.bundle,
    required this.colors,
    required this.busy,
    required this.onOpen,
    required this.onToggle,
  });

  final PluginBundle bundle;
  final DsColors colors;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final note = _bundleNote(bundle);
    return ListTile(
      onTap: onOpen,
      tileColor: c.settingsSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsCardPadH,
      ),
      minVerticalPadding: DsSpacing.settingsCardPadV,
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              bundle.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.base.copyWith(color: c.labelPrimary),
            ),
          ),
          if (bundle.version.isNotEmpty) ...<Widget>[
            const SizedBox(width: DsSpacing.settingsChipGap),
            Text(
              'v${bundle.version}',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
          ],
        ],
      ),
      subtitle: (bundle.description.isEmpty && note == null)
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                top: DsSpacing.drawerItemSubtitleGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (bundle.description.isNotEmpty)
                    Text(
                      bundle.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.small.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                  if (note != null)
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.caption.copyWith(
                        color: bundle.errorText.isEmpty
                            ? c.labelTertiary
                            : c.danger,
                      ),
                    ),
                ],
              ),
            ),
      trailing: Switch(
        value: bundle.enabled,
        activeThumbColor: c.brand,
        onChanged: busy || !bundle.manageable ? null : onToggle,
      ),
    );
  }
}

class _PluginDetailSheet extends StatelessWidget {
  const _PluginDetailSheet({
    required this.bundle,
    required this.detail,
    required this.colors,
  });

  final PluginBundle bundle;
  final Future<PluginDetail> detail;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DsSpacing.screenPad,
            DsSpacing.liGap,
            DsSpacing.screenPad,
            DsSpacing.blockGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.extension_outlined,
                    size: DsSpacing.fabIconSize,
                    color: c.brand,
                  ),
                  const SizedBox(width: DsSpacing.settingsIconGap),
                  Expanded(
                    child: Text(
                      bundle.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.h4.copyWith(color: c.labelPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    color: c.labelSecondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: DsSpacing.blockGap),
              _field(c, '版本', bundle.version.isEmpty ? '未知' : bundle.version),
              if (bundle.description.isNotEmpty)
                _field(c, '说明', bundle.description),
              if (bundle.entries.isNotEmpty)
                _field(
                  c,
                  '入口',
                  bundle.entries
                      .map((entry) => entry.label)
                      .where((label) => label.isNotEmpty)
                      .join('\n'),
                ),
              if (bundle.hasPermissions)
                _field(c, '权限', bundle.permissions.join('\n')),
              const SizedBox(height: DsSpacing.liGap),
              Text(
                '说明文档',
                style: DsTypography.smallStrong.copyWith(
                  color: c.labelSecondary,
                ),
              ),
              const SizedBox(height: DsSpacing.liGap),
              _doc(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(DsColors c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.liGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
          ),
          const SizedBox(height: DsSpacing.drawerItemSubtitleGap),
          Text(
            value,
            style: DsTypography.small.copyWith(color: c.labelPrimary),
          ),
        ],
      ),
    );
  }

  Widget _doc(DsColors c) {
    return FutureBuilder<PluginDetail>(
      future: detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(
            '正在读取说明…',
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          );
        }
        final error = snapshot.error;
        if (error != null) {
          final message =
              error is RequestException ? error.message : '插件文档加载失败';
          return Text(
            message,
            style: DsTypography.small.copyWith(color: c.settingsWarnFg),
          );
        }
        final doc = snapshot.data;
        if (doc == null || !doc.hasMarkdown) {
          return Text(
            '这个插件没有附带说明文档。',
            style: DsTypography.small.copyWith(color: c.labelTertiary),
          );
        }
        return Text(
          doc.markdown,
          style: DsTypography.small.copyWith(color: c.labelSecondary),
        );
      },
    );
  }
}

/// 行内状态注脚：内核报错 > 只读原因 > 缺失。
String? _bundleNote(PluginBundle bundle) {
  if (bundle.errorText.isNotEmpty) return '状态异常：${bundle.errorText}';
  if (bundle.readOnlyReason.isNotEmpty) {
    return switch (bundle.readOnlyReason) {
      'management-required' => '需在主机端管理',
      'unaddressable' => '当前连接无法定位该插件',
      _ => bundle.readOnlyReason,
    };
  }
  if (bundle.availability == 'missing') return '插件包缺失';
  return null;
}
