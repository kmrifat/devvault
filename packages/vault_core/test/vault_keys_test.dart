import 'dart:convert';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  final now = DateTime.utc(2026, 10, 7, 9);
  const password = 'correct horse battery staple';

  // The smallest parameters the bounds allow, to keep tests fast.
  Future<NewVault> create({String pw = password}) => VaultKeys.create(
    crypto,
    password: pw,
    now: now,
    opsLimit: 1,
    memLimit: KdfParams.minMemLimit,
  );

  String keyHex(SecureKey k) => k.runUnlockedSync(
    (b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
  );

  group('create', () {
    test('writes a header that both secrets can open', () async {
      final vault = await create();
      final byPassword = await VaultKeys.unlockWithPassword(
        crypto,
        vault.header,
        password,
      );
      final byRecovery = VaultKeys.unlockWithRecovery(
        crypto,
        vault.header,
        vault.recoveryKey,
      );
      expect(keyHex(byPassword), keyHex(vault.vaultKey));
      expect(keyHex(byRecovery), keyHex(vault.vaultKey));
      expect(vault.header.vkId, VaultKeys.vkId(crypto, vault.vaultKey));
      expect(isCanonicalUuid(vault.header.vaultId), isTrue);
      for (final k in [byPassword, byRecovery, vault.vaultKey]) {
        k.dispose();
      }
      vault.recoveryKey.dispose();
    });

    test('every vault gets its own id, key and recovery key', () async {
      final a = await create();
      final b = await create();
      expect(a.header.vaultId, isNot(b.header.vaultId));
      expect(a.header.vkId, isNot(b.header.vkId));
      expect(
        a.recoveryKey.toDisplayString(),
        isNot(b.recoveryKey.toDisplayString()),
      );
    });

    test('the recovery key works when typed back in', () async {
      final vault = await create();
      final typed = RecoveryKey.parse(
        crypto,
        vault.recoveryKey.toDisplayString(),
      );
      final vk = VaultKeys.unlockWithRecovery(crypto, vault.header, typed);
      expect(keyHex(vk), keyHex(vault.vaultKey));
    });
  });

  group('unlock', () {
    late NewVault vault;
    setUpAll(() async => vault = await create());

    test('a wrong password says so, and only that', () async {
      await expectLater(
        VaultKeys.unlockWithPassword(crypto, vault.header, 'Correct horse'),
        throwsA(isA<WrongPassword>()),
      );
    });

    test('another vault\'s recovery key is wrong', () async {
      final other = await create();
      expect(
        () => VaultKeys.unlockWithRecovery(
          crypto,
          vault.header,
          other.recoveryKey,
        ),
        throwsA(isA<WrongRecoveryKey>()),
      );
    });

    test('NFC and NFD spellings of a password are the same password', () async {
      final v = await create(pw: 'café-vault');
      final vk = await VaultKeys.unlockWithPassword(
        crypto,
        v.header,
        'café-vault',
      );
      expect(keyHex(vk), keyHex(v.vaultKey));
    });

    test('a swapped-in vault key is caught by vk_id', () async {
      // Someone with bucket access replaces both wraps with their own
      // vault's, under the same vault id, but can't produce the old vk_id.
      final attacker = await VaultKeys.create(
        crypto,
        password: password,
        now: now,
        vaultId: vault.header.vaultId,
        opsLimit: 1,
        memLimit: KdfParams.minMemLimit,
      );
      final tampered = attacker.header.copyWith(vkId: vault.header.vkId);
      await expectLater(
        VaultKeys.unlockWithPassword(crypto, tampered, password),
        throwsA(isA<VaultKeyMismatch>()),
      );
    });

    test('a wrap moved to the other slot does not open', () async {
      final swapped = vault.header.copyWith(
        wrappedVkPassword: vault.header.wrappedVkRecovery,
      );
      await expectLater(
        VaultKeys.unlockWithPassword(crypto, swapped, password),
        throwsA(isA<WrongPassword>()),
      );
    });
  });

  group('change password', () {
    test('rewraps the same key under a new salt', () async {
      final vault = await create();
      final changed = await VaultKeys.changePassword(
        crypto,
        vault.header,
        vault.vaultKey,
        'a new long password',
      );
      expect(changed.kdf.salt, isNot(vault.header.kdf.salt));
      expect(changed.vkId, vault.header.vkId);
      expect(changed.wrappedVkRecovery, vault.header.wrappedVkRecovery);
      expect(changed.vaultId, vault.header.vaultId);

      await expectLater(
        VaultKeys.unlockWithPassword(crypto, changed, password),
        throwsA(isA<WrongPassword>()),
      );
      final vk = await VaultKeys.unlockWithPassword(
        crypto,
        changed,
        'a new long password',
      );
      expect(keyHex(vk), keyHex(vault.vaultKey));
      final viaRecovery = VaultKeys.unlockWithRecovery(
        crypto,
        changed,
        vault.recoveryKey,
      );
      expect(keyHex(viaRecovery), keyHex(vault.vaultKey));
    });

    test('recovery, then a new password (forgotten password flow)', () async {
      final vault = await create();
      final vk = VaultKeys.unlockWithRecovery(
        crypto,
        vault.header,
        vault.recoveryKey,
      );
      final reset = await VaultKeys.changePassword(
        crypto,
        vault.header,
        vk,
        'remembered this time',
      );
      final again = await VaultKeys.unlockWithPassword(
        crypto,
        reset,
        'remembered this time',
      );
      expect(keyHex(again), keyHex(vault.vaultKey));
    });
  });

  group('vault.json', () {
    test('round-trips and keeps fields it does not know', () async {
      final vault = await create();
      final json = jsonDecode(vault.header.toJsonString()) as Map;
      json['future_field'] = {'from': 'v2'};
      final parsed = VaultHeader.parse(jsonEncode(json));
      expect(parsed.unknownFields, {
        'future_field': {'from': 'v2'},
      });
      final rewritten = jsonDecode(parsed.toJsonString()) as Map;
      expect(rewritten['future_field'], {'from': 'v2'});
      expect(parsed.vkId, vault.header.vkId);
      expect(parsed.kdf, vault.header.kdf);
      expect(parsed.createdAt, now);

      final vk = await VaultKeys.unlockWithPassword(crypto, parsed, password);
      expect(keyHex(vk), keyHex(vault.vaultKey));
    });

    test('is pretty, sorted and has the spec fields', () async {
      final vault = await create();
      final text = vault.header.toJsonString();
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json.keys.toList(), [...json.keys]..sort());
      expect(json['format'], 'devvault');
      expect(json['format_version'], 1);
      expect(json['vault_type'], 'personal');
      expect(json['created_at'], '2026-10-07T09:00:00Z');
      expect(text, contains('\n  "format"'));
    });

    test('refuses other formats and newer versions', () async {
      final vault = await create();
      Map<String, Object?> json() =>
          jsonDecode(vault.header.toJsonString()) as Map<String, Object?>;
      expect(
        () => VaultHeader.parse(jsonEncode(json()..['format_version'] = 2)),
        throwsA(isA<UnsupportedFormatVersion>()),
      );
      expect(
        () => VaultHeader.parse(jsonEncode(json()..['format'] = 'keepass')),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => VaultHeader.parse('not json'),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => VaultHeader.parse(
          jsonEncode(json()..['created_at'] = '2026-10-07T09:00:00'),
        ),
        throwsA(isA<VaultFormatException>()),
        reason: 'local time without Z',
      );
    });
  });

  test('UUIDs are version 4 and canonical', () {
    for (var i = 0; i < 50; i++) {
      final id = VaultKeys.uuidV4(crypto);
      expect(isCanonicalUuid(id), isTrue);
      expect(id[14], '4');
      expect('89ab', contains(id[19]));
    }
  });
}
