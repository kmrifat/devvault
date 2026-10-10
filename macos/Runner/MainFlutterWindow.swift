import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Sparkle, behind the `devvault/updater` channel (P6-04).
  private var updater: AppUpdater?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The three-pane vault layout (design frame D03) needs room for the
    // sidebar, item list and detail pane side by side.
    self.title = "DevVault"
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.contentMinSize = NSSize(width: 1100, height: 700)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    updater = AppUpdater(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
