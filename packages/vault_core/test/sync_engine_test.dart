import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

const _password = 'correct horse battery staple';
const _deviceA = '00000000-0000-4000-8000-0000000000aa';
const _deviceB = '00000000-0000-4000-8000-0000000000bb';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late MemoryBackend bucket;
  var clock = DateTime.utc(2026, 10, 7, 9);
  DateTime now() => clock = clock.add(const Duration(seconds: 1));

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('devvault_sync_');
    bucket = MemoryBackend();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  VaultStore storeOf(String device) =>
      VaultStore(Directory('${dir.path}/$device/vault'));

  Future<Vault> createOnA() async {
    final (vault, recovery) = await Vault.create(
      crypto: crypto,
      store: storeOf('a'),
      password: _password,
      deviceId: _deviceA,
      now: now,
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
    recovery.dispose();
    return vault;
  }

  Future<Vault> unlock(
    String device,
    String id, {
    String password = _password,
  }) => Vault.unlock(
    crypto: crypto,
    store: storeOf(device),
    password: password,
    deviceId: id,
    now: now,
  );

  /// Device B joins: it fetches every object as it is in the bucket (what
  /// P2-10 does) and unlocks.
  Future<Vault> joinOnB(String vaultId, {String password = _password}) async {
    final root = storeOf('b').root;
    for (final object in await bucket.list('$vaultId/')) {
      final file = File(
        '${root.path}/${object.key.substring(vaultId.length + 1)}',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes((await bucket.get(object.key))!.bytes);
    }
    return unlock('b', _deviceB, password: password);
  }

  SyncEngine engine(Vault vault) =>
      SyncEngine(vault: vault, backend: bucket, now: () => clock);

  Future<Item> addItem(Vault vault, String title, {String secret = 's'}) =>
      vault.putItem(
        vault.newItem(
          type: ItemType.genericSecret,
          title: title,
          fields: {
            'value': ItemField(
              value: secret,
              source: FieldSource.user,
              secret: true,
            ),
          },
        ),
      );

  Future<Map<String, Item>> items(Vault vault) async =>
      (await vault.loadAll()).items;

  test('a new vault pushes everything, then has nothing to do', () async {
    final a = await createOnA();
    await addItem(a, 'Stripe key');
    final first = await engine(a).sync();
    expect(first.pushed, 2); // vault.json + the item
    expect(bucket.keys, [
      '${a.vaultId}/items/${(await items(a)).keys.single}.enc',
      '${a.vaultId}/vault.json',
    ]);
    // vault.json goes first, and new objects are created conditionally.
    expect(
      bucket.log.where((l) => l.startsWith('put')).first,
      'put ${a.vaultId}/vault.json',
    );

    bucket.log.clear();
    final second = await engine(a).sync();
    expect(second.pushed + second.pulled, 0);
    expect(bucket.log, ['list ${a.vaultId}/']);
  });

  test('two devices converge, merging concurrent edits', () async {
    final a = await createOnA();
    final item = await addItem(a, 'Stripe key', secret: 'sk-1');
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    await engine(b).sync();

    // Concurrent, different fields.
    await a.putItem(item.copyWith(title: 'Stripe live key'));
    final onB = (await items(b))[item.id]!;
    await b.putItem(
      onB.copyWith(
        fields: {
          ...onB.fields,
          'value': const ItemField(
            value: 'sk-2',
            source: FieldSource.user,
            secret: true,
          ),
        },
      ),
    );

    await engine(a).sync();
    final report = await engine(b).sync(); // pulls A's edit, merges, pushes
    expect(report.merged, 1);
    expect(report.conflicts, 0);
    await engine(a).sync();

    final onA = (await items(a))[item.id]!;
    final finalB = (await items(b))[item.id]!;
    expect(onA.title, 'Stripe live key');
    expect(onA.fields['value']!.value, 'sk-2');
    expect(onA.toJson(), finalB.toJson());
  });

  test(
    'the same field edited on both: kept as a conflict on both devices',
    () async {
      final a = await createOnA();
      final item = await addItem(a, 'Token', secret: 'v0');
      await engine(a).sync();
      final b = await joinOnB(a.vaultId);
      await engine(b).sync();

      Future<void> setSecret(Vault v, String value) async {
        final current = (await items(v))[item.id]!;
        await v.putItem(
          current.copyWith(
            fields: {
              'value': ItemField(
                value: value,
                source: FieldSource.user,
                secret: true,
              ),
            },
          ),
        );
      }

      await setSecret(a, 'from-a');
      await setSecret(b, 'from-b');
      await engine(a).sync();
      expect((await engine(b).sync()).conflicts, 1);
      await engine(a).sync();

      for (final v in [a, b]) {
        final merged = (await items(v))[item.id]!;
        expect(merged.fields['value']!.value, 'from-b'); // B merged: local kept
        expect(
          Conflict.of(merged).versions.single.fields['value']!.value,
          'from-a',
        );
      }
    },
  );

  test('losing a race pulls, merges and retries', () async {
    final a = await createOnA();
    final item = await addItem(a, 'X');
    await engine(a).sync();
    await a.putItem(item.copyWith(title: 'Y'));
    bucket.failNext(
      StorageOp.put,
      const PreconditionFailed('raced'),
      key: '${a.vaultId}/items/${item.id}.enc',
    );
    final report = await engine(a).sync();
    expect(report.attempts, 2);
    expect(report.pushed, 1);
  });

  test('gives up after five lost races', () async {
    final a = await createOnA();
    final item = await addItem(a, 'X');
    await engine(a).sync();
    await a.putItem(item.copyWith(title: 'Y'));
    for (var i = 0; i < 5; i++) {
      bucket.failNext(StorageOp.put, const PreconditionFailed('raced'));
    }
    await expectLater(engine(a).sync(), throwsA(isA<PreconditionFailed>()));
  });

  test('a password change is a single PUT, of vault.json', () async {
    final a = await createOnA();
    await addItem(a, 'X');
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    await engine(b).sync();

    await a.changePassword('a whole new passphrase');
    bucket.log.clear();
    await engine(a).sync();
    expect(bucket.log.where((l) => !l.startsWith('list')), [
      'put ${a.vaultId}/vault.json',
    ]);

    // B takes the new vault.json; the new password opens it there.
    final report = await engine(b).sync();
    expect(report.pulled, 1);
    b.lock();
    await expectLater(unlock('b', _deviceB), throwsA(isA<WrongPassword>()));
    final reopened = await unlock(
      'b',
      _deviceB,
      password: 'a whole new passphrase',
    );
    expect((await items(reopened)), hasLength(1));
  });

  test('deletes propagate', () async {
    final a = await createOnA();
    final item = await addItem(a, 'Old key');
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    await engine(b).sync();

    await a.delete(item.id, TombstoneKind.item);
    await engine(a).sync();
    expect(bucket.keys, isNot(contains('${a.vaultId}/items/${item.id}.enc')));
    expect(bucket.keys, contains('${a.vaultId}/tombstones/${item.id}.enc'));

    await engine(b).sync();
    expect(await items(b), isEmpty);
    expect((await b.loadAll()).tombstones, contains(item.id));
  });

  test('an edit beats a delete', () async {
    final a = await createOnA();
    final item = await addItem(a, 'Keep me', secret: 'precious');
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    await engine(b).sync();

    await a.delete(item.id, TombstoneKind.item);
    await engine(a).sync();
    final onB = (await items(b))[item.id]!;
    await b.putItem(onB.copyWith(title: 'Kept and edited'));
    await engine(b).sync();
    await engine(a).sync();

    for (final v in [a, b]) {
      final kept = (await items(v))[item.id];
      expect(kept?.title, 'Kept and edited', reason: 'on ${v.deviceId}');
      expect(kept!.fields['value']!.value, 'precious');
      expect(Conflict.of(kept).deletions.single['device_id'], _deviceA);
      expect((await v.loadAll()).tombstones, isNot(contains(item.id)));
    }
  });

  test('attachments travel as blobs', () async {
    final a = await createOnA();
    final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 256));
    final attachment = await a.addAttachment(bytes, filename: 'upload.jks');
    final item = await a.putItem(
      a
          .newItem(type: ItemType.androidKeystore, title: 'KS')
          .copyWith(attachments: [attachment]),
    );
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    // A second file added after B joined.
    final more = await a.addAttachment(
      Uint8List.fromList([1, 2, 3]),
      filename: 'x.bin',
    );
    await a.putItem(
      (await items(a))[item.id]!.copyWith(attachments: [attachment, more]),
    );
    await engine(a).sync();
    await engine(b).sync();

    final onB = (await items(b))[item.id]!;
    expect(onB.attachments, hasLength(2));
    expect(await b.readAttachment(onB.attachments.last), [1, 2, 3]);
    expect(await b.readAttachment(onB.attachments.first), bytes);
  });

  test('a tampered remote object is left alone and reported', () async {
    final a = await createOnA();
    final x = await addItem(a, 'X');
    final y = await addItem(a, 'Y');
    await engine(a).sync();
    final b = await joinOnB(a.vaultId);
    await engine(b).sync();

    // Someone with bucket access copies X's ciphertext over Y (AAD swap).
    final xBytes = (await bucket.get('${a.vaultId}/items/${x.id}.enc'))!.bytes;
    await bucket.put('${a.vaultId}/items/${y.id}.enc', xBytes);
    final report = await engine(b).sync();
    expect(report.unreadable, 1);
    expect((await items(b))[y.id]!.title, 'Y');
  });

  test('vaults can live under a folder in the bucket', () async {
    final a = await createOnA();
    await addItem(a, 'X');
    await SyncEngine(
      vault: a,
      backend: bucket,
      rootPrefix: 'devvault/',
      now: () => clock,
    ).sync();
    expect(bucket.keys, everyElement(startsWith('devvault/${a.vaultId}/')));
    expect(
      () => SyncEngine(vault: a, backend: bucket, rootPrefix: 'no-slash'),
      throwsArgumentError,
    );
    expect(
      () => SyncEngine(vault: a, backend: bucket, rootPrefix: '../x/'),
      throwsArgumentError,
    );
  });

  test(
    'nothing local is ever uploaded unencrypted, except vault.json',
    () async {
      final a = await createOnA();
      await addItem(a, 'Secret title', secret: 'plaintext-marker');
      await engine(a).sync();
      for (final key in bucket.keys) {
        final text = String.fromCharCodes((await bucket.get(key))!.bytes);
        expect(text, isNot(contains('plaintext-marker')), reason: key);
        expect(text, isNot(contains('Secret title')), reason: key);
      }
    },
  );
}
