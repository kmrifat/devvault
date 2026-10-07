import 'dart:convert';
import 'dart:typed_data';

/// Reads an XML property list (`<plist version="1.0">`) into Dart values.
///
/// | plist | Dart |
/// |---|---|
/// | `<dict>` | `Map<String, Object>` (unmodifiable, file order) |
/// | `<array>` | `List<Object>` (unmodifiable) |
/// | `<string>` | `String` |
/// | `<integer>` | `int` |
/// | `<real>` | `double` |
/// | `<true/>`, `<false/>` | `bool` |
/// | `<date>` | `DateTime` (UTC) |
/// | `<data>` | `Uint8List` |
///
/// Strict: anything else, including binary plists (`bplist00`), attributes
/// on value elements, CDATA, unknown entities, duplicate dict keys and
/// trailing content, throws a [FormatException]. The message gives an
/// offset only and never quotes the input.
Object parseXmlPlist(String text) => _PlistReader(text).document();

/// Nesting deeper than this is refused, so hostile input can't overflow
/// the stack.
const int _maxDepth = 128;

class _PlistReader {
  _PlistReader(this._s);

  final String _s;
  int _pos = 0;
  int _depth = 0;

  Never _fail(String message) =>
      throw FormatException('Malformed plist: $message', null, _pos);

  Object document() {
    if (_s.startsWith('﻿')) _pos = 1;
    _skipSpace();
    if (_startsWith('<?xml')) {
      final end = _s.indexOf('?>', _pos);
      if (end < 0) _fail('unterminated XML declaration');
      _pos = end + 2;
    }
    _skipMisc();
    if (_startsWith('<!DOCTYPE')) {
      final end = _s.indexOf('>', _pos);
      if (end < 0) _fail('unterminated DOCTYPE');
      // An internal subset could declare entities; Apple never writes one.
      if (_s.substring(_pos, end).contains('[')) {
        _fail('DOCTYPE internal subset');
      }
      _pos = end + 1;
    }
    _skipMisc();

    if (!_startsWith('<plist')) _fail('expected <plist>');
    _pos += '<plist'.length;
    // `<plist>` may carry attributes (`version="1.0"`); nothing else may.
    final close = _s.indexOf('>', _pos);
    if (close < 0) _fail('unterminated <plist>');
    final attrs = _s.substring(_pos, close);
    if (attrs.isNotEmpty && !attrs.startsWith(RegExp(r'\s'))) {
      _fail('expected <plist>');
    }
    if (attrs.contains('<') || attrs.endsWith('/')) _fail('bad <plist> tag');
    _pos = close + 1;

    _skipMisc();
    final value = _value();
    _skipMisc();
    _expect('</plist>');
    _skipMisc();
    if (_pos != _s.length) _fail('content after </plist>');
    return value;
  }

  Object _value() {
    if (++_depth > _maxDepth) _fail('nested too deeply');
    try {
      final (name, empty) = _openTag();
      switch (name) {
        case 'dict':
          return empty ? const <String, Object>{} : _dict();
        case 'array':
          return empty ? const <Object>[] : _array();
        case 'string':
          return empty ? '' : _text('string');
        case 'integer':
          return _integer(empty ? '' : _text('integer'));
        case 'real':
          return _real(empty ? '' : _text('real'));
        case 'true':
        case 'false':
          if (!empty) _expect('</$name>');
          return name == 'true';
        case 'date':
          return _date(empty ? '' : _text('date'));
        case 'data':
          return _data(empty ? '' : _text('data'));
        default:
          _fail('unknown element');
      }
    } finally {
      _depth--;
    }
  }

  Map<String, Object> _dict() {
    final map = <String, Object>{};
    while (true) {
      _skipMisc();
      if (_startsWith('</dict>')) {
        _pos += '</dict>'.length;
        return Map.unmodifiable(map);
      }
      final (name, empty) = _openTag();
      if (name != 'key') _fail('expected <key>');
      final key = empty ? '' : _text('key');
      if (map.containsKey(key)) _fail('duplicate key');
      _skipMisc();
      map[key] = _value();
    }
  }

  List<Object> _array() {
    final list = <Object>[];
    while (true) {
      _skipMisc();
      if (_startsWith('</array>')) {
        _pos += '</array>'.length;
        return List.unmodifiable(list);
      }
      list.add(_value());
    }
  }

  /// Reads `<name>` or `<name/>`. Returns the name and whether it was
  /// self-closing.
  (String, bool) _openTag() {
    if (!_startsWith('<')) _fail('expected an element');
    var i = _pos + 1;
    while (i < _s.length && _isNameChar(_s.codeUnitAt(i))) {
      i++;
    }
    if (i == _pos + 1) _fail('expected an element');
    final name = _s.substring(_pos + 1, i);
    if (_s.startsWith('/>', i)) {
      _pos = i + 2;
      return (name, true);
    }
    if (_s.startsWith('>', i)) {
      _pos = i + 1;
      return (name, false);
    }
    _fail('unexpected attribute');
  }

  /// Character data up to `</name>`, with entities decoded and line ends
  /// normalised as XML requires.
  String _text(String name) {
    final end = _s.indexOf('<', _pos);
    if (end < 0) _fail('unterminated <$name>');
    final raw = _s.substring(_pos, end);
    _pos = end;
    _expect('</$name>');
    return _decodeEntities(raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  }

  String _decodeEntities(String raw) {
    if (!raw.contains('&')) return raw;
    final out = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final amp = raw.indexOf('&', i);
      if (amp < 0) {
        out.write(raw.substring(i));
        break;
      }
      out.write(raw.substring(i, amp));
      final semi = raw.indexOf(';', amp);
      if (semi < 0 || semi - amp > 10) _fail('bad entity');
      final entity = raw.substring(amp + 1, semi);
      switch (entity) {
        case 'amp':
          out.write('&');
        case 'lt':
          out.write('<');
        case 'gt':
          out.write('>');
        case 'quot':
          out.write('"');
        case 'apos':
          out.write("'");
        default:
          final int? code;
          if (entity.startsWith('#x')) {
            code = _parseDigits(entity.substring(2), 16);
          } else if (entity.startsWith('#')) {
            code = _parseDigits(entity.substring(1), 10);
          } else {
            code = null;
          }
          if (code == null ||
              code == 0 ||
              code > 0x10FFFF ||
              (code >= 0xD800 && code <= 0xDFFF)) {
            _fail('bad entity');
          }
          out.writeCharCode(code);
      }
      i = semi + 1;
    }
    return out.toString();
  }

  static int? _parseDigits(String digits, int radix) {
    final pattern = radix == 16 ? RegExp(r'^[0-9A-Fa-f]+$') : RegExp(r'^\d+$');
    return pattern.hasMatch(digits) ? int.tryParse(digits, radix: radix) : null;
  }

  int _integer(String text) {
    final t = text.trim();
    if (!RegExp(r'^[+-]?\d+$').hasMatch(t)) _fail('bad <integer>');
    final value = int.tryParse(t);
    if (value == null) _fail('<integer> out of range');
    return value;
  }

  double _real(String text) {
    final t = text.trim();
    if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(t)) {
      _fail('bad <real>');
    }
    return double.parse(t);
  }

  /// Plist dates are always `YYYY-MM-DDTHH:MM:SSZ`.
  DateTime _date(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$')
        .firstMatch(text.trim());
    if (m == null) _fail('bad <date>');
    final [y, mo, d, h, mi, s] = [
      for (var g = 1; g <= 6; g++) int.parse(m.group(g)!),
    ];
    final date = DateTime.utc(y, mo, d, h, mi, s);
    // DateTime.utc rolls 2026-13-01 over to 2027; a plist must not.
    if (date.year != y ||
        date.month != mo ||
        date.day != d ||
        date.hour != h ||
        date.minute != mi ||
        date.second != s) {
      _fail('bad <date>');
    }
    return date;
  }

  Uint8List _data(String text) {
    final compact = text.replaceAll(RegExp(r'\s'), '');
    try {
      return base64.decode(compact);
    } on FormatException {
      _fail('bad <data>');
    }
  }

  void _expect(String token) {
    if (!_startsWith(token)) _fail('expected $token');
    _pos += token.length;
  }

  bool _startsWith(String token) => _s.startsWith(token, _pos);

  void _skipSpace() {
    while (_pos < _s.length && _isSpace(_s.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  /// Whitespace and comments.
  void _skipMisc() {
    while (true) {
      _skipSpace();
      if (!_startsWith('<!--')) return;
      final end = _s.indexOf('-->', _pos + 4);
      if (end < 0) _fail('unterminated comment');
      _pos = end + 3;
    }
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isNameChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
}
