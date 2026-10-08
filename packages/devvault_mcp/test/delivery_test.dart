@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:devvault_mcp/devvault_mcp.dart';
import 'package:test/test.dart';

int mode(String path) => File(path).statSync().mode & 0x1ff;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dvmcp'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('checkTarget', () {
    test('wants an absolute path in a folder that exists', () {
      expect(
        () => checkTarget('relative.txt', overwrite: false),
        throwsA(isA<DeliveryError>()),
      );
      expect(
        () => checkTarget('${dir.path}/no/such/file', overwrite: false),
        throwsA(isA<DeliveryError>()),
      );
      expect(
        () => checkTarget(dir.path, overwrite: true),
        throwsA(isA<DeliveryError>()),
      );
      checkTarget('${dir.path}/new.txt', overwrite: false);
    });

    test('replaces a file only when told to', () {
      final file = File('${dir.path}/a.txt')..writeAsStringSync('x');
      expect(
        () => checkTarget(file.path, overwrite: false),
        throwsA(isA<DeliveryError>()),
      );
      checkTarget(file.path, overwrite: true);
    });
  });

  test('writeSecretFile writes 0600', () async {
    final path = '${dir.path}/AuthKey.p8';
    await writeSecretFile(path, [1, 2, 3]);
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(mode(path), 0x180); // 0600
    expect(dir.listSync(), hasLength(1)); // no temp file left behind
  });

  group('dotenv', () {
    test('values are bare when plain, quoted and escaped otherwise', () {
      expect(dotenvValue('sk_live_123'), 'sk_live_123');
      expect(dotenvValue('a b'), '"a b"');
      expect(dotenvValue(r'p"a$s\s'), r'"p\"a\$s\\s"');
      expect(dotenvValue('line1\nline2'), r'"line1\nline2"');
    });

    test('writeEnvFile replaces in place, keeps the rest, appends', () async {
      final path = '${dir.path}/.env';
      File(path).writeAsStringSync(
        '# config\nPORT=8080\nexport STRIPE_KEY=old\nOTHER="keep me"\n',
      );
      await writeEnvFile(path, {'STRIPE_KEY': 'sk_new', 'MAPS_KEY': 'a b'});
      expect(
        File(path).readAsStringSync(),
        '# config\nPORT=8080\nexport STRIPE_KEY=sk_new\nOTHER="keep me"\n'
        'MAPS_KEY="a b"\n',
      );
      expect(mode(path), 0x180);
    });

    test('isEnvName', () {
      expect(isEnvName('ASC_KEY_PATH'), isTrue);
      expect(isEnvName('_x1'), isTrue);
      expect(isEnvName('1X'), isFalse);
      expect(isEnvName('A-B'), isFalse);
    });
  });

  group('Redactor', () {
    test('replaces values, longest first, and each line of a PEM', () {
      final r = Redactor({
        'KEY': 'secret-value',
        'PEM':
            '-----BEGIN KEY-----\nMIIEvQIBADANBgkqhkiG9w0B\n-----END KEY-----',
        'SHORT': 'ab',
      });
      expect(r.redact('x secret-value y'), 'x [redacted:KEY] y');
      expect(r.redact('MIIEvQIBADANBgkqhkiG9w0B'), '[redacted:PEM]');
      expect(r.redact('ab stays'), 'ab stays');
    });

    test('catches a value cut off at the end of the output', () {
      final r = Redactor({'KEY': 'secret-value'});
      expect(r.redact('tail: secret-va'), 'tail: [redacted:KEY]');
    });
  });

  group('runWithSecrets', () {
    test('injects the env and redacts it from the output', () async {
      final result = await runWithSecrets(
        r'echo "key=$API_KEY"; echo "$API_KEY" >&2; exit 3',
        env: {'API_KEY': 'sk_live_abcdef'},
        cwd: dir.path,
      );
      expect(result.exitCode, 3);
      expect(result.stdout, 'key=[redacted:API_KEY]\n');
      expect(result.stderr, '[redacted:API_KEY]\n');
      expect(result.timedOut, isFalse);
    });

    test('a value split across writes is still caught', () async {
      final result = await runWithSecrets(
        r'printf "sk_live_"; sleep 0.2; printf "abcdef\n"',
        env: {'API_KEY': 'sk_live_abcdef'},
      );
      expect(result.stdout, '[redacted:API_KEY]\n');
    });

    test('runs in cwd', () async {
      final result = await runWithSecrets(
        'pwd',
        env: {'X': 'unused-value'},
        cwd: dir.path,
      );
      expect(
        File(result.stdout.trim()).resolveSymbolicLinksSync(),
        dir.resolveSymbolicLinksSync(),
      );
    });

    test('kills a command that runs too long', () async {
      final result = await runWithSecrets(
        'sleep 5',
        env: {'X': 'unused-value'},
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.timedOut, isTrue);
      expect(result.exitCode, isNull);
    });
  });
}
