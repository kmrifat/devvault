import Cocoa
import FlutterMacOS
import Sparkle

/// Installs a release in place with Sparkle 2 (ADR-0007 §3, P6-04).
///
/// The app's own check (lib/data/updates.dart) finds the release; Sparkle
/// starts only when the user presses Update…, so it never makes a request
/// of its own. It then fetches the appcast, checks the EdDSA signature and
/// the Developer ID team, asks the user and restarts the app.
///
/// Channel `devvault/updater`: `isAvailable` → Bool, `install` → nil.
final class AppUpdater: NSObject {
  private let channel: FlutterMethodChannel
  private var controller: SPUStandardUpdaterController?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "devvault/updater", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  /// Whether this build can update itself: it has a feed and the public
  /// half of the update key (both from Configs/AppInfo.xcconfig).
  static var isConfigured: Bool {
    let info = Bundle.main.infoDictionary ?? [:]
    let feed = (info["SUFeedURL"] as? String) ?? ""
    let key = (info["SUPublicEDKey"] as? String) ?? ""
    return feed.hasPrefix("https://") && !key.isEmpty
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(AppUpdater.isConfigured)
    case "install":
      guard AppUpdater.isConfigured else {
        result(
          FlutterError(
            code: "unavailable", message: "This build can't update itself.",
            details: nil))
        return
      }
      let controller =
        self.controller
        ?? SPUStandardUpdaterController(
          startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
      self.controller = controller
      // A user-initiated check: Sparkle shows its own window from here on.
      controller.checkForUpdates(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
