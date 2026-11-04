import 'package:flutter/services.dart';

/// 原生平台能力通道：系统 TTS 朗读与系统分享（真机反馈 2026-11-04）。
///
/// 调用系统资源、零第三方依赖：Android 走 TextToSpeech +
/// Intent.ACTION_SEND createChooser（MainActivity.kt 的 dsh/platform）；
/// iOS 未实现时 invokeMethod 抛 MissingPluginException / notImplemented，
/// 调用方 catch 后走「暂不支持」提示（与宪法 §9 未验证不写已完成一致）。
class DshPlatform {
  DshPlatform._();

  static const MethodChannel _channel = MethodChannel('dsh/platform');

  /// 用系统 TTS 朗读一段文本。返回是否成功启动（TTS 初始化失败返回 false）。
  static Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('speak', text) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 停止朗读（切换消息 / 退出页面时调用；幂等）。
  static Future<void> stopSpeak() async {
    try {
      await _channel.invokeMethod<void>('stopSpeak');
    } on PlatformException {
      // 忽略：停止失败无影响。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 调起系统分享面板（纯文本）。返回是否有可用接收方。
  static Future<bool> share(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('share', text) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 调起系统相册/文件选择器选一张图（真机反馈 2026-11-04 第 2 项，
  /// 零依赖方案：Android ACTION_GET_CONTENT，vivo 拦应用内注入但不拦系统选择器）。
  /// 返回 {path, name}（复制进应用缓存目录后返回路径）；取消返回 null。
  static Future<Map<String, String>?> pickImage() async {
    try {
      final r = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickImage');
      if (r == null) return null;
      final path = r['path'] as String?;
      final name = r['name'] as String?;
      if (path == null || path.isEmpty) return null;
      return {'path': path, 'name': name ?? ''};
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
