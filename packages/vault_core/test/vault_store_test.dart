import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late Directory dir;
  late List<String> writes;
  late VaultStore store;

  const a = '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6';
  const b = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vault_store_');
    writes = [];
    store = VaultStore(dir, onWrite: writes.add);
    await store.open();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('creates the spec layout', () {
    for (final folder in ['items', 'apps', 'blobs', 'tombstones']) {
      expect(Directory('${dir.path}/$folder').existsSync(), isTrue);
    }
  });

  test('writes, reads, lists and deletes objects', () async {
    await store.write(ObjectType.item, b, bytes('second'));
    await store.write(ObjectType.item, a, bytes('first'));
    expect(await store.read(ObjectType.item, a), bytes('first'));
    expect(await store.list(ObjectType.item), [a, b]);
    expect(await store.read(ObjectType.app, a), isNull);

    await store.write(ObjectType.item, a, bytes('first, edited'));
    expect(await store.read(ObjectType.item, a), bytes('first, edited'));

    await store.delete(ObjectType.item, a);
    expect(await store.list(ObjectType.item), [b]);
    expect(writes, [
      'items/$b.enc',
      'items/$a.enc',
      'items/$a.enc',
      '-items/$a.enc',
    ]);
  });

  test('blobs are written once', () async {
    await store.write(ObjectType.blob, a, bytes('file'));
    expect(
      () => store.write(ObjectType.blob, a, bytes('other file')),
      throwsA(isA<BlobExists>()),
    );
    expect(await store.read(ObjectType.blob, a), bytes('file'));
  });

  test('ignores files that are not objects', () async {
    await store.write(ObjectType.item, a, bytes('x'));
    File('${dir.path}/items/.DS_Store').writeAsStringSync('mac');
    File('${dir.path}/items/notes.txt').writeAsStringSync('hi');
    File('${dir.path}/items/${a.toUpperCase()}.enc').writeAsStringSync('?');
    expect(await store.list(ObjectType.item), [a]);
  });

  test('refuses ids that are not lowercase UUIDs', () {
    expect(
      () => store.write(ObjectType.item, '../vault', bytes('x')),
      throwsArgumentError,
    );
    expect(
      () => store.write(ObjectType.vkWrapPassword, a, bytes('x')),
      throwsArgumentError,
    );
  });

  group('a crash mid-write', () {
    test('leaves the previous version in place', () async {
      await store.write(ObjectType.item, a, bytes('old'));
      final crashing = VaultStore(
        dir,
        beforeRename: (_) => throw const FileSystemException('power cut'),
      );
      await expectLater(
        crashing.write(ObjectType.item, a, bytes('new')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.read(ObjectType.item, a), bytes('old'));
      expect(
        Directory('${dir.path}/items').listSync().map((e) => e.path),
        hasLength(1),
        reason: 'temporary file removed',
      );
    });

    test('leftover temporary files are cleaned up on open', () async {
      File('${dir.path}/items/$a.enc.3f9a.tmp').writeAsStringSync('half');
      await VaultStore(dir).open();
      expect(Directory('${dir.path}/items').listSync(), isEmpty);
    });
  });

  test('vault.json round-trips, including non-ASCII unknown fields', () async {
    final crypto = await VaultCrypto.init();
    final vault = await VaultKeys.create(
      crypto,
      password: 'pw',
      now: DateTime.utc(2026, 10, 7),
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
    final json = jsonDecode(vault.header.toJsonString()) as Map;
    json['note'] = 'Café ☕';
    final header = VaultHeader.parse(jsonEncode(json));

    expect(store.exists, isFalse);
    await store.writeHeader(header);
    expect(store.exists, isTrue);
    final read = await store.readHeader();
    expect(read.vkId, header.vkId);
    expect(read.unknownFields['note'], 'Café ☕');
    expect(writes, ['vault.json']);
  });
}
