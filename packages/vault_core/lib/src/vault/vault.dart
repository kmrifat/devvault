import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../crypto/vault_crypto.dart';
import '../format/envelope.dart';
import '../format/format_error.dart';
import '../format/vault_header.dart';
import '../keys/recovery_key.dart';
import '../keys/vault_keys.dart';
import '../model/item_type.dart';
import '../model/records.dart';
import '../store/vault_store.dart';
import '../sync/hlc.dart';

/// An unlocked vault: reads and writes encrypted records and files.
///
/// Holds the vault key until [lock]. Every write is stamped with this
/// device's id and a hybrid-logical-clock `rev`.
class Vault {
  Vault._({
    required this._crypto,
    required this.store,
    required this._header,
    required SecureKey this._vaultKey,
    required this.deviceId,
    required this._now,
  }) : _clock = Hlc.zero(deviceId);

  final VaultCrypto _crypto;
  final VaultStore store;
  final String deviceId;
  final DateTime Function() _now;
  VaultHeader _header;
  SecureKey? _vaultKey;
  Hlc _clock;

  /// Largest attachment v1 accepts: blobs are sealed in one AEAD call.
  static const int maxAttachmentBytes = 25 * 1024 * 1024;

  VaultHeader get header => _header;
  String get vaultId => _header.vaultId;
  bool get isLocked => _vaultKey == null;

  /// Creates a vault in [store] and returns it unlocked, together with the
  /// recovery key to show the user once.
  static Future<(Vault, RecoveryKey)> create({
    required VaultCrypto crypto,
    required VaultStore store,
    required String password,
    required String deviceId,
    required DateTime Function() now,
    int opsLimit = 3,
    int memLimit = 64 * 1024 * 1024,
  }) async {
    if (store.exists) throw StateError('A vault already exists here');
    final created = await VaultKeys.create(
      crypto,
      password: password,
      now: now(),
      opsLimit: opsLimit,
      memLimit: memLimit,
    );
    await store.open();
    await store.writeHeader(created.header);
    final vault = Vault._(
      crypto: crypto,
      store: store,
      header: created.header,
      vaultKey: created.vaultKey,
      deviceId: deviceId,
      now: now,
    );
    return (vault, created.recoveryKey);
  }

  /// Opens the vault in [store] with the master password. Throws
  /// [WrongPassword] or [VaultKeyMismatch].
  static Future<Vault> unlock({
    required VaultCrypto crypto,
    required VaultStore store,
    required String password,
    required String deviceId,
    required DateTime Function() now,
  }) async {
    await store.open();
    final header = await store.readHeader();
    final vk = await VaultKeys.unlockWithPassword(crypto, header, password);
    return Vault._(
      crypto: crypto,
      store: store,
      header: header,
      vaultKey: vk,
      deviceId: deviceId,
      now: now,
    );
  }

  /// Opens the vault with the recovery key. Follow with [changePassword]
  /// to set a new password.
  static Future<Vault> unlockWithRecovery({
    required VaultCrypto crypto,
    required VaultStore store,
    required RecoveryKey recoveryKey,
    required String deviceId,
    required DateTime Function() now,
  }) async {
    await store.open();
    final header = await store.readHeader();
    final vk = VaultKeys.unlockWithRecovery(crypto, header, recoveryKey);
    return Vault._(
      crypto: crypto,
      store: store,
      header: header,
      vaultKey: vk,
      deviceId: deviceId,
      now: now,
    );
  }

  /// Rewraps the vault key under [newPassword]. Writes `vault.json` and
  /// nothing else.
  Future<void> changePassword(String newPassword) async {
    final updated = await VaultKeys.changePassword(
      _crypto,
      _header,
      _key,
      newPassword,
    );
    await store.writeHeader(updated);
    _header = updated;
  }

  /// Wipes the vault key. The [Vault] can't be used afterwards.
  void lock() {
    _vaultKey?.dispose();
    _vaultKey = null;
  }

  /// A new random object id.
  String newId() => VaultKeys.uuidV4(_crypto);

  /// A new item, stamped but not yet saved; pass it to [putItem].
  Item newItem({
    required ItemType type,
    required String title,
    Map<String, ItemField> fields = const {},
  }) {
    final now = _now();
    return Item(
      id: newId(),
      typeName: type.wireName,
      title: title,
      fields: fields,
      createdAt: now,
      updatedAt: now,
      rev: _clock,
      deviceId: deviceId,
    );
  }

  /// Saves [item], stamping a new `rev`, this device and the update time.
  Future<Item> putItem(Item item) async {
    if (item.isReadOnly) {
      throw StateError('Item ${item.id} has a newer schema and is read-only');
    }
    final now = _now();
    final stamped = item.copyWith(
      rev: _tick(now),
      deviceId: deviceId,
      updatedAt: now,
    );
    await _writeRecord(stamped);
    return stamped;
  }

  /// Saves [app], stamping a new `rev` and this device.
  Future<AppRecord> putApp(AppRecord app) async {
    final now = _now();
    final stamped = AppRecord(
      id: app.id,
      name: app.name,
      bundleIds: app.bundleIds,
      packageNames: app.packageNames,
      iconBlobId: app.iconBlobId,
      createdAt: app.createdAt,
      updatedAt: now,
      rev: _tick(now),
      deviceId: deviceId,
      schema: app.schema,
      unknownFields: app.unknownFields,
    );
    await _writeRecord(stamped);
    return stamped;
  }

  /// Deletes a record: writes its tombstone, then removes the record file.
  /// Its blobs stay until garbage collection (P2).
  Future<Tombstone> delete(String id, TombstoneKind kind) async {
    final now = _now();
    final tombstone = Tombstone(
      id: id,
      kind: kind,
      deletedAt: now,
      rev: _tick(now),
      deviceId: deviceId,
    );
    await _writeRecord(tombstone);
    await store.delete(
      kind == TombstoneKind.item ? ObjectType.item : ObjectType.app,
      id,
    );
    return tombstone;
  }

  /// Encrypts [bytes] as a new blob and returns the attachment entry to put
  /// on an item.
  Future<Attachment> addAttachment(
    Uint8List bytes, {
    required String filename,
    String mime = 'application/octet-stream',
  }) async {
    if (bytes.length > maxAttachmentBytes) {
      throw AttachmentTooLarge(bytes.length);
    }
    final blobId = newId();
    final envelope = Envelope.seal(
      _crypto,
      slot: _slot(ObjectType.blob, blobId),
      key: _key,
      plaintext: bytes,
    );
    await store.write(ObjectType.blob, blobId, envelope);
    return Attachment(
      blobId: blobId,
      filename: filename,
      mime: mime,
      size: bytes.length,
      sha256: _hex(VaultCrypto.sha256(bytes)),
    );
  }

  /// The original file bytes of [attachment], checked against its sha256.
  /// Throws [AttachmentCorrupt] if the blob is missing, unreadable or
  /// doesn't match.
  Future<Uint8List> readAttachment(Attachment attachment) async {
    final envelope = await store.read(ObjectType.blob, attachment.blobId);
    if (envelope == null) throw AttachmentCorrupt(attachment.blobId);
    final Uint8List bytes;
    try {
      bytes = Envelope.open(
        _crypto,
        slot: _slot(ObjectType.blob, attachment.blobId),
        key: _key,
        envelope: envelope,
      );
    } on DecryptionFailed {
      throw AttachmentCorrupt(attachment.blobId);
    }
    if (bytes.length != attachment.size ||
        _hex(VaultCrypto.sha256(bytes)) != attachment.sha256) {
      throw AttachmentCorrupt(attachment.blobId);
    }
    return bytes;
  }

  /// Decrypts every item, app and tombstone. Objects that fail to open or
  /// parse are listed in [VaultContents.quarantined] instead of failing the
  /// whole load (SPEC §5). Also moves this device's clock past every `rev`
  /// it saw.
  Future<VaultContents> loadAll() async {
    final items = <String, Item>{};
    final apps = <String, AppRecord>{};
    final tombstones = <String, Tombstone>{};
    final quarantined = <ObjectSlot>[];

    for (final type in const [
      ObjectType.item,
      ObjectType.app,
      ObjectType.tombstone,
    ]) {
      for (final id in await store.list(type)) {
        final slot = _slot(type, id);
        final record = await _readRecord(slot);
        if (record == null) {
          quarantined.add(slot);
          continue;
        }
        _clock = _clock.receive(record.rev, _now());
        switch (record) {
          case final Item item:
            items[id] = item;
          case final AppRecord app:
            apps[id] = app;
          case final Tombstone tombstone:
            tombstones[id] = tombstone;
        }
      }
    }
    return VaultContents(
      items: items,
      apps: apps,
      tombstones: tombstones,
      quarantined: quarantined,
    );
  }

  /// Reads one item, or `null` if it doesn't exist. Throws if it exists
  /// but can't be opened.
  Future<Item?> readItem(String id) async {
    final slot = _slot(ObjectType.item, id);
    if (await store.read(ObjectType.item, id) == null) return null;
    final record = await _readRecord(slot);
    if (record is! Item) throw const DecryptionFailed();
    return record;
  }

  Future<SyncedRecord?> _readRecord(ObjectSlot slot) async {
    final envelope = await store.read(slot.type, slot.objectId);
    if (envelope == null) return null;
    try {
      final plaintext = Envelope.open(
        _crypto,
        slot: slot,
        key: _key,
        envelope: envelope,
      );
      final record = decodeRecord(slot.type, plaintext);
      // A record whose own id disagrees with its file name was moved.
      return record.id == slot.objectId ? record : null;
    } on DecryptionFailed {
      return null;
    } on VaultFormatException {
      return null;
    }
  }

  Future<void> _writeRecord(SyncedRecord record) => store.write(
    record.objectType,
    record.id,
    Envelope.seal(
      _crypto,
      slot: _slot(record.objectType, record.id),
      key: _key,
      plaintext: Uint8List.fromList(encodeRecord(record)),
    ),
  );

  Hlc _tick(DateTime now) => _clock = _clock.tick(now);

  ObjectSlot _slot(ObjectType type, String id) =>
      ObjectSlot(vaultId: vaultId, objectId: id, type: type);

  SecureKey get _key => _vaultKey ?? (throw StateError('The vault is locked'));

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Everything decrypted from a vault, plus what couldn't be.
class VaultContents {
  VaultContents({
    required this.items,
    required this.apps,
    required this.tombstones,
    required this.quarantined,
  });

  final Map<String, Item> items;
  final Map<String, AppRecord> apps;
  final Map<String, Tombstone> tombstones;

  /// Objects that failed to decrypt or parse. Shown to the user, never
  /// silently dropped or overwritten.
  final List<ObjectSlot> quarantined;
}

/// The file is over [Vault.maxAttachmentBytes].
class AttachmentTooLarge implements Exception {
  const AttachmentTooLarge(this.bytes);

  final int bytes;

  @override
  String toString() => 'AttachmentTooLarge($bytes bytes)';
}

/// A blob is missing, can't be decrypted, or doesn't match its sha256.
class AttachmentCorrupt implements Exception {
  const AttachmentCorrupt(this.blobId);

  final String blobId;

  @override
  String toString() => 'AttachmentCorrupt($blobId)';
}
