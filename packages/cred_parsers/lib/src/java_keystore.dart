import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/md5.dart';

import 'der.dart';

/// The two Java keystore containers DevVault reads.
enum JavaKeystoreType {
  /// Sun's `JKS`, magic `FEEDFEED`.
  jks('JKS'),

  /// SunJCE's `JCEKS`, magic `CECECECE`.
  jceks('JCEKS');

  const JavaKeystoreType(this.label);

  /// The store type as `keytool` names it.
  final String label;
}

enum KeystoreEntryKind { privateKey, trustedCertificate, secretKey }

/// A certificate as the keystore stores it: a type name and its encoding.
class KeystoreCertificate {
  KeystoreCertificate(this.type, this.encoded);

  /// `X.509` in practice. Version 1 keystores don't record it.
  final String type;
  final Uint8List encoded;

  @override
  String toString() => 'KeystoreCertificate($type, ${encoded.length} bytes)';
}

/// One entry. Aliases and certificates are stored in clear; private keys
/// are protected with the key password and secret keys are sealed.
class KeystoreEntry {
  KeystoreEntry._(
    this.kind,
    this.alias,
    this.created,
    this.chain,
    this._protectedKey,
  );

  final KeystoreEntryKind kind;
  final String alias;

  /// When the entry was added, as the file records it (UTC).
  final DateTime created;

  /// Leaf first. A trusted-certificate entry holds one; a secret key none.
  final List<KeystoreCertificate> chain;

  /// The `EncryptedPrivateKeyInfo` of a private-key entry.
  final Uint8List? _protectedKey;

  /// Never prints the protected key.
  @override
  String toString() =>
      'KeystoreEntry(${kind.name}, $alias, ${chain.length} cert(s))';
}

/// How a key password check came out.
enum KeyPasswordCheck {
  correct,
  wrong,

  /// The key is protected with something DevVault doesn't know, or the
  /// protection data is malformed. Says nothing about the password.
  unsupported,
}

/// A decoded JKS or JCEKS file.
///
/// Decoding needs no password: the structure, aliases and certificates are
/// all in clear. [checkStorePassword] and [checkKeyPassword] verify
/// passwords the way the JDK does, without keeping anything they decrypt.
class JavaKeystore {
  JavaKeystore._(
    this.type,
    this.version,
    this.entries,
    this._signed,
    this._mac,
  );

  /// Reads [bytes]. Throws [FormatException] on anything malformed; never
  /// reads outside the buffer.
  factory JavaKeystore.decode(Uint8List bytes) {
    final r = _Reader(bytes);
    final magic = r.u32();
    final JavaKeystoreType type;
    if (magic == 0xFEEDFEED) {
      type = JavaKeystoreType.jks;
    } else if (magic == 0xCECECECE) {
      type = JavaKeystoreType.jceks;
    } else {
      throw const FormatException('not a Java keystore');
    }
    final version = r.u32();
    if (version != 1 && version != 2) {
      throw const FormatException('unsupported keystore version');
    }
    final count = r.u32();
    // Each entry takes at least 14 bytes (tag, empty alias, date).
    if (count > r.remaining ~/ 14) {
      throw const FormatException('entry count past end of file');
    }

    KeystoreCertificate readCert() {
      final certType = version == 2 ? r.utf() : 'X.509';
      return KeystoreCertificate(certType, r.bytes(r.length()));
    }

    final entries = <KeystoreEntry>[];
    for (var i = 0; i < count; i++) {
      final tag = r.u32();
      final alias = r.utf();
      final created = r.date();
      switch (tag) {
        case 1:
          final key = r.bytes(r.length());
          final chainLength = r.length();
          final chain = [for (var j = 0; j < chainLength; j++) readCert()];
          entries.add(
            KeystoreEntry._(
              KeystoreEntryKind.privateKey,
              alias,
              created,
              List.unmodifiable(chain),
              key,
            ),
          );
        case 2:
          entries.add(
            KeystoreEntry._(
              KeystoreEntryKind.trustedCertificate,
              alias,
              created,
              List.unmodifiable([readCert()]),
              null,
            ),
          );
        case 3 when type == JavaKeystoreType.jceks:
          // A Java-serialized SealedObject. It has no length prefix, so it
          // is walked to find its end; its content is never decoded.
          _JavaSerialization(r).skipStream();
          entries.add(
            KeystoreEntry._(
              KeystoreEntryKind.secretKey,
              alias,
              created,
              const [],
              null,
            ),
          );
        default:
          throw const FormatException('unknown keystore entry tag');
      }
    }

    final signed = Uint8List.sublistView(bytes, 0, r.offset);
    // Like the JDK, anything after the digest is ignored.
    final mac = r.bytes(20);
    return JavaKeystore._(
      type,
      version,
      List.unmodifiable(entries),
      signed,
      mac,
    );
  }

  final JavaKeystoreType type;
  final int version;
  final List<KeystoreEntry> entries;

  /// Everything the integrity digest covers.
  final Uint8List _signed;
  final Uint8List _mac;

  /// Whether [password] matches the file's integrity digest:
  /// `SHA-1(UTF-16BE(password) ‖ "Mighty Aphrodite" ‖ file)`.
  bool checkStorePassword(String password) {
    final digest = sha1.convert([
      ..._utf16be(password),
      ...utf8.encode('Mighty Aphrodite'),
      ..._signed,
    ]).bytes;
    return _equal(digest, _mac);
  }

  /// Whether [password] unlocks the private key of [entry].
  KeyPasswordCheck checkKeyPassword(KeystoreEntry entry, String password) {
    final protectedKey = entry._protectedKey;
    if (entry.kind != KeystoreEntryKind.privateKey || protectedKey == null) {
      throw ArgumentError.value(entry.kind, 'entry', 'not a private key');
    }
    final Asn1 algorithm;
    final Uint8List encrypted;
    try {
      final info = Asn1.parse(protectedKey).expect(Asn1.tagSequence);
      algorithm = info[0].expect(Asn1.tagSequence);
      encrypted = info[1].octets;
      final oid = algorithm[0].oid;
      if (oid == _oidJdkKeyProtector) {
        return _jdkProtector(encrypted, password);
      }
      if (oid == _oidJceKeyProtector && type == JavaKeystoreType.jceks) {
        return _jceProtector(algorithm[1], encrypted, password);
      }
    } on FormatException {
      return KeyPasswordCheck.unsupported;
    }
    return KeyPasswordCheck.unsupported;
  }

  /// Sun's JDK 1.2 key protector (used by JKS): a SHA-1 keystream seeded
  /// with a 20-byte salt, XORed over the key, then
  /// `SHA-1(UTF-16BE(password) ‖ key)` as a check value.
  static KeyPasswordCheck _jdkProtector(Uint8List data, String password) {
    if (data.length <= 40) throw const FormatException('protected key short');
    final salt = Uint8List.sublistView(data, 0, 20);
    final body = Uint8List.sublistView(data, 20, data.length - 20);
    final check = Uint8List.sublistView(data, data.length - 20);
    final pw = _utf16be(password);

    final plain = Uint8List(body.length);
    List<int> digest = salt;
    for (var off = 0; off < body.length; off += 20) {
      digest = sha1.convert([...pw, ...digest]).bytes;
      for (var i = 0; i < 20 && off + i < body.length; i++) {
        plain[off + i] = body[off + i] ^ digest[i];
      }
    }
    final ok = _equal(sha1.convert([...pw, ...plain]).bytes, check);
    plain.fillRange(0, plain.length, 0);
    return ok ? KeyPasswordCheck.correct : KeyPasswordCheck.wrong;
  }

  /// SunJCE's PBEWithMD5AndTripleDES (used by JCEKS): a DESede key and IV
  /// from MD5 iterated over each salt half and the ASCII password, then
  /// DESede-CBC with PKCS#5 padding. A wrong password shows up as bad
  /// padding or a plaintext that isn't a PrivateKeyInfo.
  static KeyPasswordCheck _jceProtector(
    Asn1 params,
    Uint8List data,
    String password,
  ) {
    params.expect(Asn1.tagSequence);
    final salt = Uint8List.fromList(params[0].octets);
    final iterations = params[1].integer;
    if (salt.length != 8) throw const FormatException('bad PBE salt');
    if (iterations < BigInt.one || iterations > BigInt.from(_maxIterations)) {
      throw const FormatException('bad PBE iteration count');
    }
    if (data.isEmpty || data.length % 8 != 0) {
      throw const FormatException('bad PBE ciphertext length');
    }
    // SunJCE only takes printable ASCII; anything else can't be the
    // password that protected this key.
    if (password.codeUnits.any((c) => c < 0x20 || c > 0x7E)) {
      return KeyPasswordCheck.wrong;
    }
    final pw = Uint8List.fromList(password.codeUnits);

    // If the two salt halves are equal, the first half is reversed.
    var same = true;
    for (var i = 0; i < 4; i++) {
      if (salt[i] != salt[i + 4]) same = false;
    }
    if (same) {
      for (var i = 0; i < 2; i++) {
        final t = salt[i];
        salt[i] = salt[3 - i];
        salt[3 - i] = t;
      }
    }

    final rounds = iterations.toInt();
    final derived = Uint8List(32);
    final md5 = MD5Digest();
    final digest = Uint8List(16);
    for (var half = 0; half < 2; half++) {
      md5
        ..reset()
        ..update(salt, half * 4, 4)
        ..update(pw, 0, pw.length)
        ..doFinal(digest, 0);
      for (var j = 1; j < rounds; j++) {
        md5
          ..update(digest, 0, 16)
          ..update(pw, 0, pw.length)
          ..doFinal(digest, 0);
      }
      derived.setRange(half * 16, half * 16 + 16, digest);
    }

    final cipher = CBCBlockCipher(DESedeEngine())
      ..init(
        false,
        ParametersWithIV(
          KeyParameter(Uint8List.sublistView(derived, 0, 24)),
          Uint8List.sublistView(derived, 24, 32),
        ),
      );
    final plain = Uint8List(data.length);
    for (var off = 0; off < data.length; off += 8) {
      cipher.processBlock(data, off, plain, off);
    }
    derived.fillRange(0, derived.length, 0);

    try {
      final pad = plain.last;
      if (pad < 1 || pad > 8) return KeyPasswordCheck.wrong;
      for (var i = plain.length - pad; i < plain.length; i++) {
        if (plain[i] != pad) return KeyPasswordCheck.wrong;
      }
      return _isPrivateKeyInfo(
            Uint8List.sublistView(plain, 0, plain.length - pad),
          )
          ? KeyPasswordCheck.correct
          : KeyPasswordCheck.wrong;
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// PrivateKeyInfo { version 0|1, AlgorithmIdentifier, OCTET STRING, … }.
  static bool _isPrivateKeyInfo(Uint8List der) {
    try {
      final info = Asn1.parse(der).expect(Asn1.tagSequence);
      final version = info[0].integer;
      if (version != BigInt.zero && version != BigInt.one) return false;
      info[1].expect(Asn1.tagSequence)[0].oid;
      info[2].octets;
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  String toString() =>
      'JavaKeystore(${type.label}, v$version, ${entries.length} entries)';

  static const _oidJdkKeyProtector = '1.3.6.1.4.1.42.2.17.1.1';
  static const _oidJceKeyProtector = '1.3.6.1.4.1.42.2.19.1';

  /// The JDK refuses anything above this.
  static const _maxIterations = 5000000;
}

Uint8List _utf16be(String s) {
  final units = s.codeUnits;
  final out = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    out[2 * i] = units[i] >> 8;
    out[2 * i + 1] = units[i] & 0xFF;
  }
  return out;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// A bounds-checked big-endian reader.
class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int offset = 0;

  int get remaining => _bytes.length - offset;

  void _need(int n) {
    if (n < 0 || n > remaining) {
      throw const FormatException('truncated keystore');
    }
  }

  int u8() {
    _need(1);
    return _bytes[offset++];
  }

  int u16() {
    _need(2);
    final v = (_bytes[offset] << 8) | _bytes[offset + 1];
    offset += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v =
        (_bytes[offset] << 24) |
        (_bytes[offset + 1] << 16) |
        (_bytes[offset + 2] << 8) |
        _bytes[offset + 3];
    offset += 4;
    return v;
  }

  /// A signed 32-bit length that must be non-negative.
  int length() {
    final v = u32();
    if (v & 0x80000000 != 0) throw const FormatException('negative length');
    return v;
  }

  /// A non-negative signed 64-bit value that fits in a double.
  int i64() {
    final hi = u32();
    final lo = u32();
    if (hi & 0x80000000 != 0) throw const FormatException('negative long');
    if (hi > 0x1FFFFF) throw const FormatException('long out of range');
    return hi * 0x100000000 + lo;
  }

  DateTime date() {
    final ms = i64();
    if (ms > 8640000000000000) throw const FormatException('bad date');
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Uint8List bytes(int n) {
    _need(n);
    final v = Uint8List.sublistView(_bytes, offset, offset + n);
    offset += n;
    return v;
  }

  void skip(int n) {
    _need(n);
    offset += n;
  }

  /// Java's `DataInput.readUTF`: a u16 length and modified UTF-8.
  String utf() => modifiedUtf8(bytes(u16()));
}

/// Decodes Java's modified UTF-8 (`0xC0 0x80` for NUL, surrogates encoded
/// one at a time) into a Dart string.
String modifiedUtf8(Uint8List b) {
  final units = <int>[];
  var i = 0;
  while (i < b.length) {
    final c = b[i];
    if (c < 0x80) {
      units.add(c);
      i += 1;
    } else if (c & 0xE0 == 0xC0) {
      if (i + 1 >= b.length || b[i + 1] & 0xC0 != 0x80) {
        throw const FormatException('bad modified UTF-8');
      }
      units.add(((c & 0x1F) << 6) | (b[i + 1] & 0x3F));
      i += 2;
    } else if (c & 0xF0 == 0xE0) {
      if (i + 2 >= b.length ||
          b[i + 1] & 0xC0 != 0x80 ||
          b[i + 2] & 0xC0 != 0x80) {
        throw const FormatException('bad modified UTF-8');
      }
      units.add(
        ((c & 0x0F) << 12) | ((b[i + 1] & 0x3F) << 6) | (b[i + 2] & 0x3F),
      );
      i += 3;
    } else {
      throw const FormatException('bad modified UTF-8');
    }
  }
  return String.fromCharCodes(units);
}

/// Walks one Java object serialization stream (`ACED 0005` + one object)
/// to find where it ends, without building any objects.
///
/// Only what a `SealedObject` needs is supported: class descriptors,
/// objects, strings, arrays, enums, block data and back references.
/// Anything else is a [FormatException].
class _JavaSerialization {
  _JavaSerialization(this._r);

  final _Reader _r;
  final List<Object> _handles = [];

  static const _tcNull = 0x70;
  static const _tcReference = 0x71;
  static const _tcClassDesc = 0x72;
  static const _tcObject = 0x73;
  static const _tcString = 0x74;
  static const _tcArray = 0x75;
  static const _tcBlockData = 0x77;
  static const _tcEndBlockData = 0x78;
  static const _tcBlockDataLong = 0x7A;
  static const _tcLongString = 0x7C;
  static const _tcEnum = 0x7E;
  static const _baseHandle = 0x7E0000;

  static const _scWriteMethod = 0x01;
  static const _scSerializable = 0x02;
  static const _scExternalizable = 0x04;
  static const _scBlockData = 0x08;

  static const _maxDepth = 32;

  void skipStream() {
    if (_r.u16() != 0xACED || _r.u16() != 5) {
      throw const FormatException('not a Java serialization stream');
    }
    _content(0);
  }

  /// One `object` from the grammar; returns the class descriptor or
  /// string it was, when it was one.
  Object? _content(int depth) {
    if (depth > _maxDepth) throw const FormatException('nested too deep');
    final tc = _r.u8();
    switch (tc) {
      case _tcNull:
        return null;
      case _tcReference:
        final i = _r.u32() - _baseHandle;
        if (i < 0 || i >= _handles.length) {
          throw const FormatException('bad back reference');
        }
        return _handles[i];
      case _tcClassDesc:
        return _newClassDesc(depth);
      case _tcObject:
        final desc = _classDesc(depth);
        if (desc == null) throw const FormatException('object without class');
        _handles.add(const _Placeholder());
        _classData(desc, depth);
        return null;
      case _tcString:
        final s = _r.utf();
        _handles.add(s);
        return s;
      case _tcLongString:
        _r.skip(_r.i64());
        _handles.add(const _Placeholder());
        return null;
      case _tcArray:
        final desc = _classDesc(depth);
        if (desc == null || desc.name.length < 2 || desc.name[0] != '[') {
          throw const FormatException('array without array class');
        }
        _handles.add(const _Placeholder());
        final size = _r.length();
        final element = _primitiveSize(desc.name.codeUnitAt(1));
        if (element != null) {
          if (size > _r.remaining ~/ element) {
            throw const FormatException('array past end');
          }
          _r.skip(size * element);
        } else {
          for (var i = 0; i < size; i++) {
            _content(depth + 1);
          }
        }
        return null;
      case _tcEnum:
        _classDesc(depth);
        _handles.add(const _Placeholder());
        _content(depth + 1);
        return null;
      default:
        throw const FormatException('unsupported serialization content');
    }
  }

  /// A `classDesc`: new, null or a reference to one.
  _ClassDesc? _classDesc(int depth) {
    final value = _content(depth + 1);
    if (value == null) return null;
    if (value is! _ClassDesc) throw const FormatException('not a class');
    return value;
  }

  _ClassDesc _newClassDesc(int depth) {
    final name = _r.utf();
    _r.skip(8); // serialVersionUID
    final desc = _ClassDesc(name);
    _handles.add(desc);
    desc.flags = _r.u8();
    final fieldCount = _r.u16();
    for (var i = 0; i < fieldCount; i++) {
      final code = _r.u8();
      _r.utf(); // field name
      if (code == 0x5B /* [ */ || code == 0x4C /* L */ ) {
        final className = _content(depth + 1);
        if (className is! String) {
          throw const FormatException('field class name is not a string');
        }
      } else if (_primitiveSize(code) == null) {
        throw const FormatException('bad field type');
      }
      desc.fields.add(code);
    }
    _annotation(depth);
    desc.superclass = _classDesc(depth);
    return desc;
  }

  /// Contents up to `TC_ENDBLOCKDATA`.
  void _annotation(int depth) {
    while (true) {
      if (_r.remaining < 1) throw const FormatException('truncated');
      final peek = _peek();
      if (peek == _tcEndBlockData) {
        _r.u8();
        return;
      }
      if (peek == _tcBlockData) {
        _r.u8();
        _r.skip(_r.u8());
      } else if (peek == _tcBlockDataLong) {
        _r.u8();
        _r.skip(_r.length());
      } else {
        _content(depth + 1);
      }
    }
  }

  int _peek() {
    final v = _r.u8();
    _r.offset--;
    return v;
  }

  void _classData(_ClassDesc desc, int depth) {
    // Superclass data comes first.
    final chain = <_ClassDesc>[];
    for (_ClassDesc? d = desc; d != null; d = d.superclass) {
      if (chain.length > _maxDepth) throw const FormatException('deep class');
      chain.add(d);
    }
    for (final d in chain.reversed) {
      if (d.flags & _scExternalizable != 0) {
        if (d.flags & _scBlockData == 0) {
          throw const FormatException('old externalizable format');
        }
        _annotation(depth);
        continue;
      }
      if (d.flags & _scSerializable == 0) continue;
      for (final code in d.fields) {
        final size = _primitiveSize(code);
        if (size != null) {
          _r.skip(size);
        } else {
          _content(depth + 1);
        }
      }
      if (d.flags & _scWriteMethod != 0) _annotation(depth);
    }
  }

  /// Bytes in a primitive field of type [code], or `null` for objects.
  static int? _primitiveSize(int code) => switch (code) {
    0x42 || 0x5A => 1, // B Z
    0x43 || 0x53 => 2, // C S
    0x49 || 0x46 => 4, // I F
    0x4A || 0x44 => 8, // J D
    _ => null,
  };
}

class _ClassDesc {
  _ClassDesc(this.name);
  final String name;
  int flags = 0;
  final List<int> fields = [];
  _ClassDesc? superclass;
}

class _Placeholder {
  const _Placeholder();
}
