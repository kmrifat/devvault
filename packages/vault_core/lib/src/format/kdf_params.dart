import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../crypto/vault_crypto.dart';
import 'format_error.dart';

/// Argon2id parameters stored in `vault.json` (SPEC §4, ADR-0003).
@immutable
class KdfParams {
  KdfParams({
    required this.opsLimit,
    required this.memLimit,
    required Uint8List salt,
  }) : salt = Uint8List.fromList(salt) {
    validate();
  }

  static const String algorithm = 'argon2id13';

  static const int defaultOpsLimit = 3;
  static const int defaultMemLimit = 64 * 1024 * 1024;

  static const int minOpsLimit = 1;
  static const int maxOpsLimit = 10;
  static const int minMemLimit = 8 * 1024 * 1024;
  static const int maxMemLimit = 1024 * 1024 * 1024;

  final int opsLimit;
  final int memLimit;
  final Uint8List salt;

  /// Fresh parameters with a new random salt, for a new vault or a password
  /// change.
  factory KdfParams.generate(
    VaultCrypto crypto, {
    int opsLimit = defaultOpsLimit,
    int memLimit = defaultMemLimit,
  }) => KdfParams(
    opsLimit: opsLimit,
    memLimit: memLimit,
    salt: crypto.randomBytes(VaultCrypto.saltBytes),
  );

  /// Reads the `kdf` object of `vault.json`. Rejects anything outside the
  /// bounds **before** any key derivation runs, so a tampered header can't
  /// make a device allocate gigabytes.
  factory KdfParams.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const VaultFormatException('kdf must be an object');
    }
    if (json['alg'] != algorithm) {
      throw const VaultFormatException('kdf.alg must be argon2id13');
    }
    final ops = json['ops_limit'];
    final mem = json['mem_limit'];
    final salt = json['salt'];
    if (ops is! int || mem is! int || salt is! String) {
      throw const VaultFormatException('kdf fields have the wrong types');
    }
    final Uint8List saltBytes;
    try {
      saltBytes = base64.decode(salt);
    } on FormatException {
      throw const VaultFormatException('kdf.salt is not base64');
    }
    return KdfParams(opsLimit: ops, memLimit: mem, salt: saltBytes);
  }

  Map<String, Object?> toJson() => {
    'alg': algorithm,
    'ops_limit': opsLimit,
    'mem_limit': memLimit,
    'salt': base64.encode(salt),
  };

  @visibleForTesting
  void validate() {
    if (opsLimit < minOpsLimit || opsLimit > maxOpsLimit) {
      throw VaultFormatException(
        'kdf.ops_limit must be $minOpsLimit..$maxOpsLimit',
      );
    }
    if (memLimit < minMemLimit || memLimit > maxMemLimit) {
      throw const VaultFormatException('kdf.mem_limit must be 8 MiB..1 GiB');
    }
    if (salt.length != VaultCrypto.saltBytes) {
      throw const VaultFormatException('kdf.salt must be 16 bytes');
    }
  }

  /// The password bytes SPEC §4.2 hashes: UTF-8 of the NFC form, so the same
  /// password typed on different platforms gives the same key.
  static Uint8List passwordBytes(String password) =>
      Uint8List.fromList(utf8.encode(unorm.nfc(password)));

  /// Derives KEK_pw on a background isolate, so the UI stays responsive
  /// while Argon2id runs.
  Future<SecureKey> deriveKey(VaultCrypto crypto, String password) =>
      crypto.argon2idIsolated(
        password: passwordBytes(password),
        salt: salt,
        opsLimit: opsLimit,
        memLimit: memLimit,
      );

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.opsLimit == opsLimit &&
      other.memLimit == memLimit &&
      _bytesEqual(other.salt, salt);

  @override
  int get hashCode => Object.hash(opsLimit, memLimit, Object.hashAll(salt));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
