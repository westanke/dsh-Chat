import 'package:flutter/services.dart';

/// 原生设备信息通道：IANA 时区名 + 设备展示名 + 应用私有目录。
///
/// bridge 校验 clientTimeZone 必须是 "UTC" 或 IANA Area/Location
/// （dsh-remote-bridge src/host/bff-schedule.ts:488 IANA_ZONE 正则）；
/// Dart 的 DateTime.timeZoneName 在 Android/iOS 返回缩写或 GMT 偏移，
/// 不合规，必须经 MethodChannel 读原生 TimeZone id。
class DshDevice {
  DshDevice._();

  static const MethodChannel _channel = MethodChannel('dsh/device');

  /// 当前 IANA 时区名；通道不可用时回退 'UTC'（合法但显示时间会用零区）。
  static String ianaZone = 'UTC';

  /// 设备名称（系统设置里给这台设备起的名字；取不到回空串）。
  static String deviceName = '';

  /// 用于配对/桥登记的展示名：`DSH Chat (<设备名>)`；无设备名时退化为 `DSH Chat`。
  static String get displayName => labelFor(deviceName);

  /// 纯函数版展示名，便于测试；空格折叠、过长截断。
  static String labelFor(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\s]+'), ' ').trim();
    if (cleaned.isEmpty) return 'DSH Chat';
    if (cleaned.length > 80) return 'DSH Chat (${cleaned.substring(0, 77)}…)';
    return 'DSH Chat ($cleaned)';
  }

  /// 应用私有目录（原生 context.filesDir）。
  ///
  /// 2026-11-25：鸿蒙端 Dart 拿不到沙盒绝对路径（引擎不设 cwd），
  /// 文件日志要落在私有目录就得由原生回传；通道不可用时为 null
  /// （调用方退回相对路径 / 静默跳过）。
  static String? filesDir;

  static Future<void> init() async {
    try {
      final zone = await _channel.invokeMethod<String>('ianaZone');
      if (zone != null && zone.isNotEmpty) ianaZone = zone;
    } on PlatformException {
      // 保留 'UTC' 回退。
    } on MissingPluginException {
      // 测试环境无插件，保留回退。
    }
    try {
      final name = await _channel.invokeMethod<String>('deviceName');
      if (name != null && name.trim().isNotEmpty) {
        deviceName = name.replaceAll(RegExp(r'[\s]+'), ' ').trim();
      }
    } on PlatformException {
      // 保留空串回退。
    } on MissingPluginException {
      // 测试环境无插件，保留空串回退。
    }
    try {
      final dir = await _channel.invokeMethod<String>('filesDir');
      if (dir != null && dir.isNotEmpty) filesDir = dir;
    } on PlatformException {
      // 保留 null 回退。
    } on MissingPluginException {
      // 测试环境无插件，保留 null 回退。
    }
  }
}
