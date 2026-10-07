import 'package:vault_core/vault_core.dart';

import '../app/routes.dart';

/// A special list the sidebar can open instead of a tree filter.
enum VaultView {
  /// Items holding a sync conflict to resolve (design frame D05).
  conflicts,

  /// Objects that couldn't be decrypted or read (SPEC §6.2).
  quarantine;

  static VaultView? parse(String? name) =>
      values.where((v) => v.name == name).firstOrNull;
}

/// What the vault list shows, read from and written to the `/vault` query
/// (`?app=…&platform=…&env=…&tag=…&view=…&q=…`), so every selection is a
/// link that survives a reload and works with back and forward.
///
/// [app], [platform] and [env] take [none] for "items without one", which
/// is how the sidebar tree's "No app" and "Other" groups link.
class VaultFilter {
  const VaultFilter({
    this.app,
    this.platform,
    this.env,
    this.tag,
    this.view,
    this.q,
  });

  factory VaultFilter.fromUri(Uri uri) {
    String? param(String name) {
      final value = uri.queryParameters[name];
      return value == null || value.isEmpty ? null : value;
    }

    return VaultFilter(
      app: param('app'),
      platform: param('platform'),
      env: param('env'),
      tag: param('tag'),
      view: VaultView.parse(param('view')),
      q: param('q'),
    );
  }

  /// The query value for "items without an app, platform or environment".
  static const none = 'none';

  final String? app;
  final String? platform;
  final String? env;
  final String? tag;
  final VaultView? view;
  final String? q;

  /// Nothing narrows the list: the sidebar's "All items".
  bool get isAll =>
      app == null &&
      platform == null &&
      env == null &&
      tag == null &&
      view == null;

  /// The `/vault` link for this filter, with [item] selected.
  String location({String? item}) => Routes.vault(
    item: item,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
    view: view?.name,
    q: q,
  );

  /// This filter with a different search; an empty [query] clears it.
  VaultFilter withQuery(String? query) => VaultFilter(
    app: app,
    platform: platform,
    env: env,
    tag: tag,
    view: view,
    q: query == null || query.trim().isEmpty ? null : query,
  );

  /// The items of [index] this filter shows, sorted by title. Quarantined
  /// objects aren't items, so [VaultView.quarantine] shows none.
  List<Item> apply(VaultIndex index) {
    if (view == VaultView.quarantine) return const [];
    final withoutApp = app == none;
    return [
      for (final item in index.filter(
        appId: withoutApp ? null : app,
        withoutApp: withoutApp,
        tag: tag,
        query: q,
      ))
        if (_matches(platform, item.platform) &&
            _matches(env, item.environment) &&
            (view != VaultView.conflicts || item.conflict != null))
          item,
    ];
  }

  static bool _matches(String? wanted, String? actual) =>
      wanted == null || (wanted == none ? actual == null : actual == wanted);

  @override
  bool operator ==(Object other) =>
      other is VaultFilter &&
      other.app == app &&
      other.platform == platform &&
      other.env == env &&
      other.tag == tag &&
      other.view == view &&
      other.q == q;

  @override
  int get hashCode => Object.hash(app, platform, env, tag, view, q);

  @override
  String toString() => 'VaultFilter(${location()})';
}

/// Display names for the free-form platform and environment strings
/// (SPEC §5: clients suggest `ios`, `android`, `macos`, `web`, `server` and
/// `production`, `staging`, `development`).
abstract final class VaultLabels {
  static String platform(String? platform) => switch (platform) {
    null => 'Other',
    'ios' => 'iOS',
    'android' => 'Android',
    'macos' => 'macOS',
    'web' => 'Web',
    'server' => 'Server',
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => _capitalize(platform),
  };

  static String environment(String? environment) =>
      environment == null ? 'No environment' : _capitalize(environment);

  static String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}
