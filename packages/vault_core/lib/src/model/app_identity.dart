import 'package:meta/meta.dart';

import '../format/json_reader.dart';

/// What kind of software an app is (SPEC §6.2 `kind`). Optional and only
/// ever chosen by the user: nothing infers it from an app's identifiers or
/// files.
///
/// [wireName] is what the app JSON stores, so renaming a value never
/// changes the format.
enum AppKind {
  mobile('mobile', 'Mobile app'),
  web('web', 'Web app'),
  desktop('desktop', 'Desktop app'),
  backend('backend', 'Backend service'),
  cli('cli', 'CLI / tool'),
  library('library', 'Library'),
  other('other', 'Other');

  const AppKind(this.wireName, this.label);

  final String wireName;
  final String label;

  static final Map<String, AppKind> _byWireName = {
    for (final kind in values) kind.wireName: kind,
  };

  /// The kind for [wireName], or `null` for one this version doesn't know.
  static AppKind? fromWireName(String? wireName) => _byWireName[wireName];
}

/// The kinds of identifier an app carries (SPEC §6.2).
///
/// Bundle IDs and package names are stored in the record's original
/// `bundle_ids` / `package_names` arrays, so older clients keep reading
/// them; every other kind goes in `identifiers`.
enum IdentifierKind {
  bundleId('bundle_id', 'Bundle ID (Apple)'),
  packageName('package_name', 'Package name (Android)'),
  domain('domain', 'Domain'),
  url('url', 'URL'),
  repository('repository', 'Repository'),
  other('other', 'Other');

  const IdentifierKind(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Stored in their own legacy array rather than in `identifiers`.
  bool get isLegacy => this == bundleId || this == packageName;

  static final Map<String, IdentifierKind> _byWireName = {
    for (final kind in values) kind.wireName: kind,
  };

  /// The kind for [wireName], or `null` for one this version doesn't know.
  static IdentifierKind? fromWireName(String wireName) => _byWireName[wireName];
}

/// One identifier of an app: a bundle ID, a domain, a repository …
///
/// [kindName] is kept as stored, so a kind added by a newer version
/// survives a rewrite by this one.
@immutable
class AppIdentifier {
  AppIdentifier(
    this.kindName,
    this.value, {
    Map<String, Object?> unknownFields = const {},
  }) : unknownFields = Map.unmodifiable(unknownFields);

  /// An identifier of a kind this version knows.
  AppIdentifier.of(IdentifierKind kind, String value)
    : this(kind.wireName, value);

  final String kindName;
  final String value;
  final Map<String, Object?> unknownFields;

  /// The known kind, or `null` for a newer one.
  IdentifierKind? get kind => IdentifierKind.fromWireName(kindName);

  /// What the UI calls the kind: its label, or the stored name for a kind
  /// this version doesn't know.
  String get kindLabel => kind?.label ?? kindName;

  static const _known = {'kind', 'value'};

  factory AppIdentifier.fromJson(Object? json) {
    final r = JsonReader(json, 'app.identifiers[]');
    return AppIdentifier(
      r.string('kind'),
      r.string('value'),
      unknownFields: r.unknown(_known),
    );
  }

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'kind': kindName,
    'value': value,
  };

  @override
  bool operator ==(Object other) =>
      other is AppIdentifier &&
      other.kindName == kindName &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kindName, value);

  @override
  String toString() => 'AppIdentifier($kindName, $value)';
}
