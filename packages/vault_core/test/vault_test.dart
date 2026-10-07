import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late List<String> writes;
  var clock = DateTime.utc(2026, 10, 7, 9);
  const device = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';
  const password = 'correct horse battery staple';

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vault_');
    writes = [];
    clock = DateTime.utc(2026, 10, 7, 9);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  VaultStore store() => VaultStore(dir, onWrite: writes.add);
  DateTime now() => clock = clock.add(const Duration(seconds: 1));

  Future<(Vault, RecoveryKey)> create() => Vault.create(
    crypto: crypto,
    store: store(),
    password: password,
    deviceId: device,
    now: now,
    opsLimit: 1,
    memLimit: KdfParams.minMemLimit,
  );

  Future<Vault> unlock([String pw = password]) => Vault.unlock(
    crypto: crypto,
    store: store(),
    password: pw,
    deviceId: device,
    now: now,
  );

  final jks = Uint8List.fromList(List.generate(2614, (i) => (i * 7) % 256));

  Future<Item> addKeystore(Vault vault) async {
    final attachment = await vault.addAttachment(
      jks,
      filename: 'kitchenly-upload.jks',
    );
    final item = vault.newItem(
      type: ItemType.androidKeystore,
      title: 'Upload keystore',
      fields: const {
        'alias': ItemField(value: 'upload', source: FieldSource.file),
        'store_password': ItemField(
          value: 'hunter2-store',
          source: FieldSource.user,
          secret: true,
        ),
      },
    );
    return vault.putItem(
      item.copyWith(
        attachments: [attachment],
        expiresAt: DateTime.utc(2051, 1, 14),
        expiresSource: ExpirySource.file,
      ),
    );
  }

  test('create, write, lock, unlock: everything comes back', () async {
    final (vault, recoveryKey) = await create();
    final saved = await addKeystore(vault);
    vault.lock();
    recoveryKey.dispose();

    final reopened = await unlock();
    final contents = await reopened.loadAll();
    expect(contents.quarantined, isEmpty);
    final item = contents.items[saved.id]!;
    expect(item.toJson(), saved.toJson());
    expect(item.deviceId, device);
    expect(await reopened.readAttachment(item.attachments.single), jks);
  });

  test('nothing readable lands on disk', () async {
    final (vault, _) = await create();
    await addKeystore(vault);
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final bytes = file.readAsBytesSync();
      final text = latin1.decode(bytes);
      for (final secret in [
        'hunter2',
        'Upload keystore',
        'upload',
        'kitchenly',
      ]) {
        expect(text, isNot(contains(secret)), reason: file.path);
      }
    }
  });

  test('every write gets a later rev, this device and the time', () async {
    final (vault, _) = await create();
    final first = await addKeystore(vault);
    final second = await vault.putItem(first.copyWith(title: 'Renamed'));
    expect(second.rev > first.rev, isTrue);
    expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
    expect(second.createdAt, first.createdAt);
  });

  test('revs keep growing after unlocking on a later run', () async {
    final (vault, _) = await create();
    final first = await addKeystore(vault);
    vault.lock();
    clock = DateTime.utc(2026, 1, 1); // device clock went backwards
    final reopened = await unlock();
    await reopened.loadAll();
    final edited = await reopened.putItem(first.copyWith(title: 'Edited'));
    expect(edited.rev > first.rev, isTrue);
  });

  test('delete writes a tombstone and removes the item', () async {
    final (vault, _) = await create();
    final item = await addKeystore(vault);
    writes.clear();
    final tombstone = await vault.delete(item.id, TombstoneKind.item);
    expect(writes, ['tombstones/${item.id}.enc', '-items/${item.id}.enc']);
    final contents = await vault.loadAll();
    expect(contents.items, isEmpty);
    expect(contents.tombstones[item.id]!.rev, tombstone.rev);
    expect(await vault.readItem(item.id), isNull);
  });

  group('password change', () {
    test('rewrites vault.json and nothing else', () async {
      final (vault, _) = await create();
      await addKeystore(vault);
      writes.clear();
      await vault.changePassword('a brand new password');
      expect(writes, ['vault.json']);
    });

    test('old password stops working, new one and recovery key work', () async {
      final (vault, recoveryKey) = await create();
      final item = await addKeystore(vault);
      await vault.changePassword('a brand new password');
      vault.lock();

      await expectLater(unlock(), throwsA(isA<WrongPassword>()));
      final byPassword = await unlock('a brand new password');
      expect((await byPassword.readItem(item.id))!.title, 'Upload keystore');

      final byRecovery = await Vault.unlockWithRecovery(
        crypto: crypto,
        store: store(),
        recoveryKey: recoveryKey,
        deviceId: device,
        now: now,
      );
      expect((await byRecovery.readItem(item.id))!.title, 'Upload keystore');
    });
  });

  group('damaged or moved objects', () {
    test('an item copied over another is quarantined, not trusted', () async {
      final (vault, _) = await create();
      final a = await addKeystore(vault);
      final b = await addKeystore(vault);
      File('${dir.path}/items/${a.id}.enc')
          .copySync('${dir.path}/items/${b.id}.enc');

      final contents = await vault.loadAll();
      expect(contents.items.keys, [a.id]);
      expect(contents.quarantined.single.objectId, b.id);
      await expectLater(vault.readItem(b.id), throwsA(isA<DecryptionFailed>()));
    });

    test('a blob that does not match its sha256 is refused', () async {
      final (vault, _) = await create();
      final item = await addKeystore(vault);
      final other = await vault.addAttachment(
        Uint8List.fromList([1, 2, 3]),
        filename: 'other.bin',
      );
      // Point the item's attachment at a different, valid blob.
      final swapped = Attachment(
        blobId: other.blobId,
        filename: 'kitchenly-upload.jks',
        mime: 'application/octet-stream',
        size: item.attachments.single.size,
        sha256: item.attachments.single.sha256,
      );
      await expectLater(
        vault.readAttachment(swapped),
        throwsA(isA<AttachmentCorrupt>()),
      );
    });

    test('a missing or tampered blob is refused', () async {
      final (vault, _) = await create();
      final attachment = (await addKeystore(vault)).attachments.single;
      final blobFile = File('${dir.path}/blobs/${attachment.blobId}.enc');
      final bytes = blobFile.readAsBytesSync()..[40] ^= 1;
      blobFile.writeAsBytesSync(bytes);
      await expectLater(
        vault.readAttachment(attachment),
        throwsA(isA<AttachmentCorrupt>()),
      );
      blobFile.deleteSync();
      await expectLater(
        vault.readAttachment(attachment),
        throwsA(isA<AttachmentCorrupt>()),
      );
    });
  });

  test('attachments over 25 MiB are refused', () async {
    final (vault, _) = await create();
    await expectLater(
      vault.addAttachment(
        Uint8List(Vault.maxAttachmentBytes + 1),
        filename: 'huge.bin',
      ),
      throwsA(isA<AttachmentTooLarge>()),
    );
  });

  test('a locked vault refuses to work', () async {
    final (vault, _) = await create();
    vault.lock();
    expect(vault.isLocked, isTrue);
    expect(
      () => vault.newItem(type: ItemType.genericSecret, title: 'x'),
      returnsNormally,
      reason: 'building an unsaved item needs no key',
    );
    await expectLater(
      vault.putItem(vault.newItem(type: ItemType.genericSecret, title: 'x')),
      throwsStateError,
    );
  });

  test('refuses to create over an existing vault', () async {
    await create();
    await expectLater(create(), throwsStateError);
  });
}
