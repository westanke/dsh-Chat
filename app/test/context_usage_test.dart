/// 上下文占用投影（`context-usage` 帧）的解析与文案口径。
library;

import 'package:dshchat/bridge/context_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 contextPressure：三个字段都在', () {
    final usage = ContextUsage.fromProjections({
      'contextPressure': {
        'pressureTokens': 61234,
        'projectedTokens': 61290,
        'contextWindow': 1000000,
      },
    });
    expect(usage, isNotNull);
    expect(usage!.pressureTokens, 61234);
    expect(usage.projectedTokens, 61290);
    expect(usage.contextWindow, 1000000);
    expect(usage.percent, 6);
    expect(usage.fraction, closeTo(0.061234, 1e-9));
  });

  test('缺 projectedTokens 时按 pressure 兜底', () {
    final usage = ContextUsage.fromProjections({
      'contextPressure': {'pressureTokens': 40, 'contextWindow': 100},
    });
    expect(usage!.projectedTokens, 40);
    expect(usage.percent, 40);
  });

  test('键缺失 / 形状不对 / 窗口为 0 → null（整条不显示）', () {
    expect(ContextUsage.fromProjections(const {}), isNull);
    expect(ContextUsage.fromProjections({'contextPressure': 'x'}), isNull);
    expect(
      ContextUsage.fromProjections({
        'contextPressure': {'pressureTokens': 10},
      }),
      isNull,
    );
    final zero = ContextUsage.fromProjections({
      'contextPressure': {'pressureTokens': 1, 'contextWindow': 0},
    });
    expect(zero!.fraction, isNull);
    expect(zero.percent, isNull);
  });

  test('占比夹在 0..1（服务端给超窗数也不画爆环）', () {
    final usage = ContextUsage.fromProjections({
      'contextPressure': {'pressureTokens': 200, 'contextWindow': 100},
    });
    expect(usage!.fraction, 1.0);
    expect(usage.percent, 100);
  });

  test('short 缩写：个位 / k / M 三档', () {
    expect(ContextUsage.short(999), '999');
    expect(ContextUsage.short(61234), '61.2k');
    expect(ContextUsage.short(120000), '120k');
    expect(ContextUsage.short(1000000), '1.0M');
  });
}
