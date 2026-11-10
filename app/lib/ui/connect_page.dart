/// 连接设置页（对应官方 App 的登录页位）：
/// 历史主机点击直连（真机反馈 2026-11-04 第 8 项）+ DSH1 配置文本导入
/// + 手动配对（bridge 地址 + 配对码）三级路径。
/// 配对/导入成功后凭证写入 DshCredentials 并 upsert 进 DshHosts。
library;

import 'package:flutter/material.dart';

import '../bridge/credentials.dart';
import '../bridge/gateway.dart';
import '../bridge/hosts.dart';
import '../design/tokens.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.onReady, required this.colors});

  final ValueChanged<GatewayClient> onReady;
  final DsColors colors;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _host = TextEditingController(text: 'http://127.0.0.1:3090');
  final _code = TextEditingController();
  final _config = TextEditingController();
  final _deviceId =
      'dsh-chat-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  bool _busy = false;
  bool _showImport = false;
  String? _error;
  DshHost? _failedHost; // 直连失败的主机，供「删除这条失效记录」定位
  List<DshHost> _hosts = const [];

  DsColors get c => widget.colors;

  @override
  void initState() {
    super.initState();
    DshHosts.load().then((hosts) {
      if (mounted) setState(() => _hosts = hosts);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    _config.dispose();
    super.dispose();
  }

  /// 建网关并进入聊天；成功即记录主机（幂等）。
  Future<void> _enterWith(GatewayClient gateway, String baseUrl,
      {String? token}) async {
    await DshCredentials.save(
      baseUrl: baseUrl,
      token: token ?? gateway.token ?? '',
    );
    await DshHosts.upsert(
      DshHost(
        id: DshHost.stableId(baseUrl),
        displayName: 'DSH Bridge',
        baseUrl: baseUrl,
        token: token ?? gateway.token,
        lastUsedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    widget.onReady(gateway);
  }

  Future<void> _connect() async {
    final host = _host.text.trim().replaceAll(RegExp(r'/+$'), '');
    final code = _code.text.trim();
    if (host.isEmpty || code.isEmpty) {
      setState(() => _error = '请填写 bridge 地址与配对码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _failedHost = null;
    });
    final gateway = GatewayClient(baseUrl: host);
    try {
      await gateway.pair(
        code: code,
        newDeviceId: _deviceId,
        name: 'DSH Chat (Flutter)',
      );
      await _enterWith(gateway, host);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failedHost = null;
        _error = '配对失败：$e';
      });
    }
  }

  /// 历史主机直连（有 token 才显示；失败给显式反馈——手动点击
  /// 不同于静默自动连接）。失败时记下该主机，供「删除失效记录」入口。
  Future<void> _connectHost(DshHost host) async {
    if (host.token == null || host.token!.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _failedHost = null;
    });
    final gateway = GatewayClient(baseUrl: host.baseUrl)..token = host.token;
    try {
      await gateway.connect();
      await _enterWith(gateway, host.baseUrl, token: host.token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failedHost = host;
        _error = '直连失败：$e（可重新配对）';
      });
    }
  }

  /// 删除单条历史主机（二次确认，避免误触）。刷新内存列表与错误提示。
  Future<void> _confirmRemove(DshHost host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条主机记录？'),
        content: Text('${host.displayName}\n${host.baseUrl}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DshHosts.remove(host);
    // 删掉的若正是「一次配对，此后自动连接」当前凭证，顺手清掉，
    // 避免下次启动仍拿过期 token 静默直连失败。
    if (DshCredentials.baseUrl == host.baseUrl) {
      await DshCredentials.clear();
    }
    final hosts = await DshHosts.load();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      if (_failedHost?.baseUrl == host.baseUrl) {
        _failedHost = null;
        _error = null;
      }
    });
  }

  /// 导入 DSH1 配置文本；成功直接连（有 token）或填表。
  Future<void> _importConfig() async {
    final text = _config.text;
    final host = decodeDsh1(text);
    if (host == null) {
      setState(() => _error = '配置格式无法识别（应为 DSH1: 开头的文本）');
      return;
    }
    setState(() => _error = null);
    if (host.token != null && host.token!.isNotEmpty) {
      await _connectHost(
        DshHost(
          id: host.id,
          displayName: host.displayName,
          baseUrl: host.baseUrl,
          token: host.token,
          lastUsedAt: host.lastUsedAt,
        ),
      );
    } else {
      // 无 token：只有地址，填进手动配对表单。
      _host.text = host.baseUrl;
      setState(() => _showImport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedHosts = _hosts.where((h) => (h.token ?? '').isNotEmpty).toList();
    return Scaffold(
      backgroundColor: c.bgBase,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                '连接到 DSH Bridge',
                textAlign: TextAlign.center,
                style: DsTypography.pageTitle.copyWith(
                  fontSize: 20,
                  color: c.labelPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '一次配对，此后自动连接',
                textAlign: TextAlign.center,
                style: DsTypography.small.copyWith(color: c.labelTertiary),
              ),
              const SizedBox(height: 28),
              if (savedHosts.isNotEmpty) ...[
                Text(
                  '历史主机',
                  style: DsTypography.smallStrong.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final h in savedHosts)
                  _HostCard(
                    host: h,
                    colors: c,
                    busy: _busy,
                    onTap: () => _connectHost(h),
                    onRemove: () => _confirmRemove(h),
                  ),
                const SizedBox(height: 20),
              ],
              InkWell(
                onTap: () => setState(() {
                  _showImport = !_showImport;
                  _error = null;
                }),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _showImport
                            ? Icons.expand_less
                            : Icons.download_outlined,
                        size: 18,
                        color: c.labelSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '导入桥配置（DSH1 文本）',
                        style: DsTypography.small.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showImport) ...[
                TextField(
                  controller: _config,
                  maxLines: 3,
                  style: DsTypography.inlineCode.copyWith(
                    color: c.labelPrimary,
                  ),
                  cursorColor: c.brand,
                  decoration: InputDecoration(
                    hintText: '粘贴 DSH1: 开头的配置文本',
                    hintStyle: DsTypography.inputPlaceholder.copyWith(
                      color: c.labelTertiary,
                    ),
                    filled: true,
                    fillColor: c.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _importConfig,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.brand,
                    side: BorderSide(color: c.brand),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('导入并连接'),
                ),
                const SizedBox(height: 20),
              ],
              _Field(
                controller: _host,
                hint: 'bridge 地址（http://IP:3090）',
                colors: c,
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _code,
                hint: '配对码（dsh 终端显示，10 分钟有效）',
                colors: c,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: DsTypography.small.copyWith(color: c.danger),
                ),
                if (_failedHost != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _confirmRemove(_failedHost!),
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: c.danger),
                      label: Text(
                        '删除这条失效记录',
                        style: DsTypography.small.copyWith(color: c.danger),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _connect,
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.onBrand,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.onBrand,
                        ),
                      )
                    : Text(
                        '配对并连接',
                        style: DsTypography.baseStrong.copyWith(
                          color: c.onBrand,
                        ),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史主机卡片：显示名 + 地址，点击直连；右侧独立删除按钮可移除过期/失效记录。
class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.colors,
    required this.busy,
    required this.onTap,
    required this.onRemove,
  });

  final DshHost host;
  final DsColors colors;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderL2),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: busy ? null : onTap,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.computer_outlined, size: 20, color: c.brand),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host.displayName,
                            style: DsTypography.base.copyWith(
                              color: c.labelPrimary,
                            ),
                          ),
                          Text(
                            host.baseUrl,
                            style: DsTypography.small.copyWith(
                              color: c.labelTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: c.labelTertiary),
                  ],
                ),
              ),
            ),
          ),
          // 删除按钮独立命中区，不与「点击直连」争夺 onTap（避免误连）。
          IconButton(
            onPressed: busy ? null : onRemove,
            icon: Icon(Icons.delete_outline, size: 20, color: c.labelTertiary),
            tooltip: '删除这条主机记录',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.only(right: 8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.colors,
  });

  final TextEditingController controller;
  final String hint;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: DsTypography.base.copyWith(color: colors.labelPrimary),
      cursorColor: colors.brand,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: DsTypography.inputPlaceholder.copyWith(
          color: colors.labelTertiary,
        ),
        filled: true,
        fillColor: colors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
