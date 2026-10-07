import 'dart:convert';
import 'dart:typed_data';

/// A minimal ASN.1 reader for the DER (and BER) structures credential files
/// use: certificates, PKCS#8 keys, PKCS#12 and CMS.
///
/// Every accessor checks its input and throws [FormatException] on anything
/// malformed; it never reads outside the buffer. Indefinite lengths (BER,
/// which Apple's CMS files use) are accepted for constructed values.
class Asn1 {
  Asn1._(this.tag, this.encoded, this.content);

  /// Reads exactly one value from [bytes]. Trailing bytes are an error
  /// unless [allowTrailing] is set.
  factory Asn1.parse(Uint8List bytes, {bool allowTrailing = false}) {
    final (value, end) = _read(bytes, 0, 0);
    if (!allowTrailing && end != bytes.length) {
      throw const FormatException('trailing bytes after ASN.1 value');
    }
    return value;
  }

  static const int tagInteger = 0x02;
  static const int tagBitString = 0x03;
  static const int tagOctetString = 0x04;
  static const int tagNull = 0x05;
  static const int tagOid = 0x06;
  static const int tagUtf8String = 0x0C;
  static const int tagPrintableString = 0x13;
  static const int tagIa5String = 0x16;
  static const int tagUtcTime = 0x17;
  static const int tagGeneralizedTime = 0x18;
  static const int tagBmpString = 0x1E;
  static const int tagSequence = 0x30;
  static const int tagSet = 0x31;

  /// The identifier octet: class, constructed bit and tag number.
  final int tag;

  /// The whole encoding, header included (what fingerprints are taken of).
  final Uint8List encoded;

  /// The content octets. For an indefinite length, everything between the
  /// header and the end-of-contents marker.
  final Uint8List content;

  bool get isConstructed => tag & 0x20 != 0;

  /// `0` universal, `1` application, `2` context-specific, `3` private.
  int get tagClass => tag >> 6;
  int get tagNumber => tag & 0x1F;

  /// Whether this is context-specific `[n]`.
  bool isContext(int n) => tagClass == 2 && tagNumber == n;

  List<Asn1>? _children;

  /// The values inside a constructed value.
  List<Asn1> get children {
    if (!isConstructed) {
      throw const FormatException('ASN.1 value is not constructed');
    }
    return _children ??= _readAll(content, _depth + 1);
  }

  int _depth = 0;

  /// Child [i], or a [FormatException] if there isn't one.
  Asn1 operator [](int i) {
    final c = children;
    if (i < 0 || i >= c.length) {
      throw const FormatException('missing ASN.1 element');
    }
    return c[i];
  }

  /// Throws unless this value has [expected] as its tag.
  Asn1 expect(int expected) {
    if (tag != expected) {
      throw FormatException(
        'expected ASN.1 tag 0x${expected.toRadixString(16)}, '
        'got 0x${tag.toRadixString(16)}',
      );
    }
    return this;
  }

  /// The content of an explicitly tagged `[n] EXPLICIT` wrapper.
  Asn1 explicit(int n) {
    if (!isContext(n) || !isConstructed) {
      throw FormatException('expected [$n] EXPLICIT');
    }
    final c = children;
    if (c.length != 1) throw FormatException('[$n] must hold one value');
    return c.single;
  }

  /// An INTEGER's value.
  BigInt get integer {
    expect(tagInteger);
    if (content.isEmpty) throw const FormatException('empty INTEGER');
    var value = BigInt.zero;
    for (final b in content) {
      value = (value << 8) | BigInt.from(b);
    }
    if (content[0] & 0x80 != 0) {
      value -= BigInt.one << (content.length * 8);
    }
    return value;
  }

  /// An INTEGER that must fit comfortably in an `int`.
  int get smallInteger {
    final value = integer;
    if (value.bitLength > 31) throw const FormatException('INTEGER too large');
    return value.toInt();
  }

  /// An OBJECT IDENTIFIER in dotted form, e.g. `1.2.840.10045.2.1`.
  String get oid {
    expect(tagOid);
    if (content.isEmpty) throw const FormatException('empty OID');
    final arcs = <int>[];
    var value = 0;
    var started = false;
    for (final b in content) {
      if (!started && b == 0x80) throw const FormatException('bad OID');
      started = b & 0x80 != 0;
      value = (value << 7) | (b & 0x7F);
      if (value > 0xFFFFFFFF) throw const FormatException('OID arc too large');
      if (b & 0x80 == 0) {
        arcs.add(value);
        value = 0;
      }
    }
    if (started) throw const FormatException('truncated OID');
    final first = arcs.first;
    final head = first < 80 ? [first ~/ 40, first % 40] : [2, first - 80];
    return [...head, ...arcs.skip(1)].join('.');
  }

  /// An OCTET STRING's bytes (primitive only).
  Uint8List get octets {
    expect(tagOctetString);
    return content;
  }

  /// A BIT STRING's bytes. Only whole-byte strings are accepted.
  Uint8List get bits {
    expect(tagBitString);
    if (content.isEmpty || content[0] != 0) {
      throw const FormatException('BIT STRING with unused bits');
    }
    return Uint8List.sublistView(content, 1);
  }

  /// A character string (UTF8String, PrintableString, IA5String,
  /// BMPString and the other legacy 8-bit string types).
  String get string {
    switch (tag) {
      case tagUtf8String:
        return utf8.decode(content);
      case tagBmpString:
        if (content.length.isOdd) throw const FormatException('bad BMPString');
        return String.fromCharCodes([
          for (var i = 0; i < content.length; i += 2)
            (content[i] << 8) | content[i + 1],
        ]);
      case tagPrintableString || tagIa5String || 0x14 || 0x1A || 0x12 || 0x1C:
        return latin1.decode(content);
      default:
        throw FormatException('0x${tag.toRadixString(16)} is not a string');
    }
  }

  /// A UTCTime or GeneralizedTime, in UTC. Only the `Z` forms DER allows.
  DateTime get time {
    final text = ascii.decode(content);
    final RegExpMatch? m;
    int year;
    if (tag == tagUtcTime) {
      m = RegExp(r'^(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$').firstMatch(text);
      if (m == null) throw const FormatException('bad UTCTime');
      final yy = int.parse(m[1]!);
      year = yy >= 50 ? 1900 + yy : 2000 + yy; // RFC 5280 §4.1.2.5.1
    } else if (tag == tagGeneralizedTime) {
      m = RegExp(r'^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(?:\.\d+)?Z$')
          .firstMatch(text);
      if (m == null) throw const FormatException('bad GeneralizedTime');
      year = int.parse(m[1]!);
    } else {
      throw const FormatException('not a time');
    }
    final parts = [for (var i = 2; i <= 6; i++) int.parse(m[i]!)];
    final value = DateTime.utc(
      year,
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
    );
    if (value.month != parts[0] ||
        value.day != parts[1] ||
        parts[2] > 23 ||
        parts[3] > 59 ||
        parts[4] > 59) {
      throw const FormatException('time out of range');
    }
    return value;
  }

  @override
  String toString() =>
      'Asn1(0x${tag.toRadixString(16)}, ${content.length} bytes)';
}

/// Nesting deeper than this is treated as hostile input.
const int _maxDepth = 48;

List<Asn1> _readAll(Uint8List bytes, int depth) {
  final out = <Asn1>[];
  var offset = 0;
  while (offset < bytes.length) {
    final (value, end) = _read(bytes, offset, depth);
    out.add(value);
    offset = end;
  }
  return out;
}

(Asn1, int) _read(Uint8List bytes, int offset, int depth) {
  if (depth > _maxDepth) throw const FormatException('ASN.1 nested too deep');
  if (offset + 2 > bytes.length) throw const FormatException('truncated ASN.1');
  final tag = bytes[offset];
  if (tag & 0x1F == 0x1F) {
    throw const FormatException('high-number ASN.1 tags are not supported');
  }
  var pos = offset + 1;
  final first = bytes[pos++];

  if (first == 0x80) {
    // Indefinite length: constructed only, ends at 00 00.
    if (tag & 0x20 == 0) {
      throw const FormatException('indefinite length on a primitive value');
    }
    final start = pos;
    while (true) {
      if (pos + 2 > bytes.length) throw const FormatException('missing EOC');
      if (bytes[pos] == 0 && bytes[pos + 1] == 0) break;
      final (_, end) = _read(bytes, pos, depth + 1);
      pos = end;
    }
    final value = Asn1._(
      tag,
      Uint8List.sublistView(bytes, offset, pos + 2),
      Uint8List.sublistView(bytes, start, pos),
    ).._depth = depth;
    return (value, pos + 2);
  }

  int length;
  if (first < 0x80) {
    length = first;
  } else {
    final count = first & 0x7F;
    if (count > 4) throw const FormatException('ASN.1 length too large');
    if (pos + count > bytes.length) throw const FormatException('truncated');
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[pos++];
    }
  }
  if (length > bytes.length - pos) {
    throw const FormatException('ASN.1 length past end of input');
  }
  final value = Asn1._(
    tag,
    Uint8List.sublistView(bytes, offset, pos + length),
    Uint8List.sublistView(bytes, pos, pos + length),
  ).._depth = depth;
  return (value, pos + length);
}

/// One `-----BEGIN <label>----- … -----END <label>-----` block.
class PemBlock {
  const PemBlock(this.label, this.bytes);
  final String label;
  final Uint8List bytes;

  @override
  String toString() => 'PemBlock($label, ${bytes.length} bytes)';
}

final _pemBlock = RegExp(
  r'-----BEGIN ([A-Z0-9 ]+)-----([\s\S]*?)-----END \1-----',
);

/// Every PEM block in [text]. Headers (`Proc-Type:` …) are not supported;
/// a block that isn't clean base64 throws [FormatException].
List<PemBlock> decodePem(String text) => [
  for (final m in _pemBlock.allMatches(text))
    PemBlock(m[1]!, base64.decode(m[2]!.replaceAll(RegExp(r'\s'), ''))),
];
