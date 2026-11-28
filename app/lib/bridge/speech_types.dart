/// 语音输入的纯数据层：WAV 打包、目录/转写模型、服务端推送解析、
/// 原生录音结果模型。全部无 Flutter 依赖（除异常文案），可直接单测。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'gateway_events.dart';

/// 16 kHz PCM16 单声道：桥/官方插件唯一接受的音频格式。
const int speechSampleRate = 16000;
const int speechChannels = 1;
const int speechBitsPerSample = 16;
const int speechWavHeaderBytes = 44;

/// 16 kHz / 单声道 / 16 bit 每秒原始字节数（32000）。
const int speechBytesPerSecond =
    speechSampleRate * speechChannels * speechBitsPerSample ~/ 8;

/// 桥侧 `MAX_AUDIO_BYTES`（base64 解码后的上限）。
const int speechMaxAudioBytes = 4 * 1024 * 1024;

/// 由 WS 单帧上限推 base64 解码后的音频字节上限。
///
/// 与桥 `speechAudioLimit` 同一算式（留 4 KiB JSON 信封，base64 按 4/3 膨胀），
/// 避免客户端算得比桥宽松、发出去才被 `speech/invalid-audio` 拒绝。
int speechAudioByteLimit(int frameLimitBytes) {
  final payload = frameLimitBytes - 4096;
  if (payload <= 0) return 0;
  return math.min(speechMaxAudioBytes, (payload ~/ 4) * 3);
}

/// 把 PCM16 小端字节包成 44 字节头的 RIFF/WAVE。
Uint8List wavFromPcm16(
  List<int> pcm, {
  int sampleRate = speechSampleRate,
  int channels = speechChannels,
}) {
  final out = Uint8List(speechWavHeaderBytes + pcm.length);
  final data = ByteData.view(out.buffer);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out[at + i] = text.codeUnitAt(i);
    }
  }

  final byteRate = sampleRate * channels * speechBitsPerSample ~/ 8;
  final blockAlign = channels * speechBitsPerSample ~/ 8;
  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, speechBitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  out.setRange(speechWavHeaderBytes, out.length, pcm);
  return out;
}

/// 是否是 RIFF/WAVE 头（原生返回格式兜底核对）。
bool isWavBytes(List<int> bytes) {
  if (bytes.length < 12) return false;
  return bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;
}

/// WAV 总字节 → 录音时长（毫秒，按 16 kHz 单声道 PCM16 算）。
int wavDurationMs(int wavBytes) {
  final pcm = math.max(0, wavBytes - speechWavHeaderBytes);
  return pcm * 1000 ~/ speechBytesPerSecond;
}

String? _str(Object? value) => value is String ? value : null;

int? _int(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  _ => null,
};

double? _double(Object? value) => switch (value) {
  num v => v.toDouble(),
  _ => null,
};

/// 目录里的一个语音 provider。
class SpeechProvider {
  const SpeechProvider({
    required this.id,
    required this.name,
    this.languages = const <String>[],
    this.location,
  });

  factory SpeechProvider.fromJson(Map<String, dynamic> json) {
    final languages = <String>[];
    final raw = json['languages'];
    if (raw is List) {
      for (final language in raw) {
        final value = _str(language);
        if (value != null && value.isNotEmpty) languages.add(value);
      }
    }
    return SpeechProvider(
      id: _str(json['id']) ?? '',
      name: _str(json['name']) ?? '',
      languages: languages,
      location: _str(json['location']),
    );
  }

  final String id;
  final String name;
  final List<String> languages;

  /// 插件给出的下载/更新来源（可选，`speech-prepare` 可透传）。
  final String? location;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'languages': languages,
    if (location != null) 'location': location,
  };
}

/// `speech-catalog` / `speech-state` 归一后的目录。
class SpeechCatalog {
  const SpeechCatalog({
    required this.available,
    this.providers = const <SpeechProvider>[],
    this.providerId,
    this.language,
    this.maxAudioBytes = speechMaxAudioBytes,
    this.maxDurationSeconds = 120,
    this.code,
    this.message,
  });

  factory SpeechCatalog.fromJson(Map<String, dynamic> json) {
    final providers = <SpeechProvider>[];
    final raw = json['providers'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final provider = SpeechProvider.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (provider.id.isNotEmpty) providers.add(provider);
      }
    }
    final selection = json['selection'];
    final selected = selection is Map
        ? Map<String, dynamic>.from(selection)
        : const <String, dynamic>{};
    return SpeechCatalog(
      available: json['available'] == true,
      providers: providers,
      providerId: _str(selected['providerId']),
      language: _str(selected['language']),
      maxAudioBytes: _int(json['maxAudioBytes']) ?? speechMaxAudioBytes,
      maxDurationSeconds: _int(json['maxDurationSeconds']) ?? 120,
      code: _str(json['code']),
      message: _str(json['message']),
    );
  }

  /// 内核是否注册了官方语音服务（false 时输入条不显示话筒）。
  final bool available;
  final List<SpeechProvider> providers;

  /// 内核当前选中的 provider / 语言（catalog.selection）。
  final String? providerId;
  final String? language;

  /// 桥按本次 WS 帧预算夹过的音频上限（字节）。
  final int maxAudioBytes;

  /// 官方插件允许的单段录音时长（秒）。
  final int maxDurationSeconds;

  /// `available:false` 时桥给的原因码与引导语。
  final String? code;
  final String? message;

  /// 选中 provider 的展示名；没选中/未命中时退回 id。
  String? get providerLabel {
    final id = providerId;
    if (id == null || id.isEmpty) return null;
    for (final provider in providers) {
      if (provider.id == id) return provider.name;
    }
    return id;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'available': available,
    'providers': [for (final provider in providers) provider.toJson()],
    'selection': <String, dynamic>{
      if (providerId != null) 'providerId': providerId,
      if (language != null) 'language': language,
    },
    'maxAudioBytes': maxAudioBytes,
    'maxDurationSeconds': maxDurationSeconds,
    if (code != null) 'code': code,
    if (message != null) 'message': message,
  };
}

/// `speech-transcript` 的正文（`text` 为空串 = 没识别到语音，不是错误）。
class SpeechTranscript {
  const SpeechTranscript({
    required this.text,
    this.audioSeconds = 0,
    this.inferenceSeconds = 0,
  });

  factory SpeechTranscript.fromJson(Map<String, dynamic> json) =>
      SpeechTranscript(
        text: _str(json['text']) ?? '',
        audioSeconds: _double(json['audioSeconds']) ?? 0,
        inferenceSeconds: _double(json['inferenceSeconds']) ?? 0,
      );

  final String text;
  final double audioSeconds;
  final double inferenceSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'audioSeconds': audioSeconds,
    'inferenceSeconds': inferenceSeconds,
  };
}

/// 服务端推送（`kind` + `data`）。
sealed class SpeechPush {
  const SpeechPush();
}

/// `speech-state`：跟随流的就绪快照（目录 + selection）。
class SpeechStatePush extends SpeechPush {
  const SpeechStatePush({required this.catalog, this.followRequestId});

  final SpeechCatalog catalog;
  final String? followRequestId;
}

/// `speech-preparing`：`speech-prepare` 的响应/推送。
class SpeechPreparingPush extends SpeechPush {
  const SpeechPreparingPush({required this.providerId, this.requestId});

  final String providerId;
  final String? requestId;
}

/// `speech-transcript` 推送（本客户端走 request 响应，收到也照收）。
class SpeechTranscriptPush extends SpeechPush {
  const SpeechTranscriptPush({required this.transcript, this.requestId});

  final SpeechTranscript transcript;
  final String? requestId;
}

/// 解析一帧推送；不是语音推送返回 null。
SpeechPush? parseSpeechPush(Map<String, dynamic> frame) {
  final kind = _str(frame['kind']) ?? _str(frame['type']);
  final raw = frame['data'];
  final data = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  switch (kind) {
    case 'speech-state':
      return SpeechStatePush(
        catalog: SpeechCatalog.fromJson(data),
        followRequestId: _str(data['requestId']),
      );
    case 'speech-preparing':
      return SpeechPreparingPush(
        providerId: _str(data['providerId']) ?? '',
        requestId: _str(data['requestId']),
      );
    case 'speech-transcript':
      return SpeechTranscriptPush(
        transcript: SpeechTranscript.fromJson(data),
        requestId: _str(data['requestId']),
      );
    default:
      return null;
  }
}

/// 客户端侧失败（权限/录音/本地校验），与网关的 [RequestException] 区分。
class SpeechException implements Exception {
  const SpeechException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// 把任意异常翻成能直接上屏的一句话。
String describeSpeechError(Object error) {
  if (error is SpeechException) return error.message;
  if (error is RequestException) {
    switch (error.code) {
      case 'speech/unavailable':
        return '语音输入不可用：请在 DSH 插件管理启用官方语音输入插件';
      case 'speech/busy':
        return '语音转写正忙，请稍后再试';
      case 'speech/timeout':
        return '语音转写超时，请重试';
      case 'speech/invalid-audio':
        return '录音数据无效，请重新录制';
      case 'speech/request-in-progress':
        return '上一次语音请求还没结束，请稍等';
    }
    return error.message.isEmpty ? '语音输入失败（${error.code}）' : error.message;
  }
  return '语音输入失败：$error';
}

/// 平台录音能力（Android/iOS 原生通道；OHOS 显式不支持）。
class SpeechDeviceStatus {
  const SpeechDeviceStatus({
    required this.supported,
    required this.granted,
    required this.canRequest,
  });

  static const SpeechDeviceStatus unsupported = SpeechDeviceStatus(
    supported: false,
    granted: false,
    canRequest: false,
  );

  final bool supported;
  final bool granted;

  /// 还能弹系统授权框（false = 已永久拒绝，只能去系统设置开）。
  final bool canRequest;
}

/// 一次原生录音的结果：WAV（或裸 PCM16）base64 + 格式。
class SpeechRecording {
  const SpeechRecording({
    required this.base64,
    required this.format,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.durationMs,
    this.truncated = false,
  });

  factory SpeechRecording.fromMap(Map<String, dynamic> map) {
    final error = _str(map['error']);
    if (error != null && error.isNotEmpty) {
      throw SpeechException('mic/failed', error);
    }
    final audio = _str(map['base64']);
    if (audio == null || audio.isEmpty) {
      throw const SpeechException('mic/empty', '没有录到音频，请重试');
    }
    return SpeechRecording(
      base64: audio,
      format: _str(map['format']) ?? 'wav',
      sampleRate: _int(map['sampleRate']) ?? speechSampleRate,
      channels: _int(map['channels']) ?? speechChannels,
      bitsPerSample: _int(map['bitsPerSample']) ?? speechBitsPerSample,
      durationMs:
          _int(map['durationMs']) ?? wavDurationMs(base64Decode(audio).length),
      truncated: map['truncated'] == true,
    );
  }

  final String base64;

  /// `wav`（Android/iOS 原生写好头）或 `pcm16`（裸字节，客户端补头）。
  final String format;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int durationMs;

  /// 触到帧上限被原生截短（UI 可提示「录音过长，已截断」）。
  final bool truncated;

  /// 统一成可直接发给桥的 WAV 字节。
  Uint8List toWavBytes() {
    final raw = base64Decode(base64);
    if (format == 'pcm16') {
      return wavFromPcm16(raw, sampleRate: sampleRate, channels: channels);
    }
    return raw;
  }
}
