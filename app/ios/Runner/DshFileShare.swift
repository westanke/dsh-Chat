import Flutter
import UIKit

/// 文件字节分享：写入 caches 后交给 UIActivityViewController。
///
/// 与 DshPlatformChannels.swift 的 openFile 分开存放（宪法 §7 单文件
/// 500 行上限）；通道名、参数与 Android `shareFile` 一致。
extension DshPlatformChannels {
  static func shareFile(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let name = args["name"] as? String,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let typed = args["bytes"] as? FlutterStandardTypedData,
          !typed.data.isEmpty else {
      result(false)
      return
    }
    guard let caches = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first,
      let host = topViewController() else {
      result(false)
      return
    }
    let shareDir = caches.appendingPathComponent("share", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: shareDir,
        withIntermediateDirectories: true
      )
    } catch {
      result(false)
      return
    }
    let safeName = name.split(separator: "/").last.map(String.init) ?? "file"
    let fileURL = shareDir.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
    do {
      try typed.data.write(to: fileURL, options: .atomic)
    } catch {
      result(false)
      return
    }
    let controller = UIActivityViewController(
      activityItems: [fileURL],
      applicationActivities: nil
    )
    if let popover = controller.popoverPresentationController {
      popover.sourceView = host.view
      popover.sourceRect = CGRect(
        x: host.view.bounds.midX,
        y: host.view.bounds.midY,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }
    host.present(controller, animated: true) {
      result(true)
    }
  }
}
