/// 语音输入纯函数层回归：WAV 打包/时长、catalog/transcript 往返、
/// 推送解析、原生录音结果归一、错误文案。全程不碰麦克风与网络。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dshchat/bridge/gateway_events.dart';
import 'package:dshchat/bridge/speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WAV 打包', () {
    test('44 字节 RIFF/WAVE 头字段齐全且小端', () {
      final pcm = <int>[1, 2, 3, 4, 5, 6];
      final wav = wavFromPcm16(pcm);
      expect(wav.length, speechWavHeaderBytes + pcm.length);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
      expect(ascii.decode(wav.sublist(36, 40)), 'data');

      final data = ByteData.view(wav.buffer);
      expect(data.getUint32(4, Endian.little), 36 + pcm.length);
      expect(data.getUint32(16, Endian.little), 16);
      expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(data.getUint16(22, Endian.little), speechChannels);
      expect(data.getUint32(24, Endian.little), speechSampleRate);
      expect(
        data.getUint32(28, Endian.little),
        speechSampleRate * speechChannels * speechBitsPerSample ~/ 8,
      );
      expect(data.getUint16(32, Endian.little), 2, reason: 'block align');
      expect(data.getUint16(34, Endian.little), speechBitsPerSample);
      expect(data.getUint32(40, Endian.little), pcm.length);
      expect(wav.sublist(speechWavHeaderBytes), pcm);
      expect(isWavBytes(wav), isTrue);
    });

    test('空 PCM 也是合法 WAV（只有头）', () {
      final wav = wavFromPcm16(const <int>[]);
      expect(wav.length, speechWavHeaderBytes);
      expect(isWavBytes(wav), isTrue);
      expect(wavDurationMs(wav.length), 0);
    });

    test('wavDurationMs 按 16k/单声道/16bit 换算', () {
      expect(wavDurationMs(speechWavHeaderBytes + speechBytesPerSecond), 1000);
      expect(wavDurationMs(speechWavHeaderBytes), 0);
      expect(wavDurationMs(0), 0);
    });

    test('speechAudioByteLimit 与桥的 base64/信封算式一致', () {
      // 与 ws-speech.ts `speechAudioLimit` 同式：留 4 KiB 信封，base64 3/4。
      final frameLimit = 1024 * 1024;
      expect(
        speechAudioByteLimit(frameLimit),
        (frameLimit - 4096) ~/ 4 * 3,
      );
      // 超过桥的 4 MiB 上限时封顶。
      expect(speechAudioByteLimit(64 * 1024 * 1024), speechMaxAudioBytes);
      // 信封都不够时给 0（控制器据此拒绝录音）。
      expect(speechAudioByteLimit(1024), 0);
    });
  });

  group('目录模型', () {
    Map<String, dynamic> availableJson() => <String, dynamic>{
          'requestId': 'r1',
          'available': true,
          'providers': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sensevoice',
              'name': 'SenseVoice',
              'languages': <String>['zh', 'en'],
              'location': 'https://example.com/model',
            },
          ],
          'selection': <String, dynamic>{
            'providerId': 'sensevoice',
            'language': 'zh',
          },
          'maxAudioBytes': 64000,
          'maxDurationSeconds': 120,
        };

    test('fromJson → toJson → fromJson 字段一致', () {
      final first = SpeechCatalog.fromJson(availableJson());
      final second = SpeechCatalog.fromJson(first.toJson());
      expect(second.available, isTrue);
      expect(second.providers.single.id, 'sensevoice');
      expect(second.providers.single.name, 'SenseVoice');
      expect(second.providers.single.languages, <String>['zh', 'en']);
      expect(second.providers.single.location, 'https://example.com/model');
      expect(second.providerId, 'sensevoice');
      expect(second.language, 'zh');
      expect(second.maxAudioBytes, 64000);
      expect(second.maxDurationSeconds, 120);
      expect(second.providerLabel, 'SenseVoice');
    });

    test('available:false 带原因码与引导语', () {
      final catalog = SpeechCatalog.fromJson(const <String, dynamic>{
        'requestId': 'r2',
        'available': false,
        'providers': <Object>[],
        'code': 'speech/unavailable',
        'message': 'Enable the official voice input bundle',
      });
      expect(catalog.available, isFalse);
      expect(catalog.code, 'speech/unavailable');
      expect(catalog.message, contains('official'));
      expect(catalog.providerId, isNull);
      expect(catalog.providerLabel, isNull);
    });

    test('形状不对时退回默认值，不抛异常', () {
      final catalog = SpeechCatalog.fromJson(const <String, dynamic>{
        'available': 'yes',
        'providers': 'nope',
        'maxAudioBytes': -1,
        'maxDurationSeconds': 0,
      });
      expect(catalog.available, isFalse);
      expect(catalog.providers, isEmpty);
      expect(catalog.maxAudioBytes, -1);
      expect(catalog.maxDurationSeconds, 0);
    });
  });

  group('转写与推送', () {
    test('transcript 往返（空文本合法）', () {
      final transcript = SpeechTranscript.fromJson(const <String, dynamic>{
        'text': '你好',
        'audioSeconds': 1.5,
        'inferenceSeconds': 0.4,
      });
      final again = SpeechTranscript.fromJson(transcript.toJson());
      expect(again.text, '你好');
      expect(again.audioSeconds, 1.5);
      expect(again.inferenceSeconds, 0.4);
      expect(
        SpeechTranscript.fromJson(const <String, dynamic>{'text': ''}).text,
        '',
      );
    });

    test('parseSpeechPush 认 speech-state / preparing / transcript', () {
      final state = parseSpeechPush(const <String, dynamic>{
        'kind': 'speech-state',
        'data': <String, dynamic>{
          'requestId': 'follow-1',
          'available': true,
          'providers': <Object>[],
          'selection': <String, dynamic>{'providerId': 'p1'},
          'maxAudioBytes': 46000,
          'maxDurationSeconds': 60,
        },
      });
      expect(state, isA<SpeechStatePush>());
      final statePush = state as SpeechStatePush;
      expect(statePush.followRequestId, 'follow-1');
      expect(statePush.catalog.available, isTrue);
      expect(statePush.catalog.providerId, 'p1');

      final preparing = parseSpeechPush(const <String, dynamic>{
        'kind': 'speech-preparing',
        'data': <String, dynamic>{'requestId': 'r3', 'providerId': 'p1'},
      });
      expect((preparing as SpeechPreparingPush).providerId, 'p1');

      final transcript = parseSpeechPush(const <String, dynamic>{
        'kind': 'speech-transcript',
        'data': <String, dynamic>{'requestId': 'r4', 'text': 'hi'},
      });
      expect((transcript as SpeechTranscriptPush).transcript.text, 'hi');

      expect(
        parseSpeechPush(const <String, dynamic>{'kind': 'chat-event'}),
        isNull,
      );
    });
  });

  group('原生录音结果', () {
    test('wav 原样上送，时长由字节数推出', () {
      final wav = wavFromPcm16(List<int>.filled(speechBytesPerSecond, 0));
      final recording = SpeechRecording.fromMap(<String, dynamic>{
        'format': 'wav',
        'base64': base64Encode(wav),
        'sampleRate': 16000,
      });
      expect(recording.format, 'wav');
      expect(recording.durationMs, 1000);
      expect(recording.toWavBytes(), wav);
    });

    test('pcm16 裸字节补头后再上送', () {
      final recording = SpeechRecording.fromMap(<String, dynamic>{
        'format': 'pcm16',
        'base64': base64Encode(Uint8List.fromList(<int>[1, 2, 3, 4])),
        'sampleRate': 16000,
        'channels': 1,
      });
      final wav = recording.toWavBytes();
      expect(wav.length, speechWavHeaderBytes + 4);
      expect(isWavBytes(wav), isTrue);
    });

    test('没有 base64 / 原生报错时抛 SpeechException', () {
      expect(
        () => SpeechRecording.fromMap(const <String, dynamic>{}),
        throwsA(isA<SpeechException>()),
      );
      expect(
        () => SpeechRecording.fromMap(const <String, dynamic>{
          'error': '没有权限',
        }),
        throwsA(isA<SpeechException>()),
      );
    });
  });

  group('错误文案', () {
    test('桥错误码翻成中文引导', () {
      expect(
        describeSpeechError(
          RequestException('speech/unavailable', 'no plugin'),
        ),
        contains('插件'),
      );
      expect(
        describeSpeechError(RequestException('speech/busy', 'busy')),
        contains('正忙'),
      );
      expect(
        describeSpeechError(RequestException('weird/code', '原始信息')),
        '原始信息',
      );
      expect(
        describeSpeechError(const SpeechException('mic/permission', '要权限')),
        '要权限',
      );
    });
  });
}
