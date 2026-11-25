/// DSH Chat — Flutter client for dsh-remote-bridge。
/// 入口：浅色主题（官方默认白底），未连接 → 连接页；配对成功 → 聊天页。
///
/// 应用内主题三档与字号缩放由 design/app_settings.dart 的 appSettings 驱动，
/// 位于 MaterialApp 之上（宪法 §4/§8：改样式先改 docs/design-tokens.md）。
library;

// 2026-11-15 Flutter 3.50 拆包迁移：Material/Cupertino 组件与全局本地化
// 移入 material_ui / cupertino_ui 独立包；flutter/widgets 与 Widgets 本地化
// 仍在 flutter_localizations（hide 掉与上面两个包重名的 delegate）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';

import 'dart:async';

import 'bridge/credentials.dart';
import 'bridge/device.dart';
import 'bridge/dlog.dart';
import 'bridge/gateway.dart';
import 'bridge/host_connect.dart';
import 'bridge/hosts.dart';
import 'bridge/notify.dart';
import 'design/app_settings.dart';
import 'design/tokens.dart';
import 'ui/chat_page.dart';
import 'ui/chat_state.dart';
import 'ui/connect_page.dart';
import 'ui/notify_prefs.dart';
import 'ui/notify_watcher.dart';
import 'ui/update_prompt.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  // MethodChannel 依赖 ServicesBinding；必须先初始化绑定再读设备信息。
  WidgetsFlutterBinding.ensureInitialized();
  // 先读原生设备信息（时区 + 沙盒私有目录）：文件日志要落在 app 私有目录，
  // 鸿蒙端只有原生能给出绝对路径（DshDevice.filesDir）。
  await DshDevice.init();
  DshLog.init(DshLog.resolvePath(filesDir: DshDevice.filesDir));
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
        // 中文本地化（真机反馈 2026-11-04 第二轮 D）：不配 delegate 时
        // TextField 长按菜单（粘贴/选择）走默认英文。
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
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

  // 系统通知（对齐 dsh-go）：监听网关事件弹通知，点通知跳回对应会话。
  NotifyWatcher? _notifyWatcher;
  StreamSubscription<void>? _tapSub;
  String? _pendingNotifySession; // 未连接/未就绪时先记下要跳的会话

  @override
  void initState() {
    super.initState();
    _autoConnect();
    _initNotifications();
    // 启动即查更新（需求 2026-11-22 第 3 项）：有新版弹「是否下载」。
    // 放到首帧之后，等 Navigator 就绪；网络失败/版本读不到静默跳过。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkUpdateOnLaunch(context);
    });
  }

  /// 启动即读原生时区 + 恢复凭证；有 token 就直连（一次配对，此后自动连接）。
  ///
  /// 原生设备信息（时区 / 沙盒目录）在 main() 里已读过一次，这里不再重复
  /// 调通道（省一次 MethodChannel 往返）。
  Future<void> _autoConnect() async {
    await DshCredentials.load();
    final base = DshCredentials.baseUrl;
    final token = DshCredentials.token;
    if (base == null || base.isEmpty || token == null || token.isEmpty) return;
    // 导入时留了候选表（IKX5KQ）：启动也先探活择优，在家走 LAN、在外走隧道。
    final hosts = await DshHosts.load();
    DshHost? host;
    for (final h in hosts) {
      if (h.id == DshHost.stableId(base) || h.candidates.contains(base)) {
        host = h;
        break;
      }
    }
    try {
      if (host != null) {
        final r = await connectHost(host.copyWith(token: token));
        if (!mounted) {
          r.gateway.dispose();
          return;
        }
        _onReady(r.gateway);
        return;
      }
      final gateway = GatewayClient(baseUrl: base)..token = token;
      await gateway.connect();
      if (!mounted) return;
      _onReady(gateway);
    } catch (_) {
      // 静默回连接页（凭证可能被吊销 4001），用户重新配对即可。
    }
  }

  void _onReady(GatewayClient gateway) {
    final state = ChatState(gateway);
    _notifyWatcher?.dispose();
    _notifyWatcher = NotifyWatcher(state)
      ..onOpenSession = (sid) => state.openSessionById(sid);
    setState(() {
      _gateway = gateway;
      _chatState = state;
    });
    final pending = _pendingNotifySession;
    if (pending != null) {
      _pendingNotifySession = null;
      unawaited(state.openSessionById(pending));
    }
  }

  /// 通知：建通道 + 读偏好 + 监听点击（冷启动那次从 takeLaunchTap 取）。
  Future<void> _initNotifications() async {
    DshNotify.init();
    await NotifyPrefs.instance.load();
    unawaited(DshNotify.ensureChannels());
    _tapSub = DshNotify.taps.listen(_onNotifyTap);
    final launch = await DshNotify.takeLaunchTap();
    if (launch != null) _onNotifyTap(launch);
  }

  void _onNotifyTap(Map<Object?, Object?> payload) {
    final sid = payload['sessionId'];
    if (sid is! String || sid.isEmpty) return;
    final state = _chatState;
    if (state == null) {
      _pendingNotifySession = sid; // 连接还没就绪，等 _onReady 再跳
      return;
    }
    unawaited(state.openSessionById(sid));
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
    _tapSub?.cancel();
    _notifyWatcher?.dispose();
    _chatState?.dispose();
    _gateway?.dispose();
    super.dispose();
  }
}
