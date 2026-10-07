import 'dart:io';
import 'dart:typed_data';

import '../format/envelope.dart';
import '../format/vault_header.dart';
import '../model/records.dart';
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
///    items and apps, tombstones, then deletions. Everything is conditional
///    (`If-None-Match: *` for new objects, `If-Match` the last seen etag
///    otherwise), so a device that lost a race gets [PreconditionFailed],
///    pulls again and merges. At most [maxAttempts] rounds.
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
  static const _recordTypes = [
    ObjectType.item,
    ObjectType.app,
    ObjectType.tombstone,
  ];

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
      if (slot == null || slot.$1 == ObjectType.blob) {
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
    final type = tombstone.kind == TombstoneKind.item
        ? ObjectType.item
        : ObjectType.app;
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
        ObjectType.item || ObjectType.app => 2,
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
        present.add(key);
        if (type == ObjectType.blob) {
          if (!state.remote.containsKey(key)) {
            changes.add((key, (await vault.store.read(type, id))!));
          }
          continue;
        }
        final bytes = (await vault.store.read(type, id))!;
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
