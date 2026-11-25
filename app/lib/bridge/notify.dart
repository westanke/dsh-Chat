/// 系统通知通道（对齐 dsh-go 的通知模式：两条通道 + 点击回会话）。
///
/// 原生侧在 `dsh/notify`（Android MainActivity.kt + NotificationHelper.kt；
/// iOS Runner/DshNotifyChannels.swift）：
/// - 通道 `done`：一轮回答结束（低打扰）；
/// - 通道 `attention`：需要你确认/回答（审批、提问，带声音）。
/// 通知只在使用者「看不到该会话」时发（后台，或前台但停在别的会话），
/// 正在看的会话不打扰——与 dsh-go 的 deliveryFor 口径一致。
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// 通知可用性：原生通道是否在、系统权限是否给、系统开关是否开。
class NotifyStatus {
  const NotifyStatus({
    required this.native,
    required this.permission,
    required this.enabled,
  });

  final bool native;
  final bool permission;
  final bool enabled;

  /// 能真正弹出通知（三者同时成立）。
  bool get canPost => native && permission && enabled;

  /// 测试环境 / 通道不可用：视为不存在。
  static const unavailable = NotifyStatus(
    native: false,
    permission: false,
    enabled: false,
  );

  factory NotifyStatus.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return unavailable;
    bool v(String k) => m[k] == true;
    return NotifyStatus(native: true, permission: v('permission'), enabled: v('enabled'));
  }
}

/// 一条待弹出的通知。
class NotifyPayload {
  const NotifyPayload({
    required this.title,
    required this.text,
    required this.key,
    required this.attention,
    this.sessionId,
    this.kind,
    this.eventId,
  });

  final String title;
  final String text;

  /// 去重键：同一 key 的通知原地替换（避免刷屏）。
  final String key;

  /// true → attention 通道（响铃/弹出）；false → done 通道。
  final bool attention;

  final String? sessionId;
  final String? kind;
  final String? eventId;

  Map<String, Object?> toMap() => {
    'title': title,
    'text': text,
    'key': key,
    'attention': attention,
    if (sessionId != null) 'sessionId': sessionId,
    if (kind != null) 'kind': kind,
    if (eventId != null) 'eventId': eventId,
  };
}

class DshNotify {
  DshNotify._();

  static const MethodChannel _channel = MethodChannel('dsh/notify');
  static bool _handlerInstalled = false;
  static final StreamController<Map<Object?, Object?>> _taps =
      StreamController<Map<Object?, Object?>>.broadcast();

  /// 通知点击事件（App 在前台时由原生回推；冷启动用 [takeLaunchTap]）。
  static Stream<Map<Object?, Object?>> get taps => _taps.stream;

  /// 装好通道回调；重复调用幂等（main 与设置页都会调）。
  static void init() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tap') {
        final m = call.arguments;
        if (m is Map) _taps.add(m);
      }
      return null;
    });
  }

  static Future<NotifyStatus> status() async {
    init();
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      return NotifyStatus.fromMap(r);
    } on PlatformException {
      return NotifyStatus.unavailable;
    } on MissingPluginException {
      return NotifyStatus.unavailable;
    }
  }

  /// 建两条通道（幂等，启动与设置页都可调）。
  static Future<void> ensureChannels() async {
    init();
    try {
      await _channel.invokeMethod<void>('ensureChannels');
    } on PlatformException {
      // 忽略：通道已存在或平台不支持。
    } on MissingPluginException {
      // iOS / 测试环境无实现。
    }
  }

  /// 申请通知权限（Android 13+ 首次会弹系统对话框）。返回是否已授权。
  static Future<bool> requestPermission() async {
    init();
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳系统通知设置（权限被永久拒绝时只能去这里改）。
  static Future<void> openSettings() async {
    init();
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // 忽略。
    } on MissingPluginException {
      // 忽略。
    }
  }

  /// 弹一条通知。返回是否真的发出去（无权限/通道缺失返回 false）。
  static Future<bool> show(NotifyPayload p) async {
    init();
    try {
      return await _channel.invokeMethod<bool>('show', p.toMap()) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> cancel(String key) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'key': key});
    } on PlatformException {
      // 忽略。
    } on MissingPluginException {
      // 忽略。
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on PlatformException {
      // 忽略。
    } on MissingPluginException {
      // 忽略。
    }
  }

  /// 冷启动取「从通知进来」的那次点击载荷（取走即清，避免重复跳转）。
  static Future<Map<Object?, Object?>?> takeLaunchTap() async {
    init();
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>('takeLaunchTap');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
