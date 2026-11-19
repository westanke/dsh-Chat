/// 连接活性判据的回归（companion PITFALLS「WS 半死：socket 断了但状态还写着已连接」）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dshchat/bridge/gateway_liveness.dart';

void main() {
  test('没收到过帧 → 不算死；静默超上限才算死；reset 回到未知', () {
    final live = Liveness();
    final t0 = DateTime(2026, 11, 19, 12);
    expect(live.isStaleAt(t0), isFalse);
    live.seenAt(t0);
    expect(live.isStaleAt(t0.add(kLivenessSilentLimit)), isFalse); // 边界内
    expect(live.isStaleAt(t0.add(kLivenessSilentLimit + const Duration(seconds: 1))),
        isTrue);
    expect(live.silentFor(t0.add(const Duration(seconds: 3))),
        const Duration(seconds: 3));
    live.reset();
    expect(live.isStaleAt(t0), isFalse);
    expect(live.silentFor(t0), isNull);
  });
}
