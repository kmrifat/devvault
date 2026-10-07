import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets this device keeps outside any vault: storage access keys. They
/// never go into a vault file, a log or the bucket.
abstract interface class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The OS keychain: Keychain on macOS and iOS, Keystore-backed storage on
/// Android, Credential Manager on Windows, libsecret on Linux.
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
