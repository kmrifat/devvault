#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif
import Foundation
import LocalAuthentication
import Security

/// Keeps a vault key behind Face ID or Touch ID (SPEC §9.1): a Keychain item
/// readable only after a biometric check against the biometrics enrolled
/// when it was stored (`.biometryCurrentSet`), on this device only, and
/// only while a passcode is set. The bytes go to Dart only after a
/// successful prompt, and are never logged.
///
/// Channel `devvault/biometric_key`. Errors carry a code and nothing else:
/// `gone` (enrolment changed or no key), `cancelled`, `keychain-<status>`.
public class BiometricKeyPlugin: NSObject, FlutterPlugin {
  private static let service = "com.binarycastle.devvault.biometric-key"
  private let queue = DispatchQueue(label: "devvault.biometric-key")

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(
      name: "devvault/biometric_key", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(BiometricKeyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let vault = args["vault"] as? String
    let reason = args["reason"] as? String ?? ""
    // Keychain reads with a prompt block: keep them off the main thread.
    queue.async {
      let reply: Any?
      switch call.method {
      case "biometry":
        reply = self.biometry()
      case "has":
        reply = vault.map(self.has) ?? false
      case "save":
        reply = self.save(
          vault, (args["key"] as? FlutterStandardTypedData)?.data, reason: reason)
      case "read":
        reply = self.read(vault, reason: reason)
      case "delete":
        if let vault { self.delete(vault) }
        reply = nil
      default:
        reply = FlutterMethodNotImplemented
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  // MARK: - Calls

  private func biometry() -> String? {
    let context = LAContext()
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    else { return nil }
    #if os(macOS)
      // Biometric Keychain items need the data protection keychain, which an
      // unsigned build (no keychain-access-groups entitlement) can't use.
      guard dataProtectionKeychainUsable() else { return nil }
    #endif
    switch context.biometryType {
    case .faceID: return "faceId"
    case .touchID: return "touchId"
    default: return "biometrics"
    }
  }

  /// Never prompts: attributes aren't behind the access control.
  private func has(_ vault: String) -> Bool {
    storedDomainState(vault) != nil
  }

  private func save(_ vault: String?, _ key: Data?, reason: String) -> Any? {
    guard let vault, let key else { return error("bad-arguments") }
    // Prove the biometrics work before relying on them.
    let context = LAContext()
    var domainState: Data?
    switch evaluate(context, reason: reason) {
    case .success:
      domainState = context.evaluatedPolicyDomainState
    case .cancelled:
      return false
    case .failed(let code):
      return error(code)
    }
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil)
    else { return error("access-control") }

    delete(vault)
    var query = baseQuery(vault)
    query[kSecAttrAccessControl as String] = access
    query[kSecValueData as String] = key
    // Remembered so a changed enrolment is told apart from a failed scan.
    query[kSecAttrGeneric as String] = domainState ?? Data()
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess ? true : error("keychain-\(status)")
  }

  private func read(_ vault: String?, reason: String) -> Any? {
    guard let vault else { return error("bad-arguments") }
    guard let stored = storedDomainState(vault) else { return error("gone") }
    if enrolmentChanged(since: stored) {
      delete(vault)
      return error("gone")
    }
    let context = LAContext()
    context.localizedReason = reason
    var query = baseQuery(vault)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return error("gone") }
      return FlutterStandardTypedData(bytes: data)
    case errSecUserCanceled:
      return nil
    case errSecItemNotFound:
      return error("gone")
    default:
      if enrolmentChanged(since: stored) {
        delete(vault)
        return error("gone")
      }
      return error("keychain-\(status)")
    }
  }

  private func delete(_ vault: String) {
    SecItemDelete(baseQuery(vault) as CFDictionary)
  }

  // MARK: - Helpers

  private func baseQuery(_ vault: String, service: String = BiometricKeyPlugin.service) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: vault,
    ]
    #if os(macOS)
      query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  /// The enrolment state saved with the key, or nil when there's no key.
  private func storedDomainState(_ vault: String) -> Data? {
    let context = LAContext()
    context.interactionNotAllowed = true
    var query = baseQuery(vault)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let attributes = item as? [String: Any]
    else { return nil }
    return attributes[kSecAttrGeneric as String] as? Data ?? Data()
  }

  /// Whether the enrolled biometrics differ from [stored]. Unknown (no
  /// biometrics right now, or nothing was stored) counts as unchanged: the
  /// Keychain itself still refuses a key bound to another set.
  private func enrolmentChanged(since stored: Data) -> Bool {
    guard !stored.isEmpty else { return false }
    let context = LAContext()
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
      let current = context.evaluatedPolicyDomainState
    else { return false }
    return current != stored
  }

  private enum Outcome {
    case success
    case cancelled
    case failed(String)
  }

  private func evaluate(_ context: LAContext, reason: String) -> Outcome {
    let done = DispatchSemaphore(value: 0)
    var outcome = Outcome.failed("unknown")
    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
      ok, err in
      if ok {
        outcome = .success
      } else if let code = (err as? LAError)?.code,
        [.userCancel, .appCancel, .systemCancel, .userFallback].contains(code)
      {
        outcome = .cancelled
      } else {
        outcome = .failed("auth-\((err as? LAError)?.code.rawValue ?? -1)")
      }
      done.signal()
    }
    done.wait()
    return outcome
  }

  #if os(macOS)
    private func dataProtectionKeychainUsable() -> Bool {
      let probe = baseQuery("probe", service: Self.service + ".probe")
      SecItemDelete(probe as CFDictionary)
      var add = probe
      add[kSecValueData as String] = Data()
      let status = SecItemAdd(add as CFDictionary, nil)
      SecItemDelete(probe as CFDictionary)
      return status == errSecSuccess
    }
  #endif

  private func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
