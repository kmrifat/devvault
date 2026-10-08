import 'package:vault_core/vault_core.dart';

import '../../data/vault_filter.dart';

/// What the window calls the vault list for [filter]: a title ("Production")
/// and the path to it ("Acme Corp", "Kitchenly", "Android"); an app's
/// organization leads its path.
({String title, List<String> path}) vaultHeading(
  VaultFilter filter,
  Map<String, AppRecord> apps,
) {
  String appName(String id) =>
      id == VaultFilter.none ? 'No app' : apps[id]?.name ?? 'Unknown app';
  final app = filter.app;
  final platform = filter.platform;
  final path = <String>[
    if (filter.view == null && filter.tag == null && app != null) ...[
      ?apps[app]?.organization,
      if (platform != null) appName(app),
      if (platform != null && filter.env != null)
        VaultLabels.platform(platform == VaultFilter.none ? null : platform),
    ],
  ];
  final title = switch (filter) {
    VaultFilter(view: VaultView.conflicts) => 'Conflicts',
    VaultFilter(view: VaultView.quarantine) => 'Unreadable',
    VaultFilter(:final tag?) => '#$tag',
    VaultFilter(:final env?) => VaultLabels.environment(
      env == VaultFilter.none ? null : env,
    ),
    VaultFilter(platform: final platform?) => VaultLabels.platform(
      platform == VaultFilter.none ? null : platform,
    ),
    VaultFilter(:final app?) => appName(app),
    VaultFilter(:final org?) => org == VaultFilter.none ? 'Personal' : org,
    _ => 'All items',
  };
  return (title: title, path: path);
}
