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
      setState(() {
        _busy = false;
        _error = '配对失败：$e';
      });
    }
  }

  /// 历史主机直连（有 token 才显示；失败给显式反馈——手动点击
  /// 不同于静默自动连接）。
  Future<void> _connectHost(DshHost host) async {
    if (host.token == null || host.token!.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final gateway = GatewayClient(baseUrl: host.baseUrl)..token = host.token;
    try {
      await gateway.connect();
      await _enterWith(gateway, host.baseUrl, token: host.token);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '直连失败：$e（可重新配对）';
      });
    }
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

/// 历史主机卡片：显示名 + 地址，点击直连。
class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.colors,
    required this.busy,
    required this.onTap,
  });

  final DshHost host;
  final DsColors colors;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.borderL2),
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
                    style: DsTypography.base.copyWith(color: c.labelPrimary),
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
