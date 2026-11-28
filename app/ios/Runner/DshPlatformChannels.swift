import AVFoundation
import Flutter
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS 原生能力：与 Android MainActivity 的 `dsh/device` / `dsh/platform`
/// 两个通道保持同名同参数。实现只用系统框架，不引入第三方依赖。
enum DshPlatformChannels {
  private static let tts = DshTts()
  private static var imagePicker: DshImagePicker?
  private static var documentController: UIDocumentInteractionController?

  static func register(_ registry: FlutterPluginRegistry) {
    registerDevice(registry)
    registerPlatform(registry)
  }

  // MARK: - dsh/device

  private static func registerDevice(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DshDevice") else { return }
    let channel = FlutterMethodChannel(
      name: "dsh/device",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "ianaZone":
        result(TimeZone.current.identifier)
      case "deviceName":
        result(UIDevice.current.name)
      case "filesDir":
        // Android context.filesDir 的 iOS 等价物：Application Support 是应用私有、
        // 不暴露给 Files.app，适合放日志等运行数据；目录不存在时先建出来。
        guard let base = FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first else {
          result(nil)
          return
        }
        do {
          try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
          )
          result(base.path)
        } catch {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - dsh/platform

  private static func registerPlatform(_ registry: FlutterPluginRegistry) {
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

      case "speak":
        guard let text = call.arguments as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(false)
          return
        }
        result(tts.speak(text))

      case "stopSpeak":
        tts.stop()
        result(nil)

      case "share":
        guard let text = call.arguments as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(false)
          return
        }
        share(text: text, result: result)

      case "pickImage":
        pickImage(result: result)

      case "downloadApk":
        // iOS 不允许 App 内下载并安装可执行包；Dart 侧 supportsInAppUpdate
        // 已只在 Android 为 true，这里保持与平台能力一致的降级返回。
        result(-1)

      case "downloadStatus":
        result(nil)

      case "installApk":
        result(false)

      case "openFile":
        openFile(arguments: call.arguments, result: result)

      case "shareFile":
        shareFile(arguments: call.arguments, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - 分享

  private static func share(text: String, result: @escaping FlutterResult) {
    guard let host = topViewController() else {
      result(false)
      return
    }
    let controller = UIActivityViewController(
      activityItems: [text],
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

  // MARK: - 选图

  private static func pickImage(result: @escaping FlutterResult) {
    guard imagePicker == nil else {
      result(["error": "已有一个选图操作在进行，请稍候"])
      return
    }
    guard let host = topViewController() else {
      result(["error": "无法打开系统相册"])
      return
    }
    let picker = DshImagePicker()
    imagePicker = picker
    picker.present(from: host, result: result) { [weak picker] in
      if imagePicker === picker {
        imagePicker = nil
      }
    }
  }

  // MARK: - 打开文件

  private static func openFile(arguments: Any?, result: @escaping FlutterResult) {
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
    ).first else {
      result(false)
      return
    }
    let openDir = caches.appendingPathComponent("open", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: openDir,
        withIntermediateDirectories: true
      )
    } catch {
      result(false)
      return
    }
    let safeName = sanitizedFileName(name)
    let fileURL = openDir.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
    do {
      try typed.data.write(to: fileURL, options: .atomic)
    } catch {
      result(false)
      return
    }
    guard let host = topViewController() else {
      result(false)
      return
    }
    let controller = UIDocumentInteractionController(url: fileURL)
    if let mime = args["mime"] as? String,
       !mime.isEmpty,
       let uti = UTType(mimeType: mime)?.identifier {
      controller.uti = uti
    }
    documentController = controller
    result(controller.presentOptionsMenu(
      from: host.view.bounds,
      in: host.view,
      animated: true
    ))
  }

  // MARK: - 工具

  static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
    let root: UIViewController?
    if let base = base {
      root = base
    } else {
      root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?
        .rootViewController
    }
    guard let root = root else { return nil }
    if let nav = root as? UINavigationController {
      return topViewController(nav.visibleViewController ?? nav)
    }
    if let tab = root as? UITabBarController {
      return topViewController(tab.selectedViewController ?? tab)
    }
    if let presented = root.presentedViewController {
      return topViewController(presented)
    }
    return root
  }

  private static func sanitizedFileName(_ raw: String) -> String {
    let base = URL(fileURLWithPath: raw).lastPathComponent
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. "
    )
    let cleaned = base.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "_"
    }.joined()
    let compact = cleaned.replacingOccurrences(of: " ", with: "_")
    let trimmed = compact.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    let name = trimmed.isEmpty ? "file" : trimmed
    return String(name.prefix(120))
  }
}

// MARK: - TTS

private final class DshTts: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var activeUtterance: AVSpeechUtterance?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String) -> Bool {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    let session = AVAudioSession.sharedInstance()
    // duckOthers 必须与 mixWithOthers 搭配；说完在 delegate 里松手，
    // 避免把别的 App 的声音长期压低。
    try? session.setCategory(
      .playback,
      mode: .spokenAudio,
      options: [.duckOthers, .mixWithOthers]
    )
    try? session.setActive(true)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
    activeUtterance = utterance
    synthesizer.speak(utterance)
    return true
  }

  func stop() {
    activeUtterance = nil
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    releaseAudioSession()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    finishUtterance(utterance)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    finishUtterance(utterance)
  }

  private func finishUtterance(_ utterance: AVSpeechUtterance) {
    // 新朗读已排队时，旧句子的 cancel 回调不能把新句子的 session 关掉。
    guard utterance === activeUtterance else { return }
    activeUtterance = nil
    releaseAudioSession()
  }

  private func releaseAudioSession() {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }
}

// MARK: - PHPicker

private final class DshImagePicker: NSObject, PHPickerViewControllerDelegate {
  private static let maxBytes = 8 * 1024 * 1024
  private static let maxPixels = 4096 * 4096
  private var result: FlutterResult?
  private var onFinish: (() -> Void)?

  func present(
    from host: UIViewController,
    result: @escaping FlutterResult,
    onFinish: @escaping () -> Void
  ) {
    self.result = result
    self.onFinish = onFinish
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    config.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    host.present(picker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      finish(nil)
      return
    }
    load(provider)
  }

  private func load(_ provider: NSItemProvider) {
    let type = provider.registeredTypeIdentifiers.first { identifier in
      UTType(identifier)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
    provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
      guard let self = self else { return }
      if let error = error {
        self.finish(["error": "读取图片失败：\(error.localizedDescription)"])
        return
      }
      guard let data = data else {
        self.finish(["error": "读取图片失败：没有拿到数据"])
        return
      }
      self.process(data: data, suggestedName: provider.suggestedName)
    }
  }

  private func process(data: Data, suggestedName: String?) {
    var mediaType = Self.sniffMediaType(data)
    var output = data

    if !Self.supportedTypes.contains(mediaType) {
      guard let image = UIImage(data: data) else {
        finish(["error": "不支持的图片格式，请换一张 PNG/JPEG 图片"])
        return
      }
      if let cg = image.cgImage, cg.width * cg.height > Self.maxPixels {
        finish(["error": "图片尺寸过大，请选小一点的图"])
        return
      }
      if Self.hasAlpha(image) {
        guard let png = image.pngData() else {
          finish(["error": "图片转码失败，请换一张图片"])
          return
        }
        output = png
        mediaType = "image/png"
      } else {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
          finish(["error": "图片转码失败，请换一张图片"])
          return
        }
        output = jpeg
        mediaType = "image/jpeg"
      }
    }

    guard output.count <= Self.maxBytes else {
      finish(["error": "图片转码后超过 8MB，请选小一点的图"])
      return
    }
    guard let caches = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first else {
      finish(["error": "无法访问应用缓存目录"])
      return
    }
    let dir = caches.appendingPathComponent("picked", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      finish(["error": "无法创建图片缓存目录"])
      return
    }

    let ext = Self.fileExtension(for: mediaType)
    let base = Self.baseName(suggestedName)
    let fileName = "pick-\(Int(Date().timeIntervalSince1970 * 1000))-\(base).\(ext)"
    let url = dir.appendingPathComponent(fileName)
    do {
      try output.write(to: url, options: .atomic)
    } catch {
      finish(["error": "图片写入缓存失败"])
      return
    }
    finish([
      "path": url.path,
      "name": fileName,
      "mediaType": mediaType,
    ])
  }

  private func finish(_ value: Any?) {
    let callback = result
    let cleanup = onFinish
    result = nil
    onFinish = nil
    DispatchQueue.main.async {
      callback?(value)
      cleanup?()
    }
  }

  private static let supportedTypes: Set<String> = [
    "image/png", "image/jpeg", "image/gif", "image/webp",
  ]

  private static func sniffMediaType(_ data: Data) -> String {
    let bytes = [UInt8](data.prefix(16))
    if bytes.count >= 8,
       bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
      return "image/png"
    }
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return "image/jpeg"
    }
    if bytes.count >= 6 {
      let head = String(bytes: bytes[0..<6], encoding: .ascii)
      if head == "GIF87a" || head == "GIF89a" {
        return "image/gif"
      }
    }
    if bytes.count >= 12 {
      let riff = String(bytes: bytes[0..<4], encoding: .ascii)
      let webp = String(bytes: bytes[8..<12], encoding: .ascii)
      if riff == "RIFF" && webp == "WEBP" {
        return "image/webp"
      }
    }
    return "application/octet-stream"
  }

  private static func hasAlpha(_ image: UIImage) -> Bool {
    guard let alpha = image.cgImage?.alphaInfo else { return false }
    switch alpha {
    case .none, .noneSkipFirst, .noneSkipLast:
      return false
    default:
      return true
    }
  }

  private static func fileExtension(for mediaType: String) -> String {
    switch mediaType {
    case "image/png": return "png"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    default: return "jpg"
    }
  }

  private static func baseName(_ suggestedName: String?) -> String {
    let raw = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let stem = raw.isEmpty ? "image" : URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )
    let cleaned = stem.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "_"
    }.joined()
    let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    return trimmed.isEmpty ? "image" : String(trimmed.prefix(80))
  }
}
