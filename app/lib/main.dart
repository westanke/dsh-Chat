/// DSH Chat — Flutter client for dsh-remote-bridge。
/// 入口：浅色主题（官方默认白底），未连接 → 连接页；配对成功 → 聊天页。
///
/// 应用内主题三档与字号缩放由 design/app_settings.dart 的 appSettings 驱动，
/// 位于 MaterialApp 之上（宪法 §4/§8：改样式先改 docs/design-tokens.md）。
library;

import 'package:flutter/material.dart';

import 'bridge/credentials.dart';
import 'bridge/device.dart';
import 'bridge/dlog.dart';
import 'bridge/gateway.dart';
import 'design/app_settings.dart';
import 'design/tokens.dart';
import 'ui/chat_page.dart';
import 'ui/chat_state.dart';
import 'ui/connect_page.dart';
import 'ui/settings_page.dart';

void main() {
  DshLog.init('/data/data/com.dsh.dshchat/files/dsh.log');
  // 偏好异步加载（失败保留默认，绝不让聊天页起不来）；load() 末尾 notifyListeners
  // 会触发这里的监听，把持久化的「诊断日志」开关同步给 DshLog.enabled。
  appSettings.addListener(_syncDiagLog);
  appSettings.load();
  runApp(const DshChatApp());
}

void _syncDiagLog() => DshLog.enabled = appSettings.diagLog;

class DshChatApp extends StatelessWidget {
  const DshChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => MaterialApp(
        title: 'DSH Chat',
        debugShowCheckedModeBanner: false,
        theme: _theme(DsColors(false)),
        darkTheme: _theme(DsColors(true)),
        themeMode: _toThemeMode(appSettings.themeMode),
        builder: (context, child) {
          // 与系统字号相乘而非覆盖（对齐 companion ui/theme/AppFontScale.kt）：
          // 读的是 View 提供的原始 MediaQuery，再向下覆盖 textScaler。
          final mq = MediaQuery.of(context);
          final scale = appSettings.effectiveFontScale;
          final scaler = scale == 1.0
              ? mq.textScaler
              : AppFontScaler(mq.textScaler, scale);
          return MediaQuery(
            data: mq.copyWith(textScaler: scaler),
            child: child!,
          );
        },
        home: Builder(
          builder: (context) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            return _AppRoot(colors: DsColors(dark));
          },
        ),
      ),
    );
  }

  ThemeMode _toThemeMode(AppThemeMode m) => switch (m) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// 官方配色：浅/深两套 semantic alias 全部来自 DsColors。
  ThemeData _theme(DsColors c) {
    final brand = c.brand;
    return ThemeData(
      useMaterial3: true,
      brightness: c.dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: c.bgBase,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand,
        brightness: c.dark ? Brightness.dark : Brightness.light,
      ).copyWith(primary: brand, surface: c.bgBase),
      appBarTheme: AppBarTheme(backgroundColor: c.bgBase, elevation: 0),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.colors});

  final DsColors colors;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  GatewayClient? _gateway;
  ChatState? _chatState;

  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  /// 启动即读原生时区 + 恢复凭证；有 token 就直连（一次配对，此后自动连接）。
  Future<void> _autoConnect() async {
    await DshDevice.init();
    await DshCredentials.load();
    final base = DshCredentials.baseUrl;
    final token = DshCredentials.token;
    if (base == null || base.isEmpty || token == null || token.isEmpty) return;
    final gateway = GatewayClient(baseUrl: base)..token = token;
    try {
      await gateway.connect();
      if (!mounted) return;
      _onReady(gateway);
    } catch (_) {
      gateway.dispose();
      // 静默回连接页（凭证可能被吊销 4001），用户重新配对即可。
    }
  }

  void _onReady(GatewayClient gateway) {
    final state = ChatState(gateway);
    setState(() {
      _gateway = gateway;
      _chatState = state;
    });
  }

  /// 从抽屉进入设置页；设置页只读展示 hello 帧里的连接/设备信息。
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          colors: widget.colors,
          gateway: _gateway,
          onDisconnect: _disconnect,
        ),
      ),
    );
  }

  /// 断开连接：关闭 WS、清内存态、清除本机配对并回连接页。
  /// 下次启动需重新输入配对码（与设置页按钮说明一致）。
  Future<void> _disconnect() async {
    await DshCredentials.clear();
    _chatState?.dispose();
    _gateway?.dispose();
    if (mounted) {
      setState(() {
        _gateway = null;
        _chatState = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = _chatState;
    if (chatState != null) {
      return ChatPage(
        state: chatState,
        colors: widget.colors,
        onOpenSettings: _openSettings,
      );
    }
    return ConnectPage(onReady: _onReady, colors: widget.colors);
  }

  @override
  void dispose() {
    _chatState?.dispose();
    _gateway?.dispose();
    super.dispose();
  }
}
