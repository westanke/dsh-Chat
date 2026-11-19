/// WS 在途请求登记表（requestId → 结算器）。从 gateway.dart 拆出：
/// 宪法 §7 单文件 ≤500 行，且这块逻辑值得单独单测。
///
/// 三条结算路径（对应 bridge 协议的三种应答形态）：
/// 1. 正常应答 / error 帧带 `data.requestId` → [take] 后由调用方结算；
/// 2. 分发前被拒（`UNKNOWN_TYPE` / `INVALID_FRAME` / `MISSING_TYPE`）只回
///    `data.requestType`、**不回 requestId**（bridge `ws-protocol.ts`）→ [failOfType]；
/// 3. 连接掉线 → [failAll]（companion 坑「请求悬挂」：不结算就干挂到 30s 超时，
///    UI 上表现为按钮一直转圈）。
library;

import 'dart:async';

import 'gateway_events.dart';

/// 一条在途请求：发出时的帧类型 + 结算器。
class PendingRequest {
  PendingRequest(this.type, this.completer);

  /// 帧类型（`history` / `models` / `session-wait` 等）：error 帧没有
  /// requestId 时靠它把「同类型的在途请求」一并结算掉。
  final String type;
  final Completer<Map<String, dynamic>> completer;

  bool get isCompleted => completer.isCompleted;
}

/// requestId → 在途请求。只做登记与结算，不发帧。
class PendingRegistry {
  final Map<String, PendingRequest> _map = {};

  int get length => _map.length;

  /// 登记一条新请求（同 id 覆盖：id 由递增序号+时间戳生成，实际不会撞）。
  PendingRequest add(
    String requestId,
    String type,
    Completer<Map<String, dynamic>> completer,
  ) => _map[requestId] = PendingRequest(type, completer);

  /// 取出并摘除；已摘除的不会被二次结算。
  PendingRequest? take(String? requestId) {
    if (requestId == null || requestId.isEmpty) return null;
    return _map.remove(requestId);
  }

  /// 按帧类型失败所有同类型在途请求。
  void failOfType(String type, String code, String message) {
    for (final key in List.of(_map.keys)) {
      final p = _map[key];
      if (p == null || p.type != type) continue;
      _map.remove(key);
      fail(p, RequestException(code, message));
    }
  }

  /// 全部失败（掉线 / 关闭）。
  void failAll(String message) {
    final all = List.of(_map.values);
    _map.clear();
    for (final p in all) {
      fail(p, RequestException('NOT_CONNECTED', message));
    }
  }

  /// 结算一条为失败。先挂一个吞异常监听：没人 await 的 fire-and-forget
  /// 请求如果直接 completeError，会冒成未捕获异步异常（用例直接判红）。
  static void fail(PendingRequest p, RequestException error) {
    if (p.completer.isCompleted) return;
    p.completer.future.catchError((Object _) => <String, dynamic>{});
    p.completer.completeError(error);
  }
}
