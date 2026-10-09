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

  test('app records normalize to their committed canonical bytes', () {
    final vectors = jsonDecode(
      File('${committed.path}/vectors.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final cases = vectors['app_records']! as List<Object?>;
    expect(cases, isNotEmpty);
    for (final c in cases.cast<Map<String, Object?>>()) {
      final app = AppRecord.fromJson(c['record']);
      final canonical = c['canonical']! as String;
      expect(
        utf8.decode(encodeRecord(app)),
        canonical,
        reason: '${c['about']}',
      );
      expect(
        [
          for (final id in app.allIdentifiers)
            {'kind': id.kindName, 'value': id.value},
        ],
        c['identifiers'],
        reason: '${c['about']}',
      );
      // The canonical form reads back to itself.
      final again = decodeRecord(ObjectType.app, utf8.encode(canonical));
      expect(utf8.decode(encodeRecord(again)), canonical);
    }
  });

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

    final apps = expected['app_records']! as Map<String, Object?>;
    expect(contents.apps.keys.toSet(), apps.keys.toSet());
    for (final MapEntry(key: id, value: want as Map) in apps.entries) {
      final app = contents.apps[id]!;
      expect(app.name, want['name']);
      expect(app.organization, want['organization']);
      expect(app.kindName, want['kind']);
      expect(app.bundleIds, want['bundle_ids']);
      expect(app.packageNames, want['package_names']);
      expect([
        for (final i in app.identifiers) i.toJson(),
      ], want['identifiers']);
      expect(app.notes, want['notes']);
    }

    final organizations = expected['organizations']! as Map<String, Object?>;
    expect(organizations, isNotEmpty);
    expect({
      for (final o in contents.organizations.values) o.id: o.name,
    }, organizations);
    // Globex has no apps; Acme Corp exists through an app alone. Both are
    // organizations (SPEC §6.7).
    final index = VaultIndex(contents);
    expect(index.organizations, ['Acme Corp', 'Globex']);
    expect(
      [for (final g in index.orgGroups) (g.organization, g.records.length)],
      [('Acme Corp', 0), ('Globex', 1), (null, 0)],
    );

    final recovery = RecoveryKey.parse(
      crypto,
      expected['recovery_key_text']! as String,
    );
    VaultKeys.unlockWithRecovery(crypto, vault.header, recovery).dispose();
  });
}
