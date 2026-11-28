/// 输入条语音键回归：catalog 不可用时不出现；可用时点按开始/结束录音，
/// 转写文本插入输入框；录音中可取消。原生通道与网关都用 mock，不碰真麦克风。
library;

import 'dart:convert';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/speech.dart';
import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/composer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SpeechGateway extends GatewayClient {
  _SpeechGateway(this.catalog)
      : super(baseUrl: 'http://127.0.0.1:1');

  Map<String, dynamic> catalog;

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) =>
      requestWithTimeout(type, payload, const Duration(seconds: 30));

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    switch (type) {
      case 'speech-catalog':
        return catalog;
      case 'speech-transcribe':
        return <String, dynamic>{'text': '你好世界'};
      default:
        return const <String, dynamic>{};
    }
  }
}

Map<String, dynamic> _availableCatalog() => <String, dynamic>{
      'requestId': 'r1',
      'available': true,
      'providers': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'p1',
          'name': 'Provider 1',
          'languages': <String>['zh'],
        },
      ],
      'selection': <String, dynamic>{'providerId': 'p1', 'language': 'zh'},
      'maxAudioBytes': 64044,
      'maxDurationSeconds': 60,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  final wav = wavFromPcm16(List<int>.filled(32000, 0));

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dsh/platform'), (
      call,
    ) async {
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('dsh/speech'), (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'supported': true,
            'granted': true,
            'canRequest': false,
          };
        case 'stop':
          return <String, Object?>{
            'format': 'wav',
            'base64': base64Encode(wav),
            'sampleRate': 16000,
            'channels': 1,
            'bitsPerSample': 16,
          };
        case 'start':
        case 'cancel':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dsh/platform'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('dsh/speech'), null);
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    GatewayClient? gateway,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            colors: DsColors(false),
            gateway: gateway,
            onSend: (_) {},
            onSendWithImages: (_, _) {},
            onCancel: () {},
            onCommand: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('catalog 不可用时不显示话筒', (tester) async {
    final gateway = _SpeechGateway(<String, dynamic>{
      'available': false,
      'providers': <Object>[],
      'code': 'speech/unavailable',
    });
    await pumpComposer(tester, gateway: gateway);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(calls, isNot(contains('start')));
  });

  testWidgets('没有网关时不显示话筒', (tester) async {
    await pumpComposer(tester);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('可用时点按录音、再点结束并插入转写文本', (tester) async {
    final gateway = _SpeechGateway(_availableCatalog());
    await pumpComposer(tester, gateway: gateway);

    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    expect(calls, contains('start'));
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // 录音中 hint 显示状态。
    expect(find.text('正在录音 · 点按话筒结束'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(calls, contains('stop'));
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, '你好世界');
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('录音中点取消回 idle，不插入文本', (tester) async {
    final gateway = _SpeechGateway(_availableCatalog());
    await pumpComposer(tester, gateway: gateway);

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(calls, contains('cancel'));
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
