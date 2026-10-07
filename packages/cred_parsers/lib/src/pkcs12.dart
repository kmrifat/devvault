import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// Thrown when a password doesn't open a PKCS#12 file: the MAC doesn't
/// match, or (in a file without a MAC) the contents don't decrypt.
///
/// Carries no detail, so it can't leak the password or the file.
class Pkcs12PasswordException implements Exception {
  const Pkcs12PasswordException();

  @override
  String toString() => 'Pkcs12PasswordException';
}

/// A certificate bag from a PKCS#12 file.
class Pkcs12Certificate {
  const Pkcs12Certificate(this.der, {this.localKeyId, this.friendlyName});

  /// The X.509 certificate, DER-encoded.
  final Uint8List der;

  /// The `localKeyId` attribute, which pairs a certificate with its key.
  final Uint8List? localKeyId;

  /// The `friendlyName` attribute, if the file has one.
  final String? friendlyName;

  @override
  String toString() => 'Pkcs12Certificate(${der.length} bytes)';
}

/// A private-key bag. Only its presence and attributes are read; the key
/// itself is never decrypted.
class Pkcs12KeyBag {
  const Pkcs12KeyBag({required this.shrouded, this.localKeyId});

  /// Whether the key is password-encrypted (`pkcs8ShroudedKeyBag`).
  final bool shrouded;

  /// The `localKeyId` attribute, which pairs a key with its certificate.
  final Uint8List? localKeyId;

  @override
  String toString() => 'Pkcs12KeyBag(shrouded: $shrouded)';
}

/// The certificates and keys in a PKCS#12 (`.p12`, `.pfx`) file.
///
/// [Pkcs12Contents.read] checks the MAC, decrypts the encrypted parts that
/// hold certificates, and lists every bag. Supported:
///
/// - MAC: HMAC with SHA-1, SHA-224, SHA-256, SHA-384 or SHA-512, keyed by
///   the PKCS#12 KDF (RFC 7292 Appendix B);
/// - encryption: PBES2 (PBKDF2 + AES-CBC or DES-EDE3-CBC), as OpenSSL 3
///   writes by default, and the legacy PKCS#12 PBEs with SHA-1 and 3DES or
///   RC2 (40 or 128 bit), as `-legacy`, Keychain and Windows write.
///
/// Anything else throws [FormatException]. Private keys are only counted.
class Pkcs12Contents {
  const Pkcs12Contents._(this.certificates, this.keys, {required this.hasMac});

  final List<Pkcs12Certificate> certificates;
  final List<Pkcs12KeyBag> keys;

  /// Whether the file has a MAC (which [read] verified). Without one, the
  /// password was only checked by decrypting (if anything is encrypted).
  final bool hasMac;

  bool get hasPrivateKey => keys.isNotEmpty;

  /// The end-entity certificate, or `null` if there is no certificate or
  /// the file doesn't say which one it is. Nothing is guessed:
  ///
  /// 1. the one certificate whose `localKeyId` matches a key bag's;
  /// 2. failing that, the one certificate that issued none of the others
  ///    (compared by the raw issuer and subject names).
  ///
  /// Duplicate copies of a certificate count once. Two matches by either
  /// rule is ambiguous and gives `null`.
  Pkcs12Certificate? get leaf {
    final unique = <Pkcs12Certificate>[];
    for (final cert in certificates) {
      if (!unique.any((u) => _bytesEqual(u.der, cert.der))) unique.add(cert);
    }

    final keyIds = [for (final key in keys) ?key.localKeyId];
    final paired = unique.where((cert) {
      final id = cert.localKeyId;
      return id != null && keyIds.any((k) => _bytesEqual(k, id));
    }).toList();
    if (paired.length == 1) return paired.single;
    if (paired.length > 1) return null;

    final names = [for (final cert in unique) _IssuerAndSubject.of(cert.der)];
    final leaves = [
      for (var i = 0; i < unique.length; i++)
        if (!_issuesAnother(i, names)) unique[i],
    ];
    return leaves.length == 1 ? leaves.single : null;
  }

  static bool _issuesAnother(int i, List<_IssuerAndSubject> names) {
    for (var j = 0; j < names.length; j++) {
      if (j != i && _bytesEqual(names[j].issuer, names[i].subject)) {
        return true;
      }
    }
    return false;
  }

  /// Opens [bytes] with [password] (`''` for none). Throws
  /// [Pkcs12PasswordException] if the password is wrong and
  /// [FormatException] if the file is malformed or uses something
  /// unsupported. Neither quotes the password.
  static Pkcs12Contents read(Uint8List bytes, String password) {
    final pfx = Asn1.parse(bytes, allowTrailing: true).expect(Asn1.tagSequence);
    if (pfx[0].integer != BigInt.from(3)) {
      throw const FormatException('unsupported PFX version');
    }
    final authSafe = pfx[1].expect(Asn1.tagSequence);
    if (authSafe[0].oid != _oidData) {
      // signedData would be public-key integrity mode; nobody writes it.
      throw const FormatException('unsupported PFX integrity mode');
    }
    final authSafeBytes = _octetString(authSafe[1].explicit(0));
    final infos = Asn1.parse(authSafeBytes).expect(Asn1.tagSequence).children;
    final mac = pfx.children.length > 2 ? pfx[2] : null;

    final candidates = _Password.encodings(password);
    if (mac != null) {
      final key = candidates.firstWhere(
        (candidate) => _macMatches(mac, authSafeBytes, candidate.bmp),
        orElse: () => throw const Pkcs12PasswordException(),
      );
      try {
        return _open(infos, key, hasMac: true);
      } on _WrongKey {
        // The MAC says the password is right, so the file is damaged.
        throw const FormatException('PKCS#12 contents do not decrypt');
      }
    }
    for (final key in candidates) {
      try {
        return _open(infos, key, hasMac: false);
      } on _WrongKey {
        // The other encodings differ only for the PKCS#12 KDF.
        if (!key.usedBmp) break;
      }
    }
    throw const Pkcs12PasswordException();
  }

  static Pkcs12Contents _open(
    List<Asn1> infos,
    _Password key, {
    required bool hasMac,
  }) {
    final certificates = <Pkcs12Certificate>[];
    final keys = <Pkcs12KeyBag>[];
    for (final info in infos) {
      info.expect(Asn1.tagSequence);
      final type = info[0].oid;
      final List<Asn1> bags;
      if (type == _oidData) {
        bags = _safeContents(_octetString(info[1].explicit(0)));
      } else if (type == _oidEncryptedData) {
        final plain = _decryptEncryptedData(info[1].explicit(0), key);
        try {
          bags = _safeContents(plain);
        } on FormatException {
          throw const _WrongKey();
        }
      } else {
        // envelopedData (public-key privacy mode) isn't supported.
        throw const FormatException('unsupported PKCS#12 content type');
      }
      _readBags(bags, certificates, keys);
    }
    return Pkcs12Contents._(
      List.unmodifiable(certificates),
      List.unmodifiable(keys),
      hasMac: hasMac,
    );
  }

  @override
  String toString() =>
      'Pkcs12Contents(${certificates.length} certificate(s), '
      '${keys.length} key(s))';
}

// ── OIDs ────────────────────────────────────────────────────────────────

const _oidData = '1.2.840.113549.1.7.1';
const _oidEncryptedData = '1.2.840.113549.1.7.6';

const _oidKeyBag = '1.2.840.113549.1.12.10.1.1';
const _oidShroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
const _oidCertBag = '1.2.840.113549.1.12.10.1.3';
const _oidSafeContentsBag = '1.2.840.113549.1.12.10.1.6';
const _oidX509Certificate = '1.2.840.113549.1.9.22.1';

const _oidFriendlyName = '1.2.840.113549.1.9.20';
const _oidLocalKeyId = '1.2.840.113549.1.9.21';

const _oidPbeSha1Rc4_128 = '1.2.840.113549.1.12.1.1';
const _oidPbeSha1Des3Key3 = '1.2.840.113549.1.12.1.3';
const _oidPbeSha1Des3Key2 = '1.2.840.113549.1.12.1.4';
const _oidPbeSha1Rc2_128 = '1.2.840.113549.1.12.1.5';
const _oidPbeSha1Rc2_40 = '1.2.840.113549.1.12.1.6';

const _oidPbes2 = '1.2.840.113549.1.5.13';
const _oidPbkdf2 = '1.2.840.113549.1.5.12';
const _oidDesEde3Cbc = '1.2.840.113549.3.7';
const _oidAes128Cbc = '2.16.840.1.101.3.4.1.2';
const _oidAes192Cbc = '2.16.840.1.101.3.4.1.22';
const _oidAes256Cbc = '2.16.840.1.101.3.4.1.42';

/// Digest OIDs (for the MAC) and their HMAC OIDs (for PBKDF2's PRF).
const _digests = {
  '1.3.14.3.2.26': 'SHA-1',
  '2.16.840.1.101.3.4.2.4': 'SHA-224',
  '2.16.840.1.101.3.4.2.1': 'SHA-256',
  '2.16.840.1.101.3.4.2.2': 'SHA-384',
  '2.16.840.1.101.3.4.2.3': 'SHA-512',
};
const _hmacs = {
  '1.2.840.113549.2.7': 'SHA-1',
  '1.2.840.113549.2.8': 'SHA-224',
  '1.2.840.113549.2.9': 'SHA-256',
  '1.2.840.113549.2.10': 'SHA-384',
  '1.2.840.113549.2.11': 'SHA-512',
};

Digest _digest(String name) => switch (name) {
  'SHA-1' => SHA1Digest(),
  'SHA-224' => SHA224Digest(),
  'SHA-256' => SHA256Digest(),
  'SHA-384' => SHA384Digest(),
  'SHA-512' => SHA512Digest(),
  _ => throw const FormatException('unsupported digest'),
};

/// Iteration counts above this are treated as hostile: real files use a
/// few thousand (OpenSSL 2048, Java 10 000).
const int _maxIterations = 1000000;

// ── Passwords ───────────────────────────────────────────────────────────

/// A password in the two encodings PKCS#12 uses.
class _Password {
  _Password(this.bmp, this.utf8);

  /// The ways [password] may have been applied. An empty password may also
  /// have been applied as no bytes at all (OpenSSL's NULL password), so
  /// both are tried.
  static List<_Password> encodings(String password) {
    final utf8 = Uint8List.fromList(const Utf8Encoder().convert(password));
    return [
      _Password(_bmpString(password), utf8),
      if (password.isEmpty) _Password(Uint8List(0), utf8),
    ];
  }

  /// BMPString with a two-byte terminator, for the PKCS#12 KDF.
  final Uint8List bmp;

  /// UTF-8, for PBES2.
  final Uint8List utf8;

  /// Whether a decryption used [bmp] (rather than only [utf8]).
  bool usedBmp = false;

  static Uint8List _bmpString(String password) {
    final units = password.codeUnits;
    final out = Uint8List(units.length * 2 + 2);
    for (var i = 0; i < units.length; i++) {
      out[i * 2] = units[i] >> 8;
      out[i * 2 + 1] = units[i] & 0xFF;
    }
    return out;
  }
}

// ── MAC ─────────────────────────────────────────────────────────────────

/// MacData { mac DigestInfo, macSalt OCTET STRING, iterations INTEGER
/// DEFAULT 1 }, an HMAC over the AuthenticatedSafe's content octets.
bool _macMatches(Asn1 macData, Uint8List authSafe, Uint8List bmp) {
  macData.expect(Asn1.tagSequence);
  final digestInfo = macData[0].expect(Asn1.tagSequence);
  final name = _digests[digestInfo[0].expect(Asn1.tagSequence)[0].oid];
  if (name == null) throw const FormatException('unsupported MAC algorithm');
  final expected = digestInfo[1].octets;
  final salt = macData[1].octets;
  final iterations = macData.children.length > 2 ? _iterations(macData[2]) : 1;

  final digestSize = _digest(name).digestSize;
  final kdf = PKCS12ParametersGenerator(_digest(name))
    ..init(bmp, salt, iterations);
  final key = kdf.generateDerivedMacParameters(digestSize);
  final hmac = HMac.withDigest(_digest(name))..init(key);
  return _constantTimeEquals(hmac.process(authSafe), expected);
}

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

int _iterations(Asn1 value) {
  final n = value.smallInteger;
  if (n < 1 || n > _maxIterations) {
    throw const FormatException('iteration count out of range');
  }
  return n;
}

// ── Decryption ──────────────────────────────────────────────────────────

/// A decryption that produced garbage: the key (so the password) is wrong.
class _WrongKey implements Exception {
  const _WrongKey();
}

/// EncryptedData { version, EncryptedContentInfo { contentType,
/// contentEncryptionAlgorithm, [0] IMPLICIT encryptedContent } }.
Uint8List _decryptEncryptedData(Asn1 data, _Password key) {
  data.expect(Asn1.tagSequence);
  final info = data[1].expect(Asn1.tagSequence);
  if (info[0].oid != _oidData) {
    throw const FormatException('unsupported encrypted content type');
  }
  if (info.children.length < 3 || !info[2].isContext(0)) {
    throw const FormatException('no encrypted content');
  }
  final content = info[2];
  final ciphertext = content.isConstructed
      ? _concatOctets(content.children)
      : content.content;
  return _decrypt(info[1], ciphertext, key);
}

/// Decrypts [data] under the password-based [algorithm]. Throws [_WrongKey]
/// when the padding is wrong.
Uint8List _decrypt(Asn1 algorithm, Uint8List data, _Password password) {
  algorithm.expect(Asn1.tagSequence);
  final oid = algorithm[0].oid;
  if (oid == _oidPbes2) {
    return _decryptPbes2(algorithm[1], data, password.utf8);
  }

  final (keyLength, rc2Bits) = switch (oid) {
    _oidPbeSha1Des3Key3 => (24, null),
    _oidPbeSha1Des3Key2 => (16, null),
    _oidPbeSha1Rc2_128 => (16, 128),
    _oidPbeSha1Rc2_40 => (5, 40),
    _oidPbeSha1Rc4_128 => throw const FormatException('RC4 is not supported'),
    _ => throw const FormatException('unsupported PKCS#12 encryption'),
  };
  final params = algorithm[1].expect(Asn1.tagSequence);
  password.usedBmp = true;
  final kdf = PKCS12ParametersGenerator(SHA1Digest())
    ..init(password.bmp, params[0].octets, _iterations(params[1]));
  final derived = kdf.generateDerivedParametersWithIV(keyLength, 8);
  final key = derived.parameters! as KeyParameter;
  return rc2Bits == null
      ? _cbc(DESedeEngine(), key, derived.iv, data)
      : _cbc(
          RC2Engine(),
          RC2Parameters(key.key, bits: rc2Bits),
          derived.iv,
          data,
        );
}

/// PBES2-params { keyDerivationFunc (PBKDF2), encryptionScheme }.
Uint8List _decryptPbes2(Asn1 params, Uint8List data, Uint8List password) {
  params.expect(Asn1.tagSequence);
  final kdf = params[0].expect(Asn1.tagSequence);
  final scheme = params[1].expect(Asn1.tagSequence);
  if (kdf[0].oid != _oidPbkdf2) {
    throw const FormatException('unsupported PBES2 key derivation');
  }

  final (BlockCipher engine, keyLength) = switch (scheme[0].oid) {
    _oidAes128Cbc => (AESEngine(), 16),
    _oidAes192Cbc => (AESEngine(), 24),
    _oidAes256Cbc => (AESEngine(), 32),
    _oidDesEde3Cbc => (DESedeEngine(), 24),
    _ => throw const FormatException('unsupported PBES2 cipher'),
  };
  final iv = scheme[1].octets;
  if (iv.length != engine.blockSize) throw const FormatException('bad IV');

  // PBKDF2-params { salt OCTET STRING, iterationCount, keyLength?, prf? }
  final p = kdf[1].expect(Asn1.tagSequence).children;
  if (p.length < 2) throw const FormatException('bad PBKDF2 parameters');
  final salt = p[0].octets;
  final iterations = _iterations(p[1]);
  var prf = 'SHA-1';
  for (final extra in p.skip(2)) {
    if (extra.tag == Asn1.tagInteger) {
      if (extra.smallInteger != keyLength) {
        throw const FormatException('PBKDF2 key length mismatch');
      }
    } else {
      prf =
          _hmacs[extra.expect(Asn1.tagSequence)[0].oid] ??
          (throw const FormatException('unsupported PBKDF2 PRF'));
    }
  }

  final derivator = PBKDF2KeyDerivator(HMac.withDigest(_digest(prf)))
    ..init(Pbkdf2Parameters(salt, iterations, keyLength));
  final key = derivator.process(password);
  return _cbc(engine, KeyParameter(key), iv, data);
}

/// CBC decryption with PKCS#7 padding, checked here so a wrong key is a
/// [_WrongKey] rather than whatever the cipher library throws.
Uint8List _cbc(
  BlockCipher engine,
  CipherParameters key,
  Uint8List iv,
  Uint8List data,
) {
  final size = engine.blockSize;
  if (data.isEmpty || data.length % size != 0) {
    throw const FormatException('ciphertext is not whole blocks');
  }
  final cbc = CBCBlockCipher(engine)..init(false, ParametersWithIV(key, iv));
  final out = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += size) {
    cbc.processBlock(data, offset, out, offset);
  }
  final pad = out.last;
  if (pad < 1 || pad > size) throw const _WrongKey();
  for (var i = out.length - pad; i < out.length; i++) {
    if (out[i] != pad) throw const _WrongKey();
  }
  return Uint8List.sublistView(out, 0, out.length - pad);
}

// ── Bags ────────────────────────────────────────────────────────────────

/// SafeContents ::= SEQUENCE OF SafeBag.
List<Asn1> _safeContents(Uint8List bytes) =>
    Asn1.parse(bytes).expect(Asn1.tagSequence).children;

/// SafeBag { bagId, [0] EXPLICIT bagValue, bagAttributes SET OPTIONAL }.
void _readBags(
  List<Asn1> bags,
  List<Pkcs12Certificate> certificates,
  List<Pkcs12KeyBag> keys,
) {
  for (final bag in bags) {
    bag.expect(Asn1.tagSequence);
    final id = bag[0].oid;
    final value = bag[1].explicit(0);
    final attributes = bag.children.length > 2
        ? _Attributes.read(bag[2])
        : const _Attributes();
    switch (id) {
      case _oidCertBag:
        // CertBag { certId, [0] EXPLICIT certValue }
        value.expect(Asn1.tagSequence);
        if (value[0].oid != _oidX509Certificate) continue; // SDSI certs
        certificates.add(
          Pkcs12Certificate(
            Uint8List.fromList(_octetString(value[1].explicit(0))),
            localKeyId: attributes.localKeyId,
            friendlyName: attributes.friendlyName,
          ),
        );
      case _oidKeyBag || _oidShroudedKeyBag:
        value.expect(Asn1.tagSequence);
        keys.add(
          Pkcs12KeyBag(
            shrouded: id == _oidShroudedKeyBag,
            localKeyId: attributes.localKeyId,
          ),
        );
      case _oidSafeContentsBag:
        _readBags(value.expect(Asn1.tagSequence).children, certificates, keys);
      default:
        // CRL and secret bags hold nothing DevVault reads.
        break;
    }
  }
}

/// The bag attributes DevVault reads.
class _Attributes {
  const _Attributes({this.localKeyId, this.friendlyName});

  /// PKCS12Attribute { attrId, attrValues SET OF ANY }.
  factory _Attributes.read(Asn1 set) {
    set.expect(Asn1.tagSet);
    Uint8List? localKeyId;
    String? friendlyName;
    for (final attribute in set.children) {
      attribute.expect(Asn1.tagSequence);
      final values = attribute[1].expect(Asn1.tagSet).children;
      if (values.isEmpty) continue;
      switch (attribute[0].oid) {
        case _oidLocalKeyId:
          localKeyId = Uint8List.fromList(values.first.octets);
        case _oidFriendlyName:
          friendlyName = values.first.string;
      }
    }
    return _Attributes(localKeyId: localKeyId, friendlyName: friendlyName);
  }

  final Uint8List? localKeyId;
  final String? friendlyName;
}

// ── Certificates ────────────────────────────────────────────────────────

/// The raw issuer and subject `Name`s of a certificate, for chain order.
class _IssuerAndSubject {
  const _IssuerAndSubject(this.issuer, this.subject);

  /// Certificate { TBSCertificate { [0] version?, serialNumber, signature,
  /// issuer, validity, subject, … }, … }.
  factory _IssuerAndSubject.of(Uint8List der) {
    final tbs = Asn1.parse(der).expect(Asn1.tagSequence)[0];
    tbs.expect(Asn1.tagSequence);
    final skip = tbs[0].isContext(0) ? 1 : 0;
    return _IssuerAndSubject(
      tbs[skip + 2].expect(Asn1.tagSequence).encoded,
      tbs[skip + 4].expect(Asn1.tagSequence).encoded,
    );
  }

  final Uint8List issuer;
  final Uint8List subject;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── OCTET STRING helpers ────────────────────────────────────────────────

/// An OCTET STRING's bytes, primitive or BER-constructed.
Uint8List _octetString(Asn1 value) {
  if (value.tag == Asn1.tagOctetString) return value.content;
  if (value.tag == Asn1.tagOctetString | 0x20) {
    return _concatOctets(value.children);
  }
  throw const FormatException('expected OCTET STRING');
}

/// The concatenated bytes of BER segments ([_octetString] each).
Uint8List _concatOctets(List<Asn1> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(_octetString(part));
  }
  return builder.takeBytes();
}
