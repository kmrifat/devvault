import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:cred_parsers/src/pkcs12.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// openssl-style SHA-256 fingerprint of [der].
String fingerprint(Uint8List der) => SHA256Digest()
    .process(der)
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

const password = 'test-password';

ParseResult parse(String name, [String? password]) =>
    CredentialParsers.standard().parse(
      ParseInput(
        filename: name,
        bytes: fixture(name),
        secrets: {'password': ?password},
      ),
    );

Map<String, String> values(ParseResult result) => {
  for (final MapEntry(:key, :value) in result.facts.entries) key: value.value,
};

/// `openssl x509 -noout -fingerprint -sha256` of the Apple-style leaf in
/// every fixture except `cert.p12`.
const leafSha256 =
    'FD:5B:8D:FF:E4:2D:26:46:AA:87:4B:E6:12:F1:6B:4E:'
    '13:67:D3:D8:97:A8:84:38:16:F7:C0:37:A6:9B:D3:56';

/// The same for the test CA in `chain*.p12`.
const caSha256 =
    'CF:15:E1:65:51:1F:04:1C:96:EB:EA:8E:B7:22:6E:5B:'
    '17:5F:ED:76:80:3B:65:70:00:5D:02:D8:F3:C5:C8:90';

/// The same for `cert.pem`, the certificate in `cert.p12`.
const certPemSha256 =
    'FD:7A:15:4E:BA:6C:EE:59:DA:9C:08:23:1B:39:C6:9D:'
    '5D:20:76:2A:9D:36:A0:DA:EE:8C:08:68:96:1C:28:F2';

void main() {
  group('Pkcs12Contents.read', () {
    test('OpenSSL 3 default: PBES2/AES-256, HMAC-SHA256', () {
      final p12 = Pkcs12Contents.read(fixture('cert.p12'), password);
      expect(p12.hasMac, isTrue);
      expect(p12.certificates, hasLength(1));
      expect(fingerprint(p12.certificates.single.der), certPemSha256);
      expect(p12.hasPrivateKey, isTrue);
      expect(p12.keys.single.shrouded, isTrue);
      expect(fingerprint(p12.leaf!.der), certPemSha256);
    });

    test('-legacy: RC2-40 certificates, 3DES key, HMAC-SHA1', () {
      final p12 = Pkcs12Contents.read(fixture('legacy.p12'), password);
      expect(p12.hasMac, isTrue);
      expect(fingerprint(p12.certificates.single.der), leafSha256);
      expect(p12.certificates.single.friendlyName, 'DevVault Test');
      expect(p12.hasPrivateKey, isTrue);
      expect(fingerprint(p12.leaf!.der), leafSha256);
    });

    test('3DES certificates (as Keychain exports)', () {
      final p12 = Pkcs12Contents.read(fixture('3des.p12'), password);
      expect(fingerprint(p12.certificates.single.der), leafSha256);
      expect(p12.hasPrivateKey, isTrue);
    });

    test('an empty password', () {
      final p12 = Pkcs12Contents.read(fixture('empty-password.p12'), '');
      expect(fingerprint(p12.leaf!.der), leafSha256);
    });

    test('no MAC: the password is checked by decrypting', () {
      final p12 = Pkcs12Contents.read(fixture('nomac.p12'), password);
      expect(p12.hasMac, isFalse);
      expect(fingerprint(p12.leaf!.der), leafSha256);
      expect(
        () => Pkcs12Contents.read(fixture('nomac.p12'), 'wrong'),
        throwsA(isA<Pkcs12PasswordException>()),
      );
    });

    test('a wrong password fails the MAC, for every fixture', () {
      for (final name in [
        'cert.p12',
        'legacy.p12',
        '3des.p12',
        'chain.p12',
        'empty-password.p12',
      ]) {
        expect(
          () => Pkcs12Contents.read(fixture(name), 'wrong'),
          throwsA(isA<Pkcs12PasswordException>()),
          reason: name,
        );
      }
      expect(
        () => Pkcs12Contents.read(fixture('cert.p12'), ''),
        throwsA(isA<Pkcs12PasswordException>()),
      );
    });

    test('a truncated file is malformed, not a password problem', () {
      final bytes = fixture('cert.p12');
      for (final cut in [0, 1, 10, 100, bytes.length - 1]) {
        expect(
          () => Pkcs12Contents.read(
            Uint8List.sublistView(bytes, 0, cut),
            password,
          ),
          throwsFormatException,
          reason: '$cut',
        );
      }
    });
  });

  group('leaf', () {
    test('is the certificate paired with the key by localKeyId', () {
      final p12 = Pkcs12Contents.read(fixture('chain.p12'), password);
      expect(p12.certificates.map((c) => fingerprint(c.der)), [
        leafSha256,
        caSha256,
      ]);
      expect(fingerprint(p12.leaf!.der), leafSha256);
    });

    test('without a key, is the one that issued no other certificate', () {
      final p12 = Pkcs12Contents.read(fixture('chain-nokey.p12'), password);
      expect(p12.hasPrivateKey, isFalse);
      expect(p12.certificates.every((c) => c.localKeyId == null), isTrue);
      expect(fingerprint(p12.leaf!.der), leafSha256);
    });

    test('is null when two unrelated certificates could be it', () {
      final p12 = Pkcs12Contents.read(fixture('two-certs.p12'), password);
      expect(p12.certificates, hasLength(2));
      expect(p12.leaf, isNull);
    });
  });

  group('Pkcs12Parser', () {
    // Expected values are from `openssl pkcs12 -info` and
    // `openssl x509 -noout -subject -issuer -serial -dates -fingerprint`.
    const appleLeaf = {
      'common_name': 'Apple Development: DevVault Test (TESTTEAM01)',
      'team_id': 'TESTTEAM01',
      'organization': 'DevVault Tests',
      'issuer': 'DevVault Test CA',
      'serial_number': '1A:2B:3C:4D:5E:6F',
      'not_before': '2026-10-07T00:00:00Z',
      'not_after': '2027-10-07T00:00:00Z',
      'sha1': '89:AF:82:5A:C8:62:1F:06:4A:50:52:07:50:0C:6C:3D:C3:D9:60:52',
      'sha256': leafSha256,
      'certificate_type': 'Apple Development',
    };

    test('is registered for PKCS#12', () {
      expect(
        CredentialParsers.standard().supportedFormats,
        contains(CredentialFormat.pkcs12),
      );
    });

    test('OpenSSL 3 default file: the certificate and its key', () {
      final result = parse('cert.p12', password);
      // Its leaf has no Apple marker, so it keeps its facts as a generic
      // file, the same as cert.cer.
      expect(result.type, ItemType.genericFile);
      expect(result.format, CredentialFormat.pkcs12);
      expect(result.needsSecrets, isFalse);
      expect(values(result), {
        'common_name': 'DevVault Test Certificate',
        // Not an Apple certificate, so the OU isn't called a Team ID.
        'organizational_unit': 'TESTTEAM01',
        'organization': 'DevVault Tests',
        'issuer': 'DevVault Test Certificate',
        'serial_number':
            '2E:97:92:BE:D9:BF:2D:91:10:D2:24:50:20:DB:79:5D:96:18:CD:95',
        'not_before': '2026-10-07T13:08:52Z',
        'not_after': '2036-10-04T13:08:52Z',
        'sha1': '4E:9E:E4:74:92:22:82:F8:8D:52:21:8C:23:84:30:4C:FC:63:42:55',
        'sha256': certPemSha256,
        'has_private_key': 'true',
        'certificate_count': '1',
      });
      expect(result.expiresAt, DateTime.utc(2036, 10, 4, 13, 8, 52));
      expect(result.warnings.single, contains('generic file'));
    });

    for (final name in ['legacy.p12', '3des.p12', 'nomac.p12']) {
      test('$name: the Apple leaf, expiring at notAfter', () {
        final result = parse(name, password);
        expect(result.type, ItemType.appleCertificate);
        expect(values(result), {
          ...appleLeaf,
          'has_private_key': 'true',
          'certificate_count': '1',
        });
        expect(result.expiresAt, DateTime.utc(2027, 10, 7));
        expect(result.warnings, isEmpty);
      });
    }

    test('every fact comes from the file', () {
      final result = parse('legacy.p12', password);
      expect(
        result.facts.values.every((f) => f.source == FieldSource.file),
        isTrue,
      );
      expect(result.facts.values.any((f) => f.secret), isFalse);
    });

    test('no password: asks for one, reads nothing', () {
      for (final name in ['cert.p12', 'legacy.p12', 'chain.p12']) {
        final result = parse(name);
        expect(result.type, ItemType.appleCertificate, reason: name);
        expect(result.format, CredentialFormat.pkcs12);
        expect(result.secretsNeeded, [
          const SecretRequest(key: 'password', label: 'Password'),
        ]);
        expect(result.facts, isEmpty);
        expect(result.expiresAt, isNull);
      }
    });

    test('a wrong password is rejected, and never repeated back', () {
      const wrong = 'hunter2-SECRET';
      for (final name in ['cert.p12', 'legacy.p12', 'nomac.p12']) {
        final result = parse(name, wrong);
        expect(result.secretsNeeded, [
          const SecretRequest(
            key: 'password',
            label: 'Password',
            rejected: true,
          ),
        ], reason: name);
        expect(result.facts, isEmpty);
        expect(result.toString(), isNot(contains('hunter2')));
        expect(result.warnings.join(), isNot(contains('hunter2')));
      }
      // An empty password typed in is still a password the file rejected.
      expect(parse('cert.p12', '').secretsNeeded.single.rejected, isTrue);
    });

    test('the right password is never repeated back either', () {
      final result = parse('legacy.p12', password);
      expect(result.toString(), isNot(contains(password)));
      expect(
        result.facts.values.map((f) => f.value),
        isNot(contains(password)),
      );
    });

    test('an empty password is tried first, so no prompt is needed', () {
      final result = parse('empty-password.p12');
      expect(result.needsSecrets, isFalse);
      expect(values(result)['sha256'], leafSha256);
      expect(result.expiresAt, DateTime.utc(2027, 10, 7));
      expect(
        parse('empty-password.p12', 'x').secretsNeeded.single.rejected,
        isTrue,
      );
    });

    test('a chain: the leaf is the certificate paired with the key', () {
      final result = parse('chain.p12', password);
      expect(values(result), {
        ...appleLeaf,
        'has_private_key': 'true',
        'certificate_count': '2',
      });
      expect(result.expiresAt, DateTime.utc(2027, 10, 7));
    });

    test('a chain without a key: the leaf is the one that issued nothing', () {
      final result = parse('chain-nokey.p12', password);
      expect(values(result), {
        ...appleLeaf,
        'has_private_key': 'false',
        'certificate_count': '2',
      });
      expect(result.expiresAt, DateTime.utc(2027, 10, 7));
    });

    test('two unrelated certificates: no leaf is guessed', () {
      final result = parse('two-certs.p12', password);
      expect(result.type, ItemType.genericFile);
      expect(values(result), {
        'has_private_key': 'false',
        'certificate_count': '2',
      });
      expect(result.expiresAt, isNull);
      expect(result.warnings.single, contains('2 certificates'));
    });

    test('truncated or damaged files import as generic files', () {
      final bytes = fixture('cert.p12');
      for (final cut in [1, 64, bytes.length ~/ 2, bytes.length - 1]) {
        final result = CredentialParsers.standard().parse(
          ParseInput(
            filename: 'cert.p12',
            bytes: Uint8List.sublistView(bytes, 0, cut),
            secrets: const {'password': password},
          ),
        );
        expect(result.facts, isEmpty, reason: '$cut');
        expect(result.expiresAt, isNull);
      }
      // A valid structure with an unsupported integrity mode.
      final copy = Uint8List.fromList(bytes);
      final oid = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01];
      final at = _indexOf(copy, oid);
      copy[at + oid.length - 1] = 0x02; // data -> signedData
      final result = CredentialParsers.standard().parse(
        ParseInput(
          filename: 'cert.p12',
          bytes: copy,
          secrets: const {'password': password},
        ),
      );
      expect(result.isGeneric, isTrue);
      expect(result.format, CredentialFormat.pkcs12);
      expect(result.warnings.single, contains('could not be read'));
    });

    test('runs in an isolate', () async {
      final result = await CredentialParsers.standard().parseInIsolate(
        ParseInput(
          filename: 'legacy.p12',
          bytes: fixture('legacy.p12'),
          secrets: const {'password': password},
        ),
      );
      expect(values(result)['sha256'], leafSha256);
    });
  });
}

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  throw StateError('not found');
}
