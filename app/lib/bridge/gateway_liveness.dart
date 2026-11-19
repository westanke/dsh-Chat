/// 连接活性的时间戳判据（从 gateway.dart 拆出，宪法 §7 单文件 ≤500 行）。
///
/// 姊妹仓踩过的坑（companion PITFALLS「WS 半死：socket 断了但状态还写着已连接」）：
/// 安卓/鸿蒙的 socket 断线通知要等对端发话或 TCP 超时，App 进后台被冻结时那条
/// 连接既没关也没人写，状态会停在「已连接」——之后每一帧都写进死连接，等满
/// 30s 超时才失败。判据必须是**最近一次收到帧的时刻**（连解析不了的帧也算活着），
/// 不是「最近一次状态迁移」。
///
/// 阈值取心跳 2 倍以内：桥自身 30s 一次 ping、客户端 25s 一次 ping，
/// 45s 收不到任何入站帧即可判定半死（真实断网/桥挂了都落在这里）。
library;

/// 静默多久算死（心跳 25s × 2 - 5s）。
const Duration kLivenessSilentLimit = Duration(seconds: 45);

class Liveness {
  DateTime? _lastInbound;

  /// 收到任意入站帧时调用（**解析之前**，坏帧也证明链路是活的）。
  void seenAt(DateTime now) => _lastInbound = now;

  /// 连接建立/重连时重置（新连接还没收到 hello 之前的静默不算死）。
  void reset() => _lastInbound = null;

  /// 从没收到过帧 → 不算死（等 hello 超时那条路负责）；否则看静默时长。
  bool isStaleAt(DateTime now) {
    final last = _lastInbound;
    if (last == null) return false;
    return now.difference(last) > kLivenessSilentLimit;
  }

  /// 诊断/测试用：距今静默时长（没收到过帧时 null）。
  Duration? silentFor(DateTime now) {
    final last = _lastInbound;
    return last == null ? null : now.difference(last);
  }
}
