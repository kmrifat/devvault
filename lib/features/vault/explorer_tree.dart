import 'package:vault_core/vault_core.dart';

/// The sidebar explorer's tree: Organization › App › Item, like a file
/// explorer. Every app shows, with or without items, and every
/// organization the vault names ([VaultIndex.organizations]).
///
/// Without any organization the tree is flat: [orgs] is empty and [apps]
/// holds every app. Otherwise [orgs] holds each organization A–Z, then
/// "Personal" (name null) when some app has none. Items without an app
/// are [noApp], shown last.
class ExplorerTree {
  ExplorerTree._({required this.orgs, required this.apps, required this.noApp});

  factory ExplorerTree.of(VaultIndex index) {
    final byApp = <String, List<Item>>{};
    final noApp = <Item>[];
    // index.all is in title order, so each list is too.
    for (final item in index.all) {
      if (index.apps.containsKey(item.appId)) {
        (byApp[item.appId!] ??= []).add(item);
      } else {
        noApp.add(item);
      }
    }
    final apps = [
      for (final app in index.apps.values)
        ExplorerApp._(app: app, items: byApp[app.id] ?? const []),
    ]..sort(_byName);
    final names = index.organizations;
    if (names.isEmpty) {
      return ExplorerTree._(orgs: const [], apps: apps, noApp: noApp);
    }
    final personal = [
      for (final node in apps)
        if (node.app.organization == null) node,
    ];
    return ExplorerTree._(
      orgs: [
        for (final name in names)
          ExplorerOrg._(
            name: name,
            apps: [
              for (final node in apps)
                if (node.app.organization == name) node,
            ],
          ),
        if (personal.isNotEmpty) ExplorerOrg._(name: null, apps: personal),
      ],
      apps: apps,
      noApp: noApp,
    );
  }

  final List<ExplorerOrg> orgs;

  /// Every app, A–Z.
  final List<ExplorerApp> apps;

  /// Items without an app (or whose app is gone), by title.
  final List<Item> noApp;

  bool get isEmpty => apps.isEmpty && noApp.isEmpty && orgs.isEmpty;

  static int _byName(ExplorerApp a, ExplorerApp b) {
    final byName = a.app.name.toLowerCase().compareTo(b.app.name.toLowerCase());
    return byName != 0 ? byName : a.app.id.compareTo(b.app.id);
  }
}

/// An organization and its apps; [name] is null for "Personal", the apps
/// without one. An organization may have no apps.
class ExplorerOrg {
  ExplorerOrg._({required this.name, required this.apps})
    : count = apps.fold(0, (sum, node) => sum + node.items.length);

  final String? name;
  final List<ExplorerApp> apps;

  /// Items across [apps].
  final int count;
}

/// An app and its items, by title.
class ExplorerApp {
  ExplorerApp._({required this.app, required this.items});

  final AppRecord app;
  final List<Item> items;
}
