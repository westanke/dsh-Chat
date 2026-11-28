import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生平台能力通道：系统 TTS 朗读与系统分享（真机反馈 2026-11-04）。
///
/// 调用系统资源、零第三方依赖：Android 走 TextToSpeech +
/// Intent.ACTION_SEND createChooser（MainActivity.kt 的 dsh/platform）；
/// iOS 走 AVSpeechSynthesizer + UIActivityViewController + PHPickerViewController
/// （AppDelegate 注册的 DshPlatformChannels.swift）。通道不可用时调用方
/// catch 后走「暂不支持」提示（与宪法 §9 未验证不写已完成一致）。
class DshPlatform {
  DshPlatform._();

  static const MethodChannel _channel = MethodChannel('dsh/platform');

  /// 能否在 App 内完成「下载新版 + 拉起安装」全流程。
  ///
  /// 只有 Android 走系统 DownloadManager 能做到。鸿蒙是应用市场审核制
  /// （装 HAP / 升级都要走市场），iOS 是 App Store 分发 —— 两端都只能
  /// 提示用户去对应商店升级（2026-11-25 三端统一口径）。
  static bool get supportsInAppUpdate =>
      defaultTargetPlatform == TargetPlatform.android;

  /// 升级要去的应用商店名（提示文案用；Android 不需要）。
  static String get updateStoreName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.ohos:
        return '华为应用市场（AppGallery）';
      case TargetPlatform.iOS:
        return 'App Store';
      case TargetPlatform.android:
        return '应用商店';
      default:
        return '应用商店';
    }
  }

  /// 本机安装版本（"versionName+versionCode"，如 1.0.14+15）。
  ///
  /// Android 读 gradle versionName/longVersionCode、iOS 读
  /// CFBundleShortVersionString/CFBundleVersion——两者都由 Flutter 工具链从
  /// app/pubspec.yaml 的 version 自动注入，随发版自动同步（2026-11-15
  /// 发版号漂移修复：不再在 Dart 侧写死版本字符串）。
  /// 成功结果缓存（整包生命周期版本不变）；失败（含测试环境无 handler）
  /// 返回 null，调用方降级展示并跳过更新比较。
  static String? _cachedVersion;

  static Future<String?> appVersion() async {
    if (_cachedVersion != null) return _cachedVersion;
    try {
      final r =
          await _channel.invokeMethod<Map<Object?, Object?>>('appVersion');
      final v = r?['version'] as String?;
      final c = r?['code'] as num?;
      if (v != null && v.isNotEmpty && c != null) {
        _cachedVersion = '$v+$c';
      }
    } on PlatformException {
      // 原生侧异常：落 null 降级。
    } on MissingPluginException {
      // 测试环境无 handler：落 null 降级。
    }
    return _cachedVersion;
  }

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

  /// 调起系统分享面板分享**文件字节**（产物卡/交付卡用）。
  ///
  /// 与 [share] 的区别：接收方收到的是文件本体，不是路径字符串。
  /// Android 写应用缓存 + FileProvider + ACTION_SEND；iOS 写 caches +
  /// UIActivityViewController；鸿蒙暂未接入，返回 false，调用方回退路径分享。
  static Future<bool> shareFile({
    required String name,
    required List<int> bytes,
    String? mime,
  }) async {
    if (name.trim().isEmpty || bytes.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('shareFile', {
            'name': name,
            'mime': mime ?? '',
            'bytes': Uint8List.fromList(bytes),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 调起系统相册/文件选择器选一张图（真机反馈 2026-11-04 第 2 项，
  /// 零依赖方案：Android ACTION_GET_CONTENT，vivo 拦应用内注入但不拦系统选择器）。
  ///
  /// 返回 {path, name, mediaType}（原生侧已按字节魔数定类型，并把内核不收的
  /// HEIC/HEIF/BMP/AVIF 转码成 JPEG/PNG 后复制进应用缓存目录）；
  /// 失败返回 {error: 中文原因}（不再静默吞掉，docs/huawei-heic-upload-report.md
  /// §4.4）；用户取消返回 null。
  static Future<Map<String, String>?> pickImage() async {
    try {
      final r = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickImage');
      if (r == null) return null;
      final error = r['error'] as String?;
      if (error != null && error.isNotEmpty) {
        return {'error': error};
      }
      final path = r['path'] as String?;
      final name = r['name'] as String?;
      final mediaType = r['mediaType'] as String?;
      if (path == null || path.isEmpty) return null;
      return {
        'path': path,
        'name': name ?? '',
        'mediaType': mediaType ?? '',
      };
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 交给系统 DownloadManager 下载 APK（真机反馈 2026-11-04 第 9 项）。
  /// 返回任务 id（>0 有效，-1 = 失败）；用 [downloadStatus] 轮询进度，
  /// 完成后用 [installApk] 拉起安装（第二轮反馈 C）。
  static Future<int> downloadApk(String url, String name) async {
    if (url.trim().isEmpty || name.trim().isEmpty) return -1;
    try {
      return await _channel.invokeMethod<int>('downloadApk', {
            'url': url,
            'name': name,
          }) ??
          -1;
    } on PlatformException {
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }

  /// 查询下载任务状态（第二轮反馈 C）。status：8 = 完成，16 = 失败，
  /// 1-4 = 运行中（DownloadManager.STATUS_* 原值透传）。
  /// 任务不存在/被清理也按失败回（status 16）。
  static Future<Map<String, int>?> downloadStatus(int id) async {
    if (id <= 0) return null;
    try {
      final r = await _channel
          .invokeMethod<Map<Object?, Object?>>('downloadStatus', {'id': id});
      if (r == null) return null;
      return {
        'status': (r['status'] as num?)?.toInt() ?? 16,
        'bytes': (r['bytes'] as num?)?.toInt() ?? 0,
        'total': (r['total'] as num?)?.toInt() ?? 0,
      };
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 拉起系统安装器安装已完成的 APK（第二轮反馈 C）。
  /// 返回是否成功调起；「安装未知应用」授权由系统安装器向用户索取。
  static Future<bool> installApk(int id) async {
    if (id <= 0) return false;
    try {
      return await _channel.invokeMethod<bool>('installApk', {'id': id}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 用系统「打开方式」打开文件字节（文件卡第四轮反馈 6 改进：
  /// 非 md 文件交给系统查看器）。字节写入应用缓存目录后经 FileProvider
  /// 共享——Android ACTION_VIEW，无存储权限。返回是否成功调起。
  static Future<bool> openFile({
    required String name,
    required List<int> bytes,
    String? mime,
  }) async {
    if (name.trim().isEmpty || bytes.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('openFile', {
            'name': name,
            'mime': mime ?? '',
            'bytes': Uint8List.fromList(bytes),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
