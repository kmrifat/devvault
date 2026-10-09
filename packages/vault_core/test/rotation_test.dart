import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  var clock = DateTime.utc(2026, 10, 7, 9);
  const device = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';
  const password = 'correct horse battery staple';

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() => dir = Directory.systemTemp.createTempSync('rotation_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final journal = File('${dir.path}.rotation');
    if (journal.existsSync()) journal.deleteSync();
  });

  DateTime now() => clock = clock.add(const Duration(seconds: 1));
  Future<Vault> unlock({VaultStore? store}) => Vault.unlock(
    crypto: crypto,
    store: store ?? VaultStore(dir),
    password: password,
    deviceId: device,
    now: now,
  );

  final fileA = Uint8List.fromList(List.generate(3000, (i) => i % 251));
  final fileB = Uint8List.fromList(List.generate(500, (i) => 255 - i % 256));

  /// A vault with two items holding files, a plain secret, an app, an
  /// organization and two tombstones. Returns the recovery key.
  Future<RecoveryKey> seed() async {
    final (vault, recoveryKey) = await Vault.create(
      crypto: crypto,
      store: VaultStore(dir),
      password: password,
      deviceId: device,
      now: now,
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
    for (final (title, bytes) in [('Keystore', fileA), ('Profile', fileB)]) {
      final attachment = await vault.addAttachment(
        bytes,
        filename: '$title.bin',
      );
      await vault.putItem(
        vault
            .newItem(type: ItemType.genericFile, title: title)
            .copyWith(attachments: [attachment]),
      );
    }
    await vault.putItem(
      vault.newItem(
        type: ItemType.genericSecret,
        title: 'Token',
        fields: const {
          'value': ItemField(
            value: 's3cr3t',
            source: FieldSource.user,
            secret: true,
          ),
        },
      ),
    );
    final doomed = await vault.putItem(
      vault.newItem(type: ItemType.genericSecret, title: 'Doomed'),
    );
    await vault.delete(doomed.id, TombstoneKind.item);
    await vault.putApp(
      AppRecord(
        id: vault.newId(),
        name: 'Kitchenly',
        createdAt: clock,
        updatedAt: clock,
        rev: Hlc.zero(device),
        deviceId: device,
      ),
    );
    await vault.putOrganization(vault.newOrganization(name: 'Globex'));
    final gone = await vault.putOrganization(
      vault.newOrganization(name: 'Initech'),
    );
    await vault.delete(gone.id, TombstoneKind.organization);
    vault.lock();
    return recoveryKey;
  }

  /// Everything a user cares about, decrypted.
  Future<Map<String, Object>> snapshot(Vault vault) async {
    final contents = await vault.loadAll();
    expect(contents.quarantined, isEmpty);
    return {
      for (final item in contents.items.values)
        item.title: [
          item.fields.map((k, v) => MapEntry(k, v.value)).toString(),
          for (final a in item.attachments) await vault.readAttachment(a),
        ],
      'apps': contents.apps.values.map((a) => a.name).toList(),
      'organizations': contents.organizations.values
          .map((o) => o.name)
          .toList(),
      'tombstones': contents.tombstones.length,
    };
  }

  test('rotation keeps every record and file, under a new key', () async {
    final oldRecovery = await seed();
    final vault = await unlock();
    final before = await snapshot(vault);
    final oldVkId = vault.header.vkId;
    final oldBlobs = await vault.store.list(ObjectType.blob);

    final newRecovery = await vault.rotateVaultKey(password);

    expect(vault.header.vkId, isNot(oldVkId));
    expect(await snapshot(vault), before);
    expect(before['organizations'], ['Globex']);
    expect(before['tombstones'], 2);
    final newBlobs = await vault.store.list(ObjectType.blob);
    expect(newBlobs, hasLength(oldBlobs.length));
    expect(newBlobs.toSet().intersection(oldBlobs.toSet()), isEmpty);
    expect(File('${dir.path}.rotation').existsSync(), isFalse);

    // Same password; new recovery key; the old recovery key is dead.
    final again = await unlock();
    expect(await snapshot(again), before);
    final header = await VaultStore(dir).readHeader();
    expect(
      () => VaultKeys.unlockWithRecovery(crypto, header, oldRecovery),
      throwsA(isA<WrongRecoveryKey>()),
    );
    VaultKeys.unlockWithRecovery(crypto, header, newRecovery).dispose();
  });

  test('a wrong password stops rotation before anything is written', () async {
    await seed();
    final writes = <String>[];
    final vault = await unlock(store: VaultStore(dir, onWrite: writes.add));
    await expectLater(
      vault.rotateVaultKey('not the password'),
      throwsA(isA<WrongPassword>()),
    );
    expect(writes, isEmpty);
  });

  test('replacing the recovery key writes vault.json only', () async {
    final oldRecovery = await seed();
    final writes = <String>[];
    final vault = await unlock(store: VaultStore(dir, onWrite: writes.add));
    final fresh = await vault.replaceRecoveryKey();
    expect(writes, ['vault.json']);
    final header = await VaultStore(dir).readHeader();
    VaultKeys.unlockWithRecovery(crypto, header, fresh).dispose();
    expect(
      () => VaultKeys.unlockWithRecovery(crypto, header, oldRecovery),
      throwsA(isA<WrongRecoveryKey>()),
    );
  });

  test('a crash after vault.json but before clean-up just tidies up', () async {
    await seed();
    final journal = File('${dir.path}.rotation');
    late Uint8List saved;
    final vault = await unlock(
      store: VaultStore(
        dir,
        onWrite: (path) {
          if (path == '../rotation journal') saved = journal.readAsBytesSync();
        },
      ),
    );
    final before = await snapshot(vault);
    await vault.rotateVaultKey(password);
    final rotatedVkId = vault.header.vkId;
    journal.writeAsBytesSync(saved); // as if the delete never happened

    final reopened = await unlock();
    expect(reopened.header.vkId, rotatedVkId);
    expect(reopened.pendingRecoveryKey, isNull);
    expect(await snapshot(reopened), before);
    expect(journal.existsSync(), isFalse);
  });

  group('a crash at any write', () {
    // How many atomic writes one rotation of the seed vault makes.
    late int rotationWrites;
    setUpAll(() async {
      final probeDir = Directory.systemTemp.createTempSync('rotation_probe_');
      dir = probeDir;
      await seed();
      var count = 0;
      final vault = await unlock(
        store: VaultStore(
          probeDir,
          onWrite: (p) {
            if (!p.startsWith('-')) count++;
          },
        ),
      );
      await vault.rotateVaultKey(password);
      rotationWrites = count;
      probeDir.deleteSync(recursive: true);
    });

    for (var crashAt = 0; crashAt < 11; crashAt++) {
      test('#$crashAt either resumes on unlock or never started', () async {
        expect(crashAt, lessThan(rotationWrites), reason: 'write exists');
        await seed();
        final reference = await unlock();
        final before = await snapshot(reference);
        final oldVkId = reference.header.vkId;
        reference.lock();

        var writes = 0;
        final crashing = await unlock(
          store: VaultStore(
            dir,
            beforeRename: (_) {
              if (writes++ == crashAt) {
                throw const FileSystemException('power cut');
              }
            },
          ),
        );
        await expectLater(
          crashing.rotateVaultKey(password),
          throwsA(isA<FileSystemException>()),
        );

        // Next launch: unlock as usual.
        final recovered = await unlock();
        expect(await snapshot(recovered), before, reason: 'nothing lost');
        if (crashAt == 0) {
          // The journal never landed: the vault is untouched.
          expect(recovered.header.vkId, oldVkId);
          expect(recovered.pendingRecoveryKey, isNull);
        } else {
          expect(recovered.header.vkId, isNot(oldVkId));
          final shown = recovered.takePendingRecoveryKey()!;
          // Handed over once.
          expect(recovered.takePendingRecoveryKey(), isNull);
          expect(recovered.pendingRecoveryKey, isNull);
          VaultKeys.unlockWithRecovery(
            crypto,
            await VaultStore(dir).readHeader(),
            shown,
          ).dispose();
        }
        expect(File('${dir.path}.rotation').existsSync(), isFalse);
      });
    }

    test('covers every write the rotation makes', () {
      expect(rotationWrites, 11);
    });
  });
}
