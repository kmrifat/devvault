import 'dart:typed_data';

import 'package:devvault/data/vault_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

/// Organization records through the session (SPEC §6.7): each rename or
/// delete is one operation over the records and the apps that name them.
void main() {
  setUpAll(loadTestCrypto);

  late ProviderContainer container;

  VaultSessionNotifier session() =>
      container.read(vaultSessionProvider.notifier);
  Unlocked unlocked() => container.read(vaultSessionProvider) as Unlocked;
  VaultIndex index() => unlocked().index;
  List<String> recordNames() =>
      [for (final org in index().organizationRecords.values) org.name]..sort();
  Map<String, String?> appOrgs() => {
    for (final app in index().apps.values) app.name: app.organization,
  };

  setUp(() async {
    final dir = await testSupportDir(TestVault.locked);
    container = ProviderContainer(overrides: testOverrides(supportDir: dir));
    addTearDown(container.dispose);
    await session().unlock(testPassword);
  });

  Future<AppRecord> app(String name, {String? organization}) => session()
      .saveApp(session().newApp(name).copyWith(organization: organization));

  test('an organization saved with no apps is in the index', () async {
    final saved = await session().saveOrganization(
      session().newOrganization(' Globex '),
    );
    expect(saved.name, 'Globex');
    expect(index().organizationRecords.keys, [saved.id]);
    expect(index().organizations, ['Globex']);
    expect(index().orgGroups.single.apps, isEmpty);
    // It's on disk, not just in memory.
    final contents = await unlocked().vault.loadAll();
    expect(contents.organizations[saved.id]!.name, 'Globex');
  });

  test('renaming rewrites the records and every app that names it', () async {
    final acme = await session().saveOrganization(
      session().newOrganization('Acme'),
    );
    final twin = await session().saveOrganization(
      session().newOrganization('Acme'),
    );
    await app('Billing API', organization: 'Acme');
    await app('Web', organization: 'Acme');
    await app('Kitchenly');
    await session().saveOrganization(session().newOrganization('Initech'));

    await session().renameOrganization('Acme', 'Acme Corp');

    expect(recordNames(), ['Acme Corp', 'Acme Corp', 'Initech']);
    expect(index().organizationRecords[acme.id]!.name, 'Acme Corp');
    expect(index().organizationRecords[twin.id]!.name, 'Acme Corp');
    expect(appOrgs(), {
      'Billing API': 'Acme Corp',
      'Web': 'Acme Corp',
      'Kitchenly': null,
    });
    expect(index().organizations, ['Acme Corp', 'Initech']);
  });

  test('renaming one that only apps name creates its record', () async {
    await app('Billing API', organization: 'Acme');
    expect(index().organizationRecords, isEmpty);

    await session().renameOrganization('Acme', 'Acme Corp');

    expect(recordNames(), ['Acme Corp']);
    expect(appOrgs(), {'Billing API': 'Acme Corp'});
  });

  test(
    'a read-only record stops the rename before anything is written',
    () async {
      final vault = unlocked().vault;
      final newer = OrganizationRecord.fromJson({
        ...vault.newOrganization(name: 'Acme').toJson(),
        'schema': recordSchema + 1,
      });
      // Written the way a newer client would have.
      await vault.store.write(
        ObjectType.organization,
        newer.id,
        _sealed(vault, newer),
      );
      await session().reload();
      await app('Billing API', organization: 'Acme');

      await expectLater(
        session().renameOrganization('Acme', 'Acme Corp'),
        throwsStateError,
      );
      expect(recordNames(), ['Acme']);
      expect(appOrgs(), {'Billing API': 'Acme'});
    },
  );

  test('deleting tombstones every record and clears it on its apps; the '
      'apps stay', () async {
    final acme = await session().saveOrganization(
      session().newOrganization('Acme'),
    );
    final twin = await session().saveOrganization(
      session().newOrganization('Acme'),
    );
    final globex = await session().saveOrganization(
      session().newOrganization('Globex'),
    );
    await app('Billing API', organization: 'Acme');
    await app('Web', organization: 'Globex');

    await session().deleteOrganization('Acme');

    expect(index().organizationRecords.keys, [globex.id]);
    expect(appOrgs(), {'Billing API': null, 'Web': 'Globex'});
    expect(index().organizations, ['Globex']);
    final contents = await unlocked().vault.loadAll();
    for (final id in [acme.id, twin.id]) {
      expect(contents.tombstones[id]!.kind, TombstoneKind.organization);
    }
  });

  test('deleting one that only apps name clears it on them', () async {
    await app('Billing API', organization: 'Acme');
    await session().deleteOrganization('Acme');
    expect(appOrgs(), {'Billing API': null});
    expect(index().organizations, isEmpty);
    expect(index().orgGroups, isEmpty);
  });
}

/// [record] encrypted for its slot, as a newer client would store it
/// ([Vault.putOrganization] refuses a read-only record).
Uint8List _sealed(Vault vault, OrganizationRecord record) {
  final key = testCrypto.keyFromBytes(
    vault.withVaultKeyBytes(Uint8List.fromList),
  );
  try {
    return Envelope.seal(
      testCrypto,
      slot: ObjectSlot(
        vaultId: vault.vaultId,
        objectId: record.id,
        type: ObjectType.organization,
      ),
      key: key,
      plaintext: Uint8List.fromList(encodeRecord(record)),
    );
  } finally {
    key.dispose();
  }
}
