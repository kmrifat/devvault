import 'package:vault_core/vault_core.dart';

import 'format.dart';

/// Why an item turned up in a search: the field that holds one of the
/// query's words, and where in its value the word is. Search results show
/// it under the title, so a result never appears without a visible reason.
///
/// It looks at the same metadata as `VaultIndex.filter`, never at a secret
/// field.
class SearchMatch {
  const SearchMatch({
    required this.label,
    required this.value,
    this.start,
    this.end,
    this.mono = false,
  });

  /// The field's name: "Bundle ID", "File", "Key ID"…
  final String label;

  /// The field's whole value.
  final String value;

  /// The matched characters in [value], or null when the word only matches
  /// with the colons taken out (a fingerprint typed without them).
  final int? start;
  final int? end;

  /// IDs, file names and field values are shown in monospace.
  final bool mono;

  /// The first field of [item] (or of its [app]) that holds a word of
  /// [query] other than in the title. Null when every word is in the title,
  /// or the query is empty.
  static SearchMatch? of(Item item, AppRecord? app, String query) {
    final words = [
      for (final word in query.toLowerCase().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ];
    final title = item.title.toLowerCase();
    for (final word in words) {
      if (title.contains(word)) continue;
      final match = _find(item, app, word);
      if (match != null) return match;
    }
    return null;
  }

  static SearchMatch? _find(Item item, AppRecord? app, String word) {
    final candidates = <(String, String, bool)>[
      ('Type', item.type?.label ?? item.typeName, false),
      if (item.platform case final platform?) ('Platform', platform, false),
      if (item.environment case final env?) ('Environment', env, false),
      for (final tag in item.tags) ('Tag', '#$tag', false),
      if (app != null) ...[
        ('App', app.name, false),
        if (app.organization case final org?) ('Organization', org, false),
        for (final id in app.allIdentifiers)
          (_identifierLabel(id), id.value, true),
      ],
      for (final attachment in item.attachments)
        ('File', attachment.filename, true),
      for (final MapEntry(:key, value: field) in item.fields.entries)
        if (!field.secret) (Format.fieldLabel(key), field.value, true),
    ];
    for (final (label, value, mono) in candidates) {
      final lower = value.toLowerCase();
      final at = lower.indexOf(word);
      if (at >= 0) {
        return SearchMatch(
          label: label,
          value: value,
          start: at,
          end: at + word.length,
          mono: mono,
        );
      }
      // `5e8f16` finds `5E:8F:16:…`, as in the index.
      final compactWord = word.replaceAll(':', '');
      if (compactWord.isNotEmpty &&
          lower.replaceAll(':', '').contains(compactWord)) {
        return SearchMatch(label: label, value: value, mono: mono);
      }
    }
    return null;
  }

  /// "Bundle ID", "Package", "Domain"…: short enough for a result line.
  static String _identifierLabel(AppIdentifier id) =>
      switch (IdentifierKind.fromWireName(id.kindName)) {
        IdentifierKind.bundleId => 'Bundle ID',
        IdentifierKind.packageName => 'Package',
        final kind? => kind.label,
        null => 'Identifier',
      };
}
