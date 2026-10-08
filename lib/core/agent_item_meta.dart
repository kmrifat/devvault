import 'package:vault_core/vault_core.dart';

/// An item's metadata as the agent bridge sends it (PROTOCOL.md §4,
/// ItemMeta): exactly what the vault stores, with nothing defaulted or
/// inferred. Secret field values and notes are never part of it.
Map<String, Object?> agentItemMeta(Item item, AppRecord? app) => {
  'id': item.id,
  'title': item.title,
  'type': item.typeName,
  if (app != null) 'app': {'id': app.id, 'name': app.name},
  'platform': ?item.platform,
  'environment': ?item.environment,
  'tags': item.tags,
  'fields': [
    for (final MapEntry(key: name, value: field) in item.fields.entries)
      {
        'name': name,
        'secret': field.secret,
        'source': field.source.wireName,
        if (!field.secret) 'value': field.value,
      },
  ],
  'attachments': [
    for (final a in item.attachments)
      {'id': a.blobId, 'filename': a.filename, 'mime': a.mime, 'size': a.size},
  ],
  'has_notes': item.notes?.isNotEmpty ?? false,
  if (item.expiresAt case final expires?) ...{
    'expires_at': formatTimestamp(expires),
    'expires_source': item.expiresSource!.wireName,
  },
  'updated_at': formatTimestamp(item.updatedAt),
};

/// Where an item sits, for the approval sheet: app › platform ›
/// environment › title, leaving out what the item doesn't have.
String agentItemPath(Item item, AppRecord? app) =>
    [?app?.name, ?item.platform, ?item.environment, item.title].join(' › ');
