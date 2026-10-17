import Flutter
import UIKit
import Vision
import VisionKit

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LabSightVisionPlugin") {
      LabSightVisionPlugin.register(with: registrar)
    }
  }
}

/// 端末内OCR（Vision）と書類自動検出撮影（VisionKit）。画像は端末外へ送信しない。
class LabSightVisionPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
  private var pendingScan: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "labsight/vision", binaryMessenger: registrar.messenger())
    let instance = LabSightVisionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recognize":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      recognize(path: path, result: result)
    case "scanDocument":
      scanDocument(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - OCR

  private func recognize(path: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      result(FlutterError(code: "bad_image", message: "画像を読み込めません", details: nil))
      return
    }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: err.localizedDescription, details: nil)) }
        return
      }
      var lines: [[String: Any]] = []
      for case let obs as VNRecognizedTextObservation in req.results ?? [] {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox // 正規化座標（原点は左下）
        lines.append([
          "text": top.string,
          "left": Double(b.minX),
          "top": Double(1 - b.maxY),
          "right": Double(b.maxX),
          "bottom": Double(1 - b.minY),
          "confidence": Double(top.confidence),
        ])
      }
      DispatchQueue.main.async { result(lines) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["ja-JP", "en-US"]
    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = false
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:]).perform([request])
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)) }
      }
    }
  }

  // MARK: - 書類の自動検出撮影

  private func scanDocument(result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported else {
      result(FlutterError(code: "unsupported", message: "この端末は書類スキャンに対応していません", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "no_view", message: "画面を取得できません", details: nil))
      return
    }
    pendingScan = result
    let vc = VNDocumentCameraViewController()
    vc.delegate = self
    presenter.present(vc, animated: true)
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    var paths: [String] = []
    // 全ページ（最大10ページ）を一時ファイルに書き出す（読み取り後に Dart 側で削除）
    for i in 0..<min(scan.pageCount, 10) {
      let img = scan.imageOfPage(at: i)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan_\(UUID().uuidString).jpg")
      if let data = img.jpegData(compressionQuality: 0.9), (try? data.write(to: url, options: .completeFileProtection)) != nil {
        paths.append(url.path)
      }
    }
    controller.dismiss(animated: true) { [weak self] in
      self?.pendingScan?(paths)
      self?.pendingScan = nil
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true) { [weak self] in
      self?.pendingScan?([String]())
      self?.pendingScan = nil
    }
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true) { [weak self] in
      self?.pendingScan?(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
      self?.pendingScan = nil
    }
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

extension CGImagePropertyOrientation {
  init(_ o: UIImage.Orientation) {
    switch o {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
