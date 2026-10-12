import 'package:vault_core/vault_core.dart';

import '../app/routes.dart';

/// What the phone's Search tab shows, read from and written to the
/// `/search` query (`?q=…&type=…&app=…&platform=…&env=…&tag=…`), so back
/// and forward keep it and a search is a link.
///
/// [q] is what was typed. The rest is a scope picked from Browse: one item
/// type (its wire name), app id, platform, environment or tag.
class SearchQuery {
  const SearchQuery({
    this.q,
    this.type,
    this.app,
    this.platform,
    this.env,
    this.tag,
  });

  factory SearchQuery.fromUri(Uri uri) {
    String? param(String name) {
      final value = uri.queryParameters[name];
      return value == null || value.trim().isEmpty ? null : value;
    }

    return SearchQuery(
      q: param('q'),
      type: param('type'),
      app: param('app'),
      platform: param('platform'),
      env: param('env'),
      tag: param('tag'),
    );
  }

  final String? q;
  final String? type;
  final String? app;
  final String? platform;
  final String? env;
  final String? tag;

  /// A scope from Browse is set.
  bool get isScoped =>
      type != null ||
      app != null ||
      platform != null ||
      env != null ||
      tag != null;

  /// Nothing typed and no scope: Search shows Browse.
  bool get isBrowse => q == null && !isScoped;

  String location() => Routes.search(
    q: q,
    type: type,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
  );

  /// The same scope with [query] typed; an empty one clears it.
  SearchQuery withQ(String? query) => SearchQuery(
    q: query == null || query.trim().isEmpty ? null : query,
    type: type,
    app: app,
    platform: platform,
    env: env,
    tag: tag,
  );

  /// The same typed text, without a scope.
  SearchQuery get unscoped => SearchQuery(q: q);

  /// The items that match, sorted by title like the vault list.
  List<Item> apply(VaultIndex index) => [
    for (final item in index.filter(
      appId: app,
      platform: platform,
      environment: env,
      tag: tag,
      query: q,
    ))
      if (type == null || item.typeName == type) item,
  ];
}
