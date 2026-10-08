import 'dart:convert';

import 'package:devvault/core/pairing.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  const vaultId = '7f3c2a10-4b5d-4e6f-8a9b-0c1d2e3f4a5b';
  const settings = SyncSettings(
    provider: StorageProvider.r2,
    accountId: '0123456789abcdef0123456789abcdef',
    bucket: 'devvault-test',
    prefix: 'team/',
  );
  const credentials = AwsCredentials(
    accessKeyId: 'TESTACCESSKEY',
    secretAccessKey: 'test-secret-not-real',
  );
  final now = DateTime.utc(2026, 10, 8, 9);

  // The cheapest costs the format accepts, so tests stay fast.
  Future<String> seal(String code, {DateTime? at}) => Pairing.seal(
    crypto: testCrypto,
    vaultId: vaultId,
    settings: settings,
    credentials: credentials,
    code: code,
    now: at ?? now,
    ops: 1,
    mem: 8 * 1024 * 1024,
  );

  Future<PairingContents> open(String text, String code, {DateTime? at}) =>
      Pairing.open(crypto: testCrypto, text: text, code: code, now: at ?? now);

  group('codes', () {
    test('eight Crockford characters, 40 bits, all different', () {
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        final code = Pairing.newCode(testCrypto);
        expect(code, hasLength(8));
        expect(code.split('').every(Pairing.alphabet.contains), isTrue);
        seen.add(code);
      }
      expect(seen.length, greaterThan(495));
      expect(Pairing.alphabet.contains(RegExp('[ILOU]')), isFalse);
    });

    test('typed codes forgive case, dashes, spaces and look-alikes', () {
      expect(Pairing.normalize('ab1d-efgh'), 'AB1DEFGH');
      expect(Pairing.normalize(' ABCD EFGH '), 'ABCDEFGH');
      expect(Pairing.normalize('oOiI-lL00'), '00111100');
      expect(Pairing.normalize('ABC'), isNull);
      expect(Pairing.normalize('ABCD-EFG!'), isNull);
      expect(Pairing.normalize('ABCDEFGU'), isNull); // U isn't in the set
      expect(Pairing.display('ABCDEFGH'), 'ABCD-EFGH');
    });
  });

  group('payload', () {
    test(
      'opens with the code to exactly the storage settings and keys',
      () async {
        final code = Pairing.newCode(testCrypto);
        final text = await seal(code);
        expect(text, startsWith(Pairing.prefix));
        expect(text, isNot(contains('test-secret')));
        expect(text, isNot(contains('TESTACCESSKEY')));

        final contents = await open(text, Pairing.display(code).toLowerCase());
        expect(contents.vaultId, vaultId);
        expect(contents.settings.toJson(), settings.toJson());
        expect(contents.credentials.accessKeyId, 'TESTACCESSKEY');
        expect(contents.credentials.secretAccessKey, 'test-secret-not-real');
        expect(contents.toString(), isNot(contains('test-secret')));
      },
    );

    test(
      'the box holds the storage settings and keys, never a vault key',
      () async {
        // Opened by hand, as docs/format/pairing.md describes it, so the
        // check doesn't rely on what Pairing.open chooses to return.
        const code = 'ABCDEFGH';
        final envelope = Pairing.read(await seal(code));
        final key = await testCrypto.argon2idIsolated(
          password: VaultCrypto.utf8Bytes(code),
          salt: envelope.salt,
          opsLimit: envelope.ops,
          memLimit: envelope.mem,
        );
        final plain = testCrypto.aeadDecrypt(
          cipherText: envelope.box,
          additionalData: VaultCrypto.utf8Bytes(
            'devvault/v1/pair|${envelope.vaultId}|${envelope.expiresAtText}'
            '|${envelope.ops}|${envelope.mem}',
          ),
          nonce: envelope.nonce,
          key: key,
        );
        key.dispose();
        final json = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
        expect(json.keys.toSet(), {
          'settings',
          'access_key_id',
          'secret_access_key',
        });
        expect(json['settings'], settings.toJson());
      },
    );

    test(
      'the envelope says which vault and until when, nothing more',
      () async {
        final text = await seal('ABCDEFGH');
        final envelope = Pairing.read(text);
        expect(envelope.vaultId, vaultId);
        expect(envelope.expiresAt, now.add(Pairing.lifetime));
        final body = text.substring(Pairing.prefix.length);
        final json = jsonDecode(
          utf8.decode(
            base64Url.decode(body.padRight((body.length + 3) ~/ 4 * 4, '=')),
          ),
        ) as Map<String, Object?>;
        expect(json.keys.toSet(), {
          'vault_id',
          'expires_at',
          'salt',
          'ops',
          'mem',
          'nonce',
          'box',
        });
      },
    );

    test('a wrong code fails without saying more', () async {
      final text = await seal('ABCDEFGH');
      await expectLater(
        open(text, 'ABCDEFGJ'),
        throwsA(isA<WrongPairingCode>()),
      );
      await expectLater(open(text, 'nope'), throwsA(isA<WrongPairingCode>()));
    });

    test(
      'expires after ten minutes (with two minutes of clock skew)',
      () async {
        final text = await seal('ABCDEFGH');
        await open(text, 'ABCDEFGH', at: now.add(const Duration(minutes: 11)));
        await expectLater(
          open(
            text,
            'ABCDEFGH',
            at: now.add(const Duration(minutes: 12, seconds: 1)),
          ),
          throwsA(isA<PairingExpired>()),
        );
        // A payload claiming to last far longer than ten minutes is refused.
        final future = await seal(
          'ABCDEFGH',
          at: now.add(const Duration(hours: 1)),
        );
        await expectLater(
          open(future, 'ABCDEFGH'),
          throwsA(isA<PairingExpired>()),
        );
      },
    );

    test('changing the vault id or expiry breaks the seal', () async {
      final text = await seal('ABCDEFGH');
      final body = text.substring(Pairing.prefix.length);
      final json = jsonDecode(
        utf8.decode(
          base64Url.decode(body.padRight((body.length + 3) ~/ 4 * 4, '=')),
        ),
      ) as Map<String, Object?>;
      String rewrite(Map<String, Object?> j) =>
          '${Pairing.prefix}${base64Url.encode(utf8.encode(jsonEncode(j)))}';
      await expectLater(
        open(
          rewrite({
            ...json,
            'vault_id': '00000000-0000-4000-8000-000000000000',
          }),
          'ABCDEFGH',
        ),
        throwsA(isA<WrongPairingCode>()),
      );
      await expectLater(
        open(
          rewrite({...json, 'expires_at': '2026-10-08T09:05:00Z'}),
          'ABCDEFGH',
        ),
        throwsA(isA<WrongPairingCode>()),
      );
    });

    test('costs outside the bounds are refused before any work', () async {
      final text = await seal('ABCDEFGH');
      final body = text.substring(Pairing.prefix.length);
      final json = jsonDecode(
        utf8.decode(
          base64Url.decode(body.padRight((body.length + 3) ~/ 4 * 4, '=')),
        ),
      ) as Map<String, Object?>;
      for (final bad in [
        {...json, 'mem': 4 * 1024 * 1024 * 1024},
        {...json, 'ops': 500},
        {...json, 'ops': 0},
      ]) {
        expect(
          () => Pairing.read(
            '${Pairing.prefix}${base64Url.encode(utf8.encode(jsonEncode(bad)))}',
          ),
          throwsA(isA<PairingFormatException>()),
        );
      }
    });

    test('anything else is not a pairing code', () {
      for (final text in [
        '',
        'hello',
        'devvault-pair:2:abc',
        '${Pairing.prefix}!!!',
        '${Pairing.prefix}${base64Url.encode(utf8.encode('[]'))}',
      ]) {
        expect(
          () => Pairing.read(text),
          throwsA(isA<PairingFormatException>()),
          reason: text,
        );
      }
    });

    test('a fixed vector opens (the format is a contract)', () async {
      final crypto = await VaultCrypto.withFixedRandom(
        utf8.encode('devvault pairing vector'),
      );
      final code = Pairing.newCode(crypto);
      final text = await Pairing.seal(
        crypto: crypto,
        vaultId: vaultId,
        settings: settings,
        credentials: credentials,
        code: code,
        now: now,
        ops: 1,
        mem: 8 * 1024 * 1024,
      );
      expect(code, _vectorCode);
      expect(text, _vectorText);
      final contents = await Pairing.open(
        crypto: testCrypto,
        text: _vectorText,
        code: _vectorCode,
        now: now,
      );
      expect(contents.credentials.secretAccessKey, 'test-secret-not-real');
    });
  });
}

// Generated by the test above with seed "devvault pairing vector" and
// documented in docs/format/pairing.md.
const _vectorCode = '0FHKC03H';
const _vectorText =
    'devvault-pair:1:eyJ2YXVsdF9pZCI6IjdmM2MyYTEwLTRiNWQtNGU2Zi04YTli'
    'LTBjMWQyZTNmNGE1YiIsImV4cGlyZXNfYXQiOiIyMDI2LTEwLTA4VDA5OjEwOjAw'
    'WiIsInNhbHQiOiJIX3RWQ1lnSkJHT3JSNk1lZmlQX1NnPT0iLCJvcHMiOjEsIm1l'
    'bSI6ODM4ODYwOCwibm9uY2UiOiI2b1I1dFpxM0FIWUUySVZwQkFwcnd0UlNVOTBQ'
    'TTFQeSIsImJveCI6IkdKaWd3R2tLc2p0WHNQd2lLUkszZUZsSnhkbWI5dml0VVZ5'
    'MW05QVR6Y1phRG9JNGFrUldNcVUxMHlxNUtXVEZkcFNEbWh2MV82cGY0cjlLR0to'
    'Y2xKMElJUFdfYVJUZUcya3JmaVZnbVFFc19RbkxEaXhqcU9ROXg5SE5KWkxOdmZv'
    'Z1h6ak5rN1RFN251bmdrSm04UWFTOEhSdzFkczQzRnRjNVpLVThtOFRFSTRKeGNI'
    'azl2cmlUOXplYzJ3Rm5wLTEwNnVHUy1ZR2NlLUUzTTdoZS1mZDlUN3U0SVdQQVRm'
    'THR0TnhlcHVtMjIwVFh0Rjc3MXlyb05sR082cWtIMkhhWW1LeEVndDdsWnlZQ2U2'
    'Z2oyZy0wNGFnejhvZ05pSDRjUVd4QkZFTERSM2xUVURGX3NWUEtFYkJhUzFHcldL'
    'WHE5cVV3ZmpUUHI0LWprTG0ifQ';
