import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cred_parsers/cred_parsers.dart';
import 'package:cred_parsers/src/java_keystore.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

const storePw = 'test-password';
const keyPw = 'key-password';

ParseResult parse(
  String name, {
  Map<String, String> secrets = const {},
  Uint8List? bytes,
}) => CredentialParsers.standard().parse(
  ParseInput(filename: name, bytes: bytes ?? fixture(name), secrets: secrets),
);

String fact(ParseResult r, String key) => r.facts[key]!.value;

/// keytool-style fingerprint of [der].
String fingerprint(Hash hash, List<int> der) => hash
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

const storeRequest = SecretRequest(
  key: JavaKeystoreParser.storePassword,
  label: 'Store password',
);
const storeRejected = SecretRequest(
  key: JavaKeystoreParser.storePassword,
  label: 'Store password',
  rejected: true,
);
const keyRequest = SecretRequest(
  key: JavaKeystoreParser.keyPassword,
  label: 'Key password',
);
const keyRejected = SecretRequest(
  key: JavaKeystoreParser.keyPassword,
  label: 'Key password',
  rejected: true,
);

/// Fingerprints and expiry as `keytool -list -v` prints them for each
/// fixture's private key (see test/fixtures/README.md).
const leaf = {
  'test.jks': (
    sha1: '3D:72:24:2E:3D:D2:66:E2:49:90:A2:EA:82:1C:F5:02:38:0F:5A:9A',
    sha256:
        '32:D4:51:8B:EB:58:4C:4F:1F:2E:99:81:22:C3:A4:00:'
        '2A:E3:97:11:70:36:7D:9A:18:C3:99:45:57:D3:77:31',
    notAfter: '2036-10-04T13:08:52Z',
  ),
  'test.jceks': (
    sha1: '41:F4:B7:24:70:35:71:C5:B6:EE:E2:19:D2:6D:76:FC:8D:D0:35:F0',
    sha256:
        'C8:EB:83:EE:DB:CE:A1:D5:53:30:1D:9B:9D:E6:92:58:'
        'A5:89:E0:F7:E2:61:9A:6C:48:1E:40:03:22:7E:D6:3C',
    notAfter: '2036-10-04T13:09:05Z',
  ),
  'keypass.jks': (
    sha1: '06:07:53:06:4C:4B:5F:7D:9E:BA:CD:90:C9:89:A8:81:5E:12:80:82',
    sha256:
        'B0:BD:B7:59:56:F2:CD:F9:02:88:5E:77:19:47:BD:35:'
        '08:2C:81:1F:19:2C:8E:F3:35:F8:A4:46:A1:5A:75:5A',
    notAfter: '2036-10-04T13:30:57Z',
  ),
  'keypass.jceks': (
    sha1: '7D:0E:66:A4:B4:ED:35:D4:9A:D3:90:C7:4E:1F:76:C2:D3:6D:F1:3E',
    sha256:
        'EF:CA:08:92:5A:B6:74:7E:A3:1E:5E:9D:F3:D6:9D:2B:'
        '65:CA:7F:0E:7E:38:71:B6:4A:F2:55:07:72:D9:EB:36',
    notAfter: '2036-10-04T13:30:59Z',
  ),
  'secret.jceks': (
    sha1: 'C9:F9:AA:FA:CA:A7:69:C4:B6:8D:DE:48:5F:46:6A:F9:9B:59:00:70',
    sha256:
        '14:FB:51:4F:4E:4C:1B:5B:3C:61:98:DF:82:C7:F7:7A:'
        '59:D9:34:A9:50:64:DE:8F:C7:B5:88:1E:99:73:5D:EB',
    notAfter: '2036-10-04T13:35:50Z',
  ),
  'chain.jks': (
    sha1: 'B8:45:B6:2F:0C:3B:F0:81:19:E3:8A:75:4B:7A:CF:0C:51:81:74:96',
    sha256:
        '5E:F4:5B:58:2D:E4:C1:37:45:F6:8B:87:27:EE:7B:FF:'
        '8E:30:D4:71:01:14:F5:AF:AC:3F:EF:72:79:A1:DB:AC',
    notAfter: '2031-10-06T13:31:58Z',
  ),
};

void main() {
  group('JavaKeystore.decode', () {
    test('lists every entry and certificate as keytool does', () {
      // alias → SHA-256 of each certificate in the chain, from keytool.
      const expected = {
        'two-keys.jks': {
          'release': [
            'BA:FE:D4:E2:A6:4E:00:EC:2D:A7:DB:5B:67:59:70:7A:'
                '2B:A2:36:7B:D2:61:D4:65:CD:72:19:DC:AF:40:A0:84',
          ],
          'upload': [
            '38:FE:38:1D:89:52:1C:D7:B9:2E:AB:36:8A:E2:7F:C5:'
                'F0:44:50:9B:00:2C:3F:94:3D:D2:35:F9:30:D7:47:DF',
          ],
        },
        'chain.jks': {
          'upload': [
            '5E:F4:5B:58:2D:E4:C1:37:45:F6:8B:87:27:EE:7B:FF:'
                '8E:30:D4:71:01:14:F5:AF:AC:3F:EF:72:79:A1:DB:AC',
            'E7:83:34:7D:3E:30:65:17:1C:0A:6A:93:16:40:A3:F8:'
                '7D:A2:29:42:65:D2:68:DA:CB:EE:DD:34:36:8A:3D:2C',
          ],
        },
        'trusted.jks': {
          'ca': [
            'FD:7A:15:4E:BA:6C:EE:59:DA:9C:08:23:1B:39:C6:9D:'
                '5D:20:76:2A:9D:36:A0:DA:EE:8C:08:68:96:1C:28:F2',
          ],
        },
        'secret.jceks': {
          'api': <String>[],
          'signing': [
            '14:FB:51:4F:4E:4C:1B:5B:3C:61:98:DF:82:C7:F7:7A:'
                '59:D9:34:A9:50:64:DE:8F:C7:B5:88:1E:99:73:5D:EB',
          ],
        },
      };
      for (final MapEntry(key: name, value: aliases) in expected.entries) {
        final ks = JavaKeystore.decode(fixture(name));
        expect(
          {
            for (final e in ks.entries)
              e.alias: [
                for (final c in e.chain) fingerprint(sha256, c.encoded),
              ],
          },
          aliases,
          reason: name,
        );
        for (final e in ks.entries) {
          for (final c in e.chain) {
            expect(c.type, 'X.509');
          }
        }
      }
    });

    test('reads the entry kinds', () {
      KeystoreEntryKind kindOf(String name, String alias) =>
          JavaKeystore.decode(fixture(name)).entries
              .firstWhere((e) => e.alias == alias)
              .kind;

      expect(kindOf('test.jks', 'upload'), KeystoreEntryKind.privateKey);
      expect(kindOf('trusted.jks', 'ca'), KeystoreEntryKind.trustedCertificate);
      expect(kindOf('secret.jceks', 'api'), KeystoreEntryKind.secretKey);
      expect(kindOf('secret.jceks', 'signing'), KeystoreEntryKind.privateKey);
    });

    test('checks the store password against the integrity digest', () {
      for (final name in ['test.jks', 'test.jceks', 'secret.jceks']) {
        final ks = JavaKeystore.decode(fixture(name));
        expect(ks.checkStorePassword(storePw), isTrue, reason: name);
        expect(ks.checkStorePassword('wrong'), isFalse, reason: name);
        expect(ks.checkStorePassword(''), isFalse, reason: name);
      }
    });

    test('a tampered file fails the store password check', () {
      final bytes = fixture('test.jks');
      final i = latin1.decode(bytes).indexOf('upload');
      bytes[i] = 'U'.codeUnitAt(0);
      final ks = JavaKeystore.decode(bytes);
      expect(ks.entries.single.alias, 'Upload');
      expect(ks.checkStorePassword(storePw), isFalse);
    });

    test('reads version 1 files, which have no certificate types', () {
      // test.jks re-encoded as version 1: drop the "X.509" type string and
      // re-seal the integrity digest.
      final v2 = fixture('test.jks');
      final marker = [0x00, 0x05, ...ascii.encode('X.509')];
      final at = _indexOf(v2, marker);
      final body = [
        ...v2.sublist(0, 4),
        0, 0, 0, 1, // version
        ...v2.sublist(8, at),
        ...v2.sublist(at + marker.length, v2.length - 20),
      ];
      final digest = sha1.convert([
        for (final c in storePw.codeUnits) ...[c >> 8, c & 0xFF],
        ...utf8.encode('Mighty Aphrodite'),
        ...body,
      ]).bytes;
      final ks = JavaKeystore.decode(Uint8List.fromList([...body, ...digest]));
      expect(ks.version, 1);
      expect(ks.checkStorePassword(storePw), isTrue);
      final entry = ks.entries.single;
      expect(
        fingerprint(sha256, entry.chain.single.encoded),
        leaf['test.jks']!.sha256,
      );
      expect(ks.checkKeyPassword(entry, storePw), KeyPasswordCheck.correct);
    });

    test('checks key passwords for both protectors', () {
      for (final name in ['keypass.jks', 'keypass.jceks']) {
        final ks = JavaKeystore.decode(fixture(name));
        final key = ks.entries.single;
        expect(ks.checkKeyPassword(key, keyPw), KeyPasswordCheck.correct);
        expect(ks.checkKeyPassword(key, storePw), KeyPasswordCheck.wrong);
        expect(ks.checkKeyPassword(key, ''), KeyPasswordCheck.wrong);
      }
    });

    test('a non-ASCII password is wrong for a JCEKS key, not an error', () {
      final ks = JavaKeystore.decode(fixture('test.jceks'));
      expect(
        ks.checkKeyPassword(ks.entries.single, 'tést-password'),
        KeyPasswordCheck.wrong,
      );
    });

    test('toString never shows key material', () {
      final ks = JavaKeystore.decode(fixture('test.jks'));
      expect(ks.toString(), 'JavaKeystore(JKS, v2, 1 entries)');
      expect(
        ks.entries.single.toString(),
        'KeystoreEntry(privateKey, upload, 1 cert(s))',
      );
    });

    test('malformed input is a FormatException', () {
      final bytes = fixture('test.jks');
      for (var cut = 0; cut < bytes.length - 20; cut += 7) {
        expect(
          () => JavaKeystore.decode(Uint8List.sublistView(bytes, 0, cut)),
          throwsFormatException,
          reason: 'cut at $cut',
        );
      }
      final badTag = Uint8List.fromList(bytes)..[15] = 9;
      expect(() => JavaKeystore.decode(badTag), throwsFormatException);
      final badVersion = Uint8List.fromList(bytes)..[7] = 3;
      expect(() => JavaKeystore.decode(badVersion), throwsFormatException);
      final hugeCount = Uint8List.fromList(bytes)..[8] = 0x7F;
      expect(() => JavaKeystore.decode(hugeCount), throwsFormatException);
      // A secret-key entry is JCEKS only.
      final secret = fixture('secret.jceks');
      final asJks = Uint8List.fromList(secret)..setRange(0, 4, bytes);
      expect(() => JavaKeystore.decode(asJks), throwsFormatException);
    });
  });

  group('JavaKeystoreParser', () {
    test('lists the certificate without any password', () {
      final r = parse('test.jks');
      expect(r.type, ItemType.androidKeystore);
      expect(r.format, CredentialFormat.jks);
      expect(fact(r, JavaKeystoreParser.storeType), 'JKS');
      expect(fact(r, JavaKeystoreParser.entryCount), '1');
      expect(fact(r, JavaKeystoreParser.alias), 'upload');
      expect(fact(r, JavaKeystoreParser.chainLength), '1');
      expect(r.facts[JavaKeystoreParser.aliases], isNull);
      expect(fact(r, CertificateFields.sha1), leaf['test.jks']!.sha1);
      expect(fact(r, CertificateFields.sha256), leaf['test.jks']!.sha256);
      expect(r.expiresAt, DateTime.parse(leaf['test.jks']!.notAfter));
      // keytool: Owner CN=DevVault Test Upload, serial e3a3d0112d71fb5d.
      expect(fact(r, CertificateFields.commonName), 'DevVault Test Upload');
      expect(
        fact(r, CertificateFields.serialNumber),
        'E3:A3:D0:11:2D:71:FB:5D',
      );
      expect(fact(r, CertificateFields.notAfter), '2036-10-04T13:08:52Z');
      expect(r.facts[CertificateFields.certificateType], isNull);
      expect(r.facts.values.every((f) => f.source == FieldSource.file), isTrue);
      expect(r.secretsNeeded, [storeRequest]);
      expect(r.warnings, isEmpty);
    });

    test('a wrong store password is rejected, facts stay', () {
      final r = parse('test.jks', secrets: {'store_password': 'nope'});
      expect(r.secretsNeeded, [storeRejected]);
      expect(fact(r, CertificateFields.sha256), leaf['test.jks']!.sha256);
    });

    test('the right store password also opens a key that shares it', () {
      final r = parse('test.jks', secrets: {'store_password': storePw});
      expect(r.needsSecrets, isFalse);
      expect(r.warnings, isEmpty);
    });

    for (final name in ['keypass.jks', 'keypass.jceks']) {
      group(name, () {
        test('asks for the key password after the store password', () {
          final r = parse(name, secrets: {'store_password': storePw});
          expect(r.secretsNeeded, [keyRequest]);
          expect(fact(r, CertificateFields.sha256), leaf[name]!.sha256);
        });

        test('a wrong key password is rejected as the key password', () {
          final r = parse(
            name,
            secrets: {'store_password': storePw, 'key_password': 'nope'},
          );
          expect(r.secretsNeeded, [keyRejected]);
        });

        test('a wrong store password is reported as the store password', () {
          final r = parse(
            name,
            secrets: {'store_password': 'nope', 'key_password': keyPw},
          );
          expect(r.secretsNeeded, [storeRejected]);
        });

        test('both passwords right: nothing more to ask', () {
          final r = parse(
            name,
            secrets: {'store_password': storePw, 'key_password': keyPw},
          );
          expect(r.needsSecrets, isFalse);
          expect(r.warnings, isEmpty);
          expect(fact(r, CertificateFields.sha1), leaf[name]!.sha1);
          expect(r.expiresAt, DateTime.parse(leaf[name]!.notAfter));
        });
      });
    }

    test('JCEKS reads the same way', () {
      final none = parse('test.jceks');
      expect(none.format, CredentialFormat.jceks);
      expect(fact(none, JavaKeystoreParser.storeType), 'JCEKS');
      expect(fact(none, JavaKeystoreParser.alias), 'upload');
      expect(fact(none, CertificateFields.sha1), leaf['test.jceks']!.sha1);
      expect(fact(none, CertificateFields.sha256), leaf['test.jceks']!.sha256);
      expect(none.expiresAt, DateTime.parse(leaf['test.jceks']!.notAfter));
      expect(none.secretsNeeded, [storeRequest]);

      final wrong = parse('test.jceks', secrets: {'store_password': 'x'});
      expect(wrong.secretsNeeded, [storeRejected]);

      final right = parse('test.jceks', secrets: {'store_password': storePw});
      expect(right.needsSecrets, isFalse);
    });

    test('the leaf of a certificate chain is the one described', () {
      final r = parse('chain.jks');
      expect(fact(r, JavaKeystoreParser.chainLength), '2');
      expect(fact(r, CertificateFields.sha256), leaf['chain.jks']!.sha256);
      expect(r.expiresAt, DateTime.parse(leaf['chain.jks']!.notAfter));
    });

    test('several keys: aliases listed, nothing chosen for the user', () {
      final r = parse('two-keys.jks');
      expect(r.facts[JavaKeystoreParser.alias], isNull);
      expect(fact(r, JavaKeystoreParser.aliases), 'release, upload');
      expect(fact(r, JavaKeystoreParser.entryCount), '2');
      expect(r.facts[CertificateFields.sha256], isNull);
      expect(r.expiresAt, isNull);
      expect(r.warnings.single, contains('release, upload'));
      expect(r.secretsNeeded, [storeRequest]);
    });

    test('several keys: per-alias password results go to a warning', () {
      final byStore = parse(
        'two-keys.jks',
        secrets: {'store_password': storePw},
      );
      expect(byStore.needsSecrets, isFalse);
      expect(
        byStore.warnings.last,
        'The store password opens the key for upload but not for release.',
      );

      final byKey = parse(
        'two-keys.jks',
        secrets: {'store_password': storePw, 'key_password': keyPw},
      );
      expect(byKey.needsSecrets, isFalse);
      expect(
        byKey.warnings.last,
        'The key password opens the key for release but not for upload.',
      );

      final none = parse(
        'two-keys.jks',
        secrets: {'store_password': storePw, 'key_password': 'nope'},
      );
      expect(none.secretsNeeded, [keyRejected]);
    });

    test('a keystore of trusted certificates only', () {
      final r = parse('trusted.jks');
      expect(r.type, ItemType.androidKeystore);
      expect(fact(r, JavaKeystoreParser.aliases), 'ca');
      expect(r.facts[JavaKeystoreParser.alias], isNull);
      expect(r.expiresAt, isNull);
      expect(r.warnings.single, contains('no private key'));

      final open = parse('trusted.jks', secrets: {'store_password': storePw});
      expect(open.needsSecrets, isFalse);
    });

    test('a JCEKS secret-key entry is listed, the private key described', () {
      final r = parse('secret.jceks', secrets: {'store_password': storePw});
      expect(fact(r, JavaKeystoreParser.entryCount), '2');
      expect(fact(r, JavaKeystoreParser.aliases), 'api, signing');
      expect(fact(r, JavaKeystoreParser.alias), 'signing');
      expect(fact(r, CertificateFields.sha256), leaf['secret.jceks']!.sha256);
      expect(r.expiresAt, DateTime.parse(leaf['secret.jceks']!.notAfter));
      expect(r.needsSecrets, isFalse);
      expect(r.warnings, isEmpty);
    });

    test('magic bytes decide, not the extension', () {
      final r = parse('upload.keystore', bytes: fixture('test.jks'));
      expect(r.format, CredentialFormat.jks);
      expect(fact(r, JavaKeystoreParser.alias), 'upload');
    });

    test('truncated or corrupt files come back generic', () {
      final bytes = fixture('test.jks');
      for (final cut in [4, 12, 40, 200, bytes.length - 21]) {
        final r = parse(
          'test.jks',
          bytes: Uint8List.sublistView(bytes, 0, cut),
          secrets: {'store_password': storePw},
        );
        expect(r.isGeneric, isTrue, reason: 'cut at $cut');
        expect(r.format, CredentialFormat.jks);
        expect(r.facts, isEmpty);
      }
      final corrupt = Uint8List.fromList(fixture('secret.jceks'));
      corrupt[29] = 0x00; // breaks the serialized secret key
      expect(parse('secret.jceks', bytes: corrupt).isGeneric, isTrue);
    });

    test('a damaged digest is a rejected store password, not a crash', () {
      final bytes = Uint8List.fromList(fixture('test.jks'));
      bytes[bytes.length - 1] ^= 0xFF;
      final r = parse(
        'test.jks',
        bytes: bytes,
        secrets: {'store_password': storePw},
      );
      expect(r.secretsNeeded, [storeRejected]);
      expect(fact(r, JavaKeystoreParser.alias), 'upload');
    });

    test('passwords never appear in facts, warnings or toString', () {
      const store = 'store-SECRET-123';
      const key = 'key-SECRET-456';
      for (final name in [
        'test.jks',
        'keypass.jceks',
        'two-keys.jks',
        'trusted.jks',
      ]) {
        for (final secrets in [
          {'store_password': store},
          {'store_password': storePw, 'key_password': key},
          {'store_password': storePw, 'key_password': keyPw},
        ]) {
          final r = parse(name, secrets: secrets);
          final text = [
            r.toString(),
            ...r.warnings,
            ...r.facts.values.map((f) => f.value),
            ...r.secretsNeeded.map((s) => '$s ${s.label}'),
          ].join('\n');
          for (final secret in [store, key, storePw, keyPw]) {
            expect(text, isNot(contains(secret)), reason: '$name $secrets');
          }
        }
      }
    });
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  throw StateError('not found');
}
