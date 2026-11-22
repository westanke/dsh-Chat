/// 通知偏好（对齐 dsh-go 的 NotifyPrefs：总开关 + 四类事件分别可关）。
///
/// 存 SharedPreferences（`notify_*` 与 dsh-go 同名，便于两端口径对齐）；
/// 默认全开——用户装完就有通知，想静音再关。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 四类可独立开关的通知事件。
enum NotifyKind { done, failed, approval, question }

class NotifyPrefs extends ChangeNotifier {
  NotifyPrefs._();

  /// 全局单例：设置页改完立即影响监听器，不用重建。
  static final NotifyPrefs instance = NotifyPrefs._();

  bool enabled = true;
  bool done = true;
  bool failed = true;
  bool approval = true;
  bool question = true;

  /// 已读过盘（避免启动早期把默认值写回去覆盖用户设置）。
  bool loaded = false;

  bool allows(NotifyKind kind) {
    if (!enabled) return false;
    return switch (kind) {
      NotifyKind.done => done,
      NotifyKind.failed => failed,
      NotifyKind.approval => approval,
      NotifyKind.question => question,
    };
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('notify_enabled') ?? true;
    done = p.getBool('notify_done') ?? true;
    failed = p.getBool('notify_failed') ?? true;
    approval = p.getBool('notify_approval') ?? true;
    question = p.getBool('notify_question') ?? true;
    loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) => _set('notify_enabled', v, () => enabled = v);

  Future<void> setDone(bool v) => _set('notify_done', v, () => done = v);

  Future<void> setFailed(bool v) => _set('notify_failed', v, () => failed = v);

  Future<void> setApproval(bool v) =>
      _set('notify_approval', v, () => approval = v);

  Future<void> setQuestion(bool v) =>
      _set('notify_question', v, () => question = v);

  Future<void> _set(String key, bool v, VoidCallback apply) async {
    apply();
    notifyListeners();
    // 用户改设置时 loaded 必然为 true（设置页在启动后才可达）。
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }

  /// 是否该为这次事件弹系统通知（纯逻辑，便于单测）。
  ///
  /// [foreground] 应用是否在前台；[sameSession] 前台且正停在该会话。
  /// 正在看的会话不打扰（与 dsh-go deliveryFor 一致）。
  static bool shouldPost({
    required bool allowsKind,
    required bool canPost,
    required bool foreground,
    required bool sameSession,
  }) {
    if (!allowsKind || !canPost) return false;
    if (foreground && sameSession) return false;
    return true;
  }
}
