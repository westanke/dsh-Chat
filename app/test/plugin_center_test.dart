/// 插件管理面板的回归：内核参数、容错解析、中文错误与开关回写。
///
/// 内核调用在 SDK 里是 extension，不能被 `@override`；所以 fake 在自己身上
/// 定义同名 `kernelCall`，再把 tear-off 注入 [PluginCenter]。
library;

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/plugin_center.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_state.dart';
import 'package:dshchat/ui/plugins_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Handler = Future<KernelCallResult> Function(
  String endpoint,
  Map<String, dynamic>? args,
);

class _FakeGateway extends GatewayClient {
  _FakeGateway(this._handler) : super(baseUrl: 'http://127.0.0.1:3090');

  final _Handler _handler;
  final List<_Call> calls = <_Call>[];

  Future<KernelCallResult> kernelCall(
    String endpoint,
    Map<String, dynamic>? args,
  ) {
    calls.add(_Call(endpoint, args));
    return _handler(endpoint, args);
  }
}

class _Call {
  const _Call(this.endpoint, this.args);

  final String endpoint;
  final Map<String, dynamic>? args;
}

PluginCenter _center(_FakeGateway gateway, {bool available = true}) {
  return PluginCenter(
    gateway,
    kernelCall: gateway.kernelCall,
    kernelAvailableOverride: available,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  PluginCenter center,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final state = ChatState(GatewayClient(baseUrl: 'http://127.0.0.1:3090'));
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PluginsPanel(
            state: state,
            colors: const DsColors(false),
            center: center,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PluginCenter', () {
    test('listPlugins 解析裸数组，兼容 id / 本地化 meta / 字符串布尔', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        expect(endpoint, PluginCenter.listBundlesEndpoint);
        expect(args, isNull);
        return KernelCallResult.ok(<Object?>[
          <String, dynamic>{
            'name': 'katex',
            'version': '1.2.0',
            'enabled': true,
            'meta': <String, dynamic>{
              'title': <String, String>{'en': 'KaTeX', 'zh-cn': '公式渲染'},
              'description': <String, String>{
                'en': 'math',
                'zh-cn': '数学公式',
              },
            },
            'rows': <Object?>[
              <String, dynamic>{'rowId': 'main', 'moduleName': 'katex'},
            ],
            'permissions': <String>['fs.read'],
          },
          <String, dynamic>{
            'id': 'legacy',
            'title': '旧插件',
            'enabled': 'false',
          },
        ]);
      });

      final bundles = await _center(gateway).listPlugins();

      expect(bundles, hasLength(2));
      expect(bundles.first.id, 'katex');
      expect(bundles.first.displayTitle, '公式渲染');
      expect(bundles.first.description, '数学公式');
      expect(bundles.first.version, '1.2.0');
      expect(bundles.first.enabled, isTrue);
      expect(bundles.first.entries.single.label, 'katex');
      expect(bundles.first.permissions, <String>['fs.read']);

      expect(bundles.last.id, 'legacy');
      expect(bundles.last.displayTitle, '旧插件');
      expect(bundles.last.enabled, isFalse);
      expect(bundles.last.description, isEmpty);
    });

    test('listPlugins 兼容 bundles / items 包装', () async {
      Future<List<PluginBundle>> load(String key) {
        final gateway = _FakeGateway((endpoint, args) async {
          return KernelCallResult.ok(<String, dynamic>{
            key: <Object?>[
              <String, dynamic>{'name': key, 'enabled': true},
            ],
          });
        });
        return _center(gateway).listPlugins();
      }

      expect((await load('bundles')).single.id, 'bundles');
      expect((await load('items')).single.id, 'items');
    });

    test('pluginDetail 发 name + language，并解析 found 文档', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        expect(endpoint, PluginCenter.readBundleDetailEndpoint);
        expect(args, <String, dynamic>{
          'name': 'katex',
          'language': 'zh-CN',
        });
        return KernelCallResult.ok(<String, dynamic>{
          'status': 'found',
          'origin': 'readme',
          'path': '/plugins/katex/README.md',
          'markdown': '# KaTeX\n\n公式渲染。',
        });
      });

      final detail = await _center(gateway).pluginDetail('katex');

      expect(detail.found, isTrue);
      expect(detail.origin, 'readme');
      expect(detail.path, '/plugins/katex/README.md');
      expect(detail.markdown, contains('KaTeX'));
    });

    test('pluginDetail 的 status=none 不抛错，返回 found=false', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        return KernelCallResult.ok(<String, dynamic>{'status': 'none'});
      });

      final detail = await _center(gateway).pluginDetail('quiet');

      expect(detail.found, isFalse);
      expect(detail.hasMarkdown, isFalse);
    });

    test('setPluginEnabled 发 name + enabled，并按 ChangeResult 回写状态', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        expect(endpoint, PluginCenter.setBundleEnabledEndpoint);
        expect(args, <String, dynamic>{'name': 'katex', 'enabled': false});
        return KernelCallResult.ok(<String, dynamic>{
          'changed': true,
          'application': 'applied',
          'stage': 'enable',
          'target': 'katex',
          'enabled': false,
        });
      });

      final effective = await _center(gateway).setPluginEnabled('katex', false);

      expect(effective, isFalse);
    });

    test('开关帧失败（主机拒权）转中文错误并保留 code', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        return KernelCallResult.failed(
          'gateway/access-denied',
          'scope settings.write is required',
        );
      });

      await expectLater(
        _center(gateway).setPluginEnabled('katex', true),
        throwsA(
          isA<RequestException>()
              .having((error) => error.code, 'code', 'gateway/access-denied')
              .having(
                (error) => error.message,
                'message',
                contains('没有授权'),
              ),
        ),
      );
    });

    test('列表参数不匹配转中文错误', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        return KernelCallResult.failed(
          'gateway/arguments-invalid',
          'args fields do not match the descriptor',
        );
      });

      await expectLater(
        _center(gateway).listPlugins(),
        throwsA(
          isA<RequestException>().having(
            (error) => error.message,
            'message',
            allOf(contains('插件管理'), contains('参数')),
          ),
        ),
      );
    });

    test('能力缺失时 available=false 且调用抛「不支持插件管理」', () async {
      final gateway = _FakeGateway((endpoint, args) async {
        fail('能力缺失时不应发内核帧');
      });
      final center = _center(gateway, available: false);

      expect(center.available, isFalse);
      await expectLater(
        center.listPlugins(),
        throwsA(
          isA<RequestException>()
              .having((error) => error.code, 'code', 'NOT_SUPPORTED')
              .having(
                (error) => error.message,
                'message',
                '当前连接不支持插件管理',
              ),
        ),
      );
      expect(gateway.calls, isEmpty);
    });

    test('能力位 + 端点目录都齐才 available', () {
      final gateway = _FakeGateway((endpoint, args) async {
        return KernelCallResult.ok(const <Object?>[]);
      });
      final center = PluginCenter(gateway);

      expect(center.available, isFalse);
      gateway.capabilities = <String>['kernel-call-v1'];
      expect(center.available, isFalse, reason: '只有能力位、没有端点目录不算可用');
      gateway.debugSetKernelCatalog(<KernelEndpoint>[
        const KernelEndpoint(
          endpoint: PluginCenter.listBundlesEndpoint,
          scope: 'settings.read',
          summary: 'List installed plugin bundles.',
        ),
      ]);
      expect(center.available, isTrue);
    });
  });

  group('PluginsPanel', () {
    testWidgets('列表显示名称/版本/说明，点开关走 setBundleEnabled 并本地回写', (
      tester,
    ) async {
      final gateway = _FakeGateway((endpoint, args) async {
        if (endpoint == PluginCenter.listBundlesEndpoint) {
          return KernelCallResult.ok(<Object?>[
            <String, dynamic>{
              'name': 'katex',
              'title': '公式渲染',
              'version': '1.2.0',
              'description': '数学公式',
              'enabled': true,
            },
          ]);
        }
        expect(endpoint, PluginCenter.setBundleEnabledEndpoint);
        expect(args, <String, dynamic>{'name': 'katex', 'enabled': false});
        return KernelCallResult.ok(<String, dynamic>{
          'changed': true,
          'application': 'applied',
          'enabled': false,
        });
      });

      await _pumpPanel(tester, _center(gateway));

      expect(find.text('公式渲染'), findsOneWidget);
      expect(find.text('v1.2.0'), findsOneWidget);
      expect(find.text('数学公式'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(gateway.calls.last.endpoint, PluginCenter.setBundleEnabledEndpoint);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('点行开详情 sheet，展示版本/说明/入口/权限与说明文档', (
      tester,
    ) async {
      final gateway = _FakeGateway((endpoint, args) async {
        if (endpoint == PluginCenter.listBundlesEndpoint) {
          return KernelCallResult.ok(<Object?>[
            <String, dynamic>{
              'name': 'katex',
              'title': '公式渲染',
              'version': '1.2.0',
              'description': '数学公式',
              'enabled': true,
              'rows': <Object?>[
                <String, dynamic>{'rowId': 'main', 'moduleName': 'katex'},
              ],
              'permissions': <String>['fs.read'],
            },
          ]);
        }
        expect(endpoint, PluginCenter.readBundleDetailEndpoint);
        return KernelCallResult.ok(<String, dynamic>{
          'status': 'found',
          'markdown': '# KaTeX 文档',
        });
      });

      await _pumpPanel(tester, _center(gateway));
      await tester.tap(find.text('公式渲染'));
      await tester.pumpAndSettle();

      expect(find.text('版本'), findsOneWidget);
      expect(find.text('1.2.0'), findsOneWidget);
      expect(find.text('入口'), findsOneWidget);
      expect(find.text('katex'), findsOneWidget);
      expect(find.text('权限'), findsOneWidget);
      expect(find.text('fs.read'), findsOneWidget);
      expect(find.text('# KaTeX 文档'), findsOneWidget);
    });

    testWidgets('加载失败显示错误与重试，重试成功后出列表', (tester) async {
      var attempt = 0;
      final gateway = _FakeGateway((endpoint, args) async {
        attempt++;
        if (attempt == 1) {
          return KernelCallResult.failed('TIMEOUT', 'kernel call timed out');
        }
        return KernelCallResult.ok(<Object?>[
          <String, dynamic>{'name': 'katex', 'enabled': true},
        ]);
      });

      await _pumpPanel(tester, _center(gateway));

      expect(find.text('插件列表加载失败'), findsOneWidget);
      expect(find.textContaining('超时'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('katex'), findsOneWidget);
      expect(attempt, 2);
    });

    testWidgets('能力缺失显示明确占位，不抛异常', (tester) async {
      final gateway = _FakeGateway((endpoint, args) async {
        fail('能力缺失时不应发内核帧');
      });

      await _pumpPanel(tester, _center(gateway, available: false));

      expect(find.text('当前连接不支持插件管理'), findsOneWidget);
      expect(gateway.calls, isEmpty);
    });
  });
}
