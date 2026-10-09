import 'dart:io';
import 'dart:typed_data';

import '../crypto/vault_crypto.dart';
import '../format/envelope.dart';
import '../format/vault_header.dart';
import '../keys/vault_keys.dart';
import '../model/records.dart';
import '../store/vault_store.dart';
import '../vault/vault.dart';
import 'merge.dart';
import 'storage_backend.dart';
import 'sync_state.dart';

/// What one [SyncEngine.sync] did.
class SyncReport {
  /// Remote objects taken as they were (nothing local had changed).
  int pulled = 0;

  /// Local objects written to storage (including deletions).
  int pushed = 0;

  /// Objects changed on both sides and merged.
  int merged = 0;

  /// Merges that kept a conflicting version for the user to resolve.
  int conflicts = 0;

  /// Remote objects that couldn't be opened: left alone, never overwritten.
  int unreadable = 0;

  /// Pull/push rounds needed (more than 1 after losing a race).
  int attempts = 0;

  /// Whether anything in the local vault changed (the index needs a reload).
  bool get changedLocally => pulled > 0 || merged > 0;

  /// Things the user should hear about.
  final List<String> notices = [];

  @override
  String toString() =>
      'SyncReport(pulled: $pulled, pushed: $pushed, merged: $merged, '
      'conflicts: $conflicts, unreadable: $unreadable, attempts: $attempts)';
}

/// Two-way sync between an unlocked [Vault] and a [StorageBackend].
///
/// Objects live remotely under `[rootPrefix]<vault_id>/` with the local layout
/// (SPEC §3). Each round:
///
/// 1. **Pull.** Every remote object whose etag moved since the last sync is
///    read. When the local copy is unchanged since its base it is replaced
///    byte for byte; when both changed they are merged (ADR-0004) and the
///    result saved locally, to be pushed. Remote deletions are applied
///    unless the local copy changed (an edit beats a delete).
/// 2. **Push**, in dependency order: `vault.json` for a new vault, blobs,
///    items, apps and organizations, tombstones, then deletions. Everything
///    is conditional (`If-None-Match: *` for new objects, `If-Match` the
///    last seen etag otherwise), so a device that lost a race gets
///    [PreconditionFailed], pulls again and merges. At most [maxAttempts]
///    rounds.
///
/// Local changes are found by comparing each object's ciphertext with its
/// base (the bytes last synced), so no write hook is needed: a password
/// change touches only `vault.json`, so that is all that is pushed.
class SyncEngine {
  SyncEngine({
    required this.vault,
    required this.backend,
    SyncStateStore? stateStore,
    this.maxAttempts = 5,
    this.rootPrefix = '',
    DateTime Function()? now,
  }) : stateStore = stateStore ?? SyncStateStore(vault.store),
       _now = now ?? DateTime.now {
    if (rootPrefix.isNotEmpty && !rootPrefix.endsWith('/')) {
      throw ArgumentError.value(rootPrefix, 'rootPrefix', 'must end with /');
    }
    StorageKeys.checkPrefix(rootPrefix);
  }

  final Vault vault;
  final StorageBackend backend;
  final SyncStateStore stateStore;
  final int maxAttempts;

  /// A folder in the bucket to keep vaults under, such as `devvault/`;
  /// empty for the bucket root.
  final String rootPrefix;
  final DateTime Function() _now;

  static const _header = VaultHeader.fileName;
  static const _recordTypes = Vault.recordTypes;

  String get _prefix => '$rootPrefix${vault.vaultId}/';

  Future<SyncReport> sync() async {
    final report = SyncReport();
    final state = await stateStore.load();
    for (var attempt = 1; ; attempt++) {
      report.attempts = attempt;
      try {
        await _pull(state, report);
        await _push(state, report);
        state
          ..dirty.clear()
          ..lastSync = _now();
        await stateStore.save(state);
        return report;
      } on PreconditionFailed {
        // Another device wrote first: pull its change, merge, try again.
        await stateStore.save(state);
        if (attempt >= maxAttempts) rethrow;
      }
    }
  }

  /// Local keys with changes not pushed yet, for a "pending" count.
  Future<Set<String>> pendingChanges() async {
    final state = await stateStore.load();
    return {for (final (key, _) in await _localChanges(state)) key};
  }

  // ------------------------------------------------------- key adoption

  /// Takes the vault key the bucket has now, after [RemoteKeyChanged]: the
  /// key was rotated on another device (SPEC §9), or `vault.json` was
  /// replaced. [password] must open the remote `vault.json`, which a
  /// tampered one can't (SPEC §4.4); otherwise [WrongPassword] and nothing
  /// changes.
  ///
  /// Edits made here and not synced yet are opened with the old key first,
  /// then the local copy is replaced by the bucket's, and the edits are
  /// merged on top (ADR-0004) and pushed: nothing written here is lost.
  /// Returns the vault reopened under the new key; this engine's vault is
  /// locked. Sync on with a new engine for it.
  ///
  /// The new copy is built in `<vault>.adopting/` and only swapped in once
  /// it's complete, so a failure part way leaves this device as it was.
  Future<KeyAdoption> adoptRemoteKey(
    String password, {
    required VaultCrypto crypto,
  }) async {
    final body = await backend.get('$_prefix$_header');
    if (body == null) throw const RemoteKeyChanged();
    final remoteHeader = VaultHeader.parse(String.fromCharCodes(body.bytes));
    if (remoteHeader.vaultId != vault.vaultId) {
      throw const VaultKeyMismatch();
    }
    final newKey = await VaultKeys.unlockWithPassword(
      crypto,
      remoteHeader,
      password,
    );

    // 1. Rescue what changed here, while the old key still opens it.
    final state = await stateStore.load();
    final rescued = <_Rescued>[];
    for (final key in await pendingChanges()) {
      final slot = _slotOf(key);
      if (slot == null || slot.$1 == ObjectType.blob) continue;
      final (type, id) = slot;
      final bytes = await vault.store.read(type, id);
      if (bytes == null) continue; // a deletion: its tombstone is rescued
      final local = vault.openRecord(type, id, bytes);
      if (local == null) continue;
      // For a deletion, the base is the item as it was last synced: the
      // deletion only wins if nobody edited it since (ADR-0004).
      final (baseType, baseKey) = local is Tombstone
          ? (ObjectType.item, '${ObjectType.item.folder}/$id.enc')
          : (type, key);
      final baseBytes = await stateStore.base(baseKey);
      final base = baseBytes == null
          ? null
          : vault.openRecord(baseType, id, baseBytes);
      final files = <String, Uint8List>{};
      if (local is Item) {
        for (final a in local.attachments) {
          try {
            files[a.blobId] = await vault.readAttachment(a);
          } on AttachmentCorrupt {
            // Not here: the rotation carried it over, or it's lost anyway.
          }
        }
      }
      rescued.add(_Rescued(local, base, files));
    }
    final uploaded = {
      for (final key in state.remote.keys)
        if (_slotOf(key) case (ObjectType.blob, final id)) id,
    };

    // 2. Build the vault as the bucket has it, next to this one, and put
    //    the edits back on top. Until the swap below, a failure (offline,
    //    a crash) leaves this device's vault as it was.
    final store = vault.store;
    final staging = VaultStore(Directory('${store.root.path}.adopting'));
    final stagingState = SyncStateStore(staging);
    for (final dir in [staging.root, stagingState.root]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
    await staging.open();
    await staging.writeHeader(remoteHeader);
    final building = await Vault.unlockWithKey(
      crypto: crypto,
      store: staging,
      vaultKey: newKey,
      deviceId: vault.deviceId,
      now: _now,
    );
    var conflicts = 0;
    try {
      final engine = SyncEngine(
        vault: building,
        backend: backend,
        stateStore: stagingState,
        rootPrefix: rootPrefix,
        maxAttempts: maxAttempts,
        now: _now,
      );
      await engine.sync();
      for (final r in rescued) {
        conflicts += await engine._reapply(r, uploaded);
      }
      if (rescued.isNotEmpty) await engine.sync();
    } catch (_) {
      building.lock();
      rethrow;
    }

    // 3. Swap it in: the old copy (old key) goes, the new one takes its
    //    place, and the vault reopens there.
    final keyBytes = building.withVaultKeyBytes(Uint8List.fromList);
    building.lock();
    vault.lock();
    final retired = Directory('${store.root.path}.retired');
    if (retired.existsSync()) await retired.delete(recursive: true);
    await store.root.rename(retired.path);
    await staging.root.rename(store.root.path);
    await stateStore.clear();
    await stagingState.root.rename(stateStore.root.path);
    await retired.delete(recursive: true);
    final adopted = await Vault.unlockWithKey(
      crypto: crypto,
      store: VaultStore(store.root),
      vaultKey: crypto.keyFromBytes(keyBytes),
      deviceId: building.deviceId,
      now: _now,
    );
    keyBytes.fillRange(0, keyBytes.length, 0);
    return KeyAdoption(adopted, rescued: rescued.length, conflicts: conflicts);
  }

  /// Merges one rescued record into the adopted vault. Returns 1 when the
  /// merge kept a conflict.
  Future<int> _reapply(_Rescued r, Set<String> uploaded) async {
    Future<Item> moveFiles(Item item) async => item.copyWith(
      attachments: [
        for (final a in item.attachments) await _moveFile(a, r.files, uploaded),
      ],
    );

    switch (r.local) {
      case final Item local:
        final mine = await moveFiles(local);
        final base = r.base is Item ? await moveFiles(r.base! as Item) : null;
        final theirs = await vault.readItem(local.id);
        if (theirs != null) {
          final result = mergeItems(base: base, local: mine, remote: theirs);
          await vault.putItem(result.value);
          return result.conflicted ? 1 : 0;
        }
        final tombstone = await _localTombstone(local.id);
        final kept = tombstone == null
            ? mine
            : resolveDeletion(base: base, live: mine, tombstone: tombstone);
        if (kept == null) return 0;
        await vault.store.delete(ObjectType.tombstone, local.id);
        await vault.putItem(kept);
        return 0;
      case final AppRecord local:
        final theirs = (await vault.loadAll()).apps[local.id];
        await vault.putApp(
          theirs == null
              ? local
              : mergeApps(
                  base: r.base is AppRecord ? r.base! as AppRecord : null,
                  local: local,
                  remote: theirs,
                ),
        );
        return 0;
      case final OrganizationRecord local:
        final theirs = (await vault.loadAll()).organizations[local.id];
        await vault.putOrganization(
          theirs == null
              ? local
              : mergeOrganizations(
                  base: r.base is OrganizationRecord
                      ? r.base! as OrganizationRecord
                      : null,
                  local: local,
                  remote: theirs,
                ),
        );
        return 0;
      case final Tombstone local:
        final live = await vault.readItem(local.id);
        if (live != null && local.kind == TombstoneKind.item) {
          // Edited there since: the edit wins, the deletion is recorded.
          final kept = resolveDeletion(
            base: r.base is Item ? r.base! as Item : null,
            live: live,
            tombstone: local,
          );
          if (kept != null) {
            await vault.putItem(kept);
            return 0;
          }
        }
        await vault.delete(local.id, local.kind);
        return 0;
    }
    return 0;
  }

  /// Where [a]'s file lives under the new key: the id the rotation gave it
  /// if it was in the bucket, a new blob if it only existed here.
  Future<Attachment> _moveFile(
    Attachment a,
    Map<String, Uint8List> files,
    Set<String> uploaded,
  ) async {
    final rotated = vault.rotatedBlobId(a.blobId);
    final bytes = files[a.blobId];
    if (uploaded.contains(a.blobId) || bytes == null) {
      return Attachment(
        blobId: rotated,
        filename: a.filename,
        mime: a.mime,
        size: a.size,
        sha256: a.sha256,
        unknownFields: a.unknownFields,
      );
    }
    return vault.addAttachment(bytes, filename: a.filename, mime: a.mime);
  }

  Future<Tombstone?> _localTombstone(String id) async {
    final bytes = await vault.store.read(ObjectType.tombstone, id);
    if (bytes == null) return null;
    final record = vault.openRecord(ObjectType.tombstone, id, bytes);
    return record is Tombstone ? record : null;
  }

  // ---------------------------------------------------------------- pull

  Future<void> _pull(SyncState state, SyncReport report) async {
    final remote = {
      for (final o in await backend.list(_prefix))
        o.key.substring(_prefix.length): o,
    };

    await _pullHeader(state, remote[_header], report);

    for (final MapEntry(key: key, value: object) in remote.entries) {
      if (key == _header) continue;
      final slot = _slotOf(key);
      if (slot == null) continue; // not ours: ignore
      if (state.remote[key]?.etag == object.etag) continue;
      if (slot.$1 == ObjectType.blob) {
        await _pullBlob(state, key, slot.$2, object, report);
      } else {
        await _pullRecord(state, key, slot.$1, slot.$2, object, report);
      }
    }

    // Gone remotely since the last sync.
    for (final key in state.remote.keys.toList()) {
      if (remote.containsKey(key) || key == _header) continue;
      final slot = _slotOf(key);
      if (slot == null) {
        state.remote.remove(key);
        continue;
      }
      if (slot.$1 == ObjectType.blob) {
        // Collected by blob GC on another device (nothing referenced it
        // for 30 days): drop it here too rather than upload it again.
        await vault.store.delete(ObjectType.blob, slot.$2);
        state.remote.remove(key);
        continue;
      }
      final local = await vault.store.read(slot.$1, slot.$2);
      final base = await stateStore.base(key);
      if (local != null && !_same(local, base)) {
        // Changed here meanwhile: keep it; it's pushed as new.
        state.remote.remove(key);
        await stateStore.deleteBase(key);
        continue;
      }
      await vault.store.delete(slot.$1, slot.$2);
      state.remote.remove(key);
      await stateStore.deleteBase(key);
      report.pulled++;
    }
  }

  Future<void> _pullHeader(
    SyncState state,
    RemoteObject? object,
    SyncReport report,
  ) async {
    if (object == null || state.remote[_header]?.etag == object.etag) return;
    final body = await backend.get('$_prefix$_header');
    if (body == null) return;
    final local = await _readHeaderBytes();
    final base = await stateStore.base(_header);
    if (!_same(body.bytes, local)) {
      final remoteHeader = VaultHeader.parse(String.fromCharCodes(body.bytes));
      if (remoteHeader.vaultId == vault.vaultId &&
          remoteHeader.vkId != vault.header.vkId) {
        // Rotated on another device, or replaced: nothing is touched until
        // the user adopts it with the master password.
        throw const RemoteKeyChanged();
      }
      if (local != null && base != null && !_same(local, base)) {
        report.notices.add(
          'The master password was also changed on another device. That '
          'change is kept; use the password set there.',
        );
      }
      await vault.adoptHeader(remoteHeader);
      report.pulled++;
    }
    // Base is what's on disk now, so re-serialising never looks like a change.
    await stateStore.putBase(_header, (await _readHeaderBytes())!);
    state.remote[_header] = SyncedObject(etag: object.etag);
  }

  Future<void> _pullBlob(
    SyncState state,
    String key,
    String id,
    RemoteObject object,
    SyncReport report,
  ) async {
    if (await vault.store.read(ObjectType.blob, id) == null) {
      final body = await backend.get('$_prefix$key');
      if (body == null) return;
      await vault.store.write(ObjectType.blob, id, body.bytes);
      report.pulled++;
    }
    state.remote[key] = SyncedObject(etag: object.etag);
  }

  Future<void> _pullRecord(
    SyncState state,
    String key,
    ObjectType type,
    String id,
    RemoteObject object,
    SyncReport report,
  ) async {
    final body = await backend.get('$_prefix$key');
    if (body == null) return; // deleted while listing; next round sees it
    final remote = vault.openRecord(type, id, body.bytes);
    if (remote == null) {
      report.unreadable++;
      return;
    }
    vault.observe(remote.rev);

    final localBytes = await vault.store.read(type, id);
    final baseBytes = await stateStore.base(key);
    final changedHere =
        (localBytes != null && !_same(localBytes, baseBytes)) ||
        (localBytes == null && baseBytes != null);

    if (!changedHere || _same(localBytes, body.bytes)) {
      await vault.store.write(type, id, body.bytes);
      report.pulled++;
      if (remote is Tombstone) await _applyTombstone(state, remote, report);
    } else {
      await _merge(state, type, id, localBytes, baseBytes, remote, report);
    }
    await stateStore.putBase(key, body.bytes);
    state.remote[key] = SyncedObject(
      etag: body.etag,
      rev: remote.rev.toString(),
    );
  }

  Future<void> _merge(
    SyncState state,
    ObjectType type,
    String id,
    Uint8List? localBytes,
    Uint8List? baseBytes,
    SyncedRecord remote,
    SyncReport report,
  ) async {
    final local = localBytes == null
        ? null
        : vault.openRecord(type, id, localBytes);
    final base = baseBytes == null
        ? null
        : vault.openRecord(type, id, baseBytes);
    report.merged++;
    switch (remote) {
      case Item():
        if (local is Item) {
          final result = mergeItems(
            base: base is Item ? base : null,
            local: local,
            remote: remote,
          );
          if (result.conflicted) report.conflicts++;
          await vault.putItem(result.value);
        } else {
          // Deleted here, edited there: the edit wins (ADR-0004).
          final tombstoneBytes = await vault.store.read(
            ObjectType.tombstone,
            id,
          );
          final tombstone = tombstoneBytes == null
              ? null
              : vault.openRecord(ObjectType.tombstone, id, tombstoneBytes);
          final kept = tombstone is Tombstone
              ? resolveDeletion(
                  base: base is Item ? base : null,
                  live: remote,
                  tombstone: tombstone,
                )
              : remote;
          if (kept != null) {
            await vault.store.delete(ObjectType.tombstone, id);
            await vault.putItem(kept);
          }
        }
      case AppRecord():
        if (local is AppRecord) {
          await vault.putApp(
            mergeApps(
              base: base is AppRecord ? base : null,
              local: local,
              remote: remote,
            ),
          );
        } else {
          await vault.putApp(remote);
        }
      case OrganizationRecord():
        await vault.putOrganization(
          local is OrganizationRecord
              ? mergeOrganizations(
                  base: base is OrganizationRecord ? base : null,
                  local: local,
                  remote: remote,
                )
              : remote,
        );
      case Tombstone():
        // Deleted on both sides: either tombstone says the same.
        await vault.store.write(
          ObjectType.tombstone,
          id,
          (await backend.get('$_prefix${ObjectType.tombstone.folder}/$id.enc'))!
              .bytes,
        );
        await _applyTombstone(state, remote, report);
    }
  }

  /// A tombstone arrived: remove the record it deletes, unless it was
  /// edited here since it last synced (then it stays, with the deletion
  /// recorded, and the tombstone is withdrawn).
  Future<void> _applyTombstone(
    SyncState state,
    Tombstone tombstone,
    SyncReport report,
  ) async {
    final type = tombstone.kind.recordType;
    final key = '${type.folder}/${tombstone.id}.enc';
    final localBytes = await vault.store.read(type, tombstone.id);
    if (localBytes == null) return;
    final baseBytes = await stateStore.base(key);
    if (type == ObjectType.item && !_same(localBytes, baseBytes)) {
      final live = vault.openRecord(type, tombstone.id, localBytes);
      final base = baseBytes == null
          ? null
          : vault.openRecord(type, tombstone.id, baseBytes);
      if (live is Item) {
        final kept = resolveDeletion(
          base: base is Item ? base : null,
          live: live,
          tombstone: tombstone,
        );
        if (kept != null) {
          await vault.putItem(kept);
          // Withdraw the tombstone: deleted locally, so pushed as a delete.
          await vault.store.delete(ObjectType.tombstone, tombstone.id);
          report.conflicts++;
          return;
        }
      }
    }
    await vault.store.delete(type, tombstone.id);
  }

  // ---------------------------------------------------------------- push

  Future<void> _push(SyncState state, SyncReport report) async {
    final changes = await _localChanges(state);
    int order((String, Uint8List?) change) {
      final (key, bytes) = change;
      if (key == _header) return 0;
      if (bytes == null) return 5; // deletions last
      return switch (_slotOf(key)?.$1) {
        ObjectType.blob => 1,
        ObjectType.item || ObjectType.app || ObjectType.organization => 2,
        _ => 3,
      };
    }

    changes.sort((a, b) => order(a).compareTo(order(b)));
    for (final (key, bytes) in changes) {
      final remoteKey = '$_prefix$key';
      final known = state.remote[key];
      if (bytes == null) {
        await backend.delete(remoteKey, ifMatch: known?.etag);
        state.remote.remove(key);
        await stateStore.deleteBase(key);
      } else {
        final String etag;
        try {
          etag = await backend.put(
            remoteKey,
            bytes,
            condition: known == null
                ? const WriteCondition.ifAbsent()
                : WriteCondition.ifMatch(known.etag),
          );
        } on PreconditionFailed {
          if (_slotOf(key)?.$1 == ObjectType.blob) {
            // Blobs are immutable under a fresh id: already uploaded.
            final existing = await backend.get(remoteKey);
            if (existing != null) {
              state.remote[key] = SyncedObject(etag: existing.etag);
              continue;
            }
          }
          rethrow;
        }
        state.remote[key] = SyncedObject(etag: etag);
        if (_slotOf(key)?.$1 != ObjectType.blob) {
          await stateStore.putBase(key, bytes);
        }
      }
      report.pushed++;
      await stateStore.save(state);
    }
  }

  /// Every local change since the last sync: (key, new bytes) for writes,
  /// (key, null) for deletions.
  Future<List<(String, Uint8List?)>> _localChanges(SyncState state) async {
    final changes = <(String, Uint8List?)>[];
    final header = await _readHeaderBytes();
    if (header != null && !_same(header, await stateStore.base(_header))) {
      changes.add((_header, header));
    }
    final present = <String>{};
    for (final type in [..._recordTypes, ObjectType.blob]) {
      for (final id in await vault.store.list(type)) {
        final key = '${type.folder}/$id.enc';
        if (type == ObjectType.blob && state.remote.containsKey(key)) {
          present.add(key);
          continue;
        }
        // Gone since the listing (a delete or blob GC racing this sync):
        // treat it as absent, as the next listing would.
        final bytes = await vault.store.read(type, id);
        if (bytes == null) continue;
        present.add(key);
        if (type == ObjectType.blob) {
          changes.add((key, bytes));
          continue;
        }
        if (!_same(bytes, await stateStore.base(key))) {
          changes.add((key, bytes));
        }
      }
    }
    for (final key in state.remote.keys) {
      if (key == _header || present.contains(key)) continue;
      if (_slotOf(key)?.$1 == ObjectType.blob) continue; // GC's job (P2-12)
      changes.add((key, null));
    }
    return changes;
  }

  // ---------------------------------------------------------------- helpers

  Future<Uint8List?> _readHeaderBytes() async {
    final file = File('${vault.store.root.path}/$_header');
    return file.existsSync() ? file.readAsBytes() : null;
  }

  /// `items/<id>.enc` → (item, id); null for anything else.
  static (ObjectType, String)? _slotOf(String key) {
    final parts = key.split('/');
    if (parts.length != 2 || !parts[1].endsWith('.enc')) return null;
    final id = parts[1].substring(0, parts[1].length - 4);
    if (!isCanonicalUuid(id)) return null;
    for (final type in ObjectType.values) {
      if (type.folder == parts[0]) return (type, id);
    }
    return null;
  }

  static bool _same(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The bucket's `vault.json` has another vault key than this device
/// (SPEC §4.4): rotated on another device, or replaced. Sync stops before
/// touching anything; [SyncEngine.adoptRemoteKey] takes the new key once
/// the user enters the master password.
class RemoteKeyChanged extends VaultKeyMismatch {
  const RemoteKeyChanged();

  @override
  String toString() => 'RemoteKeyChanged';
}

/// The outcome of [SyncEngine.adoptRemoteKey].
class KeyAdoption {
  const KeyAdoption(
    this.vault, {
    required this.rescued,
    required this.conflicts,
  });

  /// The vault, open under the new key.
  final Vault vault;

  /// Records changed here before the switch and merged back on top.
  final int rescued;

  /// Of those, how many kept a conflict to resolve.
  final int conflicts;
}

/// A record changed here, opened with the old key, with its last synced
/// version and the bytes of its files.
class _Rescued {
  _Rescued(this.local, this.base, this.files);

  final SyncedRecord local;
  final SyncedRecord? base;
  final Map<String, Uint8List> files;
}
