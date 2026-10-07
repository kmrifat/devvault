import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

ParseResult parse(String name, {Uint8List? bytes}) =>
    CredentialParsers.standard().parse(
      ParseInput(filename: name, bytes: bytes ?? fixture(name)),
    );

Map<String, String> values(ParseResult r) => {
  for (final MapEntry(:key, :value) in r.facts.entries) key: value.value,
};

void main() {
  group('OpenSSH private keys', () {
    // Expected values are `ssh-keygen -lf <file>` output.
    test('ed25519 without a passphrase: type, size, fingerprint, comment', () {
      final result = parse('id_ed25519');
      expect(result.format, CredentialFormat.sshPrivateKey);
      expect(result.type, ItemType.sshKey);
      expect(values(result), {
        'key_type': 'ED25519',
        'bits': '256',
        'fingerprint': 'SHA256:bQivbEQc59x3qpDO1XWF2t8e6Gq635URk8mrH3HlDaY',
        'comment': 'devvault-test@example',
        'passphrase_protected': 'false',
      });
      expect(result.expiresAt, isNull);
      expect(result.warnings, isEmpty);
    });

    test('ECDSA P-384', () {
      expect(values(parse('id_ecdsa')), {
        'key_type': 'ECDSA',
        'bits': '384',
        'fingerprint': 'SHA256:dKucDqgW0HRsZIraK/Kbst4J06271L0MvYc6o3311X4',
        'comment': 'devvault-ecdsa',
        'passphrase_protected': 'false',
      });
    });

    test('a passphrase hides the comment but not the public facts', () {
      expect(values(parse('id_rsa_encrypted')), {
        'key_type': 'RSA',
        'bits': '3072',
        'fingerprint': 'SHA256:cuO8kpHXjllQP1Z1SG5BHKB83Oysq+7RZenie/xak4I',
        'passphrase_protected': 'true',
      });
    });

    test('is detected whatever the file is called', () {
      expect(
        detectFormat('deploy_key', fixture('id_ed25519')),
        CredentialFormat.sshPrivateKey,
      );
      expect(
        detectFormat('id_ed25519.txt', fixture('id_ed25519')),
        CredentialFormat.sshPrivateKey,
      );
    });

    test('never reports key material', () {
      final text = String.fromCharCodes(fixture('id_ed25519'));
      final body = text.split('\n').skip(1).take(3).join();
      final result = parse('id_ed25519');
      for (final fact in result.facts.values) {
        expect(fact.secret, isFalse);
        expect(body, isNot(contains(fact.value)));
      }
      expect(result.toString(), isNot(contains(body)));
    });

    test('a mangled key falls back to a generic file', () {
      final text = String.fromCharCodes(fixture('id_ed25519'));
      final lines = text.split('\n');
      for (final broken in [
        text.replaceFirst('b3BlbnNzaC1rZXktdjE', 'b3BlbnNzaC1rZXktdjI'),
        [lines.first, lines[1], lines.last].join('\n'),
        '$text$text',
      ]) {
        final result = parse(
          'id_ed25519',
          bytes: Uint8List.fromList(broken.codeUnits),
        );
        expect(result.isGeneric, isTrue);
        expect(result.facts, isEmpty);
      }
    });
  });

  group('PEM bundles', () {
    test('a chain: the leaf is the certificate nobody else was issued by', () {
      final result = parse('chain.pem');
      expect(result.format, CredentialFormat.pemBundle);
      expect(result.type, ItemType.appleCertificate);
      final facts = values(result);
      // `openssl x509 -noout -fingerprint -sha256 -serial -enddate` on the leaf.
      expect(
        facts[CertificateFields.sha256],
        '9D:47:41:27:7D:39:0D:13:E5:94:43:73:72:EE:85:6A:'
        '3E:AC:B6:59:8D:8C:60:C4:BF:D2:45:46:6A:1A:A2:20',
      );
      expect(facts[CertificateFields.serialNumber], '0D:EA:D5');
      expect(facts[CertificateFields.certificateType], 'Apple Distribution');
      expect(facts[CertificateFields.team], 'TESTTEAM01');
      expect(facts[CertificateFields.issuer], 'DevVault Test Bundle CA');
      expect(facts[PemBundleParser.certificateCount], '2');
      expect(facts[PemBundleParser.hasPrivateKey], 'false');
      expect(facts.containsKey(PemBundleParser.privateKeyEncrypted), isFalse);
      expect(result.expiresAt, DateTime.utc(2027, 11, 11, 17, 16, 1));
      expect(result.warnings, isEmpty);
    });

    test('an APNs certificate with its key', () {
      final result = parse('apns.pem');
      expect(result.type, ItemType.appleCertificate);
      final facts = values(result);
      expect(facts[CertificateFields.certificateType], 'Apple Push Services');
      expect(
        facts[CertificateFields.sha256],
        startsWith('46:99:02:FB:BE:6B:12:B6:1A:0D:C2:60'),
      );
      expect(facts[PemBundleParser.hasPrivateKey], 'true');
      expect(facts[PemBundleParser.privateKeyEncrypted], 'false');
      expect(facts[PemBundleParser.certificateCount], '1');
      expect(result.expiresAt, DateTime.utc(2027, 10, 7, 17, 16, 1));
      expect(result.secretsNeeded, isEmpty);
    });

    test('an encrypted key is noticed without asking for its password', () {
      final result = parse('encrypted-key.pem');
      expect(values(result)[PemBundleParser.privateKeyEncrypted], 'true');
      expect(result.secretsNeeded, isEmpty);
      expect(result.type, ItemType.appleCertificate);
    });

    test('two unrelated certificates: no leaf is guessed', () {
      final two = [
        ...fixture('cert.pem'),
        ...String.fromCharCodes(fixture('apns.pem'))
            .split('-----BEGIN PRIVATE KEY-----')
            .first
            .codeUnits,
      ];
      final result = parse('two.pem', bytes: Uint8List.fromList(two));
      expect(result.format, CredentialFormat.pemBundle);
      expect(result.isGeneric, isTrue);
      expect(values(result), {
        PemBundleParser.hasPrivateKey: 'false',
        PemBundleParser.certificateCount: '2',
      });
      expect(result.expiresAt, isNull);
      expect(result.warnings.single, contains("doesn't say which one"));
    });

    test('blocks it doesn\'t read are kept and mentioned', () {
      final withExtra = [
        ...fixture('apns.pem'),
        ...'-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n'
            .codeUnits,
      ];
      final result = parse('extra.pem', bytes: Uint8List.fromList(withExtra));
      expect(result.type, ItemType.appleCertificate);
      expect(result.warnings.single, contains('1 other PEM block'));
    });

    test('a corrupt certificate falls back to a generic file', () {
      final text = String.fromCharCodes(fixture('chain.pem'));
      final result = parse(
        'chain.pem',
        bytes: Uint8List.fromList(text.replaceFirst('MII', 'MIX').codeUnits),
      );
      expect(result.isGeneric, isTrue);
      expect(result.facts, isEmpty);
    });
  });
}
