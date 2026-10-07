import Flutter
import UIKit
import UniformTypeIdentifiers

/// Keeps vault contents out of places iOS copies them to (P3-06):
///
/// - A cover over every window while the app isn't active, so the app
///   switcher snapshot never shows the vault.
/// - Secrets copied as local-only (no Universal Clipboard) with an
///   expiration date, so iOS removes them even if DevVault never runs again.
///
/// Channel `devvault/privacy`.
public class DevicePrivacyPlugin: NSObject, FlutterPlugin {
  private var covers: [UIView] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "devvault/privacy", binaryMessenger: registrar.messenger())
    let instance = DevicePrivacyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    let center = NotificationCenter.default
    center.addObserver(
      instance, selector: #selector(cover),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      instance, selector: #selector(uncover),
      name: UIScene.didActivateNotification, object: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "copySensitive":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let text = args["text"] as? String else {
        return result(FlutterError(code: "bad-arguments", message: nil, details: nil))
      }
      let seconds = args["expiresInSeconds"] as? Int ?? 30
      UIPasteboard.general.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(TimeInterval(seconds)),
        ])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func cover() {
    guard covers.isEmpty else { return }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where !window.isHidden {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(blur)
        covers.append(blur)
      }
    }
  }

  @objc private func uncover() {
    covers.forEach { $0.removeFromSuperview() }
    covers.removeAll()
  }
}
