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

/// Why biometrics the device has can't be used right now, as the platform
/// reports it.
enum BiometryUnavailable {
  /// Nothing is enrolled (no fingerprint, no face).
  notEnrolled,

  /// Locked after too many failed tries until the device password is used.
  lockedOut,

  /// Anything else, such as a MacBook's sensor while its lid is closed.
  unavailable,
}

/// The biometric the device has, and why it can't be used right now, if
/// it can't.
class BiometryState {
  const BiometryState(this.kind, {this.unavailable});

  final Biometry kind;
  final BiometryUnavailable? unavailable;

  bool get ready => unavailable == null;
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

  /// Whether the biometric check itself failed (no match), rather than the
  /// key store.
  bool get failedCheck => code.startsWith('auth-');

  @override
  String toString() => 'BiometricKeyUnavailable($code)';
}

/// Keeps a vault key on this device behind Face ID, Touch ID or a
/// fingerprint (SPEC §9.1): a Keychain item bound to the current biometric
/// set on Apple platforms, a Keystore key with per-use strong biometric
/// authentication wrapping it on Android. Never synced or backed up.
abstract interface class BiometricKeyStore {
  /// The biometric this device has, ready or not, or null when it has none.
  /// Never prompts.
  Future<BiometryState?> biometry();

  /// Whether this build can keep a key behind biometrics at all. False on a
  /// macOS build signed without a keychain access group: the data
  /// protection keychain refuses it. Never prompts.
  Future<bool> canStore();

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
  Future<BiometryState?> biometry() async => null;

  @override
  Future<bool> canStore() async => false;

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
  Future<BiometryState?> biometry() async {
    try {
      final reply = await _channel.invokeMapMethod<String, String>('biometry');
      final kind = Biometry.values
          .where((b) => b.name == reply?['kind'])
          .firstOrNull;
      if (kind == null) return null;
      final why = reply?['unavailable'];
      return BiometryState(
        kind,
        unavailable: why == null
            ? null
            : BiometryUnavailable.values
                      .where((u) => u.name == why)
                      .firstOrNull ??
                  BiometryUnavailable.unavailable,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> canStore() async {
    try {
      return await _channel.invokeMethod<bool>('canStore') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
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
  Future<Uint8List?> read(String vaultId, {required String reason}) =>
      _call(() async {
        final reply = await _channel.invokeMethod<Uint8List>('read', {
          'vault': vaultId,
          'reason': reason,
        });
        // A reply is a read-only view of the platform's message, so the
        // caller couldn't wipe it: hand over a copy it can.
        return reply == null ? null : Uint8List.fromList(reply);
      });

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
  MemoryBiometricKeyStore({
    this.kind = Biometry.faceId,
    this.unavailable,
    this.storable = true,
  });

  Biometry? kind;

  /// Set to play biometrics the device has but can't use right now.
  BiometryUnavailable? unavailable;

  /// False plays a build that can't keep a key (see [canStore]).
  bool storable;
  final keys = <String, Uint8List>{};

  /// What the next prompt does: `true` succeeds, `false` is a cancel.
  bool nextPromptSucceeds = true;

  /// How many times a prompt was shown.
  int prompts = 0;

  @override
  Future<BiometryState?> biometry() async {
    final kind = this.kind;
    return kind == null ? null : BiometryState(kind, unavailable: unavailable);
  }

  @override
  Future<bool> canStore() async => storable;

  @override
  Future<bool> has(String vaultId) async => keys.containsKey(vaultId);

  @override
  Future<bool> save(
    String vaultId,
    Uint8List key, {
    required String reason,
  }) async {
    if (kind == null) throw const BiometricKeyUnavailable('none');
    if (!storable) throw const BiometricKeyUnavailable('keychain--34018');
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
