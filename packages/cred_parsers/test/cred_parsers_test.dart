import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

ParseInput input(String name, [Map<String, String> secrets = const {}]) =>
    ParseInput(filename: name, bytes: fixture(name), secrets: secrets);

/// Stands in for a real parser, so the framework's behaviour around one
/// can be tested before P1-12+ land.
class _FakeParser implements CredentialParser {
  _FakeParser(this.formats, this.onParse);

  @override
  final Set<CredentialFormat> formats;
  final ParseResult Function(ParseInput, CredentialFormat) onParse;

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) =>
      onParse(input, format);
}

void main() {
  test('recognises the credential file types from the plan', () {
    expect(
      knownExtensions,
      containsAll(['p8', 'p12', 'mobileprovision', 'jks']),
    );
  });

  group('detectFormat', () {
    const expected = {
      'AuthKey_TESTKEY123.p8': CredentialFormat.appleAuthKey,
      'cert.pem': CredentialFormat.x509Certificate,
      'cert.cer': CredentialFormat.x509Certificate,
      'cert.p12': CredentialFormat.pkcs12,
      'test.mobileprovision': CredentialFormat.mobileProvision,
      'test.jks': CredentialFormat.jks,
      'test.jceks': CredentialFormat.jceks,
      'google-services.json': CredentialFormat.googleServicesJson,
      'GoogleService-Info.plist': CredentialFormat.googleServiceInfoPlist,
      'service-account.json': CredentialFormat.serviceAccountJson,
      'client_secret_000000000000-test.apps.googleusercontent.com.json':
          CredentialFormat.oauthClientJson,
    };
    for (final MapEntry(key: name, value: format) in expected.entries) {
      test('$name is ${format.name}', () {
        expect(detectFormat(name, fixture(name)), format);
      });
    }

    test('magic bytes win over the extension', () {
      expect(
        detectFormat('upload.keystore', fixture('test.jks')),
        CredentialFormat.jks,
      );
      expect(
        detectFormat('release.bin', fixture('test.jceks')),
        CredentialFormat.jceks,
      );
      expect(
        detectFormat('renamed.dat', fixture('cert.p12')),
        CredentialFormat.pkcs12,
      );
      expect(
        detectFormat('profile', fixture('test.mobileprovision')),
        CredentialFormat.mobileProvision,
      );
      expect(
        detectFormat('cert.txt', fixture('cert.cer')),
        CredentialFormat.x509Certificate,
      );
    });

    test('a directory in the filename is ignored', () {
      expect(
        detectFormat(
          '/Users/me/Keys/AuthKey_TESTKEY123.p8',
          fixture('AuthKey_TESTKEY123.p8'),
        ),
        CredentialFormat.appleAuthKey,
      );
    });

    test('a PKCS#8 key is only an Apple auth key when it is a .p8', () {
      expect(
        detectFormat('server.key', fixture('AuthKey_TESTKEY123.p8')),
        CredentialFormat.unknown,
      );
    });

    test('the extension alone never decides the format', () {
      final noise = Uint8List.fromList(List.generate(64, (i) => i));
      for (final ext in knownExtensions) {
        expect(
          detectFormat('file.$ext', noise),
          CredentialFormat.unknown,
          reason: ext,
        );
      }
      expect(
        detectFormat('AuthKey_ABC.p8', Uint8List(0)),
        CredentialFormat.unknown,
      );
    });

    test('unrelated JSON and plists are unknown', () {
      Uint8List text(String s) => Uint8List.fromList(s.codeUnits);
      expect(
        detectFormat('package.json', text('{"name": "x"}')),
        CredentialFormat.unknown,
      );
      expect(
        detectFormat('list.json', text('[1, 2]')),
        CredentialFormat.unknown,
      );
      expect(
        detectFormat('bad.json', text('{"type": ')),
        CredentialFormat.unknown,
      );
      expect(
        detectFormat(
          'Info.plist',
          text('<?xml version="1.0"?><plist><dict></dict></plist>'),
        ),
        CredentialFormat.unknown,
      );
    });

    test('formats map to the item types in SPEC §6.5', () {
      expect(CredentialFormat.appleAuthKey.itemType, ItemType.appleAuthKey);
      expect(
        CredentialFormat.mobileProvision.itemType,
        ItemType.provisioningProfile,
      );
      expect(CredentialFormat.jks.itemType, ItemType.androidKeystore);
      expect(
        CredentialFormat.serviceAccountJson.itemType,
        ItemType.gcpServiceAccount,
      );
      expect(CredentialFormat.unknown.itemType, ItemType.genericFile);
      for (final format in CredentialFormat.values) {
        expect(format.itemType, isNot(ItemType.genericSecret));
      }
    });
  });

  group('CredentialParsers.parse', () {
    test('unknown input is a generic file with no facts or warnings', () {
      final result = CredentialParsers.standard().parse(
        ParseInput(
          filename: 'notes.txt',
          bytes: Uint8List.fromList('hello'.codeUnits),
        ),
      );
      expect(result.type, ItemType.genericFile);
      expect(result.format, CredentialFormat.unknown);
      expect(result.facts, isEmpty);
      expect(result.expiresAt, isNull);
      expect(result.secretsNeeded, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('a known format without a parser says so and stays generic', () {
      final result = CredentialParsers(const []).parse(input('test.jks'));
      expect(result.isGeneric, isTrue);
      expect(result.format, CredentialFormat.jks);
      expect(result.facts, isEmpty);
      expect(result.warnings.single, contains('Java KeyStore'));
    });

    test('runs the parser registered for the detected format', () {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.appleAuthKey}, (input, format) {
          return ParseResult(
            type: ItemType.appleAuthKey,
            format: format,
            facts: {
              'key_id': const ItemField(
                value: 'TESTKEY123',
                source: FieldSource.file,
              ),
            },
          );
        }),
      ]);
      expect(parsers.supportedFormats, {CredentialFormat.appleAuthKey});
      final result = parsers.parse(input('AuthKey_TESTKEY123.p8'));
      expect(result.type, ItemType.appleAuthKey);
      expect(result.facts['key_id']!.value, 'TESTKEY123');
    });

    test('a parser that throws becomes a generic file, quoting nothing', () {
      const secret = 'hunter2-SECRET';
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.pkcs12}, (input, format) {
          throw FormatException('bad MAC for ${input.secrets['password']}');
        }),
      ]);
      final result = parsers.parse(input('cert.p12', {'password': secret}));
      expect(result.isGeneric, isTrue);
      expect(result.format, CredentialFormat.pkcs12);
      expect(result.facts, isEmpty);
      expect(result.warnings.single, contains('could not be read'));
      expect(result.warnings.join(), isNot(contains(secret)));
      expect(result.toString(), isNot(contains(secret)));
    });

    test('Errors as well as Exceptions are caught', () {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.jks}, (_, _) => throw StateError('x')),
        _FakeParser({
          CredentialFormat.jceks,
        }, (_, _) => throw RangeError.index(9, const [])),
      ]);
      expect(parsers.parse(input('test.jks')).isGeneric, isTrue);
      expect(parsers.parse(input('test.jceks')).isGeneric, isTrue);
    });

    test('a parser cannot report a fact the user typed', () {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.oauthClientJson}, (input, format) {
          return ParseResult(
            type: ItemType.oauthClient,
            format: format,
            facts: {
              'team_id': const ItemField(
                value: 'GUESSED',
                source: FieldSource.user,
              ),
            },
          );
        }),
      ]);
      final result = parsers.parse(
        input(
          'client_secret_000000000000-test.apps.googleusercontent.com.json',
        ),
      );
      expect(result.isGeneric, isTrue);
      expect(result.facts, isEmpty);
    });

    test('a parser cannot relabel the format it was given', () {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.x509Certificate}, (_, _) {
          return ParseResult(
            type: ItemType.appleCertificate,
            format: CredentialFormat.pkcs12,
          );
        }),
      ]);
      final result = parsers.parse(input('cert.cer'));
      expect(result.isGeneric, isTrue);
      expect(result.format, CredentialFormat.x509Certificate);
    });

    test('a parser can ask for a password and say it was wrong', () {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.pkcs12}, (input, format) {
          final password = input.secrets['password'];
          if (password != 'test-password') {
            return ParseResult(
              type: ItemType.appleCertificate,
              format: format,
              secretsNeeded: [
                SecretRequest(
                  key: 'password',
                  label: 'Password',
                  rejected: password != null,
                ),
              ],
            );
          }
          return ParseResult(
            type: ItemType.appleCertificate,
            format: format,
            expiresAt: DateTime.parse('2036-10-07T19:08:00+02:00'),
          );
        }),
      ]);

      final first = parsers.parse(input('cert.p12'));
      expect(first.needsSecrets, isTrue);
      expect(first.secretsNeeded.single.rejected, isFalse);

      final wrong = parsers.parse(input('cert.p12', {'password': 'nope'}));
      expect(wrong.secretsNeeded.single.rejected, isTrue);

      final right = parsers.parse(
        input('cert.p12', {'password': 'test-password'}),
      );
      expect(right.needsSecrets, isFalse);
      expect(right.expiresAt, DateTime.utc(2036, 10, 7, 17, 8));
      expect(right.expiresAt!.isUtc, isTrue);
    });
  });

  group('never leaks', () {
    test('ParseInput.toString omits bytes and secrets', () {
      final s = input('cert.p12', {'password': 'hunter2-SECRET'}).toString();
      expect(s, isNot(contains('hunter2')));
      expect(s, contains('cert.p12'));
    });

    test('ParseResult.toString lists fact keys, not values', () {
      final result = ParseResult(
        type: ItemType.gcpServiceAccount,
        format: CredentialFormat.serviceAccountJson,
        facts: {
          'private_key': const ItemField(
            value: '-----BEGIN PRIVATE KEY-----SECRET',
            source: FieldSource.file,
            secret: true,
          ),
        },
      );
      expect(result.toString(), contains('private_key'));
      expect(result.toString(), isNot(contains('SECRET')));
    });
  });

  group('parseInIsolate', () {
    test('gives the same result as parse', () async {
      final parsers = CredentialParsers.standard();
      for (final name in ['test.jks', 'cert.p12', 'google-services.json']) {
        final direct = parsers.parse(input(name));
        final isolated = await parsers.parseInIsolate(input(name));
        expect(isolated.type, direct.type);
        expect(isolated.format, direct.format);
        expect(isolated.warnings, direct.warnings);
      }
    });

    test('a throwing parser still comes back generic', () async {
      final parsers = CredentialParsers([
        _FakeParser({CredentialFormat.jks}, (_, _) => throw StateError('x')),
      ]);
      final result = await parsers.parseInIsolate(input('test.jks'));
      expect(result.isGeneric, isTrue);
      expect(result.format, CredentialFormat.jks);
    });
  });

  group('fuzzing never throws', () {
    final fixtures = Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n != 'README.md')
        .toList();
    final names = [
      ...fixtures,
      for (final ext in knownExtensions) 'file.$ext',
      'noext',
      '.p8',
      'AuthKey_.p8',
      'GoogleService-Info.plist',
      'a/b\\c.json',
      '',
    ];
    final prefixes = <List<int>>[
      [0xFE, 0xED, 0xFE, 0xED],
      [0xCE, 0xCE, 0xCE, 0xCE],
      [0x30, 0x82],
      [0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF],
      [0x30, 0x80],
      [0x30, 0x03, 0x02, 0x01, 0x03],
      '-----BEGIN CERTIFICATE-----'.codeUnits,
      '-----BEGIN PRIVATE KEY-----'.codeUnits,
      '{"type":"service_account"'.codeUnits,
      '{"installed":{"client_id":'.codeUnits,
      'bplist00'.codeUnits,
      '<?xml version="1.0"?><plist>'.codeUnits,
      [0xEF, 0xBB, 0xBF, 0x7B],
      [],
    ];

    // Every format has a parser that throws, so fuzzed input goes through
    // the exception path as well as the no-parser path.
    final throwing = CredentialParsers([
      _FakeParser(
        CredentialFormat.values.toSet(),
        (_, _) => throw const FormatException('boom'),
      ),
    ]);
    final standard = CredentialParsers.standard();

    void check(String name, Uint8List bytes) {
      final i = ParseInput(filename: name, bytes: bytes);
      for (final parsers in [standard, throwing]) {
        final result = parsers.parse(i);
        expect(result.type, ItemType.genericFile);
        expect(result.facts, isEmpty);
      }
    }

    test('random bytes under every filename', () {
      final random = Random(0xDE7A);
      for (var i = 0; i < 3000; i++) {
        final prefix = prefixes[random.nextInt(prefixes.length)];
        final tail = List.generate(
          random.nextInt(512),
          (_) => random.nextInt(256),
        );
        check(
          names[random.nextInt(names.length)],
          Uint8List.fromList([...prefix, ...tail]),
        );
      }
    });

    test('truncated and bit-flipped fixtures', () {
      final random = Random(0xF1E7);
      for (final name in fixtures) {
        final bytes = fixture(name);
        for (var cut = 0; cut <= bytes.length; cut += 1 + bytes.length ~/ 64) {
          check(name, Uint8List.sublistView(bytes, 0, cut));
        }
        for (var i = 0; i < 200; i++) {
          final copy = Uint8List.fromList(bytes);
          for (var flips = 1 + random.nextInt(4); flips > 0; flips--) {
            copy[random.nextInt(copy.length)] = random.nextInt(256);
          }
          check(name, copy);
        }
      }
    });
  });
}
