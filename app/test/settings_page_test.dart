// 设置页单测：验证每个控件都真实接到 AppSettings（不是空开关）。
import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/settings_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 全局单例在测试间共享，逐项复位到默认值。
    appSettings.setThemeMode(AppThemeMode.system);
    appSettings.setFontScale(1.0);
    appSettings.setFontFollowsSystem(false);
    appSettings.setBusySendMode(BusySendMode.queue);
    appSettings.setDiagLog(true);
    // 2026-11-16 通用设置批次：新四项同样逐项复位。
    appSettings.setWorkStepsDetail(WorkStepsDetail.detailed);
    appSettings.setCollapseTiming(CollapseTiming.completion);
    appSettings.setFoldedReplies(FoldedReplies.all);
    appSettings.setCodeWorkView(false);
  });

  Future<void> pump(WidgetTester tester, {GatewayClient? gateway}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          colors: DsColors(false),
          gateway: gateway,
          onDisconnect: () async {},
        ),
      ),
    );
  }

  testWidgets('renders every section title', (tester) async {
    await pump(tester);
    for (final title in ['连接', '外观', '通用', '发送', '诊断', '关于']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('断开连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme segmented row actually changes AppSettings',
      (tester) async {
    await pump(tester);
    final dark = find.text('深色');
    await tester.ensureVisible(dark);
    await tester.tap(dark);
    await tester.pump();
    expect(appSettings.themeMode, AppThemeMode.dark);

    final light = find.text('浅色');
    await tester.ensureVisible(light);
    await tester.tap(light);
    await tester.pump();
    expect(appSettings.themeMode, AppThemeMode.light);
  });

  testWidgets('busy-send segmented row actually changes AppSettings',
      (tester) async {
    await pump(tester);
    final steer = find.text('插话');
    await tester.ensureVisible(steer);
    await tester.tap(steer);
    await tester.pump();
    expect(appSettings.busySendMode, BusySendMode.steer);

    final queue = find.text('排队');
    await tester.ensureVisible(queue);
    await tester.tap(queue);
    await tester.pump();
    expect(appSettings.busySendMode, BusySendMode.queue);
  });

  testWidgets('font slider is wired and disabled when following system',
      (tester) async {
    await pump(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNotNull);
    // 直接调用 onChanged 即验证它接的是 appSettings.setFontScale。
    slider.onChanged!(1.2);
    expect(appSettings.fontScale, 1.2);

    appSettings.setFontFollowsSystem(true);
    await tester.pump();
    final disabled = tester.widget<Slider>(find.byType(Slider));
    expect(disabled.onChanged, isNull);
  });

  testWidgets('diagnostics switch is wired', (tester) async {
    await pump(tester);
    // 三个 Switch：字号跟随系统、显示代码工作视图（通用）、记录诊断日志；取后者。
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(3));
    final diag = tester.widget<Switch>(switches.at(2));
    expect(diag.value, isTrue);
    diag.onChanged!(false);
    expect(appSettings.diagLog, isFalse);
  });

  testWidgets('general section rows are wired to the new settings',
      (tester) async {
    await pump(tester);
    // 工作步骤展示（四档）。
    await tester.ensureVisible(find.text('完全展开'));
    await tester.tap(find.text('完全展开'));
    await tester.pump();
    expect(appSettings.workStepsDetail, WorkStepsDetail.verbose);
    // verbose 时「收起后显示的回复」整行隐藏（verbose 从不折叠）。
    expect(find.text('收起后显示的回复'), findsNothing);
    await tester.tap(find.text('详细'));
    await tester.pump();
    expect(appSettings.workStepsDetail, WorkStepsDetail.detailed);

    // 收起时机。
    await tester.ensureVisible(find.text('下次有新消息时'));
    await tester.tap(find.text('下次有新消息时'));
    await tester.pump();
    expect(appSettings.collapseTiming, CollapseTiming.nextInput);

    // 收起后显示的回复（detailed 档下重新可见）。
    await tester.ensureVisible(find.text('仅最终回答'));
    await tester.tap(find.text('仅最终回答'));
    await tester.pump();
    expect(appSettings.foldedReplies, FoldedReplies.finalOnly);

    // 显示代码工作视图开关（通用段的 Switch，位于字号跟随系统之后）。
    final switches = find.byType(Switch);
    final workView = tester.widget<Switch>(switches.at(1));
    expect(workView.value, isFalse);
    workView.onChanged!(true);
    expect(appSettings.codeWorkView, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection section shows hello device scopes read-only',
      (tester) async {
    final gw = GatewayClient(baseUrl: 'http://192.168.1.10:3090')
      ..device = {
        'name': 'My Bridge',
        'id': 'dev-1',
        'scopes': ['chat.read', 'settings.read', 'mystery.scope'],
      };
    await pump(tester, gateway: gw);
    expect(find.text('My Bridge'), findsOneWidget);
    expect(find.text('dev-1'), findsOneWidget);
    expect(find.text('聊天读取'), findsOneWidget);
    expect(find.text('设置读取'), findsOneWidget);
    // 未识别 scope 原样保留，不假装成中文。
    expect(find.text('mystery.scope'), findsOneWidget);
    // HTTP 明文警告出现。
    expect(find.textContaining('HTTP 明文连接'), findsOneWidget);
    // 诚实说明授权前提，不摆无法生效的开关。
    expect(find.textContaining('settings.write 授权'), findsOneWidget);
    expect(tester.takeException(), isNull);
    gw.dispose();
  });

  testWidgets('unconnected state shows a placeholder, not fake rows',
      (tester) async {
    await pump(tester);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('配对后此处显示设备与授权信息'), findsOneWidget);
    expect(find.text('My Bridge'), findsNothing);
  });

  testWidgets('disconnect asks for confirmation before invoking the callback',
      (tester) async {
    var calls = 0;
    // SettingsPage 必须是可 pop 的路由：_confirm 成功后会 Navigator.pop 回到上一页。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    colors: DsColors(false),
                    gateway: null,
                    onDisconnect: () async => calls++,
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final button = find.text('断开连接');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('断开连接？'), findsOneWidget);
    expect(calls, 0); // 还没确认就不该清凭证
    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    // 确认后弹回上一页，设置页消失。
    expect(find.text('go'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于页版本行读平台注入值（不写死，随发版同步）',
      (tester) async {
    // mock dsh/platform appVersion（与 platform.dart 同一通道名）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dsh/platform'),
      (method) => method.method == 'appVersion'
          ? Future.value(<String, Object>{'version': '1.0.14', 'code': 15})
          : null,
    );
    await pump(tester);
    await tester.pump();
    expect(find.text('版本 1.0.14+15'), findsOneWidget);
    // 拉不到版本时占位，不显示写死的旧号。
    await pump(tester);
    expect(find.textContaining('版本 1.0.13'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
