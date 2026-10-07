import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late MemoryBackend bucket;
  var now = DateTime.utc(2026, 10, 7, 9);

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('devvault_gc_');
    bucket = MemoryBackend();
    now = DateTime.utc(2026, 10, 7, 9);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Vault> create() async {
    final (vault, recovery) = await Vault.create(
      crypto: crypto,
      store: VaultStore(Directory('${dir.path}/v')),
      password: 'pw',
      deviceId: '00000000-0000-4000-8000-0000000000aa',
      now: () => now,
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
    recovery.dispose();
    return vault;
  }

  BlobCollector gc(Vault vault) =>
      BlobCollector(vault: vault, backend: bucket, now: () => now);

  Future<void> sync(Vault vault) =>
      SyncEngine(vault: vault, backend: bucket, now: () => now).sync();

  String blobKey(Vault v, String id) => '${v.vaultId}/blobs/$id.enc';

  test('an unreferenced blob goes only after 30 days', () async {
    final vault = await create();
    final kept = await vault.addAttachment(
      Uint8List.fromList([1]),
      filename: 'a',
    );
    final orphan = await vault.addAttachment(
      Uint8List.fromList([2]),
      filename: 'b',
    );
    await vault.putItem(
      vault
          .newItem(type: ItemType.genericFile, title: 'X')
          .copyWith(attachments: [kept]),
    );
    await sync(vault);
    expect(bucket.keys, contains(blobKey(vault, orphan.blobId)));

    var report = await gc(vault).run();
    expect(report.waiting, [orphan.blobId]);
    expect(report.collected, isEmpty);

    now = now.add(const Duration(days: 29));
    report = await gc(vault).run();
    expect(report.collected, isEmpty);

    now = now.add(const Duration(days: 2));
    report = await gc(vault).run();
    expect(report.collected, [orphan.blobId]);
    expect(bucket.keys, isNot(contains(blobKey(vault, orphan.blobId))));
    expect(bucket.keys, contains(blobKey(vault, kept.blobId)));
    expect(await vault.store.read(ObjectType.blob, orphan.blobId), isNull);
    expect(await vault.readAttachment(kept), [1]);

    // The next sync doesn't bring it back or re-upload it.
    await sync(vault);
    expect(bucket.keys, isNot(contains(blobKey(vault, orphan.blobId))));
  });

  test('a dry run reports without deleting or recording', () async {
    final vault = await create();
    final orphan = await vault.addAttachment(
      Uint8List.fromList([2]),
      filename: 'b',
    );
    await sync(vault);
    final stateBefore = await SyncStateStore(vault.store).load();
    final report = await gc(vault).run(dryRun: true);
    expect(report.dryRun, isTrue);
    expect(report.waiting, [orphan.blobId]);
    final stateAfter = await SyncStateStore(vault.store).load();
    expect(stateAfter.unreferencedSince, stateBefore.unreferencedSince);
    expect(stateAfter.lastBlobGc, isNull);
  });

  test('files kept by a conflict version are still referenced', () async {
    final vault = await create();
    final file = await vault.addAttachment(
      Uint8List.fromList([9]),
      filename: 'old.jks',
    );
    final item = await vault.putItem(
      vault.newItem(type: ItemType.androidKeystore, title: 'KS'),
    );
    final version = Item.fromJson({
      ...item.copyWith(attachments: [file]).toJson(),
      'rev': Hlc.zero('00000000-0000-4000-8000-0000000000bb')
          .tick(now)
          .toString(),
      'device_id': '00000000-0000-4000-8000-0000000000bb',
    });
    await vault.putItem(withConflict(item, Conflict()..addVersion(version)));
    now = now.add(const Duration(days: 365));
    final report = await gc(vault).run();
    expect(report.collected, isEmpty);
    expect(report.waiting, isEmpty);
  });

  test('a blob referenced again is forgiven', () async {
    final vault = await create();
    final blob = await vault.addAttachment(
      Uint8List.fromList([3]),
      filename: 'c',
    );
    await gc(vault).run();
    expect(
      (await SyncStateStore(vault.store).load()).unreferencedSince,
      contains(blob.blobId),
    );
    await vault.putItem(
      vault
          .newItem(type: ItemType.genericFile, title: 'Now used')
          .copyWith(attachments: [blob]),
    );
    now = now.add(const Duration(days: 40));
    final report = await gc(vault).run();
    expect(report.collected, isEmpty);
    expect(
      (await SyncStateStore(vault.store).load()).unreferencedSince,
      isEmpty,
    );
  });

  test(
    'another device drops a collected blob instead of re-uploading it',
    () async {
      final a = await create();
      final orphan = await a.addAttachment(
        Uint8List.fromList([7]),
        filename: 'x',
      );
      await sync(a);
      // Device B joins with a copy of everything.
      final bRoot = Directory('${dir.path}/b');
      for (final o in await bucket.list('${a.vaultId}/')) {
        final f = File(
          '${bRoot.path}/${o.key.substring(a.vaultId.length + 1)}',
        );
        await f.parent.create(recursive: true);
        await f.writeAsBytes((await bucket.get(o.key))!.bytes);
      }
      final b = await Vault.unlock(
        crypto: crypto,
        store: VaultStore(bRoot),
        password: 'pw',
        deviceId: '00000000-0000-4000-8000-0000000000bb',
        now: () => now,
      );
      await sync(b);
      expect(await b.store.read(ObjectType.blob, orphan.blobId), isNotNull);

      await gc(a).run();
      now = now.add(const Duration(days: 31));
      expect((await gc(a).run()).collected, [orphan.blobId]);

      await sync(b);
      expect(await b.store.read(ObjectType.blob, orphan.blobId), isNull);
      expect(bucket.keys, isNot(contains(blobKey(a, orphan.blobId))));
    },
  );

  test('runs once a day', () async {
    final vault = await create();
    expect(await gc(vault).isDue(), isTrue);
    await gc(vault).run();
    expect(await gc(vault).isDue(), isFalse);
    now = now.add(const Duration(hours: 25));
    expect(await gc(vault).isDue(), isTrue);
  });
}
