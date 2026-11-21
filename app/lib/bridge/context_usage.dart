/// 上下文占用投影（`context-usage` 帧）的模型与口径。
///
/// 数据来自内核会话投影 `contextPressure`：
/// `{pressureTokens, projectedTokens, contextWindow}`（键可能整体缺席）。
/// 桌面端在输入条右侧画一个 22dp 圆环，占比 = pressureTokens / contextWindow；
/// 这里只做解析与百分比，画法留给 UI（对照 dsh-go `state/usage_state.dart`）。
library;

/// 一次上下文占用快照。
class ContextUsage {
  const ContextUsage({
    required this.pressureTokens,
    required this.projectedTokens,
    required this.contextWindow,
  });

  /// 上一次请求实际占用（分子）。
  final int pressureTokens;

  /// 下一次请求的估算占用（压力 + 新增），没有时等于 [pressureTokens]。
  final int projectedTokens;

  /// 上下文窗口（分母）；0 表示服务端没给，界面按未知处理。
  final int contextWindow;

  /// 0..1；窗口未知时 null。
  double? get fraction =>
      contextWindow <= 0 ? null : (pressureTokens / contextWindow).clamp(0, 1);

  /// 粗略百分比（0..100），窗口未知时 null。
  int? get percent => fraction == null ? null : (fraction! * 100).round();

  /// 投影里的 `contextPressure` 缺失/形状不认识 → null（不显示环）。
  static ContextUsage? fromProjections(Map<String, dynamic> values) {
    final raw = values['contextPressure'];
    if (raw is! Map) return null;
    int? n(String key) {
      final v = raw[key];
      return v is num ? v.toInt() : null;
    }

    final pressure = n('pressureTokens');
    final window = n('contextWindow');
    if (pressure == null || window == null) return null;
    return ContextUsage(
      pressureTokens: pressure,
      projectedTokens: n('projectedTokens') ?? pressure,
      contextWindow: window,
    );
  }

  /// 千分位缩写：`61.2k` / `1.0M`，用于「61k / 1M」这种一行文案。
  static String short(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      final k = tokens / 1000;
      return k >= 100 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
    }
    return '$tokens';
  }

  @override
  String toString() =>
      'ContextUsage($pressureTokens / $contextWindow, projected $projectedTokens)';
}
