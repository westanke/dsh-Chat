part of 'settings_page.dart';

// ---------- 连接（只读） ----------

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.colors, required this.gateway});

  final DsColors colors;
  final GatewayClient? gateway;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final gw = gateway;
    final base = gw?.baseUrl ?? DshCredentials.baseUrl ?? '';
    final device = gw?.device;
    final deviceName = _deviceName(device);
    final deviceId = _asString(device?['id']);
    final scopes = _scopes(device);
    return _Section(
      colors: c,
      title: '连接',
      children: [
        if (gw == null)
          _InfoRow(
            colors: c,
            icon: Icons.cloud_off_outlined,
            title: '未连接',
            subtitle: '配对后此处显示设备与授权信息',
          )
        else ...[
          StreamBuilder<GatewayState>(
            stream: gw.state,
            initialData: gw.currentState,
            builder: (context, snap) => _InfoRow(
              colors: c,
              icon: Icons.cloud_done_outlined,
              title: _stateLabel(snap.data ?? gw.currentState),
              subtitle: base.isEmpty ? 'bridge 地址未知' : base,
            ),
          ),
          if (base.startsWith('http://'))
            _WarningBanner(
              colors: c,
              text: '当前为 HTTP 明文连接，仅在可信局域网内使用。',
            ),
          _InfoRow(
            colors: c,
            icon: Icons.phone_android_outlined,
            title: deviceName.isEmpty ? 'DSH Bridge' : deviceName,
            subtitle: deviceId.isEmpty ? '设备 ID 未提供' : deviceId,
          ),
          if (scopes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.settingsCardPadH,
                vertical: DsSpacing.settingsCardPadV,
              ),
              child: Wrap(
                spacing: DsSpacing.settingsChipGap,
                runSpacing: DsSpacing.settingsChipGap,
                children: [
                  for (final s in scopes) _ScopeChip(colors: c, label: s),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.settingsCardPadH,
              vertical: DsSpacing.settingsCardPadV,
            ),
            child: Text(
              '服务端的命名空间、模型、插件与 provider 设置走 REST '
              '/api/v1/settings/*，写入需要 settings.write 授权（设备默认不含）。'
              '本版本只提供上方本地偏好，不摆无法生效的开关。',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
          ),
        ],
      ],
    );
  }

  static String _deviceName(Map<String, dynamic>? device) =>
      _asString(device?['name']);

  static String _asString(Object? value) =>
      value is String ? value.trim() : '';

  static List<String> _scopes(Map<String, dynamic>? device) {
    final raw = device?['scopes'];
    if (raw is List) {
      return List<String>.unmodifiable(raw.map((e) => e.toString()));
    }
    return const <String>[];
  }

  static String _stateLabel(GatewayState s) => switch (s) {
        GatewayState.idle => '未连接',
        GatewayState.connecting => '连接中',
        GatewayState.ready => '已连接',
        GatewayState.closed => '已断开',
        GatewayState.authFailed => '鉴权失败',
      };
}

// ---------- 外观 ----------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final follows = appSettings.fontFollowsSystem;
    return _Section(
      colors: c,
      title: '外观',
      children: [
        _SegmentedRow<AppThemeMode>(
          colors: c,
          label: '界面风格',
          values: AppThemeMode.values,
          selected: appSettings.themeMode,
          labels: const {
            AppThemeMode.system: '跟随系统',
            AppThemeMode.light: '浅色',
            AppThemeMode.dark: '深色',
          },
          onChanged: appSettings.setThemeMode,
        ),
        _SwitchRow(
          colors: c,
          title: '字号跟随系统',
          description: '开启后使用系统无障碍字号，忽略下方应用内缩放。',
          value: follows,
          onChanged: appSettings.setFontFollowsSystem,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.settingsCardPadH,
            vertical: DsSpacing.settingsCardPadV,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '应用内字号缩放',
                      style: DsTypography.base.copyWith(
                        color: c.labelPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${appSettings.fontScale.toStringAsFixed(1)}×',
                    style: DsTypography.smallStrong.copyWith(
                      color: c.brand,
                    ),
                  ),
                ],
              ),
              Slider(
                value: appSettings.fontScale,
                min: 0.8,
                max: 1.5,
                divisions: 7, // 0.8 / 0.9 / … / 1.5，与 companion 的 8 落点一致
                label: appSettings.fontScale.toStringAsFixed(1),
                activeColor: c.brand,
                inactiveColor: c.inputBorder,
                onChanged: follows ? null : appSettings.setFontScale,
              ),
              Text(
                '在系统字号基础上相乘（不覆盖无障碍设置），范围 0.8×–1.5×。',
                style: DsTypography.caption.copyWith(
                  color: c.labelTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- 发送 ----------

class _SendSection extends StatelessWidget {
  const _SendSection({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _Section(
      colors: c,
      title: '发送',
      children: [
        _SegmentedRow<BusySendMode>(
          colors: c,
          label: '繁忙时发送模式',
          values: BusySendMode.values,
          selected: appSettings.busySendMode,
          labels: const {
            BusySendMode.queue: '排队',
            BusySendMode.steer: '插话',
          },
          onChanged: appSettings.setBusySendMode,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.settingsCardPadH,
            vertical: DsSpacing.settingsCardPadV,
          ),
          child: Text(
            '运行中再发消息时：排队 = 当前回合结束后处理（message.mode=queue）；'
            '插话 = 立即打断当前回合（message.mode=steer）。',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ),
      ],
    );
  }
}

// ---------- 诊断 ----------

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _Section(
      colors: c,
      title: '诊断',
      children: [
        _SwitchRow(
          colors: c,
          title: '记录诊断日志',
          description: '写入应用私有目录 dsh.log，关闭后不再追加。',
          value: appSettings.diagLog,
          onChanged: appSettings.setDiagLog,
        ),
        _ActionRow(
          colors: c,
          icon: Icons.description_outlined,
          title: '读取诊断日志',
          subtitle: '复制全文到剪贴板',
          onTap: () => _copyLog(context),
        ),
      ],
    );
  }

  Future<void> _copyLog(BuildContext context) async {
    final text = DshLog.read();
    final messenger = ScaffoldMessenger.of(context);
    if (text.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('暂无诊断日志', style: DsTypography.small),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(
        content: Text('诊断日志已复制', style: DsTypography.small),
      ),
    );
  }
}

// ---------- 关于 ----------

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.colors});

  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return _Section(
      colors: c,
      title: '关于',
      children: [
        _InfoRow(
          colors: c,
          icon: Icons.chat_bubble_outline,
          title: 'DSH Chat',
          subtitle: 'Flutter client for dsh-remote-bridge',
        ),
        _InfoRow(
          colors: c,
          icon: Icons.tag_outlined,
          title: '版本 $_appVersion',
          subtitle: '与 app/pubspec.yaml 的 version 保持一致',
        ),
        _InfoRow(
          colors: c,
          icon: Icons.cable_outlined,
          title: '$_subprotocol · protocol $_helloProtocol',
          subtitle: '握手常量锚点在 bridge/gateway.dart',
        ),
      ],
    );
  }
}

// ---------- 断开连接 ----------

class _DisconnectSection extends StatelessWidget {
  const _DisconnectSection({
    required this.colors,
    required this.onDisconnect,
  });

  final DsColors colors;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(
        top: DsSpacing.settingsSectionGap,
        bottom: DsSpacing.settingsSectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: () => _confirm(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger),
              minimumSize: const Size.fromHeight(50),
              shape: const StadiumBorder(),
            ),
            child: Text(
              '断开连接',
              style: DsTypography.baseStrong.copyWith(color: c.danger),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '将断开当前连接、清除本机配对并回到连接页；下次启动需重新输入配对码。',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final c = colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.settingsSurface,
        title: Text(
          '断开连接？',
          style: DsTypography.h4.copyWith(color: c.labelPrimary),
        ),
        content: Text(
          '本机配对信息会被清除，需要重新输入配对码才能再次连接。',
          style: DsTypography.small.copyWith(color: c.labelSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: DsTypography.small.copyWith(color: c.labelPrimary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '断开',
              style: DsTypography.smallStrong.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await onDisconnect();
    if (context.mounted) Navigator.of(context).pop();
  }
}
