import '../format/timestamps.dart';
import '../model/item_type.dart';
import '../model/records.dart';
import 'hlc.dart';

/// What a sync conflict kept: the versions that lost a field-level clash,
/// and deletions that lost to an edit (ADR-0004, SPEC §6.1 `conflict`).
///
/// Stored in [Item.conflict] as
/// `{"versions": [<item record>, …], "deletions": [{"rev", "device_id",
/// "deleted_at"}, …]}` and kept, on every device, until the user resolves
/// it (design frame D05). Conflicts accumulate: a second clash adds to the
/// list rather than replacing what's there, so no value is lost.
class Conflict {
  Conflict({List<Item>? versions, List<Map<String, Object?>>? deletions})
    : versions = versions ?? [],
      deletions = deletions ?? [];

  final List<Item> versions;
  final List<Map<String, Object?>> deletions;

  bool get isEmpty => versions.isEmpty && deletions.isEmpty;

  /// The conflict recorded on [item], or an empty one.
  static Conflict of(Item item) {
    final json = item.conflict;
    if (json == null) return Conflict();
    return Conflict(
      versions: [
        for (final v in (json['versions'] as List?) ?? const [])
          Item.fromJson(v),
      ],
      deletions: [
        for (final d in (json['deletions'] as List?) ?? const [])
          Map<String, Object?>.from(d as Map),
      ],
    );
  }

  /// Adds [version] (without its own conflict, which is merged
  /// separately) unless a version with the same `rev` is already kept.
  void addVersion(Item version) {
    if (versions.any((v) => v.rev == version.rev)) return;
    versions.add(_withoutConflict(version));
  }

  void addDeletion(Tombstone tombstone) {
    final rev = tombstone.rev.toString();
    if (deletions.any((d) => d['rev'] == rev)) return;
    deletions.add({
      'rev': rev,
      'device_id': tombstone.deviceId,
      'deleted_at': formatTimestamp(tombstone.deletedAt),
    });
  }

  /// Drops the kept version at [rev] once the user has chosen (D05).
  void removeVersion(Hlc rev) => versions.removeWhere((v) => v.rev == rev);

  /// Drops every recorded deletion once the user has chosen to keep or
  /// delete the item.
  void clearDeletions() => deletions.clear();

  void addAll(Conflict other) {
    other.versions.forEach(addVersion);
    for (final d in other.deletions) {
      if (!deletions.any((e) => e['rev'] == d['rev'])) deletions.add(d);
    }
  }

  Map<String, Object?>? toJson() {
    if (isEmpty) return null;
    final sorted = [...versions]..sort((a, b) => a.rev.compareTo(b.rev));
    final dels = [...deletions]
      ..sort((a, b) => (a['rev']! as String).compareTo(b['rev']! as String));
    return {
      'versions': [for (final v in sorted) v.toJson()],
      'deletions': dels,
    };
  }

  static Item _withoutConflict(Item item) =>
      item.conflict == null ? item : _rebuild(item, conflict: null);
}

/// The result of merging two versions of a record.
class MergeResult<T> {
  const MergeResult(this.value, {required this.conflicted});

  final T value;

  /// Both sides changed the same thing differently; the loser is kept in
  /// the item's [Conflict].
  final bool conflicted;
}

/// Merges two concurrent versions of an item against their common
/// ancestor [base] (null when there is none, e.g. joining a vault).
///
/// Field by field: a value only one side changed wins; the same change on
/// both sides is kept; different changes keep [local]'s value and record
/// [remote] in the conflict (ADR-0004). Tags merge as sets, attachments as a
/// union, and an edited field beats a deleted one. The result has the
/// later `rev` of the two; the caller saves it, which stamps a new one.
MergeResult<Item> mergeItems({
  Item? base,
  required Item local,
  required Item remote,
}) {
  if (local.rev == remote.rev) return MergeResult(local, conflicted: false);
  if (base != null && local.rev == base.rev) {
    return MergeResult(remote, conflicted: false);
  }
  if (base != null && remote.rev == base.rev) {
    return MergeResult(local, conflicted: false);
  }

  var clash = false;
  T pick<T>(T? b, T l, T r, {bool Function(T, T)? same}) {
    final eq = same ?? (T x, T y) => x == y;
    if (eq(l, r)) return l;
    if (base != null && b == l) return r;
    if (base != null && b == r) return l;
    if (base != null && b != null && eq(b, l)) return r;
    if (base != null && b != null && eq(b, r)) return l;
    clash = true;
    return l;
  }

  final expiry = pick<(DateTime?, ExpirySource?)>(
    base == null ? null : (base.expiresAt, base.expiresSource),
    (local.expiresAt, local.expiresSource),
    (remote.expiresAt, remote.expiresSource),
  );

  final fields = <String, ItemField>{};
  for (final key in {...local.fields.keys, ...remote.fields.keys}) {
    final l = local.fields[key];
    final r = remote.fields[key];
    final b = base?.fields[key];
    final ItemField? kept;
    if (l == r) {
      kept = l;
    } else if (base != null && l == b) {
      kept = r; // only remote changed (or removed) it
    } else if (base != null && r == b) {
      kept = l;
    } else if (l == null || r == null) {
      kept = l ?? r; // an edit beats a removal
    } else {
      clash = true;
      kept = l;
    }
    if (kept != null) fields[key] = kept;
  }

  final conflict = Conflict.of(local)..addAll(Conflict.of(remote));
  final merged = Item(
    id: local.id,
    typeName: pick(base?.typeName, local.typeName, remote.typeName),
    title: pick(base?.title, local.title, remote.title),
    appId: pick(base?.appId, local.appId, remote.appId),
    platform: pick(base?.platform, local.platform, remote.platform),
    environment: pick(base?.environment, local.environment, remote.environment),
    tags: _mergeSet(base?.tags, local.tags, remote.tags),
    fields: fields,
    attachments: [
      ...local.attachments,
      for (final a in remote.attachments)
        if (!local.attachments.any((l) => l.blobId == a.blobId)) a,
    ],
    expiresAt: expiry.$1,
    expiresSource: expiry.$2,
    notes: pick(base?.notes, local.notes, remote.notes),
    createdAt: local.createdAt.isBefore(remote.createdAt)
        ? local.createdAt
        : remote.createdAt,
    updatedAt: local.updatedAt.isAfter(remote.updatedAt)
        ? local.updatedAt
        : remote.updatedAt,
    rev: local.rev > remote.rev ? local.rev : remote.rev,
    deviceId: local.deviceId,
    schema: local.schema > remote.schema ? local.schema : remote.schema,
    unknownFields: {...remote.unknownFields, ...local.unknownFields},
  );
  if (clash) conflict.addVersion(remote);
  return MergeResult(
    _rebuild(merged, conflict: conflict.toJson()),
    conflicted: clash,
  );
}

/// An item on one side, its tombstone on the other. An edit beats a
/// delete: if [live] changed since [base] (or there is no base), it stays,
/// with the deletion recorded on its conflict. Otherwise the delete wins
/// and this returns null.
Item? resolveDeletion({
  Item? base,
  required Item live,
  required Tombstone tombstone,
}) {
  final editedSinceBase = base == null || live.rev != base.rev;
  if (!editedSinceBase) return null;
  final conflict = Conflict.of(live)..addDeletion(tombstone);
  return _rebuild(live, conflict: conflict.toJson());
}

/// Merges two concurrent versions of an app. Apps carry nothing secret and
/// have no conflict slot: on a clash the local value stays. Identifier
/// lists merge as sets.
AppRecord mergeApps({
  AppRecord? base,
  required AppRecord local,
  required AppRecord remote,
}) {
  if (local.rev == remote.rev) return local;
  if (base != null && local.rev == base.rev) return remote;
  if (base != null && remote.rev == base.rev) return local;
  T pick<T>(T? b, T l, T r) {
    if (l == r) return l;
    if (base != null && b == l) return r;
    return l;
  }

  return AppRecord(
    id: local.id,
    name: pick(base?.name, local.name, remote.name),
    bundleIds: _mergeSet(base?.bundleIds, local.bundleIds, remote.bundleIds),
    packageNames: _mergeSet(
      base?.packageNames,
      local.packageNames,
      remote.packageNames,
    ),
    iconBlobId: pick(base?.iconBlobId, local.iconBlobId, remote.iconBlobId),
    createdAt: local.createdAt.isBefore(remote.createdAt)
        ? local.createdAt
        : remote.createdAt,
    updatedAt: local.updatedAt.isAfter(remote.updatedAt)
        ? local.updatedAt
        : remote.updatedAt,
    rev: local.rev > remote.rev ? local.rev : remote.rev,
    deviceId: local.deviceId,
    schema: local.schema > remote.schema ? local.schema : remote.schema,
    unknownFields: {...remote.unknownFields, ...local.unknownFields},
  );
}

/// Three-way set merge: everything either side added, minus what either
/// side removed from [base]. Without a base, the union. Local order first.
List<String> _mergeSet(
  List<String>? base,
  List<String> local,
  List<String> remote,
) {
  final b = base?.toSet() ?? const <String>{};
  final removed = {
    ...b.difference(local.toSet()),
    ...b.difference(remote.toSet()),
  };
  return [
    ...{...local, ...remote}.where((v) => !removed.contains(v)),
  ];
}

/// [item] with its conflict replaced by [conflict] (empty clears it).
Item withConflict(Item item, Conflict conflict) =>
    _rebuild(item, conflict: conflict.toJson());

/// [item] with a different conflict (null clears it).
Item _rebuild(Item item, {required Map<String, Object?>? conflict}) => Item(
  id: item.id,
  typeName: item.typeName,
  title: item.title,
  appId: item.appId,
  platform: item.platform,
  environment: item.environment,
  tags: item.tags,
  fields: item.fields,
  attachments: item.attachments,
  expiresAt: item.expiresAt,
  expiresSource: item.expiresSource,
  notes: item.notes,
  createdAt: item.createdAt,
  updatedAt: item.updatedAt,
  rev: item.rev,
  deviceId: item.deviceId,
  conflict: conflict,
  schema: item.schema,
  unknownFields: item.unknownFields,
);
