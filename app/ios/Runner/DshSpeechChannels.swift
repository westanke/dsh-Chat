import AVFoundation
import Flutter
import UIKit

/// `dsh/speech` 通道的 iOS 实现：AVAudioRecorder 录 16 kHz / 单声道 / PCM16 WAV，
/// 结束（`stop`）时把文件读成 base64 回给 Dart；桥 `speech-transcribe` 只吃这种 WAV。
///
/// 本机是 Linux，iOS 侧只写实现、不参与 `flutter analyze/test`；真机需先
/// 在 Info.plist 里有 `NSMicrophoneUsageDescription`（已补）。
enum DshSpeechChannels {
  static func register(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DshSpeech") else { return }
    let channel = FlutterMethodChannel(
      name: "dsh/speech",
      binaryMessenger: registrar.messenger()
    )
    let handler = SpeechHandler()
    channel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
    registrar.publish(handler)
  }
}

final class SpeechHandler: NSObject {
  private static let sampleRate = 16_000.0
  private static let wavHeaderBytes = 44
  private var recorder: AVAudioRecorder?
  private var fileURL: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(statusMap())
    case "requestPermission":
      requestPermission(result)
    case "start":
      let args = call.arguments as? [String: Any]
      let maxBytes = args?["maxBytes"] as? Int ?? 4 * 1024 * 1024
      do {
        try startRecording(maxBytes: maxBytes)
        result(nil)
      } catch {
        // 与 Android 对齐：回字符串当内联文案，不抛 PlatformException。
        result(error.localizedDescription)
      }
    case "stop":
      stopRecording(result: result)
    case "cancel":
      cancelRecording()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func statusMap() -> [String: Any] {
    return [
      "supported": true,
      "granted": permissionGranted(),
      "canRequest": !permissionGranted() && !permissionDenied(),
    ]
  }

  private func permissionGranted() -> Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .granted
    }
    return AVAudioSession.sharedInstance().recordPermission == .granted
  }

  private func permissionDenied() -> Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .denied
    }
    return AVAudioSession.sharedInstance().recordPermission == .denied
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    if permissionGranted() {
      result(true)
      return
    }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
      return
    }
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async { result(granted) }
    }
  }

  private func startRecording(maxBytes: Int) throws {
    cancelRecording()
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [])
    try session.setActive(true, options: [])

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("dsh-speech-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: Self.sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.isMeteringEnabled = false
    guard recorder.prepareToRecord(), recorder.record() else {
      throw NSError(
        domain: "dsh/speech",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "录音启动失败"]
      )
    }
    self.recorder = recorder
    self.fileURL = url
    // 文件由录音器增量写入，maxBytes 只用于提示上限；超长由转写前的
    // Dart 侧检查兜底（WAV 超出 catalog.maxAudioBytes 会被拒绝）。
    _ = maxBytes
  }

  private func stopRecording(result: @escaping FlutterResult) {
    guard let recorder = recorder, let url = fileURL else {
      result(
        FlutterError(code: "mic/failed", message: "没有进行中的录音", details: nil)
      )
      return
    }
    recorder.stop()
    deactivateSession()
    self.recorder = nil
    self.fileURL = nil
    do {
      let data = try Data(contentsOf: url)
      try? FileManager.default.removeItem(at: url)
      guard data.count > Self.wavHeaderBytes else {
        throw NSError(
          domain: "dsh/speech",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "录音太短，没有拿到音频"]
        )
      }
      result([
        "format": "wav",
        "base64": data.base64EncodedString(),
        "bytes": data.count,
        "sampleRate": Int(Self.sampleRate),
        "samples": (data.count - Self.wavHeaderBytes) / 2,
      ])
    } catch {
      result(
        FlutterError(
          code: "mic/failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func cancelRecording() {
    recorder?.stop()
    recorder = nil
    deactivateSession()
    if let url = fileURL {
      try? FileManager.default.removeItem(at: url)
    }
    fileURL = nil
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }
}
