import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../store/vault_store.dart';
import 'storage_backend.dart';
import 'storage_capabilities.dart';

/// What this device last saw of one remote object.
@immutable
class SyncedObject {
  const SyncedObject({required this.etag, this.rev});

  /// The remote etag when this device last read or wrote the object; the
  /// `If-Match` for its next update.
  final String etag;

  /// The record's `rev` at that point (items, apps and tombstones), for
  /// ordering without decrypting.
  final String? rev;

  Map<String, Object?> toJson() => {'etag': etag, 'rev': ?rev};

  factory SyncedObject.fromJson(Map<String, Object?> json) =>
      SyncedObject(etag: json['etag']! as String, rev: json['rev'] as String?);

  @override
  bool operator ==(Object other) =>
      other is SyncedObject && other.etag == etag && other.rev == rev;

  @override
  int get hashCode => Object.hash(etag, rev);
}

/// This device's sync bookkeeping for one vault. Keys are paths inside the
/// vault (`vault.json`, `items/<id>.enc`), the same as the store's layout.
class SyncState {
  SyncState({
    Map<String, SyncedObject>? remote,
    Set<String>? dirty,
    this.lastSync,
    this.capabilities,
    Map<String, DateTime>? unreferencedSince,
    this.lastBlobGc,
  }) : remote = remote ?? {},
       dirty = dirty ?? {},
       unreferencedSince = unreferencedSince ?? {};

  static const formatVersion = 1;

  /// Every object as of the last successful sync.
  final Map<String, SyncedObject> remote;

  /// Local changes not pushed yet.
  final Set<String> dirty;

  DateTime? lastSync;

  /// What the store enforces, from the last connection test.
  StorageCapabilities? capabilities;

  /// Blob id → when this device first saw it referenced by nothing. Blob
  /// GC deletes a blob only after it has stayed unreferenced long enough.
  final Map<String, DateTime> unreferencedSince;

  /// When blob GC last ran here.
  DateTime? lastBlobGc;

  Map<String, Object?> toJson() => {
    'format': formatVersion,
    'remote': {
      for (final key in remote.keys.toList()..sort())
        key: remote[key]!.toJson(),
    },
    'dirty': dirty.toList()..sort(),
    'last_sync': lastSync?.toUtc().toIso8601String(),
    'capabilities': capabilities?.toJson(),
    'blob_unreferenced_since': {
      for (final id in unreferencedSince.keys.toList()..sort())
        id: unreferencedSince[id]!.toUtc().toIso8601String(),
    },
    'last_blob_gc': lastBlobGc?.toUtc().toIso8601String(),
  };

  factory SyncState.fromJson(Map<String, Object?> json) {
    if (json['format'] != formatVersion) {
      throw FormatException('Unknown sync state format ${json['format']}');
    }
    final remote = json['remote']! as Map<String, Object?>;
    final capabilities = json['capabilities'] as Map<String, Object?>?;
    final lastSync = json['last_sync'] as String?;
    final lastGc = json['last_blob_gc'] as String?;
    final unreferenced =
        (json['blob_unreferenced_since'] as Map<String, Object?>?) ?? const {};
    return SyncState(
      remote: {
        for (final MapEntry(:key, :value) in remote.entries)
          key: SyncedObject.fromJson(value! as Map<String, Object?>),
      },
      dirty: {...(json['dirty']! as List).cast<String>()},
      lastSync: lastSync == null ? null : DateTime.parse(lastSync),
      capabilities: capabilities == null
          ? null
          : StorageCapabilities.fromJson(capabilities),
      unreferencedSince: {
        for (final MapEntry(:key, :value) in unreferenced.entries)
          key: DateTime.parse(value! as String),
      },
      lastBlobGc: lastGc == null ? null : DateTime.parse(lastGc),
    );
  }
}

/// Keeps [SyncState] and the merge bases for a vault next to its folder:
/// `<vault_id>.sync/state.json` and `<vault_id>.sync/base/<key>`. Like the
/// rotation journal, it sits outside the `<vault_id>/` tree, so it is
/// never uploaded (SPEC §3).
///
/// A base is the object's ciphertext exactly as last synced. It is already
/// encrypted and bound to its slot, so it needs no extra protection, and
/// decrypting it with the vault key gives the common ancestor for a
/// three-way merge.
class SyncStateStore {
  SyncStateStore(VaultStore store)
    : root = Directory('${store.root.path}.sync');

  final Directory root;

  File get _stateFile => File('${root.path}/state.json');

  File _baseFile(String key) =>
      File('${root.path}/base/${StorageKeys.check(key)}');

  /// The saved state, or a fresh one before the first sync.
  Future<SyncState> load() async {
    if (!_stateFile.existsSync()) return SyncState();
    return SyncState.fromJson(
      json.decode(await _stateFile.readAsString()) as Map<String, Object?>,
    );
  }

  Future<void> save(SyncState state) => _write(
    _stateFile,
    utf8.encode(const JsonEncoder.withIndent('  ').convert(state.toJson())),
  );

  Future<Uint8List?> base(String key) async {
    final file = _baseFile(key);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  Future<void> putBase(String key, Uint8List ciphertext) =>
      _write(_baseFile(key), ciphertext);

  Future<void> deleteBase(String key) async {
    final file = _baseFile(key);
    if (file.existsSync()) await file.delete();
  }

  /// Forgets everything (sync turned off, or the vault left this device).
  Future<void> clear() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }

  static Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }
}
