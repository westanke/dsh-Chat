/// 应用内偏好（纯本地，宪法 §4/§8：与桥接凭据分库，读偏好失败不该让聊天页起不来）。
///
/// 对照 dsh-companion data/AppPreferences.kt：
/// - 枚举存 name 不存 ordinal（调整枚举顺序不会把老用户「深色」静默读成「浅色」）；
/// - 字号 normalizeFontScale 夹 0.8..1.5，NaN/Inf 回落 1.0（否则界面尺寸 NaN 白屏）；
/// - effectiveFontScale 与系统字号相乘而非覆盖（尊重无障碍设置，见 ui/theme/AppFontScale.kt）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextScaler;
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

/// 应用内字号缩放：把「系统无障碍字号」与「应用内缩放」相乘而非覆盖，
/// 对齐 dsh-companion ui/theme/AppFontScale.kt 的 ScaledDensity（base.fontScale * appScale）。
///
/// 不能简单用 `TextScaler.linear(appScale)`：那会丢掉用户在系统设置里调大的字号。
/// `textScaleFactor` 只是向后兼容的估计值，用 `scale(1.0)` 推导，避免触碰已废弃成员。
@immutable
class AppFontScaler implements TextScaler {
  const AppFontScaler(this.base, this.appScale);

  final TextScaler base;
  final double appScale;

  @override
  double scale(double fontSize) => base.scale(fontSize) * appScale;

  @override
  double get textScaleFactor => scale(1.0);

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) =>
      AppFontScaler(
        base.clamp(
          minScaleFactor: minScaleFactor,
          maxScaleFactor: maxScaleFactor,
        ),
        appScale,
      );

  @override
  bool operator ==(Object other) =>
      other is AppFontScaler &&
      other.base == base &&
      other.appScale == appScale;

  @override
  int get hashCode => Object.hash(base, appScale);

  @override
  String toString() => '$base × ${appScale}x';
}

enum BusySendMode { queue, steer }

/// 顶层纯函数：NaN/Inf → 1.0，否则夹到 [0.8, 1.5]（对齐 AppPreferences.kt:213）。
double normalizeFontScale(double value) =>
    value.isFinite ? value.clamp(0.8, 1.5).toDouble() : 1.0;

class AppSettings extends ChangeNotifier {
  AppSettings();

  static const String _key = 'dsh.settings';

  AppThemeMode _themeMode = AppThemeMode.system;
  double _fontScale = 1.0;
  bool _fontFollowsSystem = false;
  BusySendMode _busySendMode = BusySendMode.queue;
  bool _diagLog = true;

  AppThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;
  bool get fontFollowsSystem => _fontFollowsSystem;
  BusySendMode get busySendMode => _busySendMode;
  bool get diagLog => _diagLog;

  /// 与系统字号相乘的系数：跟随系统时为 1.0（即只用系统无障碍字号），
  /// 否则为应用内设定的缩放（对齐 AppPreferences.effectiveFontScale()）。
  double get effectiveFontScale => _fontFollowsSystem ? 1.0 : _fontScale;

  Future<void> load() async {
    Map<String, dynamic>? j;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } on FormatException {
      j = null; // 坏 JSON：保留默认
    } catch (_) {
      j = null; // 测试环境无插件 / 平台异常：保留默认，绝不让聊天页起不来
    }
    if (j != null) {
      // 按 name 读取，不依赖枚举顺序（对齐 AppPreferences.kt 存 name 不存 ordinal）。
      final tm = j['themeMode'];
      _themeMode = tm is String
          ? (AppThemeMode.values.asNameMap()[tm] ?? AppThemeMode.system)
          : AppThemeMode.system;
      final fs = j['fontScale'];
      _fontScale = fs is num ? normalizeFontScale(fs.toDouble()) : 1.0;
      _fontFollowsSystem = j['fontFollowsSystem'] == true;
      final bm = j['busySendMode'];
      _busySendMode = bm is String
          ? (BusySendMode.values.asNameMap()[bm] ?? BusySendMode.queue)
          : BusySendMode.queue;
      _diagLog = j['diagLog'] != false;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _key,
        jsonEncode({
          'themeMode': _themeMode.name,
          'fontScale': _fontScale,
          'fontFollowsSystem': _fontFollowsSystem,
          'busySendMode': _busySendMode.name,
          'diagLog': _diagLog,
        }),
      );
    } catch (_) {
      // 持久化失败不影响本次会话内的偏好生效。
    }
  }

  void setThemeMode(AppThemeMode v) {
    if (_themeMode == v) return;
    _themeMode = v;
    notifyListeners();
    _save();
  }

  void setFontScale(double v) {
    final n = normalizeFontScale(v);
    if (_fontScale == n) return;
    _fontScale = n;
    notifyListeners();
    _save();
  }

  void setFontFollowsSystem(bool v) {
    if (_fontFollowsSystem == v) return;
    _fontFollowsSystem = v;
    notifyListeners();
    _save();
  }

  void setBusySendMode(BusySendMode v) {
    if (_busySendMode == v) return;
    _busySendMode = v;
    notifyListeners();
    _save();
  }

  void setDiagLog(bool v) {
    if (_diagLog == v) return;
    _diagLog = v;
    notifyListeners();
    _save();
  }
}

/// 全局单例（与 DshCredentials 的静态风格一致）：必须位于 MaterialApp 之上，
/// 因为主题三档与字号缩放要重建 MaterialApp / MediaQuery。
final AppSettings appSettings = AppSettings();
