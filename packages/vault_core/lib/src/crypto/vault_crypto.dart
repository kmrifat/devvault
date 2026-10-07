import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

/// The cryptographic primitives the vault format uses (SPEC §2), on
/// libsodium. Nothing else in vault_core touches libsodium directly.
///
/// Keys are [SecureKey]s: libsodium-allocated memory that is locked and
/// wiped on [SecureKey.dispose]. Whoever receives a key owns it and must
/// dispose it.
class VaultCrypto {
  VaultCrypto._(this._sodium, this._random);

  final SodiumSumo _sodium;
  final Uint8List Function(int length) _random;

  static const int keyBytes = 32;
  static const int nonceBytes = 24;
  static const int tagBytes = 16;
  static const int saltBytes = 16;

  /// Loads libsodium. Call once and share the instance.
  static Future<VaultCrypto> init() async {
    final sodium = await SodiumSumoInit.init();
    return VaultCrypto._(sodium, sodium.randombytes.buf);
  }

  /// A [VaultCrypto] whose random bytes come from [seed], so test vectors are
  /// reproducible. Refuses to exist in a release build.
  @visibleForTesting
  static Future<VaultCrypto> withFixedRandom(List<int> seed) async {
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw StateError('Deterministic randomness is for test vectors only');
    }
    final sodium = await SodiumSumoInit.init();
    return VaultCrypto._(sodium, _SeededStream(seed).take);
  }

  /// libsodium's version, for diagnostics.
  String get libsodiumVersion =>
      '${_sodium.version.major}.${_sodium.version.minor}';

  /// [length] bytes from the OS CSPRNG.
  Uint8List randomBytes(int length) => _random(length);

  /// A fresh random 256-bit key.
  SecureKey randomKey() => keyFromBytes(randomBytes(keyBytes));

  /// Copies [bytes] into secure memory. The caller should zero [bytes]
  /// afterwards if they came from a decryption.
  SecureKey keyFromBytes(Uint8List bytes) => _sodium.secureCopy(bytes);

  /// XChaCha20-Poly1305-IETF: `ciphertext || 16-byte tag`.
  Uint8List aeadEncrypt({
    required Uint8List message,
    required Uint8List additionalData,
    required Uint8List nonce,
    required SecureKey key,
  }) => _sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
    message: message,
    additionalData: additionalData,
    nonce: nonce,
    key: key,
  );

  /// Opens [cipherText]. Throws [DecryptionFailed] for any failure (wrong
  /// key, wrong associated data, modified bytes); the cause is not exposed.
  Uint8List aeadDecrypt({
    required Uint8List cipherText,
    required Uint8List additionalData,
    required Uint8List nonce,
    required SecureKey key,
  }) {
    if (cipherText.length < tagBytes || nonce.length != nonceBytes) {
      throw const DecryptionFailed();
    }
    try {
      return _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: cipherText,
        additionalData: additionalData,
        nonce: nonce,
        key: key,
      );
    } on SodiumException {
      throw const DecryptionFailed();
    }
  }

  /// Argon2id v1.3 with parallelism 1 (ADR-0003). [password] is the UTF-8
  /// bytes of the NFC-normalised master password.
  SecureKey argon2id({
    required Uint8List password,
    required Uint8List salt,
    required int opsLimit,
    required int memLimit,
    int outLength = keyBytes,
  }) => _sodium.crypto.pwhash.callRaw(
    outLen: outLength,
    password: Int8List.sublistView(password),
    salt: salt,
    opsLimit: opsLimit,
    memLimit: memLimit,
    alg: CryptoPwhashAlgorithm.argon2id13,
  );

  /// HKDF-SHA256 (RFC 5869): extract with [salt], then expand with [info].
  SecureKey hkdfSha256({
    required SecureKey ikm,
    required Uint8List salt,
    required String info,
    int outLength = keyBytes,
  }) {
    final kdf = _sodium.crypto.kdfHkdfSha256;
    final prk = ikm.runUnlockedSync(
      (bytes) => kdf.extract(salt: salt, ikm: Uint8List.fromList(bytes)),
    );
    try {
      return kdf.expand(masterKey: prk, context: info, outLen: outLength);
    } finally {
      prk.dispose();
    }
  }

  /// Keyed BLAKE2b with a 32-byte output.
  Uint8List keyedHash({required SecureKey key, required Uint8List message}) =>
      _sodium.crypto.genericHash(message: message, outLen: 32, key: key);

  /// SHA-256 of [bytes] (file integrity, recovery-key checksum).
  static Uint8List sha256(List<int> bytes) =>
      Uint8List.fromList(hashes.sha256.convert(bytes).bytes);

  /// UTF-8 bytes of [text].
  static Uint8List utf8Bytes(String text) =>
      Uint8List.fromList(utf8.encode(text));
}

/// Decryption failed. Deliberately says nothing about why: a wrong key, a
/// wrong slot and tampering all look the same (SPEC §5).
class DecryptionFailed implements Exception {
  const DecryptionFailed();

  @override
  String toString() => 'DecryptionFailed';
}

/// SHA-256 in counter mode over a seed: deterministic bytes for test
/// vectors. Never used for real keys.
class _SeededStream {
  _SeededStream(List<int> seed) : _seed = List.unmodifiable(seed);

  final List<int> _seed;
  int _counter = 0;
  final List<int> _buffer = [];

  Uint8List take(int length) {
    while (_buffer.length < length) {
      final block = ByteData(8)..setUint64(0, _counter++);
      _buffer.addAll(
        hashes.sha256.convert([..._seed, ...block.buffer.asUint8List()]).bytes,
      );
    }
    final out = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return out;
  }
}
