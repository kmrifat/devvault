import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vault_core/vault_core.dart';

import 'der.dart';

/// The parts of an X.509 certificate DevVault shows. Read from the DER; no
/// signature or chain is verified.
class X509Certificate {
  X509Certificate._({
    required this.der,
    required this.commonName,
    required this.organizationalUnit,
    required this.organization,
    required this.serialNumber,
    required this.notBefore,
    required this.notAfter,
    required this.sha1Fingerprint,
    required this.sha256Fingerprint,
    required this.subject,
    required this.issuer,
    required this.issuerCommonName,
    required this.extensionOids,
  });

  /// Parses one DER certificate. Throws [FormatException] if it isn't one.
  static X509Certificate parse(Uint8List der) {
    final cert = Asn1.parse(der).expect(Asn1.tagSequence);
    if (cert.children.length != 3) {
      throw const FormatException('Certificate must have three parts');
    }
    final tbs = cert[0].expect(Asn1.tagSequence);
    cert[1].expect(Asn1.tagSequence);
    cert[2].bits;

    final fields = tbs.children;
    var i = 0;
    if (fields.isNotEmpty && fields[0].isContext(0)) i++; // [0] version
    if (fields.length < i + 6) {
      throw const FormatException('TBSCertificate is too short');
    }
    final serial = fields[i].expect(Asn1.tagInteger);
    fields[i + 1].expect(Asn1.tagSequence); // signature algorithm
    final issuer = _Name.parse(fields[i + 2]);
    final validity = fields[i + 3].expect(Asn1.tagSequence);
    final subject = _Name.parse(fields[i + 4]);
    fields[i + 5].expect(Asn1.tagSequence); // subjectPublicKeyInfo

    final extensionOids = <String>{};
    for (final field in fields.skip(i + 6)) {
      if (!field.isContext(3)) continue;
      for (final ext in field.explicit(3).expect(Asn1.tagSequence).children) {
        extensionOids.add(ext.expect(Asn1.tagSequence)[0].oid);
      }
    }

    return X509Certificate._(
      der: Uint8List.fromList(der),
      commonName: subject.first(_oidCommonName),
      organizationalUnit: subject.first(_oidOrganizationalUnit),
      organization: subject.first(_oidOrganization),
      serialNumber: _hex(_unsigned(serial.content)),
      notBefore: validity[0].time,
      notAfter: validity[1].time,
      sha1Fingerprint: _hex(sha1.convert(der).bytes),
      sha256Fingerprint: _hex(sha256.convert(der).bytes),
      subject: subject.display,
      issuer: issuer.display,
      issuerCommonName: issuer.first(_oidCommonName),
      extensionOids: Set.unmodifiable(extensionOids),
    );
  }

  /// The DER bytes the fingerprints are taken over.
  final Uint8List der;

  final String? commonName;
  final String? organizationalUnit;
  final String? organization;

  /// Upper-case hex, colon-separated, without a DER sign byte.
  final String serialNumber;

  /// Validity, in UTC.
  final DateTime notBefore;
  final DateTime notAfter;

  /// Upper-case hex, colon-separated, as `openssl x509 -fingerprint` and
  /// `keytool -list -v` print them.
  final String sha1Fingerprint;
  final String sha256Fingerprint;

  /// RFC 4514-style display strings, most specific attribute first.
  final String subject;
  final String issuer;
  final String? issuerCommonName;

  /// OIDs of the certificate's extensions.
  final Set<String> extensionOids;

  /// What kind of Apple certificate this is, from the common-name prefix
  /// Apple gives it, or failing that from Apple's marker extensions.
  /// `null` when the certificate carries neither.
  AppleCertificateType? get appleType {
    final cn = commonName;
    if (cn != null) {
      for (final type in AppleCertificateType.values) {
        if (type.prefixes.any(cn.startsWith)) return type;
      }
    }
    for (final type in AppleCertificateType.values) {
      if (type.oids.any(extensionOids.contains)) return type;
    }
    return null;
  }

  @override
  String toString() => 'X509Certificate($subject, $sha256Fingerprint)';
}

/// Apple certificate kinds, each recognised by the common-name prefix
/// Apple's portal issues it with and by its Apple marker extension.
enum AppleCertificateType {
  development('Apple Development', ['Apple Development:'], []),
  distribution('Apple Distribution', ['Apple Distribution:'], []),
  iosDevelopment(
    'iOS Development',
    ['iPhone Developer:'],
    ['1.2.840.113635.100.6.1.2'],
  ),
  iosDistribution(
    'iOS Distribution',
    ['iPhone Distribution:'],
    ['1.2.840.113635.100.6.1.4'],
  ),
  macDevelopment(
    'Mac Development',
    ['Mac Developer:'],
    ['1.2.840.113635.100.6.1.12'],
  ),
  macAppDistribution('Mac App Distribution', [
    '3rd Party Mac Developer Application:',
  ], []),
  macInstallerDistribution('Mac Installer Distribution', [
    '3rd Party Mac Developer Installer:',
  ], []),
  developerIdApplication(
    'Developer ID Application',
    ['Developer ID Application:'],
    ['1.2.840.113635.100.6.1.13'],
  ),
  developerIdInstaller(
    'Developer ID Installer',
    ['Developer ID Installer:'],
    ['1.2.840.113635.100.6.1.14'],
  ),
  pushServices('Apple Push Services', ['Apple Push Services:'], []),
  pushDevelopment(
    'APNs Development',
    ['Apple Development IOS Push Services:'],
    ['1.2.840.113635.100.6.3.1'],
  ),
  pushProduction(
    'APNs Production',
    ['Apple Production IOS Push Services:'],
    ['1.2.840.113635.100.6.3.2'],
  ),
  passTypeId('Pass Type ID', ['Pass Type ID:'], []),
  websitePushId('Website Push ID', ['Website Push ID:'], []);

  const AppleCertificateType(this.label, this.prefixes, this.oids);

  final String label;
  final List<String> prefixes;
  final List<String> oids;
}

/// Field keys for certificate facts, shared by every parser that reads
/// certificates (.cer, .p12, keystores).
abstract final class CertificateFields {
  static const commonName = 'common_name';

  /// The subject OU of an Apple certificate, which is the Team ID.
  static const team = 'team_id';

  /// The subject OU of any other certificate.
  static const organizationalUnit = 'organizational_unit';
  static const organization = 'organization';
  static const issuer = 'issuer';
  static const serialNumber = 'serial_number';
  static const notBefore = 'not_before';
  static const notAfter = 'not_after';
  static const sha1 = 'sha1';
  static const sha256 = 'sha256';
  static const certificateType = 'certificate_type';
}

final _teamId = RegExp(r'^[A-Z0-9]{10}$');

/// Facts for [cert], all with [FieldSource.file]. Dates are ISO-8601 UTC.
/// The OU is only called a Team ID on an Apple certificate whose OU has
/// the Team ID shape.
Map<String, ItemField> certificateFacts(X509Certificate cert) {
  ItemField fact(String value) =>
      ItemField(value: value, source: FieldSource.file);
  final appleType = cert.appleType;
  final ou = cert.organizationalUnit;
  final ouIsTeam = appleType != null && ou != null && _teamId.hasMatch(ou);
  return {
    if (cert.commonName case final cn?) CertificateFields.commonName: fact(cn),
    if (ou != null)
      ouIsTeam ? CertificateFields.team : CertificateFields.organizationalUnit:
          fact(ou),
    if (cert.organization case final o?)
      CertificateFields.organization: fact(o),
    if (cert.issuerCommonName case final issuer?)
      CertificateFields.issuer: fact(issuer),
    CertificateFields.serialNumber: fact(cert.serialNumber),
    CertificateFields.notBefore: fact(formatTimestamp(cert.notBefore)),
    CertificateFields.notAfter: fact(formatTimestamp(cert.notAfter)),
    CertificateFields.sha1: fact(cert.sha1Fingerprint),
    CertificateFields.sha256: fact(cert.sha256Fingerprint),
    if (appleType != null)
      CertificateFields.certificateType: fact(appleType.label),
  };
}

const _oidCommonName = '2.5.4.3';
const _oidOrganization = '2.5.4.10';
const _oidOrganizationalUnit = '2.5.4.11';

const _shortNames = {
  '2.5.4.3': 'CN',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '0.9.2342.19200300.100.1.1': 'UID',
  '1.2.840.113549.1.9.1': 'emailAddress',
};

/// A distinguished name: SEQUENCE OF SET OF { type OID, value }.
class _Name {
  _Name(this.attributes);

  factory _Name.parse(Asn1 name) => _Name([
    for (final rdn in name.expect(Asn1.tagSequence).children)
      for (final attr in rdn.expect(Asn1.tagSet).children)
        (attr.expect(Asn1.tagSequence)[0].oid, attr[1].string),
  ]);

  final List<(String, String)> attributes;

  String? first(String oid) {
    for (final (type, value) in attributes) {
      if (type == oid) return value;
    }
    return null;
  }

  String get display => attributes.reversed
      .map((a) => '${_shortNames[a.$1] ?? a.$1}=${_escape(a.$2)}')
      .join(', ');

  static String _escape(String value) =>
      value.replaceAllMapped(RegExp(r'[,+"\\<>;]'), (m) => '\\${m[0]}');
}

List<int> _unsigned(Uint8List bytes) =>
    bytes.length > 1 && bytes[0] == 0 ? bytes.sublist(1) : bytes;

String _hex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');
