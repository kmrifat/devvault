import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late Directory dir;
  late VaultStore vault;
  late SyncStateStore sync;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('devvault_sync_state_');
    vault = VaultStore(Directory('${dir.path}/vaults/v1'));
    sync = SyncStateStore(vault);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('starts empty and round-trips', () async {
    expect((await sync.load()).remote, isEmpty);
    final state = SyncState(
      remote: {
        'vault.json': const SyncedObject(etag: '"h1"'),
        'items/a.enc': const SyncedObject(
          etag: '"e1"',
          rev: '000000000000001-00000-d',
        ),
      },
      dirty: {'items/b.enc'},
      lastSync: DateTime.utc(2026, 10, 7, 9),
      capabilities: const StorageCapabilities(
        conditionalCreate: true,
        conditionalUpdate: true,
        conditionalDelete: false,
      ),
    );
    await sync.save(state);
    final loaded = await sync.load();
    expect(loaded.remote, state.remote);
    expect(loaded.dirty, {'items/b.enc'});
    expect(loaded.lastSync, DateTime.utc(2026, 10, 7, 9));
    expect(loaded.capabilities, state.capabilities);
  });

  test('lives next to the vault folder, never inside it', () async {
    await sync.save(SyncState(dirty: {'items/a.enc'}));
    await sync.putBase('items/a.enc', Uint8List.fromList([1, 2, 3]));
    expect(sync.root.path, '${dir.path}/vaults/v1.sync');
    expect(Directory('${dir.path}/vaults/v1').existsSync(), isFalse);
    expect(
      File('${dir.path}/vaults/v1.sync/base/items/a.enc').readAsBytesSync(),
      [1, 2, 3],
    );
  });

  test('bases are stored, replaced and removed verbatim', () async {
    expect(await sync.base('items/a.enc'), isNull);
    await sync.putBase('items/a.enc', Uint8List.fromList([1]));
    await sync.putBase('items/a.enc', Uint8List.fromList([2]));
    expect(await sync.base('items/a.enc'), [2]);
    await sync.deleteBase('items/a.enc');
    expect(await sync.base('items/a.enc'), isNull);
    expect(() => sync.putBase('../x', Uint8List(1)), throwsArgumentError);
  });

  test('clear forgets everything; unknown formats are refused', () async {
    await sync.save(SyncState(dirty: {'x'}));
    await sync.clear();
    expect((await sync.load()).dirty, isEmpty);
    expect(
      () => SyncState.fromJson({'format': 99, 'remote': {}, 'dirty': []}),
      throwsFormatException,
    );
  });
}
