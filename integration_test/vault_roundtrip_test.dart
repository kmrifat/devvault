// The P0 gate: the vault core, with libsodium compiled for the platform,
// gives the same answers inside the real app on every platform.
//
//   flutter test integration_test -d macos      (or windows, linux,
//   an iOS simulator, an Android emulator)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  Uint8List seq(int length, [int start = 0]) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) start + i]);
  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  // Expected values computed with Go's golang.org/x/crypto, as in
  // packages/vault_core/test/vault_crypto_test.dart.
  testWidgets('known answers match Go on this platform', (tester) async {
    final watch = Stopwatch()..start();
    final argon = await crypto.argon2idIsolated(
      password: Uint8List.fromList(utf8.encode('correct horse battery staple')),
      salt: seq(16),
      opsLimit: 3,
      memLimit: 64 * 1024 * 1024,
    );
    watch.stop();
    expect(
      argon.runUnlockedSync(hex),
      '0d1a3c6523c8f06e4e0af9c515aa5b5448cfebd6838f2d52c3d8b6ef8ddc3c2e',
    );
    argon.dispose();
    // ignore: avoid_print
    print(
      'ARGON2ID ${Platform.operatingSystem}: ops=3 mem=64MiB '
      '${watch.elapsedMilliseconds} ms (libsodium ${crypto.libsodiumVersion})',
    );

    final ikm = crypto.keyFromBytes(seq(32, 0x40));
    final kek = crypto.hkdfSha256(
      ikm: ikm,
      salt: VaultCrypto.utf8Bytes('7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e'),
      info: 'devvault/v1/recovery-kek',
    );
    expect(
      kek.runUnlockedSync(hex),
      '27f8c0f0c3db65941217bac15e67dbdbd58aceada166a478dcffcda6088609ba',
    );

    final key = crypto.keyFromBytes(seq(32));
    final envelope = Envelope.seal(
      crypto,
      slot: ObjectSlot(
        vaultId: '7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e',
        objectId: '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6',
        type: ObjectType.item,
      ),
      key: key,
      plaintext: Uint8List.fromList(utf8.encode('{"schema":1}')),
      nonce: seq(24, 0x80),
    );
    expect(
      hex(envelope),
      '44564c540101808182838485868788898a8b8c8d8e8f9091929394959697'
      '39cc2a3a8ff12e0b3e221286a8be856b72c7a2918dcef19b78a0a5d6',
    );
    expect(
      hex(
        crypto.keyedHash(key: key, message: utf8.encode('devvault/v1/vk-id')),
      ),
      'cbac3b26918d0f62fd449dd3d12163ba4549e7b53d661981f7145b4e0fb42016',
    );
    for (final k in [ikm, kek, key]) {
      k.dispose();
    }
  });

  testWidgets('create, write, lock, unlock and change password', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('devvault_roundtrip_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var clock = DateTime.utc(2026, 10, 7, 9);
    DateTime now() => clock = clock.add(const Duration(seconds: 1));
    const device = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';
    final file = Uint8List.fromList(List.generate(4096, (i) => i * 31 % 256));

    final (vault, recoveryKey) = await Vault.create(
      crypto: crypto,
      store: VaultStore(dir),
      password: 'first password',
      deviceId: device,
      now: now,
    );
    final attachment = await vault.addAttachment(file, filename: 'key.p12');
    final item = await vault.putItem(
      vault
          .newItem(type: ItemType.appleCertificate, title: 'Distribution')
          .copyWith(attachments: [attachment]),
    );
    final writes = <String>[];
    final watched = await Vault.unlock(
      crypto: crypto,
      store: VaultStore(dir, onWrite: writes.add),
      password: 'first password',
      deviceId: device,
      now: now,
    );
    await watched.changePassword('second password');
    expect(writes, ['vault.json'], reason: 'password change writes one file');
    vault.lock();
    watched.lock();

    await expectLater(
      Vault.unlock(
        crypto: crypto,
        store: VaultStore(dir),
        password: 'first password',
        deviceId: device,
        now: now,
      ),
      throwsA(isA<WrongPassword>()),
    );
    final reopened = await Vault.unlock(
      crypto: crypto,
      store: VaultStore(dir),
      password: 'second password',
      deviceId: device,
      now: now,
    );
    final contents = await reopened.loadAll();
    expect(contents.items[item.id]!.title, 'Distribution');
    expect(await reopened.readAttachment(attachment), file);

    final byRecovery = await Vault.unlockWithRecovery(
      crypto: crypto,
      store: VaultStore(dir),
      recoveryKey: RecoveryKey.parse(crypto, recoveryKey.toDisplayString()),
      deviceId: device,
      now: now,
    );
    expect(await byRecovery.readItem(item.id), isNotNull);
  });
}
