import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'protocol.dart';

/// One message as one line of UTF-8 JSON (PROTOCOL.md §2).
List<int> encodeLine(Map<String, Object?> message) =>
    utf8.encode('${jsonEncode(message)}\n');

/// Splits a byte stream into JSON objects, one per line.
///
/// A line over [maxLine] bytes, or one that isn't a JSON object, ends the
/// stream with a [BridgeException]; the caller closes the connection.
Stream<Map<String, Object?>> decodeLines(
  Stream<List<int>> bytes, {
  int maxLine = maxLineBytes,
}) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0a) continue;
      buffer.add(chunk.sublist(start, i));
      start = i + 1;
      final line = buffer.takeBytes();
      if (line.length > maxLine) throw _tooLong;
      if (line.isEmpty) continue;
      yield _decode(line);
    }
    if (start < chunk.length) {
      buffer.add(chunk.sublist(start));
      if (buffer.length > maxLine) throw _tooLong;
    }
  }
}

const _tooLong = BridgeException(BridgeError.badRequest, 'line too long');

Map<String, Object?> _decode(List<int> line) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(line));
  } on FormatException {
    throw const BridgeException(BridgeError.badRequest, 'not JSON');
  }
  if (json is! Map<String, Object?>) {
    throw const BridgeException(BridgeError.badRequest, 'not an object');
  }
  return json;
}
