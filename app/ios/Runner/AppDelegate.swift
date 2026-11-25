import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 必须在 Flutter 引擎初始化前挂上，否则冷启动时通知点击回调会丢。
    UNUserNotificationCenter.current().delegate = DshNotifyChannels.shared
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DshPlatformChannels.register(engineBridge.pluginRegistry)
    DshNotifyChannels.register(engineBridge.pluginRegistry)
  }
}
