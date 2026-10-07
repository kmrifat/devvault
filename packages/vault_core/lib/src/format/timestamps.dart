import 'format_error.dart';

/// RFC 3339 in UTC with a `Z`, whole seconds: `2026-10-07T09:00:00Z`.
String formatTimestamp(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

/// Parses an RFC 3339 UTC timestamp. Fractional seconds are accepted; a
/// missing `Z` (local time) is not.
DateTime parseTimestamp(Object? value, String field) {
  if (value is! String || !value.endsWith('Z')) {
    throw VaultFormatException('$field must be an RFC 3339 UTC timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw VaultFormatException('$field must be an RFC 3339 UTC timestamp');
  }
  return parsed;
}
