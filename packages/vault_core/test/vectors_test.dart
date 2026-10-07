import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

import '../tool/gen_vectors.dart' as gen;

/// The committed vectors in docs/format/vectors are the format contract.
/// tools/vectorcheck (Go) verifies them independently; these tests make sure
/// this implementation still produces and reads exactly those bytes.
void main() {
  final committed = Directory('../../docs/format/vectors');

  test(
    'the generator reproduces the committed vectors byte for byte',
    () async {
      final fresh = Directory.systemTemp.createTempSync('vectors_');
      addTearDown(() => fresh.deleteSync(recursive: true));
      await gen.generate(fresh);

      List<String> files(Directory d) => [
        for (final f in d.listSync(recursive: true).whereType<File>())
          f.path.substring(d.path.length),
      ]..sort();

      expect(files(fresh), files(committed));
      for (final path in files(committed)) {
        expect(
          File('${fresh.path}$path').readAsBytesSync(),
          File('${committed.path}$path').readAsBytesSync(),
          reason: 'format output changed: $path (update SPEC + vectors)',
        );
      }
    },
  );

  test('the committed mini-vault opens and holds what it should', () async {
    final expected = jsonDecode(
      File('${committed.path}/mini-vault.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final crypto = await VaultCrypto.init();
    final copy = Directory.systemTemp.createTempSync('mini_vault_');
    addTearDown(() => copy.deleteSync(recursive: true));
    final source = Directory(
      '${committed.path}/mini-vault/${expected['vault_id']}',
    );
    for (final f in source.listSync(recursive: true).whereType<File>()) {
      final target = File(
        '${copy.path}${f.path.substring(source.path.length)}',
      );
      target.parent.createSync(recursive: true);
      f.copySync(target.path);
    }

    final vault = await Vault.unlock(
      crypto: crypto,
      store: VaultStore(copy),
      password: expected['password']! as String,
      deviceId: gen.deviceId,
      now: () => DateTime.utc(2026, 10, 8),
    );
    expect(vault.header.vkId, expected['vk_id']);
    final contents = await vault.loadAll();
    expect(contents.quarantined, isEmpty);

    final items = expected['items']! as Map<String, Object?>;
    expect(contents.items.keys.toSet(), items.keys.toSet());
    for (final MapEntry(key: id, value: want as Map) in items.entries) {
      final item = contents.items[id]!;
      expect(item.title, want['title']);
      expect(item.typeName, want['type']);
      for (final a in item.attachments) {
        final bytes = await vault.readAttachment(a);
        expect(bytes, isNotEmpty);
      }
    }

    final recovery = RecoveryKey.parse(
      crypto,
      expected['recovery_key_text']! as String,
    );
    VaultKeys.unlockWithRecovery(crypto, vault.header, recovery).dispose();
  });
}
