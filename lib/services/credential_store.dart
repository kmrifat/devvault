import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets this device keeps outside any vault: storage access keys. They
/// never go into a vault file, a log or the bucket.
abstract interface class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The OS keychain: Keychain on macOS and iOS, Keystore-backed storage on
/// Android, libsecret on Linux. On Windows, flutter_secure_storage keeps
/// the keys in a file in the app support folder encrypted with DPAPI, so
/// only the same Windows user can read them; it reads Credential Manager
/// only for keys an older version of the plugin stored there.
class SystemCredentialStore implements CredentialStore {
  const SystemCredentialStore();

  // The login keychain on macOS rather than the data-protection keychain,
  // which needs a signed build with a keychain access group.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keeps credentials in memory only, for tests.
class MemoryCredentialStore implements CredentialStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The keychain, falling back to memory when there is none: on Linux
/// without a Secret Service (no GNOME Keyring or KWallet running) every
/// keychain call fails. Then the keys last until DevVault quits, and
/// [isDegraded] lets the settings say so.
class FallbackCredentialStore implements CredentialStore {
  FallbackCredentialStore(this.primary);

  final CredentialStore primary;
  final _memory = MemoryCredentialStore();
  bool _degraded = false;

  /// True once the keychain failed: keys are kept in memory only.
  bool get isDegraded => _degraded;

  Future<T> _try<T>(
    Future<T> Function() keychain,
    Future<T> Function() memory,
  ) async {
    if (_degraded) return memory();
    try {
      return await keychain();
    } on Object {
      _degraded = true;
      return memory();
    }
  }

  @override
  Future<String?> read(String key) =>
      _try(() => primary.read(key), () => _memory.read(key));

  @override
  Future<void> write(String key, String value) =>
      _try(() => primary.write(key, value), () => _memory.write(key, value));

  @override
  Future<void> delete(String key) async {
    await _memory.delete(key);
    if (!_degraded) {
      try {
        await primary.delete(key);
      } on Object {
        _degraded = true;
      }
    }
  }
}
