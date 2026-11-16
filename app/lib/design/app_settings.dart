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

/// 「通用设置 · 工作步骤展示」：希望看到多少工具调用细节。
///
/// 持久化存官方 token 字符串（[jsonName]），不存 ordinal/name，
/// 与官方语义对齐（detailed 为默认）。
enum WorkStepsDetail {
  concise('concise'),
  standard('standard'),
  detailed('detailed'),
  verbose('verbose');

  const WorkStepsDetail(this.jsonName);

  /// 官方语义 token：verbose 完全展开、从不折叠。
  final String jsonName;

  static WorkStepsDetail fromJsonName(String? v) =>
      WorkStepsDetail.values.firstWhere(
        (e) => e.jsonName == v,
        orElse: () => WorkStepsDetail.detailed,
      );
}

/// 「通用设置 · 工作步骤收起时机」：何时自动收起工作步骤。
enum CollapseTiming {
  completion('completion'),
  nextInput('next-input');

  const CollapseTiming(this.jsonName);

  final String jsonName;

  static CollapseTiming fromJsonName(String? v) =>
      CollapseTiming.values.firstWhere(
        (e) => e.jsonName == v,
        orElse: () => CollapseTiming.completion,
      );
}

/// 「通用设置 · 收起后显示的回复」：工作步骤收起后保留哪些助手回复。
enum FoldedReplies {
  all('all'),
  finalOnly('final');

  const FoldedReplies(this.jsonName);

  final String jsonName;

  static FoldedReplies fromJsonName(String? v) =>
      FoldedReplies.values.firstWhere(
        (e) => e.jsonName == v,
        orElse: () => FoldedReplies.all,
      );
}

/// 「工作步骤展示」四档的组聚合方式（官方 Web policy 逆向）：
/// collapsed=组折叠行+可展开列表（standard）；history=同 collapsed 且行带
/// 详情（detailed）；none=逐条平铺无组标题（verbose）。
enum WorkStepGrouping { collapsed, history, none }

/// 「工作步骤展示」四档在会话页的落地参数（官方 Web policy 逐档核对）。
/// 派生 getter，不持久化——持久化只存官方 token（jsonName）。
extension WorkStepsDetailPolicy on WorkStepsDetail {
  /// 组聚合方式（none 时会话页按平铺逐条工具行渲染）。
  WorkStepGrouping get stepGrouping => switch (this) {
    WorkStepsDetail.verbose => WorkStepGrouping.none,
    WorkStepsDetail.detailed => WorkStepGrouping.history,
    _ => WorkStepGrouping.collapsed,
  };

  /// 运行中过程组标题是否附加「 · 细节」（官方 concise/verbose 均 false）。
  bool get liveProcessDetail =>
      this == WorkStepsDetail.standard || this == WorkStepsDetail.detailed;

  /// 已完成轮的「深度思考」折叠行是否显示一行正文预览（concise 只留标题）。
  bool get settledReasoningPreview => this != WorkStepsDetail.concise;

  /// 已完成的轮是否折叠工作步骤（verbose 平铺，无组可折叠）。
  bool get foldCompletedTurns => this != WorkStepsDetail.verbose;
}

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
  WorkStepsDetail _workStepsDetail = WorkStepsDetail.detailed;
  CollapseTiming _collapseTiming = CollapseTiming.completion;
  FoldedReplies _foldedReplies = FoldedReplies.all;
  bool _codeWorkView = false;

  AppThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;
  bool get fontFollowsSystem => _fontFollowsSystem;
  BusySendMode get busySendMode => _busySendMode;
  bool get diagLog => _diagLog;
  WorkStepsDetail get workStepsDetail => _workStepsDetail;
  CollapseTiming get collapseTiming => _collapseTiming;
  FoldedReplies get foldedReplies => _foldedReplies;
  bool get codeWorkView => _codeWorkView;

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
      final wsd = j['workStepsDetail'];
      _workStepsDetail =
          WorkStepsDetail.fromJsonName(wsd is String ? wsd : null);
      final ct = j['collapseTiming'];
      _collapseTiming = CollapseTiming.fromJsonName(ct is String ? ct : null);
      final fr = j['foldedReplies'];
      _foldedReplies = FoldedReplies.fromJsonName(fr is String ? fr : null);
      _codeWorkView = j['codeWorkView'] == true;
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
          'workStepsDetail': _workStepsDetail.jsonName,
          'collapseTiming': _collapseTiming.jsonName,
          'foldedReplies': _foldedReplies.jsonName,
          'codeWorkView': _codeWorkView,
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

  void setWorkStepsDetail(WorkStepsDetail v) {
    if (_workStepsDetail == v) return;
    _workStepsDetail = v;
    notifyListeners();
    _save();
  }

  void setCollapseTiming(CollapseTiming v) {
    if (_collapseTiming == v) return;
    _collapseTiming = v;
    notifyListeners();
    _save();
  }

  void setFoldedReplies(FoldedReplies v) {
    if (_foldedReplies == v) return;
    _foldedReplies = v;
    notifyListeners();
    _save();
  }

  void setCodeWorkView(bool v) {
    if (_codeWorkView == v) return;
    _codeWorkView = v;
    notifyListeners();
    _save();
  }
}

/// 全局单例（与 DshCredentials 的静态风格一致）：必须位于 MaterialApp 之上，
/// 因为主题三档与字号缩放要重建 MaterialApp / MediaQuery。
final AppSettings appSettings = AppSettings();
