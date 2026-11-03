/// 连接设置页（对应官方 App 的登录页位）：
/// 输入 bridge 地址 + 配对码 → WS 配对 → 进入聊天。
/// 配对成功后凭证写入 DshCredentials（shared_preferences），重启自动重连。
library;

import 'package:flutter/material.dart';

import '../bridge/credentials.dart';
import '../bridge/gateway.dart';
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
  final _deviceId =
      'dsh-chat-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  bool _busy = false;
  String? _error;

  DsColors get c => widget.colors;

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    super.dispose();
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
      await DshCredentials.save(baseUrl: host, token: gateway.token ?? '');
      if (!mounted) return;
      widget.onReady(gateway);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '配对失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
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
              const Spacer(),
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
              const Spacer(flex: 3),
            ],
          ),
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
