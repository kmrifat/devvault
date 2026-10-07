import 'format_error.dart';
import 'timestamps.dart';

/// Typed reads from a decoded JSON object, failing with
/// [VaultFormatException] naming the record and field, never the value.
class JsonReader {
  JsonReader(Object? json, this.record) : _json = _asMap(json, record);

  final Map<String, Object?> _json;
  final String record;

  static Map<String, Object?> _asMap(Object? json, String record) {
    if (json is Map<String, Object?>) return json;
    throw VaultFormatException('$record must be a JSON object');
  }

  Map<String, Object?> get raw => _json;

  /// Entries whose keys aren't in [known], to carry through a rewrite.
  Map<String, Object?> unknown(Set<String> known) => {
    for (final entry in _json.entries)
      if (!known.contains(entry.key)) entry.key: entry.value,
  };

  Never _fail(String field, String expected) =>
      throw VaultFormatException('$record.$field must be $expected');

  String string(String field) => _json[field] is String
      ? _json[field]! as String
      : _fail(field, 'a string');

  String? optionalString(String field) => switch (_json[field]) {
    null => null,
    final String value => value,
    _ => _fail(field, 'a string or null'),
  };

  int integer(String field) =>
      _json[field] is int ? _json[field]! as int : _fail(field, 'an integer');

  bool boolean(String field, {bool fallback = false}) => switch (_json[field]) {
    null => fallback,
    final bool value => value,
    _ => _fail(field, 'a boolean'),
  };

  DateTime timestamp(String field) =>
      parseTimestamp(_json[field], '$record.$field');

  DateTime? optionalTimestamp(String field) =>
      _json[field] == null ? null : timestamp(field);

  List<String> strings(String field) => switch (_json[field]) {
    null => const [],
    final List<Object?> list when list.every((e) => e is String) =>
      List.unmodifiable(list.cast<String>()),
    _ => _fail(field, 'a list of strings'),
  };

  List<Object?> list(String field) => switch (_json[field]) {
    null => const [],
    final List<Object?> list => list,
    _ => _fail(field, 'a list'),
  };

  Map<String, Object?> map(String field) => switch (_json[field]) {
    null => const {},
    final Map<String, Object?> map => map,
    _ => _fail(field, 'an object'),
  };

  Object? value(String field) => _json[field];
}
