import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/vault_crypto.dart';
import 'format_error.dart';

/// What an encrypted object holds. The code is the envelope's type byte;
/// the name goes into the associated data (SPEC §5).
enum ObjectType {
  item(0x01, 'item', 'items'),
  app(0x02, 'app', 'apps'),
  blob(0x03, 'blob', 'blobs'),
  tombstone(0x04, 'tombstone', 'tombstones'),
  vkWrapPassword(0x05, 'vk_wrap_password', null),
  vkWrapRecovery(0x06, 'vk_wrap_recovery', null),
  organization(0x07, 'organization', 'organizations');

  const ObjectType(this.code, this.wireName, this.folder);

  final int code;
  final String wireName;

  /// The folder these objects live in, or `null` for the wrapped keys,
  /// which live in `vault.json`.
  final String? folder;
}

/// Where an object lives: the vault, its id (from the file name) and its
/// type (from the folder). The associated data is built from this, never
/// from the object itself, so an object moved to another slot can't be
/// opened.
@immutable
class ObjectSlot {
  ObjectSlot({
    required this.vaultId,
    required this.objectId,
    required this.type,
  }) {
    if (!isCanonicalUuid(vaultId)) {
      throw const VaultFormatException('vault_id is not a lowercase UUID');
    }
    if (!isCanonicalUuid(objectId)) {
      throw const VaultFormatException('object_id is not a lowercase UUID');
    }
  }

  final String vaultId;
  final String objectId;
  final ObjectType type;

  /// `vault_id|object_id|object_type|format_version`, UTF-8.
  Uint8List get associatedData => VaultCrypto.utf8Bytes(
    '$vaultId|$objectId|${type.wireName}|${Envelope.formatVersion}',
  );

  @override
  bool operator ==(Object other) =>
      other is ObjectSlot &&
      other.vaultId == vaultId &&
      other.objectId == objectId &&
      other.type == type;

  @override
  int get hashCode => Object.hash(vaultId, objectId, type);

  @override
  String toString() => '${type.wireName}/$objectId';
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Whether [id] is a UUID in the canonical lowercase 8-4-4-4-12 form the
/// format uses for vault and object ids.
bool isCanonicalUuid(String id) => _uuid.hasMatch(id);

/// The binary envelope every encrypted object uses (SPEC §5):
///
/// ```
/// "DVLT" | format_version | object_type | nonce (24) | ciphertext + tag
/// ```
abstract final class Envelope {
  static const int formatVersion = 1;
  static const List<int> magic = [0x44, 0x56, 0x4C, 0x54]; // "DVLT"
  static const int headerLength = 6;
  static const int overhead =
      headerLength + VaultCrypto.nonceBytes + VaultCrypto.tagBytes;

  /// Encrypts [plaintext] for [slot] under [key] with a fresh random nonce.
  static Uint8List seal(
    VaultCrypto crypto, {
    required ObjectSlot slot,
    required SecureKey key,
    required Uint8List plaintext,
    @visibleForTesting Uint8List? nonce,
  }) {
    final n = nonce ?? crypto.randomBytes(VaultCrypto.nonceBytes);
    final cipherText = crypto.aeadEncrypt(
      message: plaintext,
      additionalData: slot.associatedData,
      nonce: n,
      key: key,
    );
    return Uint8List(headerLength + n.length + cipherText.length)
      ..setAll(0, magic)
      ..[4] = formatVersion
      ..[5] = slot.type.code
      ..setAll(headerLength, n)
      ..setAll(headerLength + n.length, cipherText);
  }

  /// Opens [envelope] found at [slot]. Any problem (bad magic, other
  /// version, another type, truncated, tampered, wrong key) throws the
  /// same [DecryptionFailed].
  static Uint8List open(
    VaultCrypto crypto, {
    required ObjectSlot slot,
    required SecureKey key,
    required Uint8List envelope,
  }) {
    if (envelope.length < overhead ||
        envelope[0] != magic[0] ||
        envelope[1] != magic[1] ||
        envelope[2] != magic[2] ||
        envelope[3] != magic[3] ||
        envelope[4] != formatVersion ||
        envelope[5] != slot.type.code) {
      throw const DecryptionFailed();
    }
    return crypto.aeadDecrypt(
      cipherText: Uint8List.sublistView(
        envelope,
        headerLength + VaultCrypto.nonceBytes,
      ),
      additionalData: slot.associatedData,
      nonce: Uint8List.sublistView(
        envelope,
        headerLength,
        headerLength + VaultCrypto.nonceBytes,
      ),
      key: key,
    );
  }
}
