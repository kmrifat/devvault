import Cocoa
import FlutterMacOS

/// macOS's Settings window (⌘,; design frames N07, N07b, N07c, N07d): the
/// window desktop_multi_window makes for a second Flutter engine, which
/// runs `runSettingsWindow` in Dart. This sets it up like a preferences
/// window (680 points wide, its title over the pane tabs, where it was last
/// left) and gives its engine the channel `devvault/settings_window`:
/// `setTitle` with `title`; `setAppearance` with `mode` (`system`,
/// `light` or `dark`), so the title bar follows DevVault's own Appearance
/// setting; and `close`.
final class SettingsWindow: NSObject {
  private static let frameName = "DevVaultSettings"

  /// The open window's, until it closes.
  private static var current: SettingsWindow?

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var closeObserver: NSObjectProtocol?

  /// Called for every window desktop_multi_window makes; DevVault makes
  /// only the Settings window.
  static func attach(_ controller: FlutterViewController) {
    guard let window = controller.view.window else { return }
    current = SettingsWindow(controller: controller, window: window)
  }

  private init(controller: FlutterViewController, window: NSWindow) {
    channel = FlutterMethodChannel(
      name: "devvault/settings_window", binaryMessenger: controller.engine.binaryMessenger)
    self.window = window
    super.init()

    window.title = "Settings"
    // The title sits over the pane tabs, which Flutter draws from the top
    // of the window, as in a preferences window's unified toolbar.
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.tabbingMode = .disallowed
    window.contentMinSize = NSSize(width: 680, height: 420)
    window.setContentSize(NSSize(width: 680, height: 560))
    if !window.setFrameUsingName(Self.frameName) { window.center() }
    window.setFrameAutosaveName(Self.frameName)

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in
      self?.channel.setMethodCallHandler(nil)
      if SettingsWindow.current === self { SettingsWindow.current = nil }
    }
  }

  deinit {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTitle":
      if let title = (call.arguments as? [String: Any])?["title"] as? String {
        window?.title = title
      }
      result(nil)
    case "setAppearance":
      let mode = (call.arguments as? [String: Any])?["mode"] as? String
      window?.appearance =
        switch mode {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
      result(nil)
    case "close":
      window?.performClose(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
