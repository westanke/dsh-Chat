/// 桥 `speech-*` WS 帧的客户端实现：目录探测、模型准备、转写、取消，
/// 以及服务端推送（`speech-state` / `speech-preparing` / `speech-transcript`）
/// 的解析（解析器在 speech_types.dart，随本文件 export）。
///
/// 协议事实见 `dsh-remote-bridge/src/host/ws-speech.ts`：
/// - 转写只收 16 kHz / 单声道 / PCM16 的 WAV，base64 编码，≤4 MiB；
/// - 每连接同时 1 个转写，转写超时 180 s；
/// - 内核没有官方语音插件时 `speech-catalog` 回 `available:false`，
///   其它帧回 `speech/unavailable`。
///
/// 推送的两点限制（不改 gateway.dart 的前提下）：
/// 1. [GatewayClient] 目前把未知 kind 直接丢弃，`speech-state` 等帧不会进
///    `events`；上层若拿到了推送帧，调 [SpeechController.ingestPush] 即可
///    （见 [SpeechController.attachPushStream]，供后续网关暴露旁路流时接线）。
/// 2. [GatewayClient.request] 不暴露它生成的 requestId，所以 `speech-cancel`
///    无法指向本客户端发起的转写；[SpeechController.cancel] 只能本地放弃
///    在途结果（服务端会跑到 180 s 超时，期间本连接可能回 `speech/busy`）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gateway.dart';
import 'speech_types.dart';

export 'speech_types.dart';

/// 录音器抽象：测试注入 fake，不依赖真实麦克风。
abstract class SpeechRecorder {
  Future<SpeechDeviceStatus> status();

  Future<bool> requestPermission();

  /// 开始录音；[maxBytes] 是 WAV 总字节上限（原生可据此截断）。
  Future<void> start({required int maxBytes});

  Future<SpeechRecording> stop();

  Future<void> cancel();
}

/// 原生通道 `dsh/speech`（Android `SpeechChannel.kt`，iOS `DshSpeechChannels.swift`）。
class NativeSpeechRecorder implements SpeechRecorder {
  const NativeSpeechRecorder([
    this._channel = const MethodChannel('dsh/speech'),
  ]);

  final MethodChannel _channel;

  /// OHOS/桌面端显式不支持：不探测通道，直接回 false。
  static bool get platformSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<SpeechDeviceStatus> status() async {
    if (!platformSupported) return SpeechDeviceStatus.unsupported;
    try {
      final map =
          await _channel.invokeMapMethod<String, Object?>('status') ?? const {};
      return SpeechDeviceStatus(
        supported: map['supported'] == true,
        granted: map['granted'] == true,
        canRequest: map['canRequest'] == true,
      );
    } on MissingPluginException {
      return SpeechDeviceStatus.unsupported;
    } on PlatformException {
      return SpeechDeviceStatus.unsupported;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!platformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> start({required int maxBytes}) async {
    try {
      final error = await _channel.invokeMethod<String>(
        'start',
        <String, Object>{'maxBytes': maxBytes},
      );
      if (error != null && error.isNotEmpty) {
        throw SpeechException('mic/failed', error);
      }
    } on MissingPluginException {
      throw const SpeechException('mic/unsupported', '当前平台暂不支持语音输入');
    } on PlatformException catch (error) {
      throw SpeechException('mic/failed', error.message ?? '录音启动失败');
    }
  }

  @override
  Future<SpeechRecording> stop() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('stop');
      if (map == null) {
        throw const SpeechException('mic/failed', '录音已结束，没有拿到音频');
      }
      return SpeechRecording.fromMap(Map<String, dynamic>.from(map));
    } on MissingPluginException {
      throw const SpeechException('mic/unsupported', '当前平台暂不支持语音输入');
    } on PlatformException catch (error) {
      throw SpeechException('mic/failed', error.message ?? '录音失败');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // 通道缺席：没有录音可取消，忽略。
    } on PlatformException {
      // 取消是尽力而为，失败不打断 UI。
    }
  }
}

/// 网关上的 `speech-*` 请求封装（不改 gateway.dart，只走公开 request）。
class SpeechClient {
  SpeechClient(this.gateway);

  final GatewayClient gateway;

  /// 探测目录。老桥没有这个帧时会超时——探测用短超时，未接通就不显示话筒。
  Future<SpeechCatalog> catalog() async {
    final data = await gateway.requestWithTimeout(
      'speech-catalog',
      const <String, dynamic>{},
      const Duration(seconds: 8),
    );
    return SpeechCatalog.fromJson(data);
  }

  /// 预下载/准备 provider（首次使用时可能较久，超时放宽到 180 s）。
  Future<void> prepare(String providerId) async {
    await gateway.requestWithTimeout('speech-prepare', <String, dynamic>{
      'providerId': providerId,
    }, const Duration(seconds: 180));
  }

  /// 转写一段 WAV（base64）。桥侧超时 180 s，客户端多留 10 s。
  Future<SpeechTranscript> transcribe(
    String audioBase64, {
    String? providerId,
    String? language,
  }) async {
    final data = await gateway.requestWithTimeout(
      'speech-transcribe',
      <String, dynamic>{
        'audioBase64': audioBase64,
        if (providerId != null && providerId.isNotEmpty)
          'providerId': providerId,
        if (language != null && language.isNotEmpty) 'language': language,
      },
      const Duration(seconds: 190),
    );
    return SpeechTranscript.fromJson(data);
  }

  /// 取消一条**已知 requestId** 的在途转写。
  ///
  /// 当前 [GatewayClient.request] 不暴露 requestId，控制器发起的转写拿不到它，
  /// 所以 UI 的「取消」只能本地放弃；此方法留给能拿到 requestId 的调用方
  /// （例如后续网关开放推送/请求句柄时）。
  Future<void> cancelTranscription(String targetRequestId) async {
    await gateway.request('speech-cancel', <String, dynamic>{
      'targetRequestId': targetRequestId,
    });
  }
}

/// 语音输入的阶段。
enum SpeechPhase { idle, recording, preparing, transcribing }

/// 输入条话筒的状态机：目录可见性、权限、录音、准备、转写、取消。
class SpeechController extends ChangeNotifier {
  SpeechController({required GatewayClient gateway, SpeechRecorder? recorder})
    : client = SpeechClient(gateway),
      _gateway = gateway,
      recorder = recorder ?? const NativeSpeechRecorder();

  final GatewayClient _gateway;
  final SpeechClient client;
  final SpeechRecorder recorder;

  SpeechPhase _phase = SpeechPhase.idle;
  SpeechCatalog? _catalog;
  SpeechDeviceStatus _device = SpeechDeviceStatus.unsupported;
  String? _error;
  String? _preparedProviderId;
  StreamSubscription<Map<String, dynamic>>? _pushSub;
  bool _disposed = false;
  int _take = 0;

  SpeechPhase get phase => _phase;
  SpeechCatalog? get catalog => _catalog;
  SpeechDeviceStatus get device => _device;
  String? get error => _error;
  bool get recording => _phase == SpeechPhase.recording;
  bool get busy =>
      _phase == SpeechPhase.preparing || _phase == SpeechPhase.transcribing;

  /// 话筒是否该出现：目录可用 + 平台支持 + （已授权或还能申请）。
  bool get visible =>
      _catalog?.available == true &&
      _device.supported &&
      (_device.granted || _device.canRequest);

  /// 录音/准备/转写时输入框的提示语。
  String? get statusText => switch (_phase) {
    SpeechPhase.recording => '正在录音 · 点按话筒结束',
    SpeechPhase.preparing => '正在准备语音模型…',
    SpeechPhase.transcribing => '正在转写…',
    SpeechPhase.idle => null,
  };

  /// 本次连接允许的 WAV 总字节：桥给的上限与 WS 单帧预算取小。
  int get maxAudioBytes => math.min(
    _catalog?.maxAudioBytes ?? speechMaxAudioBytes,
    speechAudioByteLimit(_gateway.frameLimitBytes),
  );

  /// 本次允许的录音时长（毫秒）：字节上限与插件时长上限取小。
  int get maxDurationMs {
    final byBytes =
        math.max(0, maxAudioBytes - speechWavHeaderBytes) *
        1000 ~/
        speechBytesPerSecond;
    final byPlugin = (_catalog?.maxDurationSeconds ?? 120) * 1000;
    return math.min(byBytes, byPlugin);
  }

  /// 探测目录与麦克风权限。失败只是「不显示话筒」，不弹错。
  Future<void> probe() async {
    try {
      final catalog = await client.catalog();
      if (_disposed) return;
      _catalog = catalog;
      // 即便 catalog 不可用也问一次设备能力：之后 `speech-state` 推来
      // 「可用」时不必再等一次权限探测，话筒能立刻出现。
      _device = await recorder.status();
      _error = null;
    } on Object {
      if (_disposed) return;
      _catalog = null;
      _device = SpeechDeviceStatus.unsupported;
    }
    if (!_disposed) notifyListeners();
  }

  /// 收到一帧推送：目前只吃 `speech-state`（刷新目录/selection）。
  void ingestPush(Map<String, dynamic> frame) {
    final push = parseSpeechPush(frame);
    if (push is! SpeechStatePush || _disposed) return;
    _catalog = push.catalog;
    if (push.catalog.available && !_device.supported) {
      // 探测时插件还没启用：这里补一次设备能力，成功后再通知 UI。
      unawaited(_refreshDevice());
      return;
    }
    notifyListeners();
  }

  Future<void> _refreshDevice() async {
    try {
      final device = await recorder.status();
      if (_disposed) return;
      _device = device;
    } on Object {
      return;
    }
    if (!_disposed) notifyListeners();
  }

  /// 接入网关将来暴露的推送旁路流（当前 gateway 会丢弃未知 kind）。
  void attachPushStream(Stream<Map<String, dynamic>> pushes) {
    _pushSub?.cancel();
    _pushSub = pushes.listen(ingestPush);
  }

  /// 开始录音：必要时申请权限；失败写 [error] 并回到 idle。
  Future<void> begin() async {
    if (_phase != SpeechPhase.idle) return;
    _error = null;
    try {
      var device = await recorder.status();
      if (_disposed) return;
      _device = device;
      if (!device.supported) {
        throw const SpeechException('mic/unsupported', '当前平台暂不支持语音输入');
      }
      if (!device.granted) {
        final granted = await recorder.requestPermission();
        device = await recorder.status();
        if (_disposed) return;
        _device = device;
        if (!granted || !device.granted) {
          throw const SpeechException('mic/permission', '需要麦克风权限才能语音输入');
        }
      }
      final limit = maxAudioBytes;
      if (limit <= speechWavHeaderBytes) {
        throw const SpeechException('speech/invalid-audio', '当前连接上限太小，无法发送录音');
      }
      await recorder.start(maxBytes: limit);
      if (_disposed) {
        await recorder.cancel();
        return;
      }
      _phase = SpeechPhase.recording;
      notifyListeners();
    } on Object catch (error) {
      _fail(describeSpeechError(error));
    }
  }

  /// 结束录音并转写。成功返回文本（空串 = 没识别到语音），失败返回 null。
  Future<String?> finish() async {
    if (_phase != SpeechPhase.recording) return null;
    final take = ++_take;
    try {
      final recording = await recorder.stop();
      if (take != _take || _disposed) return null;
      final wav = recording.toWavBytes();
      if (wav.length <= speechWavHeaderBytes) {
        throw const SpeechException('speech/invalid-audio', '没有录到声音，请重试');
      }
      if (wav.length > maxAudioBytes) {
        throw const SpeechException('speech/invalid-audio', '录音太长，请缩短后重试');
      }
      final providerId = _catalog?.providerId;
      if (providerId != null &&
          providerId.isNotEmpty &&
          providerId != _preparedProviderId) {
        _setPhase(SpeechPhase.preparing);
        await client.prepare(providerId);
        if (take != _take || _disposed) return null;
        _preparedProviderId = providerId;
      }
      _setPhase(SpeechPhase.transcribing);
      final transcript = await client.transcribe(
        base64Encode(wav),
        providerId: providerId,
        language: _catalog?.language,
      );
      if (take != _take || _disposed) return null;
      _setPhase(SpeechPhase.idle);
      final text = transcript.text.trim();
      if (text.isEmpty) {
        _error = '没有识别到语音';
        notifyListeners();
        return '';
      }
      return text;
    } on Object catch (error) {
      if (take != _take || _disposed) return null;
      _fail(describeSpeechError(error));
      return null;
    }
  }

  /// 取消：录音中会让原生丢弃缓冲；准备/转写中只本地放弃（见类头限制）。
  Future<void> cancel() async {
    if (_phase == SpeechPhase.idle) return;
    _take++;
    final wasRecording = _phase == SpeechPhase.recording;
    _setPhase(SpeechPhase.idle);
    if (wasRecording) {
      try {
        await recorder.cancel();
      } on Object {
        // 取消是尽力而为。
      }
    }
  }

  void _setPhase(SpeechPhase phase) {
    if (_disposed) return;
    _phase = phase;
    if (phase == SpeechPhase.idle) _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    if (_disposed) return;
    _error = message;
    _phase = SpeechPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pushSub?.cancel();
    _pushSub = null;
    unawaited(recorder.cancel());
    super.dispose();
  }
}
