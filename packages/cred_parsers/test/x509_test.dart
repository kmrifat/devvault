import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

ParseResult parse(String name) => CredentialParsers.standard().parse(
  ParseInput(filename: name, bytes: fixture(name)),
);

String fact(ParseResult r, String key) => r.facts[key]!.value;

void main() {
  group('X509Certificate', () {
    // Expected values are `openssl x509 -noout -serial -fingerprint
    // -sha1/-sha256 -startdate -enddate` output for each fixture.
    test('matches openssl for cert.cer', () {
      final cert = X509Certificate.parse(fixture('cert.cer'));
      expect(
        cert.sha1Fingerprint,
        '4E:9E:E4:74:92:22:82:F8:8D:52:21:8C:23:84:30:4C:FC:63:42:55',
      );
      expect(
        cert.sha256Fingerprint,
        'FD:7A:15:4E:BA:6C:EE:59:DA:9C:08:23:1B:39:C6:9D:'
        '5D:20:76:2A:9D:36:A0:DA:EE:8C:08:68:96:1C:28:F2',
      );
      expect(
        cert.serialNumber.replaceAll(':', ''),
        '2E9792BED9BF2D9110D2245020DB795D9618CD95',
      );
      expect(cert.notBefore, DateTime.utc(2026, 10, 7, 13, 8, 52));
      expect(cert.notAfter, DateTime.utc(2036, 10, 4, 13, 8, 52));
      expect(cert.commonName, 'DevVault Test Certificate');
      expect(cert.organizationalUnit, 'TESTTEAM01');
      expect(cert.organization, 'DevVault Tests');
      expect(
        cert.subject,
        'O=DevVault Tests, OU=TESTTEAM01, CN=DevVault Test Certificate',
      );
      expect(cert.appleType, isNull);
    });

    test('matches openssl for an Apple-style certificate', () {
      final cert = X509Certificate.parse(fixture('apple_development.cer'));
      expect(
        cert.sha1Fingerprint,
        '28:7D:5F:BF:40:5D:6F:E1:11:F1:70:7E:73:28:B3:9D:AF:E7:BF:82',
      );
      expect(cert.notAfter, DateTime.utc(2027, 10, 7, 13, 29, 20));
      expect(cert.appleType, AppleCertificateType.development);
      expect(cert.subject, startsWith('C=US, O=DevVault Tests'));
    });

    test('reads GeneralizedTime past 2049 and Apple marker extensions', () {
      final cert = X509Certificate.parse(fixture('developer_id_oid.cer'));
      expect(cert.notAfter, DateTime.utc(2126, 9, 13, 13, 29, 20));
      expect(
        cert.sha256Fingerprint,
        startsWith('DF:01:6C:9C:B8:A1:F8:6B:01:7B:4E:36'),
      );
      expect(cert.extensionOids, contains('1.2.840.113635.100.6.1.13'));
      expect(cert.appleType, AppleCertificateType.developerIdApplication);
    });

    test('every Apple type has a common-name prefix', () {
      for (final type in AppleCertificateType.values) {
        expect(type.prefixes, isNotEmpty, reason: type.name);
        expect(type.prefixes.every((p) => p.endsWith(':')), isTrue);
      }
    });

    test('rejects anything that is not a certificate', () {
      for (final name in ['cert.p12', 'test.mobileprovision']) {
        expect(
          () => X509Certificate.parse(fixture(name)),
          throwsFormatException,
        );
      }
    });
  });

  group('X509CertificateParser', () {
    test('an Apple certificate imports as one, OU as the Team ID', () {
      final result = parse('apple_development.cer');
      expect(result.type, ItemType.appleCertificate);
      expect(
        fact(result, CertificateFields.certificateType),
        'Apple Development',
      );
      expect(fact(result, CertificateFields.team), 'TESTTEAM01');
      expect(
        fact(result, CertificateFields.commonName),
        'Apple Development: DevVault Test (TESTTEAM01)',
      );
      expect(fact(result, CertificateFields.notAfter), '2027-10-07T13:29:20Z');
      expect(result.expiresAt, DateTime.utc(2027, 10, 7, 13, 29, 20));
      expect(result.warnings, isEmpty);
      expect(
        result.facts.values.every(
          (f) => f.source == FieldSource.file && !f.secret,
        ),
        isTrue,
      );
    });

    test('an Apple marker extension alone is enough', () {
      final result = parse('developer_id_oid.cer');
      expect(result.type, ItemType.appleCertificate);
      expect(
        fact(result, CertificateFields.certificateType),
        'Developer ID Application',
      );
    });

    test('any other certificate keeps its facts but is a generic file', () {
      final result = parse('cert.cer');
      expect(result.type, ItemType.genericFile);
      expect(result.format, CredentialFormat.x509Certificate);
      expect(result.facts[CertificateFields.certificateType], isNull);
      expect(result.facts[CertificateFields.team], isNull);
      expect(fact(result, CertificateFields.organizationalUnit), 'TESTTEAM01');
      expect(result.expiresAt, DateTime.utc(2036, 10, 4, 13, 8, 52));
      expect(result.warnings.single, contains('generic file'));
    });

    test('PEM and DER give the same facts', () {
      expect(parse('cert.pem').facts, parse('cert.cer').facts);
    });

    test('several PEM blocks go to the PEM bundle parser instead', () {
      final pem = File('test/fixtures/cert.pem').readAsStringSync();
      final result = CredentialParsers.standard().parse(
        ParseInput(
          filename: 'chain.pem',
          bytes: Uint8List.fromList('$pem$pem'.codeUnits),
        ),
      );
      // The same certificate twice: one leaf, read as such
      // (see pem_bundle_test.dart for real chains).
      expect(result.format, CredentialFormat.pemBundle);
      expect(
        result.facts[CertificateFields.sha256],
        parse('cert.pem').facts[CertificateFields.sha256],
      );
    });
  });
}
