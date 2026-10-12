import Cocoa
import FlutterMacOS

/// Context and pull-down menus drawn by AppKit (P7-01): the sidebar's,
/// the item table's and the inspector's ⋯. The app sends the commands; the
/// system draws the menu, tracks it and handles its keyboard and VoiceOver.
///
/// Channel `devvault/menu`: `popUp` with `x`, `y` (logical pixels from the
/// Flutter view's top-left) and `items`, each `{title, symbol?,
/// separatorBefore}` → the index of the item picked, or nil when the menu
/// is dismissed.
final class NativeMenu: NSObject {
  private let channel: FlutterMethodChannel
  private weak var view: NSView?

  /// The item picked while the menu was open.
  private var picked: Int?

  init(messenger: FlutterBinaryMessenger, view: NSView) {
    channel = FlutterMethodChannel(name: "devvault/menu", binaryMessenger: messenger)
    self.view = view
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "popUp" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let x = args["x"] as? Double,
      let y = args["y"] as? Double,
      let items = args["items"] as? [[String: Any]],
      let view = view
    else {
      result(FlutterError(code: "bad_args", message: "popUp needs x, y and items.", details: nil))
      return
    }

    let menu = NSMenu()
    menu.autoenablesItems = false
    for (index, item) in items.enumerated() {
      if (item["separatorBefore"] as? Bool) == true && menu.numberOfItems > 0 {
        menu.addItem(.separator())
      }
      let entry = NSMenuItem(
        title: item["title"] as? String ?? "", action: #selector(pick(_:)), keyEquivalent: "")
      entry.target = self
      entry.tag = index
      if let symbol = item["symbol"] as? String {
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      }
      menu.addItem(entry)
    }

    // Flutter measures from the top-left; AppKit views usually from the
    // bottom-left.
    let point = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
    picked = nil
    // After this call returns, so the channel isn't held while the menu
    // tracks. popUp returns once the menu closes, after the item's action.
    DispatchQueue.main.async { [weak self] in
      menu.popUp(positioning: nil, at: point, in: view)
      result(self?.picked)
      self?.picked = nil
    }
  }

  @objc private func pick(_ sender: NSMenuItem) {
    picked = sender.tag
  }
}
