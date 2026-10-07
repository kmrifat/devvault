import 'dart:convert';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart' show ItemType;

import 'der.dart';

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

/// DER/BER structures: CMS SignedData with a plist inside, PKCS#12 (`PFX`
/// version 3) and X.509 certificates.
CredentialFormat? _detectDer(Uint8List bytes) {
  try {
    final outer = Asn1.parse(bytes, allowTrailing: true);
    if (outer.tag != Asn1.tagSequence) return null;
    final parts = outer.children;
    if (parts.isEmpty) return null;
    final first = parts[0];

    // ContentInfo { contentType = signedData, [0] content }
    if (first.tag == Asn1.tagOid && first.oid == _oidSignedData) {
      final text = _asciiPrefix(bytes, bytes.length);
      return text.contains('<plist') || text.contains('bplist00')
          ? CredentialFormat.mobileProvision
          : null;
    }

    // PFX { version INTEGER (3), authSafe ContentInfo, macData? }
    if (first.tag == Asn1.tagInteger &&
        parts.length >= 2 &&
        parts[1].tag == Asn1.tagSequence &&
        first.integer == BigInt.from(3)) {
      return CredentialFormat.pkcs12;
    }

    // Certificate { tbsCertificate, signatureAlgorithm, signatureValue }
    if (first.tag == Asn1.tagSequence &&
        parts.length == 3 &&
        parts[1].tag == Asn1.tagSequence &&
        parts[2].tag == Asn1.tagBitString) {
      final tbs = first.children;
      if (tbs.isNotEmpty &&
          (tbs[0].isContext(0) || tbs[0].tag == Asn1.tagInteger)) {
        return CredentialFormat.x509Certificate;
      }
    }
  } on FormatException {
    return null;
  }
  return null;
}

const _oidSignedData = '1.2.840.113549.1.7.2';

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
