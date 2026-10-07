import '../format/envelope.dart';
import '../vault/vault.dart';
import 'merge.dart';
import 'storage_backend.dart';
import 'sync_state.dart';

/// What one [BlobCollector.run] found and did.
class BlobGcReport {
  /// Blobs nothing references, still inside the grace period.
  final List<String> waiting = [];

  /// Blobs past the grace period: deleted, or would be in a dry run.
  final List<String> collected = [];

  bool dryRun = false;

  @override
  String toString() =>
      'BlobGcReport(${dryRun ? 'dry run, ' : ''}collected: ${collected.length}, '
      'waiting: ${waiting.length})';
}

/// Removes file blobs nothing uses any more (P2-12).
///
/// A blob is referenced by an item's attachments, or by a version kept in
/// an item's conflict. One that nothing references is deleted, locally and
/// in storage, only after it has stayed unreferenced on this device for
/// [grace] (30 days). That also covers a blob another device has uploaded
/// but whose item hasn't arrived yet, and a file of an item deleted
/// recently. A dry run reports without deleting or recording anything.
class BlobCollector {
  BlobCollector({
    required this.vault,
    required this.backend,
    SyncStateStore? stateStore,
    this.rootPrefix = '',
    this.grace = const Duration(days: 30),
    DateTime Function()? now,
  }) : stateStore = stateStore ?? SyncStateStore(vault.store),
       _now = now ?? DateTime.now;

  final Vault vault;
  final StorageBackend? backend;
  final SyncStateStore stateStore;
  final String rootPrefix;
  final Duration grace;
  final DateTime Function() _now;

  static const interval = Duration(days: 1);

  /// Whether a day has passed since the last run (or it never ran).
  Future<bool> isDue() async {
    final last = (await stateStore.load()).lastBlobGc;
    return last == null || _now().difference(last) >= interval;
  }

  Future<BlobGcReport> run({bool dryRun = false}) async {
    final report = BlobGcReport()..dryRun = dryRun;
    final now = _now();
    final state = await stateStore.load();

    final contents = await vault.loadAll();
    final referenced = <String>{
      for (final item in contents.items.values) ...[
        for (final a in item.attachments) a.blobId,
        for (final version in Conflict.of(item).versions)
          for (final a in version.attachments) a.blobId,
      ],
    };

    final prefix = '$rootPrefix${vault.vaultId}/${ObjectType.blob.folder}/';
    final remote = <String, RemoteObject>{
      if (backend case final backend?)
        for (final o in await backend.list(prefix))
          if (o.key.endsWith('.enc'))
            o.key.substring(prefix.length, o.key.length - 4): o,
    };
    final all = {...await vault.store.list(ObjectType.blob), ...remote.keys};

    final unreferencedSince = Map.of(state.unreferencedSince)
      ..removeWhere((id, _) => referenced.contains(id) || !all.contains(id));
    for (final id in all) {
      if (referenced.contains(id)) continue;
      final since = unreferencedSince.putIfAbsent(id, () => now);
      if (now.difference(since) < grace) {
        report.waiting.add(id);
        continue;
      }
      report.collected.add(id);
      if (dryRun) continue;
      if (remote[id] case final object?) {
        await backend!.delete(object.key, ifMatch: object.etag);
      }
      await vault.store.delete(ObjectType.blob, id);
      state.remote.remove('${ObjectType.blob.folder}/$id.enc');
      unreferencedSince.remove(id);
    }

    if (!dryRun) {
      state.unreferencedSince
        ..clear()
        ..addAll(unreferencedSince);
      state.lastBlobGc = now;
      await stateStore.save(state);
    }
    report.waiting.sort();
    report.collected.sort();
    return report;
  }
}
