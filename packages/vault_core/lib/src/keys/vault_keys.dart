import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/vault_crypto.dart';
import '../format/envelope.dart';
import '../format/kdf_params.dart';
import '../format/vault_header.dart';
import 'recovery_key.dart';

/// The key hierarchy (SPEC §4): a random vault key (VK) wrapped once under
/// the master password (Argon2id) and once under the recovery key (HKDF).
abstract final class VaultKeys {
  static const String recoveryInfo = 'devvault/v1/recovery-kek';
  static const String vkIdMessage = 'devvault/v1/vk-id';

  /// Creates a new vault's header and keys. The caller shows the recovery
  /// key to the user once, then disposes it, and owns the returned VK.
  static Future<NewVault> create(
    VaultCrypto crypto, {
    required String password,
    required DateTime now,
    String? vaultId,
    int opsLimit = KdfParams.defaultOpsLimit,
    int memLimit = KdfParams.defaultMemLimit,
  }) async {
    final id = vaultId ?? uuidV4(crypto);
    final vk = crypto.randomKey();
    final recoveryKey = RecoveryKey.generate(crypto);
    final kdf = KdfParams.generate(
      crypto,
      opsLimit: opsLimit,
      memLimit: memLimit,
    );

    final kekPassword = await kdf.deriveKey(crypto, password);
    final kekRecovery = _recoveryKek(crypto, id, recoveryKey);
    try {
      final header = VaultHeader(
        vaultId: id,
        createdAt: now,
        kdf: kdf,
        wrappedVkPassword: _wrap(
          crypto,
          id,
          ObjectType.vkWrapPassword,
          kekPassword,
          vk,
        ),
        wrappedVkRecovery: _wrap(
          crypto,
          id,
          ObjectType.vkWrapRecovery,
          kekRecovery,
          vk,
        ),
        vkId: vkId(crypto, vk),
      );
      return NewVault(header: header, vaultKey: vk, recoveryKey: recoveryKey);
    } finally {
      kekPassword.dispose();
      kekRecovery.dispose();
    }
  }

  /// Unwraps the VK with the master password. Throws [WrongPassword].
  static Future<SecureKey> unlockWithPassword(
    VaultCrypto crypto,
    VaultHeader header,
    String password,
  ) async {
    final kek = await header.kdf.deriveKey(crypto, password);
    try {
      return _unwrap(
        crypto,
        header,
        ObjectType.vkWrapPassword,
        kek,
        header.wrappedVkPassword,
        onFailure: const WrongPassword(),
      );
    } finally {
      kek.dispose();
    }
  }

  /// Unwraps the VK with the recovery key. Throws [WrongRecoveryKey].
  static SecureKey unlockWithRecovery(
    VaultCrypto crypto,
    VaultHeader header,
    RecoveryKey recoveryKey,
  ) {
    final kek = _recoveryKek(crypto, header.vaultId, recoveryKey);
    try {
      return _unwrap(
        crypto,
        header,
        ObjectType.vkWrapRecovery,
        kek,
        header.wrappedVkRecovery,
        onFailure: const WrongRecoveryKey(),
      );
    } finally {
      kek.dispose();
    }
  }

  /// A header with a new salt and a new password wrap of [vk]. Everything
  /// else, including the recovery wrap and `vk_id`, is unchanged: changing
  /// the password rewrites `vault.json` and nothing else (SPEC §9).
  static Future<VaultHeader> changePassword(
    VaultCrypto crypto,
    VaultHeader header,
    SecureKey vk,
    String newPassword, {
    int? opsLimit,
    int? memLimit,
  }) async {
    final kdf = KdfParams.generate(
      crypto,
      opsLimit: opsLimit ?? header.kdf.opsLimit,
      memLimit: memLimit ?? header.kdf.memLimit,
    );
    final kek = await kdf.deriveKey(crypto, newPassword);
    try {
      return header.copyWith(
        kdf: kdf,
        wrappedVkPassword: _wrap(
          crypto,
          header.vaultId,
          ObjectType.vkWrapPassword,
          kek,
          vk,
        ),
      );
    } finally {
      kek.dispose();
    }
  }

  /// A header for [vk] with fresh password and recovery wraps and a new
  /// `vk_id`, keeping the vault id, creation time and unknown fields. Used
  /// when the vault key itself is rotated.
  static Future<VaultHeader> rewrapAll(
    VaultCrypto crypto,
    VaultHeader header,
    SecureKey vk, {
    required String password,
    required RecoveryKey recoveryKey,
  }) async {
    final kdf = KdfParams.generate(
      crypto,
      opsLimit: header.kdf.opsLimit,
      memLimit: header.kdf.memLimit,
    );
    final kekPassword = await kdf.deriveKey(crypto, password);
    final kekRecovery = _recoveryKek(crypto, header.vaultId, recoveryKey);
    try {
      return header.copyWith(
        kdf: kdf,
        wrappedVkPassword: _wrap(
          crypto,
          header.vaultId,
          ObjectType.vkWrapPassword,
          kekPassword,
          vk,
        ),
        wrappedVkRecovery: _wrap(
          crypto,
          header.vaultId,
          ObjectType.vkWrapRecovery,
          kekRecovery,
          vk,
        ),
        vkId: vkId(crypto, vk),
      );
    } finally {
      kekPassword.dispose();
      kekRecovery.dispose();
    }
  }

  /// A header whose recovery wrap is replaced with one for [recoveryKey].
  static VaultHeader rewrapRecovery(
    VaultCrypto crypto,
    VaultHeader header,
    SecureKey vk,
    RecoveryKey recoveryKey,
  ) {
    final kek = _recoveryKek(crypto, header.vaultId, recoveryKey);
    try {
      return header.copyWith(
        wrappedVkRecovery: _wrap(
          crypto,
          header.vaultId,
          ObjectType.vkWrapRecovery,
          kek,
          vk,
        ),
      );
    } finally {
      kek.dispose();
    }
  }

  /// `hex(BLAKE2b-256(key = VK, "devvault/v1/vk-id"))`.
  static String vkId(VaultCrypto crypto, SecureKey vk) => _hex(
    crypto.keyedHash(key: vk, message: VaultCrypto.utf8Bytes(vkIdMessage)),
  );

  /// A random UUIDv4 in canonical lowercase form.
  static String uuidV4(VaultCrypto crypto) =>
      uuidFromBytes(crypto.randomBytes(16));

  /// Formats 16 bytes as a canonical UUIDv4 (version and variant bits set).
  static String uuidFromBytes(List<int> bytes) {
    final b = Uint8List.fromList(bytes.sublist(0, 16));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = _hex(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static SecureKey _recoveryKek(
    VaultCrypto crypto,
    String vaultId,
    RecoveryKey recoveryKey,
  ) => crypto.hkdfSha256(
    ikm: recoveryKey.key,
    salt: VaultCrypto.utf8Bytes(vaultId),
    info: recoveryInfo,
  );

  static Uint8List _wrap(
    VaultCrypto crypto,
    String vaultId,
    ObjectType type,
    SecureKey kek,
    SecureKey vk,
  ) => vk.runUnlockedSync(
    (bytes) => Envelope.seal(
      crypto,
      slot: ObjectSlot(vaultId: vaultId, objectId: vaultId, type: type),
      key: kek,
      plaintext: Uint8List.fromList(bytes),
    ),
  );

  static SecureKey _unwrap(
    VaultCrypto crypto,
    VaultHeader header,
    ObjectType type,
    SecureKey kek,
    Uint8List wrapped, {
    required Exception onFailure,
  }) {
    final Uint8List vkBytes;
    try {
      vkBytes = Envelope.open(
        crypto,
        slot: ObjectSlot(
          vaultId: header.vaultId,
          objectId: header.vaultId,
          type: type,
        ),
        key: kek,
        envelope: wrapped,
      );
    } on DecryptionFailed {
      throw onFailure;
    }
    if (vkBytes.length != VaultCrypto.keyBytes) {
      vkBytes.fillRange(0, vkBytes.length, 0);
      throw onFailure;
    }
    final vk = crypto.keyFromBytes(vkBytes);
    vkBytes.fillRange(0, vkBytes.length, 0);
    if (vkId(crypto, vk) != header.vkId) {
      vk.dispose();
      throw const VaultKeyMismatch();
    }
    return vk;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A freshly created vault: its header, the VK and the one-time recovery key.
class NewVault {
  NewVault({
    required this.header,
    required this.vaultKey,
    required this.recoveryKey,
  });

  final VaultHeader header;
  final SecureKey vaultKey;
  final RecoveryKey recoveryKey;
}

/// The master password didn't open the vault.
class WrongPassword implements Exception {
  const WrongPassword();

  @override
  String toString() => 'WrongPassword';
}

/// The recovery key didn't open the vault.
class WrongRecoveryKey implements Exception {
  const WrongRecoveryKey();

  @override
  String toString() => 'WrongRecoveryKey';
}

/// The unwrapped key doesn't match the header's `vk_id`: `vault.json` was
/// changed by something other than DevVault (SPEC §4.4).
class VaultKeyMismatch implements Exception {
  const VaultKeyMismatch();

  @override
  String toString() => 'VaultKeyMismatch';
}
