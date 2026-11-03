/// DSH Chat — Flutter client for dsh-remote-bridge。
/// 入口：浅色主题（官方默认白底），未连接 → 连接页；配对成功 → 聊天页。
library;

import 'package:flutter/material.dart';

import 'bridge/credentials.dart';
import 'bridge/device.dart';
import 'bridge/dlog.dart';
import 'bridge/gateway.dart';
import 'design/tokens.dart';
import 'ui/chat_page.dart';
import 'ui/chat_state.dart';
import 'ui/connect_page.dart';

void main() {
  DshLog.init('/data/data/com.dsh.dshchat/files/dsh.log');
  runApp(const DshChatApp());
}

class DshChatApp extends StatelessWidget {
  const DshChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Chat',
      debugShowCheckedModeBanner: false,
      theme: _theme(DsColors(false)),
      darkTheme: _theme(DsColors(true)),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return _AppRoot(colors: DsColors(dark));
        },
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final chatState = _chatState;
    if (chatState != null) {
      return ChatPage(state: chatState, colors: widget.colors);
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
