import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerDeviceChannel(engineBridge.pluginRegistry)
    registerPlatformChannel(engineBridge.pluginRegistry)
  }

  /// 与 Android MainActivity 的 "dsh/device" 通道对齐：
  /// 返回 IANA 时区（如 Asia/Shanghai），bridge 校验 clientTimeZone 必须是 Area/Location。
  private func registerDeviceChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DshDevice") else { return }
    let channel = FlutterMethodChannel(
      name: "dsh/device",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "ianaZone":
        result(TimeZone.current.identifier)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "dsh/platform" 的 iOS 实现（当前只有 appVersion）：CFBundleShortVersionString
  /// / CFBundleVersion 由构建系统从 pubspec version 注入，与发版号自动同步
  /// （与 Android MainActivity 的 appVersion 分支对齐）。
  private func registerPlatformChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DshPlatform") else { return }
    let channel = FlutterMethodChannel(
      name: "dsh/platform",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "appVersion":
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleShortVersionString"] as? String ?? ""
        let code = Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        result(["version": name, "code": code])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
