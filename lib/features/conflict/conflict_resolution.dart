import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/format.dart';
import '../../data/vault_filter.dart';

/// Which version of a value to keep.
enum ConflictSide { mine, theirs }

/// One difference between this device's item and a version kept by a
/// conflict. [key] is `title`, `app`, …, or `field:<name>` for a field.
class ConflictRow {
  const ConflictRow({
    required this.key,
    required this.label,
    required this.mine,
    required this.theirs,
    this.secret = false,
  });

  final String key;
  final String label;

  /// Display text; null when that side has no value.
  final String? mine;
  final String? theirs;

  /// Shown masked until revealed.
  final bool secret;
}

/// Everything that differs between [mine] and [theirs], in the order the
/// item form shows it. Attachments never conflict (they're unioned).
List<ConflictRow> conflictRows(
  Item mine,
  Item theirs,
  Map<String, AppRecord> apps,
) {
  String? app(String? id) =>
      id == null ? null : apps[id]?.name ?? 'Unknown app';
  String? expiry(Item i) => i.expiresAt == null
      ? null
      : '${DateFormat.yMMMd().format(i.expiresAt!.toLocal())} '
            '(${i.expiresSource == ExpirySource.file ? 'from file' : 'set by you'})';
  String? tags(Item i) => i.tags.isEmpty ? null : i.tags.join(', ');

  String? platform(String? p) => p == null ? null : VaultLabels.platform(p);
  String? env(String? e) => e == null ? null : VaultLabels.environment(e);

  // Compared on the stored values; [show] only formats them.
  final rows = <ConflictRow>[
    for (final (key, label, m, t, show)
        in <(String, String, Object?, Object?, String? Function(Item))>[
          ('title', 'Name', mine.title, theirs.title, (i) => i.title),
          ('app', 'App', mine.appId, theirs.appId, (i) => app(i.appId)),
          (
            'platform',
            'Platform',
            mine.platform,
            theirs.platform,
            (i) => platform(i.platform),
          ),
          (
            'environment',
            'Environment',
            mine.environment,
            theirs.environment,
            (i) => env(i.environment),
          ),
          (
            'expiry',
            'Expires',
            (mine.expiresAt, mine.expiresSource),
            (theirs.expiresAt, theirs.expiresSource),
            expiry,
          ),
          ('tags', 'Tags', tags(mine), tags(theirs), tags),
          ('notes', 'Notes', mine.notes, theirs.notes, (i) => i.notes),
        ])
      if (m != t)
        ConflictRow(
          key: key,
          label: label,
          mine: show(mine),
          theirs: show(theirs),
        ),
  ];
  for (final name in {...mine.fields.keys, ...theirs.fields.keys}) {
    final m = mine.fields[name];
    final t = theirs.fields[name];
    if (m == t) continue;
    rows.add(
      ConflictRow(
        key: 'field:$name',
        label: Format.fieldLabel(name),
        mine: m?.value,
        theirs: t?.value,
        secret: (m?.secret ?? false) || (t?.secret ?? false),
      ),
    );
  }
  return rows;
}

/// [mine] with [theirs]' value for every row chosen as
/// [ConflictSide.theirs], and [theirs] removed from the conflict. Every row
/// of [conflictRows] must have a choice: nothing is resolved by default.
Item resolveConflict({
  required Item mine,
  required Item theirs,
  required Map<String, ConflictSide> choices,
}) {
  final rows = conflictRows(mine, theirs, const {});
  final missing = rows.where((r) => !choices.containsKey(r.key));
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'No choice for ${missing.map((r) => r.key).join(', ')}',
    );
  }
  bool take(String key) => choices[key] == ConflictSide.theirs;

  final fields = <String, ItemField>{...mine.fields};
  for (final name in {...mine.fields.keys, ...theirs.fields.keys}) {
    if (!take('field:$name')) continue;
    final t = theirs.fields[name];
    if (t == null) {
      fields.remove(name);
    } else {
      fields[name] = t;
    }
  }
  final source = take('expiry') ? theirs : mine;
  final resolved = Item(
    id: mine.id,
    typeName: mine.typeName,
    title: take('title') ? theirs.title : mine.title,
    appId: take('app') ? theirs.appId : mine.appId,
    platform: take('platform') ? theirs.platform : mine.platform,
    environment: take('environment') ? theirs.environment : mine.environment,
    tags: take('tags') ? theirs.tags : mine.tags,
    fields: fields,
    attachments: mine.attachments,
    expiresAt: source.expiresAt,
    expiresSource: source.expiresSource,
    notes: take('notes') ? theirs.notes : mine.notes,
    createdAt: mine.createdAt,
    updatedAt: mine.updatedAt,
    rev: mine.rev,
    deviceId: mine.deviceId,
    schema: mine.schema,
    unknownFields: mine.unknownFields,
  );
  final conflict = Conflict.of(mine)..removeVersion(theirs.rev);
  return withConflict(resolved, conflict);
}

/// [mine] without [theirs] in its conflict: for "Keep both", where
/// [theirs] becomes an item of its own.
Item dropVersion(Item mine, Item theirs) =>
    withConflict(mine, Conflict.of(mine)..removeVersion(theirs.rev));

/// [mine] without any recorded deletion: the user keeps the item.
Item keepDespiteDeletion(Item mine) =>
    withConflict(mine, Conflict.of(mine)..clearDeletions());
