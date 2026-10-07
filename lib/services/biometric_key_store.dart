import 'package:flutter/services.dart';

/// The biometric this device offers, named as the platform names it.
enum Biometry {
  faceId('Face ID'),
  touchId('Touch ID'),
  fingerprint('Fingerprint'),
  biometrics('Biometrics');

  const Biometry(this.label);

  final String label;
}

/// The stored key is gone: the enrolled biometrics changed (which
/// invalidates it by design), or it was deleted. Use the master password.
class BiometricKeyGone implements Exception {
  const BiometricKeyGone();

  @override
  String toString() => 'BiometricKeyGone';
}

/// The platform refused to store or read the key (no secure hardware, no
/// passcode set, an unsigned macOS build without keychain entitlements…).
class BiometricKeyUnavailable implements Exception {
  const BiometricKeyUnavailable(this.code);

  /// The platform's error code; never contains key material.
  final String code;

  @override
  String toString() => 'BiometricKeyUnavailable($code)';
}

/// Keeps a vault key on this device behind Face ID, Touch ID or a
/// fingerprint (SPEC §9.1): a Keychain item bound to the current biometric
/// set on Apple platforms, a Keystore key with per-use strong biometric
/// authentication wrapping it on Android. Never synced or backed up.
abstract interface class BiometricKeyStore {
  /// What this device offers, or null when there's no biometric hardware or
  /// nothing is enrolled.
  Future<Biometry?> biometry();

  /// Whether a key for [vaultId] is stored. Never prompts.
  Future<bool> has(String vaultId);

  /// Stores [key] for [vaultId], replacing any earlier one. Android asks
  /// for a fingerprint first; returns false if the user cancels. Throws
  /// [BiometricKeyUnavailable].
  Future<bool> save(String vaultId, Uint8List key, {required String reason});

  /// The key for [vaultId], after the biometric prompt, or null if the user
  /// cancels. Throws [BiometricKeyGone] or [BiometricKeyUnavailable].
  Future<Uint8List?> read(String vaultId, {required String reason});

  Future<void> delete(String vaultId);
}

/// Platforms without a device-bound unlock (Windows, Linux) and tests.
class NoBiometricKeyStore implements BiometricKeyStore {
  const NoBiometricKeyStore();

  @override
  Future<Biometry?> biometry() async => null;

  @override
  Future<bool> has(String vaultId) async => false;

  @override
  Future<bool> save(String vaultId, Uint8List key, {required String reason}) =>
      throw const BiometricKeyUnavailable('unsupported');

  @override
  Future<Uint8List?> read(String vaultId, {required String reason}) =>
      throw const BiometricKeyGone();

  @override
  Future<void> delete(String vaultId) async {}
}

/// The native key store on the `devvault/biometric_key` channel
/// (`BiometricKey.swift` on iOS and macOS, `BiometricKey.kt` on Android).
class ChannelBiometricKeyStore implements BiometricKeyStore {
  const ChannelBiometricKeyStore();

  static const _channel = MethodChannel('devvault/biometric_key');

  @override
  Future<Biometry?> biometry() async {
    try {
      final kind = await _channel.invokeMethod<String>('biometry');
      return Biometry.values.where((b) => b.name == kind).firstOrNull;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> has(String vaultId) async {
    try {
      return await _channel.invokeMethod<bool>('has', {'vault': vaultId}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> save(String vaultId, Uint8List key, {required String reason}) =>
      _call(() async {
        final saved = await _channel.invokeMethod<bool>('save', {
          'vault': vaultId,
          'key': key,
          'reason': reason,
        });
        return saved ?? false;
      });

  @override
  Future<Uint8List?> read(String vaultId, {required String reason}) => _call(
    () => _channel.invokeMethod<Uint8List>('read', {
      'vault': vaultId,
      'reason': reason,
    }),
  );

  @override
  Future<void> delete(String vaultId) async {
    try {
      await _channel.invokeMethod<void>('delete', {'vault': vaultId});
    } on MissingPluginException {
      // Nothing was ever stored.
    }
  }

  /// Maps the native error codes. Messages are dropped: only the code is
  /// kept, so nothing the platform says ends up in logs or toasts.
  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      if (e.code == 'gone') throw const BiometricKeyGone();
      throw BiometricKeyUnavailable(e.code);
    } on MissingPluginException {
      throw const BiometricKeyUnavailable('unsupported');
    }
  }
}

/// An in-memory store for tests: [nextRead] decides what the "prompt"
/// does.
class MemoryBiometricKeyStore implements BiometricKeyStore {
  MemoryBiometricKeyStore({this.kind = Biometry.faceId});

  Biometry? kind;
  final keys = <String, Uint8List>{};

  /// What the next prompt does: `true` succeeds, `false` is a cancel.
  bool nextPromptSucceeds = true;

  /// How many times a prompt was shown.
  int prompts = 0;

  @override
  Future<Biometry?> biometry() async => kind;

  @override
  Future<bool> has(String vaultId) async => keys.containsKey(vaultId);

  @override
  Future<bool> save(
    String vaultId,
    Uint8List key, {
    required String reason,
  }) async {
    if (kind == null) throw const BiometricKeyUnavailable('none');
    keys[vaultId] = Uint8List.fromList(key);
    return true;
  }

  @override
  Future<Uint8List?> read(String vaultId, {required String reason}) async {
    final key = keys[vaultId];
    if (key == null) throw const BiometricKeyGone();
    prompts++;
    return nextPromptSucceeds ? Uint8List.fromList(key) : null;
  }

  @override
  Future<void> delete(String vaultId) async => keys.remove(vaultId);
}
