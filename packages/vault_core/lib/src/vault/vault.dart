import 'dart:convert';
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
  /// recovery key to show the user once. [vaultId] lets the caller choose
  /// the id up front (it names the vault's folder); it's random otherwise.
  static Future<(Vault, RecoveryKey)> create({
    required VaultCrypto crypto,
    required VaultStore store,
    required String password,
    required String deviceId,
    required DateTime Function() now,
    String? vaultId,
    int opsLimit = 3,
    int memLimit = 64 * 1024 * 1024,
  }) async {
    if (store.exists) throw StateError('A vault already exists here');
    final created = await VaultKeys.create(
      crypto,
      password: password,
      now: now(),
      vaultId: vaultId,
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
    final vault = Vault._(
      crypto: crypto,
      store: store,
      header: header,
      vaultKey: vk,
      deviceId: deviceId,
      now: now,
    );
    await vault._resumeRotation(password);
    return vault;
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

  /// Set when unlocking finished a rotation that was interrupted: the new
  /// recovery key, which the user has not seen yet.
  RecoveryKey? get pendingRecoveryKey => _pendingRecoveryKey;
  RecoveryKey? _pendingRecoveryKey;

  /// Replaces the vault key after a suspected compromise (SPEC §9).
  ///
  /// Every item, app and tombstone is re-encrypted in place and every blob
  /// under a new id; `vault.json` is written last, with a new recovery key,
  /// which is returned for the user to save. Old blobs are then removed.
  ///
  /// The new key is kept in a device-local journal sealed with the old key
  /// until `vault.json` is replaced, so a crash at any point either leaves a
  /// vault that opens with the old key or is finished on the next unlock.
  Future<RecoveryKey> rotateVaultKey(String password) async {
    // Prove the password before touching anything.
    (await VaultKeys.unlockWithPassword(_crypto, _header, password)).dispose();
    final newKey = _crypto.randomKey();
    final newRecoveryKey = RecoveryKey.generate(_crypto);
    await store.writeJournal(_sealJournal(newKey, newRecoveryKey));
    await _finishRotation(password, newKey, newRecoveryKey);
    return newRecoveryKey;
  }

  /// Replaces the recovery key (for example when the old one was lost).
  /// Writes `vault.json` only.
  Future<RecoveryKey> replaceRecoveryKey() async {
    final recoveryKey = RecoveryKey.generate(_crypto);
    final updated = VaultKeys.rewrapRecovery(
      _crypto,
      _header,
      _key,
      recoveryKey,
    );
    await store.writeHeader(updated);
    _header = updated;
    return recoveryKey;
  }

  static const String _journalInfo = 'devvault/v1/rotation-journal';

  Uint8List _journalAad() =>
      VaultCrypto.utf8Bytes('$_journalInfo|$vaultId|${_header.vkId}');

  Uint8List _sealJournal(SecureKey newKey, RecoveryKey newRecoveryKey) {
    final plaintext = Uint8List(64);
    newKey.runUnlockedSync((b) => plaintext.setAll(0, b));
    newRecoveryKey.key.runUnlockedSync((b) => plaintext.setAll(32, b));
    final nonce = _crypto.randomBytes(VaultCrypto.nonceBytes);
    final sealed = _crypto.aeadEncrypt(
      message: plaintext,
      additionalData: _journalAad(),
      nonce: nonce,
      key: _key,
    );
    plaintext.fillRange(0, 64, 0);
    return Uint8List.fromList([...nonce, ...sealed]);
  }

  Future<void> _resumeRotation(String password) async {
    final journal = await store.readJournal();
    if (journal == null) return;
    final Uint8List plaintext;
    try {
      plaintext = _crypto.aeadDecrypt(
        cipherText: Uint8List.sublistView(journal, VaultCrypto.nonceBytes),
        additionalData: _journalAad(),
        nonce: Uint8List.sublistView(journal, 0, VaultCrypto.nonceBytes),
        key: _key,
      );
    } on DecryptionFailed {
      // Sealed with a key this header no longer uses: the rotation already
      // replaced vault.json and only the clean-up was interrupted.
      await store.deleteJournal();
      return;
    }
    final newKey = _crypto.keyFromBytes(
      Uint8List.sublistView(plaintext, 0, 32),
    );
    final newRecoveryKey = RecoveryKey.fromKey(
      _crypto.keyFromBytes(Uint8List.sublistView(plaintext, 32, 64)),
    );
    plaintext.fillRange(0, plaintext.length, 0);
    await _finishRotation(password, newKey, newRecoveryKey);
    _pendingRecoveryKey = newRecoveryKey;
  }

  /// The id an old blob gets under the new key. Derived, not random, so a
  /// resumed rotation finds the blobs it already wrote.
  String _rotatedBlobId(SecureKey newKey, String oldId) =>
      VaultKeys.uuidFromBytes(
        _crypto.keyedHash(
          key: newKey,
          message: VaultCrypto.utf8Bytes('devvault/v1/rotated-blob|$oldId'),
        ),
      );

  Future<void> _finishRotation(
    String password,
    SecureKey newKey,
    RecoveryKey newRecoveryKey,
  ) async {
    final oldKey = _key;

    // Opens an object with the old key, or reports that it's already been
    // moved to the new one, or that neither key opens it (left alone and
    // quarantined later).
    (Uint8List, bool)? openEither(ObjectSlot slot, Uint8List envelope) {
      for (final (key, isOld) in [(oldKey, true), (newKey, false)]) {
        try {
          return (
            Envelope.open(_crypto, slot: slot, key: key, envelope: envelope),
            isOld,
          );
        } on DecryptionFailed {
          continue;
        }
      }
      return null;
    }

    // 1. Blobs: re-encrypt each old blob under its derived new id.
    final retiredBlobs = <String>[];
    for (final id in await store.list(ObjectType.blob)) {
      final envelope = (await store.read(ObjectType.blob, id))!;
      final opened = openEither(_slot(ObjectType.blob, id), envelope);
      if (opened == null || !opened.$2) continue; // corrupt, or already new
      final newId = _rotatedBlobId(newKey, id);
      if (await store.read(ObjectType.blob, newId) == null) {
        await store.write(
          ObjectType.blob,
          newId,
          Envelope.seal(
            _crypto,
            slot: _slot(ObjectType.blob, newId),
            key: newKey,
            plaintext: opened.$1,
          ),
        );
      }
      retiredBlobs.add(id);
    }

    // 2. Records: re-encrypt in place; items point at the new blob ids.
    for (final type in const [
      ObjectType.item,
      ObjectType.app,
      ObjectType.tombstone,
    ]) {
      for (final id in await store.list(type)) {
        final slot = _slot(type, id);
        final envelope = (await store.read(type, id))!;
        final opened = openEither(slot, envelope);
        if (opened == null || !opened.$2) continue;
        var plaintext = opened.$1;
        if (type == ObjectType.item) {
          final item = Item.fromJson(jsonDecode(utf8.decode(plaintext)));
          final moved = item.copyWith(
            attachments: [
              for (final a in item.attachments)
                Attachment(
                  blobId: _rotatedBlobId(newKey, a.blobId),
                  filename: a.filename,
                  mime: a.mime,
                  size: a.size,
                  sha256: a.sha256,
                  unknownFields: a.unknownFields,
                ),
            ],
          );
          plaintext = Uint8List.fromList(encodeRecord(moved));
        }
        await store.write(
          type,
          id,
          Envelope.seal(_crypto, slot: slot, key: newKey, plaintext: plaintext),
        );
      }
    }

    // 3. vault.json last: from here on only the new key opens the vault.
    final updated = await VaultKeys.rewrapAll(
      _crypto,
      _header,
      newKey,
      password: password,
      recoveryKey: newRecoveryKey,
    );
    await store.writeHeader(updated);
    _header = updated;
    _vaultKey = newKey;
    oldKey.dispose();

    // 4. Clean up.
    await store.deleteJournal();
    for (final id in retiredBlobs) {
      await store.delete(ObjectType.blob, id);
    }
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
