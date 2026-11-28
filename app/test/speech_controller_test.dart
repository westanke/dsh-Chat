/// [SpeechController] 状态机回归：目录不可用时隐藏、prepare→transcribe 成功、
/// 准备/转写失败、取消在途转写、权限拒绝、平台不支持。用 fake 网关与
/// fake 录音器，不依赖真实麦克风与 bridge。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dshchat/bridge/gateway.dart';
import 'package:dshchat/bridge/speech.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway extends GatewayClient {
  _FakeGateway() : super(baseUrl: 'http://127.0.0.1:1');

  final List<String> types = <String>[];
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> responses =
      <String, Map<String, dynamic>>{};
  final Map<String, Object> failures = <String, Object>{};
  Completer<Map<String, dynamic>>? transcribeGate;

  @override
  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload,
  ) => requestWithTimeout(type, payload, const Duration(seconds: 30));

  @override
  Future<Map<String, dynamic>> requestWithTimeout(
    String type,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    types.add(type);
    payloads.add(payload);
    final failure = failures[type];
    if (failure != null) throw failure;
    if (type == 'speech-transcribe' && transcribeGate != null) {
      return transcribeGate!.future;
    }
    return responses[type] ?? const <String, dynamic>{};
  }
}

class _FakeRecorder implements SpeechRecorder {
  SpeechDeviceStatus statusValue = const SpeechDeviceStatus(
    supported: true,
    granted: true,
    canRequest: true,
  );
  bool permissionAnswer = true;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int permissionCalls = 0;
  int lastMaxBytes = 0;
  Object? startError;
  Object? stopError;
  List<int> wav = List<int>.filled(32000, 0);

  @override
  Future<SpeechDeviceStatus> status() async => statusValue;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    if (permissionAnswer) {
      statusValue = const SpeechDeviceStatus(
        supported: true,
        granted: true,
        canRequest: true,
      );
    }
    return permissionAnswer;
  }

  @override
  Future<void> start({required int maxBytes}) async {
    startCalls++;
    lastMaxBytes = maxBytes;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<SpeechRecording> stop() async {
    stopCalls++;
    final error = stopError;
    if (error != null) throw error;
    return SpeechRecording(
      base64: base64Encode(wavFromPcm16(wav)),
      format: 'wav',
      sampleRate: speechSampleRate,
      channels: speechChannels,
      bitsPerSample: speechBitsPerSample,
      durationMs: wavDurationMs(speechWavHeaderBytes + wav.length),
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

Map<String, dynamic> _catalogJson({
  String? providerId = 'p1',
}) => <String, dynamic>{
  'requestId': 'r-catalog',
  'available': true,
  'providers': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'p1',
      'name': 'Provider 1',
      'languages': <String>['zh'],
    },
  ],
  if (providerId != null)
    'selection': <String, dynamic>{'providerId': providerId, 'language': 'zh'},
  'maxAudioBytes': 64044,
  'maxDurationSeconds': 60,
};

void main() {
  late _FakeGateway gateway;
  late _FakeRecorder recorder;
  late SpeechController controller;

  setUp(() {
    gateway = _FakeGateway();
    recorder = _FakeRecorder();
    controller = SpeechController(gateway: gateway, recorder: recorder);
  });

  tearDown(() => controller.dispose());

  group('目录探测', () {
    test('available:false 时不显示话筒，也不碰录音器', () async {
      gateway.responses['speech-catalog'] = <String, dynamic>{
        'available': false,
        'providers': <Object>[],
        'code': 'speech/unavailable',
      };
      await controller.probe();
      expect(controller.catalog?.available, isFalse);
      expect(controller.visible, isFalse);
      expect(controller.error, isNull);
      expect(recorder.startCalls, 0);
    });

    test('探测失败只隐藏话筒，不抛给 UI', () async {
      gateway.failures['speech-catalog'] = RequestException(
        'NOT_CONNECTED',
        '未连接',
      );
      await controller.probe();
      expect(controller.catalog, isNull);
      expect(controller.visible, isFalse);
      expect(controller.error, isNull);
    });

    test('目录可用 + 已授权才显示，且按帧上限夹字节数', () async {
      gateway.responses['speech-catalog'] = _catalogJson();
      await controller.probe();
      expect(controller.visible, isTrue);
      expect(controller.maxAudioBytes, 64044);
      expect(controller.maxDurationMs, 2000);
    });

    test('平台不支持（OHOS/桌面）时不显示', () async {
      recorder.statusValue = SpeechDeviceStatus.unsupported;
      gateway.responses['speech-catalog'] = _catalogJson();
      await controller.probe();
      expect(controller.visible, isFalse);
    });

    test('speech-state 推送刷新目录', () async {
      gateway.responses['speech-catalog'] = <String, dynamic>{
        'available': false,
      };
      await controller.probe();
      expect(controller.visible, isFalse);
      controller.ingestPush(<String, dynamic>{
        'kind': 'speech-state',
        'data': _catalogJson(),
      });
      expect(controller.catalog?.available, isTrue);
      expect(controller.visible, isTrue);
    });
  });

  group('录音 → 准备 → 转写', () {
    setUp(() {
      gateway.responses['speech-catalog'] = _catalogJson();
      gateway.responses['speech-prepare'] = const <String, dynamic>{};
      gateway.responses['speech-transcribe'] = <String, dynamic>{
        'text': '你好世界',
        'audioSeconds': 1.0,
        'inferenceSeconds': 0.2,
      };
    });

    test('成功路径：prepare 一次、transcribe 带 base64、文本返回', () async {
      await controller.probe();
      await controller.begin();
      expect(controller.phase, SpeechPhase.recording);
      expect(recorder.startCalls, 1);
      expect(recorder.lastMaxBytes, 64044);

      final text = await controller.finish();
      expect(text, '你好世界');
      expect(controller.phase, SpeechPhase.idle);
      expect(controller.error, isNull);
      expect(gateway.types, <String>[
        'speech-catalog',
        'speech-prepare',
        'speech-transcribe',
      ]);
      expect(gateway.payloads[1]['providerId'], 'p1');
      final audio = gateway.payloads[2]['audioBase64'] as String;
      expect(base64Decode(audio).length, speechWavHeaderBytes + 32000);
      expect(gateway.payloads[2]['language'], 'zh');

      // 同一 provider 准备过就不再重复 prepare。
      await controller.begin();
      await controller.finish();
      expect(gateway.types.where((type) => type == 'speech-prepare').length, 1);
    });

    test('没有 selection 时跳过 prepare，直接转写', () async {
      gateway.responses['speech-catalog'] = _catalogJson(providerId: null);
      await controller.probe();
      await controller.begin();
      await controller.finish();
      expect(gateway.types, <String>['speech-catalog', 'speech-transcribe']);
    });

    test('空文本返回空串并给出提示', () async {
      gateway.responses['speech-transcribe'] = <String, dynamic>{'text': '  '};
      await controller.probe();
      await controller.begin();
      final text = await controller.finish();
      expect(text, '');
      expect(controller.error, '没有识别到语音');
      expect(controller.phase, SpeechPhase.idle);
    });

    test('录音为空（只有 WAV 头）时本地拒绝，不发转写', () async {
      recorder.wav = const <int>[];
      await controller.probe();
      await controller.begin();
      final text = await controller.finish();
      expect(text, isNull);
      expect(controller.error, contains('没有录到声音'));
      expect(gateway.types, isNot(contains('speech-transcribe')));
    });
  });

  group('失败与取消', () {
    setUp(() {
      gateway.responses['speech-catalog'] = _catalogJson();
      gateway.responses['speech-prepare'] = const <String, dynamic>{};
      gateway.responses['speech-transcribe'] = <String, dynamic>{'text': 'x'};
    });

    test('prepare 失败：不上屏文本，错误翻成引导语', () async {
      gateway.failures['speech-prepare'] = RequestException(
        'speech/unavailable',
        'no plugin',
      );
      await controller.probe();
      await controller.begin();
      final text = await controller.finish();
      expect(text, isNull);
      expect(controller.phase, SpeechPhase.idle);
      expect(controller.error, contains('插件'));
      expect(gateway.types, isNot(contains('speech-transcribe')));
    });

    test('转写失败：错误上屏，状态回 idle', () async {
      gateway.failures['speech-transcribe'] = RequestException(
        'speech/busy',
        'busy',
      );
      await controller.probe();
      await controller.begin();
      expect(await controller.finish(), isNull);
      expect(controller.error, contains('正忙'));
      expect(controller.phase, SpeechPhase.idle);
    });

    test('转写中取消：丢弃在途结果，不插文本', () async {
      final gate = Completer<Map<String, dynamic>>();
      gateway.transcribeGate = gate;
      await controller.probe();
      await controller.begin();
      final pending = controller.finish();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, SpeechPhase.transcribing);

      await controller.cancel();
      expect(controller.phase, SpeechPhase.idle);
      gate.complete(<String, dynamic>{'text': '迟到的结果'});
      expect(await pending, isNull);
    });

    test('录音中取消走原生 cancel', () async {
      await controller.probe();
      await controller.begin();
      expect(controller.recording, isTrue);
      await controller.cancel();
      expect(controller.phase, SpeechPhase.idle);
      expect(recorder.cancelCalls, greaterThanOrEqualTo(1));
      expect(recorder.stopCalls, 0);
    });

    test('麦克风权限被拒：提示且不开始录音', () async {
      recorder.statusValue = const SpeechDeviceStatus(
        supported: true,
        granted: false,
        canRequest: true,
      );
      recorder.permissionAnswer = false;
      gateway.responses['speech-catalog'] = _catalogJson();
      await controller.probe();
      expect(controller.visible, isTrue);
      await controller.begin();
      expect(controller.phase, SpeechPhase.idle);
      expect(controller.error, contains('麦克风权限'));
      expect(recorder.startCalls, 0);
    });

    test('平台不支持时 begin 直接给提示', () async {
      recorder.statusValue = SpeechDeviceStatus.unsupported;
      await controller.begin();
      expect(controller.error, contains('不支持'));
      expect(controller.phase, SpeechPhase.idle);
    });
  });
}
