import '../format/envelope.dart';
import '../model/records.dart';
import '../vault/vault.dart';

/// The decrypted vault, indexed for the sidebar tree, tags, expiry and
/// search. Built in memory on unlock and dropped on lock.
///
/// Search only looks at metadata that isn't secret (SPEC §6.1): titles,
/// types, platforms, environments, tags, file names, non-secret field
/// values such as key IDs, team IDs and fingerprints, and the item's app:
/// its name, organization and every identifier (bundle IDs, package names,
/// domains, URLs, repositories …). Secret values and notes are never
/// searchable.
class VaultIndex {
  VaultIndex(VaultContents contents)
    : items = Map.unmodifiable(contents.items),
      apps = Map.unmodifiable(contents.apps),
      organizationRecords = Map.unmodifiable(contents.organizations),
      quarantined = List.unmodifiable(contents.quarantined) {
    for (final item in items.values) {
      _tokens[item.id] = _searchTextFor(item);
    }
  }

  final Map<String, Item> items;
  final Map<String, AppRecord> apps;

  /// Organization records by id. An organization can also exist only
  /// through its apps' `organization`; [organizations] has both.
  final Map<String, OrganizationRecord> organizationRecords;
  final List<ObjectSlot> quarantined;
  final Map<String, String> _tokens = {};

  /// Items sorted by title, then id for a stable order.
  late final List<Item> all = items.values.toList()..sort(_byTitle);

  /// Items that have an expiry, soonest first.
  late final List<Item> byExpiry =
      items.values.where((i) => i.expiresAt != null).toList()
        ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));

  /// Tag → number of items carrying it, sorted by tag.
  late final Map<String, int> tagCounts = () {
    final counts = <String, int>{};
    for (final item in items.values) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }();

  /// The sidebar tree: apps (by name, then items without an app), each
  /// with its platforms, each with its environments, with item counts.
  late final List<AppNode> tree = () {
    final byApp = <String?, List<Item>>{};
    for (final item in items.values) {
      final appId = apps.containsKey(item.appId) ? item.appId : null;
      (byApp[appId] ??= []).add(item);
    }
    final nodes = [
      for (final entry in byApp.entries)
        AppNode._(
          app: entry.key == null ? null : apps[entry.key],
          items: entry.value,
        ),
    ];
    nodes.sort((a, b) {
      if (a.app == null) return 1;
      if (b.app == null) return -1;
      return a.app!.name.toLowerCase().compareTo(b.app!.name.toLowerCase());
    });
    return nodes;
  }();

  /// Every organization, once each, A–Z ignoring case: the names of the
  /// organization records and every name the vault's apps give. What the
  /// app form suggests.
  late final List<String> organizations = {
    for (final org in organizationRecords.values) org.name,
    for (final app in apps.values) ?app.organization,
  }.toList()..sort(_byText);

  /// The [tree]'s apps grouped by organization: every organization in
  /// [organizations] A–Z, those without apps too, then the apps without
  /// one (organization null, "Personal") if there are any. The "No app"
  /// node isn't an app and is in no group. Empty when there is no
  /// organization: then the tree stays flat.
  late final List<OrgGroup> orgGroups = () {
    if (organizations.isEmpty) return const <OrgGroup>[];
    final byOrg = <String?, List<AppNode>>{};
    for (final node in tree) {
      if (node.app case final app?) {
        (byOrg[app.organization] ??= []).add(node);
      }
    }
    final records = <String, List<OrganizationRecord>>{};
    for (final org in organizationRecords.values) {
      (records[org.name] ??= []).add(org);
    }
    return [
      for (final org in organizations)
        OrgGroup._(
          organization: org,
          apps: byOrg[org] ?? const [],
          records: (records[org] ?? [])..sort((a, b) => a.id.compareTo(b.id)),
        ),
      if (byOrg[null] case final personal?)
        OrgGroup._(organization: null, apps: personal, records: const []),
    ];
  }();

  /// Items matching every filter that is set. [query] matches when every
  /// word in it appears in the item's searchable metadata. [organization]
  /// keeps the items of that organization's apps; [personal], the items of
  /// apps without one.
  List<Item> filter({
    String? appId,
    bool withoutApp = false,
    String? organization,
    bool personal = false,
    String? platform,
    String? environment,
    String? tag,
    String? query,
  }) {
    final words = _words(query ?? '');
    return [
      for (final item in all)
        if ((appId == null || item.appId == appId) &&
            (!withoutApp || !apps.containsKey(item.appId)) &&
            (organization == null ||
                apps[item.appId]?.organization == organization) &&
            (!personal ||
                (apps.containsKey(item.appId) &&
                    apps[item.appId]!.organization == null)) &&
            (platform == null || item.platform == platform) &&
            (environment == null || item.environment == environment) &&
            (tag == null || item.tags.contains(tag)) &&
            _matches(item.id, words))
          item,
    ];
  }

  bool _matches(String id, List<String> words) {
    if (words.isEmpty) return true;
    final text = _tokens[id]!;
    return words.every(text.contains);
  }

  static List<String> _words(String query) => [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) ...{word, _compact(word)},
  ];

  /// Fingerprints are written with colons; `5e8f16` should still find
  /// `5E:8F:16:…`.
  static String _compact(String text) => text.replaceAll(':', '');

  String _searchTextFor(Item item) {
    final app = apps[item.appId];
    final parts = <String>[
      item.title,
      item.type?.label ?? item.typeName,
      ?item.platform,
      ?item.environment,
      ...item.tags,
      if (app != null) ...[
        app.name,
        ?app.organization,
        for (final id in app.allIdentifiers) id.value,
      ],
      for (final attachment in item.attachments) attachment.filename,
      for (final field in item.fields.values)
        if (!field.secret) field.value,
    ];
    final text = parts.join('\n').toLowerCase();
    return '$text\n${_compact(text)}';
  }

  static int _byText(String a, String b) {
    final byLower = a.toLowerCase().compareTo(b.toLowerCase());
    return byLower != 0 ? byLower : a.compareTo(b);
  }

  static int _byTitle(Item a, Item b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }
}

/// An organization's apps in the sidebar tree; [organization] is null for
/// the apps without one ("Personal").
class OrgGroup {
  OrgGroup._({
    required this.organization,
    required List<AppNode> apps,
    required List<OrganizationRecord> records,
  }) : apps = List.unmodifiable(apps),
       records = List.unmodifiable(records),
       count = apps.fold(0, (sum, node) => sum + node.count);

  final String? organization;

  /// In the tree's order (by name). Empty for an organization without
  /// apps.
  final List<AppNode> apps;

  /// The organization records with exactly this name, by id: usually one,
  /// more when two devices created it at once. Empty when it exists only
  /// through its apps, and for "Personal".
  final List<OrganizationRecord> records;

  /// Items across [apps].
  final int count;
}

/// An app in the sidebar tree, or the "No app" group when [app] is null.
class AppNode {
  AppNode._({required this.app, required List<Item> items})
    : count = items.length,
      platforms = _group(items);

  final AppRecord? app;
  final int count;
  final List<PlatformNode> platforms;

  static List<PlatformNode> _group(List<Item> items) {
    final byPlatform = <String?, List<Item>>{};
    for (final item in items) {
      (byPlatform[item.platform] ??= []).add(item);
    }
    return [
      for (final entry in byPlatform.entries)
        PlatformNode._(platform: entry.key, items: entry.value),
    ]..sort((a, b) => _nullsLast(a.platform, b.platform));
  }
}

/// A platform under an app; [platform] is null for items without one.
class PlatformNode {
  PlatformNode._({required this.platform, required List<Item> items})
    : count = items.length,
      environments = _group(items);

  final String? platform;
  final int count;

  /// Environment → item count; the `null` key holds items without one.
  final Map<String?, int> environments;

  static Map<String?, int> _group(List<Item> items) {
    final counts = <String?, int>{};
    for (final item in items) {
      counts[item.environment] = (counts[item.environment] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => _nullsLast(a.key, b.key)),
    );
  }
}

int _nullsLast(String? a, String? b) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
