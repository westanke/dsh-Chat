import 'package:flutter/services.dart';

/// 原生设备信息通道：IANA 时区名。
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

  static Future<void> init() async {
    try {
      final zone = await _channel.invokeMethod<String>('ianaZone');
      if (zone != null && zone.isNotEmpty) ianaZone = zone;
    } on PlatformException {
      // 保留 'UTC' 回退。
    } on MissingPluginException {
      // 测试环境无插件，保留回退。
    }
  }
}
