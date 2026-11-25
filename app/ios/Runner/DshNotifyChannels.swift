import Flutter
import UIKit
import UserNotifications

/// iOS 通知：与 Android NotificationHelper 的两条通道（done / attention）
/// 对齐。iOS 没有“通道”概念，ensureChannels 是空操作；权限、静音、点击
/// 回推按 UNUserNotificationCenter 的语义实现。
final class DshNotifyChannels: NSObject, UNUserNotificationCenterDelegate {
  static let shared = DshNotifyChannels()

  private var channel: FlutterMethodChannel?
  private var pendingTap: [String: Any]?

  static func register(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DshNotify") else { return }
    let channel = FlutterMethodChannel(
      name: "dsh/notify",
      binaryMessenger: registrar.messenger()
    )
    shared.channel = channel
    channel.setMethodCallHandler { [weak shared = DshNotifyChannels.shared] call, result in
      shared?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ensureChannels":
      // iOS 无通知通道；保持幂等空操作，避免 Dart 侧启动时报 notImplemented。
      result(nil)

    case "status":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let permission = Self.canAuthorize(settings)
        let enabled = permission && (
          settings.alertSetting == .enabled
            || settings.soundSetting == .enabled
            || settings.badgeSetting == .enabled
            || settings.notificationCenterSetting == .enabled
        )
        DispatchQueue.main.async {
          result(["permission": permission, "enabled": enabled])
        }
      }

    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge]
      ) { granted, _ in
        DispatchQueue.main.async {
          result(granted)
        }
      }

    case "openSettings":
      DispatchQueue.main.async {
        // 打开本应用设置页；iOS 15 没有独立的通知设置 deep link，
        // 用户可在设置页里继续点“通知”。
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(nil)
          return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        result(nil)
      }

    case "show":
      show(arguments: call.arguments, result: result)

    case "cancel":
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String,
            !key.isEmpty else {
        result(nil)
        return
      }
      UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: [key]
      )
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: [key]
      )
      result(nil)

    case "cancelAll":
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      result(nil)

    case "takeLaunchTap":
      let tap = pendingTap
      pendingTap = nil
      result(tap)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let key = args["key"] as? String,
          !key.isEmpty,
          let title = args["title"] as? String,
          !title.isEmpty else {
      result(false)
      return
    }
    let attention = args["attention"] as? Bool ?? false
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = args["text"] as? String ?? ""
    content.sound = attention ? .default : nil
    content.interruptionLevel = attention ? .active : .passive

    var info: [String: Any] = [
      "key": key,
      "attention": attention,
    ]
    if let sessionId = args["sessionId"] as? String, !sessionId.isEmpty {
      info["sessionId"] = sessionId
    }
    if let kind = args["kind"] as? String, !kind.isEmpty {
      info["kind"] = kind
    }
    if let eventId = args["eventId"] as? String, !eventId.isEmpty {
      info["eventId"] = eventId
    }
    content.userInfo = info

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard Self.canAuthorize(settings) else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let request = UNNotificationRequest(
        identifier: key,
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async {
          result(error == nil)
        }
      }
    }
  }

  private static func canAuthorize(_ settings: UNNotificationSettings) -> Bool {
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let attention = notification.request.content.userInfo["attention"] as? Bool ?? false
    completionHandler(attention ? [.banner, .sound, .badge] : [.banner, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    var payload: [String: Any] = [:]
    for (rawKey, rawValue) in info {
      guard let key = rawKey as? String else { continue }
      if let value = rawValue as? String {
        payload[key] = value
      } else if let value = rawValue as? Bool {
        payload[key] = value
      } else if let value = rawValue as? NSNumber {
        payload[key] = value
      }
    }
    DispatchQueue.main.async {
      if let channel = self.channel {
        channel.invokeMethod("tap", arguments: payload) { [weak self] response in
          // Dart handler 尚未装好时 invoke 会回 FlutterError；留待
          // takeLaunchTap 取，避免冷启动丢点击。
          if response is FlutterError {
            self?.pendingTap = payload
          }
        }
      } else {
        // Flutter 引擎尚未初始化完（冷启动）：留到 Dart 侧 takeLaunchTap。
        self.pendingTap = payload
      }
    }
    completionHandler()
  }
}
