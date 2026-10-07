import Flutter
import UIKit

/// Files other apps hand to DevVault ("Open in DevVault" from Files, Mail,
/// AirDrop) arrive here as file URLs (P3-03). Each is copied into a fresh
/// temporary folder and its path kept until Dart takes it on the
/// `devvault/incoming_files` channel, so a file that arrives before Flutter
/// is listening, or while the vault is locked, still gets imported.
class SceneDelegate: FlutterSceneDelegate {
  private var pending: [String] = []
  private var channel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    attachChannel()
    receive(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    attachChannel()
    receive(URLContexts)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) {
    let paths = contexts.map(\.url).filter(\.isFileURL).compactMap(copyIn)
    guard !paths.isEmpty else { return }
    pending.append(contentsOf: paths)
    channel?.invokeMethod("available", arguments: nil)
  }

  /// Copies a file the system lent us (possibly security-scoped, possibly
  /// in our Inbox) into a folder of its own in the temporary directory.
  private func copyIn(_ url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("devvault-incoming-\(UUID().uuidString)")
    let dest = dir.appendingPathComponent(url.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: url, to: dest)
      // An Inbox copy made for us is ours to remove.
      if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
      return dest.path
    } catch {
      return nil
    }
  }

  private func attachChannel() {
    guard channel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let channel = FlutterMethodChannel(
      name: "devvault/incoming_files",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pending ?? [])
      self?.pending = []
    }
    self.channel = channel
  }
}
