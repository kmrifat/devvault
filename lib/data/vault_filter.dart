import 'package:vault_core/vault_core.dart';

import '../app/routes.dart';
import '../core/expiry.dart';

/// A special list the sidebar can open instead of a tree filter.
enum VaultView {
  /// Items holding a sync conflict to resolve (design frame D05).
  conflicts,

  /// Objects that couldn't be decrypted or read (SPEC §6.2).
  quarantine;

  static VaultView? parse(String? name) =>
      values.where((v) => v.name == name).firstOrNull;
}

/// The list's tabs, which narrow whatever the sidebar selected.
enum VaultKind {
  all('All'),
  expiring('Expiring'),
  files('Files'),
  secrets('Secrets');

  const VaultKind(this.label);

  final String label;

  static VaultKind parse(String? name) =>
      values.where((k) => k.name == name).firstOrNull ?? all;

  /// Whether [item] belongs under this tab at [now]: expiring includes the
  /// expired, files are items with an attachment, secrets the rest.
  bool includes(Item item, DateTime now) => switch (this) {
    all => true,
    expiring => switch (ExpiryState.of(item, now)) {
      ExpiryState.soon || ExpiryState.expired => true,
      _ => false,
    },
    files => item.attachments.isNotEmpty,
    secrets => item.attachments.isEmpty,
  };
}

/// What the vault list shows, read from and written to the `/vault` query
/// (`?org=…&app=…&platform=…&env=…&tag=…&view=…&kind=…&q=…`), so every
/// selection is a link that survives a reload and works with back and
/// forward.
///
/// [org], [app], [platform] and [env] take [none] for "items without one",
/// which is how the sidebar tree's "Personal", "No app" and "Other" groups
/// link. [org] keeps the items of that organization's apps; [none] keeps
/// the items of apps without an organization (not items without an app).
class VaultFilter {
  const VaultFilter({
    this.org,
    this.app,
    this.platform,
    this.env,
    this.tag,
    this.view,
    this.kind = VaultKind.all,
    this.q,
  });

  factory VaultFilter.fromUri(Uri uri) {
    String? param(String name) {
      final value = uri.queryParameters[name];
      return value == null || value.isEmpty ? null : value;
    }

    return VaultFilter(
      org: param('org'),
      app: param('app'),
      platform: param('platform'),
      env: param('env'),
      tag: param('tag'),
      view: VaultView.parse(param('view')),
      kind: VaultKind.parse(param('kind')),
      q: param('q'),
    );
  }

  /// The query value for "items without an app, platform or environment".
  static const none = 'none';

  final String? org;
  final String? app;
  final String? platform;
  final String? env;
  final String? tag;
  final VaultView? view;
  final VaultKind kind;
  final String? q;

  /// The sidebar selected nothing: "All items". The list's [kind] tab and
  /// the search don't count.
  bool get isAll =>
      org == null &&
      app == null &&
      platform == null &&
      env == null &&
      tag == null &&
      view == null;

  /// The `/vault` link for this filter, with [item] selected.
  String location({String? item}) => Routes.vault(
    item: item,
    org: org,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
    view: view?.name,
    kind: kind == VaultKind.all ? null : kind.name,
    q: q,
  );

  /// This filter with a different search; an empty [query] clears it.
  VaultFilter withQuery(String? query) => VaultFilter(
    org: org,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
    view: view,
    kind: kind,
    q: query == null || query.trim().isEmpty ? null : query,
  );

  /// This filter on a different tab.
  VaultFilter withKind(VaultKind kind) => VaultFilter(
    org: org,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
    view: view,
    kind: kind,
    q: q,
  );

  /// The items of [index] the sidebar selection and search show, sorted by
  /// title, before the [kind] tab narrows them ([VaultKind.includes]).
  /// Quarantined objects aren't items, so [VaultView.quarantine] shows none.
  List<Item> apply(VaultIndex index) {
    if (view == VaultView.quarantine) return const [];
    final withoutApp = app == none;
    return [
      for (final item in index.filter(
        appId: withoutApp ? null : app,
        withoutApp: withoutApp,
        organization: org == none ? null : org,
        personal: org == none,
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
      other.org == org &&
      other.app == app &&
      other.platform == platform &&
      other.env == env &&
      other.tag == tag &&
      other.view == view &&
      other.kind == kind &&
      other.q == q;

  @override
  int get hashCode => Object.hash(org, app, platform, env, tag, view, kind, q);

  @override
  String toString() => 'VaultFilter(${location()})';
}

/// A row of the sidebar's App › Platform › Environment tree as a place to
/// put an item: what dropping an item on the row changes. Values are as
/// in [VaultFilter]: an id or name, or [VaultFilter.none] for "without
/// one". A null [platform] or [env] leaves the item's own as it is, so
/// dropping on an app keeps the item's platform and environment.
class TreePlace {
  const TreePlace({required this.app, this.platform, this.env});

  /// Exactly where [item] is now, to put it back.
  TreePlace.of(Item item)
    : app = item.appId ?? VaultFilter.none,
      platform = item.platform ?? VaultFilter.none,
      env = item.environment ?? VaultFilter.none;

  final String app;
  final String? platform;
  final String? env;

  /// [item] moved here; nothing else about it changes.
  Item applyTo(Item item) {
    String? value(String? v) => v == VaultFilter.none ? null : v;
    return item.copyWith(
      appId: value(app),
      clearApp: app == VaultFilter.none,
      platform: value(platform),
      clearPlatform: platform == VaultFilter.none,
      environment: value(env),
      clearEnvironment: env == VaultFilter.none,
    );
  }

  /// Whether [item] already sits here in [index]'s tree, where an item
  /// whose app is gone counts as "No app".
  bool holds(Item item, VaultIndex index) {
    final appKey = index.apps.containsKey(item.appId)
        ? item.appId!
        : VaultFilter.none;
    return app == appKey &&
        (platform == null || platform == (item.platform ?? VaultFilter.none)) &&
        (env == null || env == (item.environment ?? VaultFilter.none));
  }

  /// "Kitchenly › iOS › Staging", as far down as this place goes.
  String label(VaultIndex index) => [
    app == VaultFilter.none ? 'No app' : index.apps[app]?.name ?? 'Unknown app',
    if (platform case final p?)
      VaultLabels.platform(p == VaultFilter.none ? null : p),
    if (env case final e?)
      VaultLabels.environment(e == VaultFilter.none ? null : e),
  ].join(' \u203a ');
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
