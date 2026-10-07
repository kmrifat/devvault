import 'dart:convert';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart' show ItemType;

/// The file formats DevVault knows how to read.
///
/// Detection says what a file *is*; whether a parser can read facts out of
/// it is a separate question (see `CredentialParsers.parse`).
enum CredentialFormat {
  /// PKCS#8 private key in a `.p8` file (App Store Connect / APNs key).
  appleAuthKey('Apple Auth Key (.p8)', ItemType.appleAuthKey),

  /// X.509 certificate, DER or PEM.
  x509Certificate('Certificate', ItemType.appleCertificate),

  /// PKCS#12 bundle (`.p12`, `.pfx`).
  pkcs12('PKCS#12', ItemType.appleCertificate),

  /// CMS-signed plist (`.mobileprovision`, `.provisionprofile`).
  mobileProvision('Provisioning Profile', ItemType.provisioningProfile),

  /// Java KeyStore, magic `FEEDFEED`.
  jks('Java KeyStore', ItemType.androidKeystore),

  /// Java Cryptography Extension KeyStore, magic `CECECECE`.
  jceks('JCEKS KeyStore', ItemType.androidKeystore),

  /// `google-services.json`.
  googleServicesJson('google-services.json', ItemType.firebaseConfig),

  /// `GoogleService-Info.plist`.
  googleServiceInfoPlist('GoogleService-Info.plist', ItemType.firebaseConfig),

  /// GCP service-account key (`"type": "service_account"`).
  serviceAccountJson('Service account key', ItemType.gcpServiceAccount),

  /// OAuth client secret (`client_secret_*.json`).
  oauthClientJson('OAuth client', ItemType.oauthClient),

  /// Anything else. Imported as a generic file.
  unknown('File', ItemType.genericFile);

  const CredentialFormat(this.label, this.itemType);

  /// Human-readable name, safe for warnings and the UI.
  final String label;

  /// The item type a successful parse of this format produces. A parser may
  /// still fall back to [ItemType.genericFile].
  final ItemType itemType;
}

/// JSON and plist files are only decoded for detection up to this size.
/// Real config files are a few KiB.
const int _maxStructuredTextBytes = 4 * 1024 * 1024;

/// Works out what [bytes] are, from magic bytes first, then structure, then
/// [filename]. Never throws: anything it can't place is
/// [CredentialFormat.unknown].
CredentialFormat detectFormat(String filename, Uint8List bytes) {
  try {
    return _detect(filename, bytes);
  } catch (_) {
    return CredentialFormat.unknown;
  }
}

CredentialFormat _detect(String filename, Uint8List bytes) {
  if (bytes.isEmpty) return CredentialFormat.unknown;
  final name = _basename(filename);
  final ext = _extension(name);

  // Keystores carry a 4-byte magic, whatever they are called.
  if (_startsWith(bytes, const [0xFE, 0xED, 0xFE, 0xED])) {
    return CredentialFormat.jks;
  }
  if (_startsWith(bytes, const [0xCE, 0xCE, 0xCE, 0xCE])) {
    return CredentialFormat.jceks;
  }

  if (bytes[0] == 0x30) {
    final der = _detectDer(bytes);
    if (der != null) return der;
  }

  final text = _asciiPrefix(bytes, 64 * 1024);
  if (text.contains('-----BEGIN CERTIFICATE-----')) {
    return CredentialFormat.x509Certificate;
  }
  // A bare PKCS#8 key could be anything; only a .p8 is an Apple auth key.
  if (ext == 'p8' && text.contains('-----BEGIN PRIVATE KEY-----')) {
    return CredentialFormat.appleAuthKey;
  }

  if (_isPlist(bytes, text)) {
    if (name.toLowerCase().startsWith('googleservice-info') ||
        text.contains('<key>GOOGLE_APP_ID</key>')) {
      return CredentialFormat.googleServiceInfoPlist;
    }
    return CredentialFormat.unknown;
  }

  if (ext == 'json' || text.trimLeft().startsWith('{')) {
    return _detectJson(name, bytes);
  }

  return CredentialFormat.unknown;
}

/// DER structures: CMS SignedData with a plist inside, PKCS#12 (`PFX`
/// version 3) and X.509 certificates.
CredentialFormat? _detectDer(Uint8List bytes) {
  final outer = _readTlv(bytes, 0);
  if (outer == null || outer.tag != 0x30) return null;
  final first = _readTlv(bytes, outer.contentStart);
  if (first == null) return null;

  // ContentInfo { contentType = signedData (1.2.840.113549.1.7.2) }
  if (first.tag == 0x06 && _matches(bytes, first, _oidSignedData)) {
    final head = _asciiPrefix(bytes, bytes.length);
    return head.contains('<plist') || head.contains('bplist00')
        ? CredentialFormat.mobileProvision
        : null;
  }

  // PFX { version INTEGER (3), authSafe ContentInfo, ... }
  if (first.tag == 0x02 && _matches(bytes, first, const [0x03])) {
    final authSafe = _readTlv(bytes, first.end);
    if (authSafe != null && authSafe.tag == 0x30) {
      return CredentialFormat.pkcs12;
    }
    return null;
  }

  // Certificate { tbsCertificate SEQUENCE { [0] version?, serial, ... } }
  if (first.tag == 0x30) {
    final tbsFirst = _readTlv(bytes, first.contentStart);
    if (tbsFirst != null && (tbsFirst.tag == 0xA0 || tbsFirst.tag == 0x02)) {
      final sigAlg = _readTlv(bytes, first.end);
      if (sigAlg != null && sigAlg.tag == 0x30) {
        return CredentialFormat.x509Certificate;
      }
    }
  }
  return null;
}

const _oidSignedData = [
  0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, //
];

CredentialFormat _detectJson(String name, Uint8List bytes) {
  if (bytes.length > _maxStructuredTextBytes) return CredentialFormat.unknown;
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return CredentialFormat.unknown;
  }
  if (json is! Map<String, Object?>) return CredentialFormat.unknown;

  if (json['type'] == 'service_account') {
    return CredentialFormat.serviceAccountJson;
  }
  if (json['project_info'] is Map && json['client'] is List) {
    return CredentialFormat.googleServicesJson;
  }
  for (final key in const ['installed', 'web']) {
    final client = json[key];
    if (client is Map && client['client_id'] is String) {
      return CredentialFormat.oauthClientJson;
    }
  }
  return CredentialFormat.unknown;
}

bool _isPlist(Uint8List bytes, String text) =>
    _startsWith(bytes, ascii.encode('bplist00')) ||
    (text.contains('<plist') && text.trimLeft().startsWith('<'));

/// One DER tag-length-value header. Only single-byte tags and definite
/// lengths are accepted, which is all the formats above use at the top.
class _Tlv {
  const _Tlv(this.tag, this.contentStart, this.length);
  final int tag;
  final int contentStart;
  final int length;
  int get end => contentStart + length;
}

_Tlv? _readTlv(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 2 > bytes.length) return null;
  final tag = bytes[offset];
  if (tag & 0x1F == 0x1F) return null;
  var pos = offset + 1;
  final first = bytes[pos++];
  int length;
  if (first < 0x80) {
    length = first;
  } else {
    final count = first & 0x7F;
    if (count == 0 || count > 4 || pos + count > bytes.length) return null;
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[pos++];
    }
  }
  if (pos + length > bytes.length) return null;
  return _Tlv(tag, pos, length);
}

bool _matches(Uint8List bytes, _Tlv tlv, List<int> content) {
  if (tlv.length != content.length) return false;
  for (var i = 0; i < content.length; i++) {
    if (bytes[tlv.contentStart + i] != content[i]) return false;
  }
  return true;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// The first [max] bytes with every non-printable byte replaced, so binary
/// files can be searched for ASCII markers without a decode error.
String _asciiPrefix(Uint8List bytes, int max) {
  final n = bytes.length < max ? bytes.length : max;
  final codes = List<int>.filled(n, 0x20);
  for (var i = 0; i < n; i++) {
    final b = bytes[i];
    if (b == 0x09 || b == 0x0A || b == 0x0D || (b >= 0x20 && b < 0x7F)) {
      codes[i] = b;
    }
  }
  return String.fromCharCodes(codes);
}

String _basename(String filename) {
  final i = filename.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? filename : filename.substring(i + 1);
}

String _extension(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}
