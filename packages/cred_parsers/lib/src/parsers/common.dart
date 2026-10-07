import 'dart:convert';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

/// Helpers shared by the parsers. Every error they throw is a
/// [FormatException] that names no file content.

/// Config files are a few KiB; anything past this isn't one.
const int maxConfigBytes = 4 * 1024 * 1024;

/// Decodes [bytes] as a UTF-8 JSON object.
Map<String, Object?> decodeJsonObject(Uint8List bytes) {
  if (bytes.length > maxConfigBytes) {
    throw const FormatException('File too large');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const FormatException('Not valid JSON');
  }
  if (json is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object');
  }
  return json;
}

/// Decodes [bytes] as UTF-8 text.
String decodeUtf8(Uint8List bytes) {
  if (bytes.length > maxConfigBytes) {
    throw const FormatException('File too large');
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('Not valid UTF-8');
  }
}

/// The value under [key] as the file wrote it, or `null` if it's missing,
/// `null` or empty. A JSON integer is kept as its decimal digits. Anything
/// else is a malformed file.
String? readString(Map<String, Object?> map, String key) {
  final value = map[key];
  return switch (value) {
    null => null,
    String() => value.isEmpty ? null : value,
    int() => '$value',
    _ => throw FormatException('Unexpected value type for a known key'),
  };
}

/// The map under [key], or `null` if it's missing. Anything else is a
/// malformed file.
Map<String, Object?>? readMap(Map<String, Object?> map, String key) {
  final value = map[key];
  return switch (value) {
    null => null,
    Map<String, Object?>() => value,
    _ => throw FormatException('Unexpected value type for a known key'),
  };
}

/// The list of strings under [key], or `null` if it's missing or empty.
List<String>? readStrings(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! List || value.any((e) => e is! String)) {
    throw const FormatException('Unexpected value type for a known key');
  }
  final strings = [
    for (final e in value.cast<String>())
      if (e.isNotEmpty) e,
  ];
  return strings.isEmpty ? null : strings;
}

/// A fact read from the file.
ItemField fileFact(String value, {bool secret = false}) =>
    ItemField(value: value, source: FieldSource.file, secret: secret);

/// Adds `key: value` to [facts] when [value] is present.
void putFact(
  Map<String, ItemField> facts,
  String key,
  String? value, {
  bool secret = false,
}) {
  if (value != null) facts[key] = fileFact(value, secret: secret);
}
