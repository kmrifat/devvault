import 'dart:io';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  late Directory dir;
  late Vault vault;
  var clock = DateTime.utc(2026, 10, 7, 9);
  const device = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('index_');
    (vault, _) = await Vault.create(
      crypto: crypto,
      store: VaultStore(dir),
      password: 'pw',
      deviceId: device,
      now: () => clock = clock.add(const Duration(seconds: 1)),
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppRecord> app(String name, {List<String> bundleIds = const []}) =>
      vault.putApp(
        AppRecord(
          id: vault.newId(),
          name: name,
          bundleIds: bundleIds,
          createdAt: clock,
          updatedAt: clock,
          rev: Hlc.zero(device),
          deviceId: device,
        ),
      );

  Future<Item> item(
    String title,
    ItemType type, {
    AppRecord? app,
    String? platform,
    String? environment,
    List<String> tags = const [],
    Map<String, ItemField> fields = const {},
    DateTime? expires,
    String? notes,
  }) => vault.putItem(
    vault
        .newItem(type: type, title: title, fields: fields)
        .copyWith(
          appId: app?.id,
          platform: platform,
          environment: environment,
          tags: tags,
          expiresAt: expires,
          expiresSource: expires == null ? null : ExpirySource.file,
          notes: notes,
        ),
  );

  Future<VaultIndex> index() async => VaultIndex(await vault.loadAll());

  test('builds the App → Platform → Environment tree with counts', () async {
    final kitchenly = await app('Kitchenly');
    final fieldnote = await app('fieldnote');
    await item(
      'Upload keystore',
      ItemType.androidKeystore,
      app: kitchenly,
      platform: 'android',
      environment: 'production',
    );
    await item(
      'Play publisher',
      ItemType.gcpServiceAccount,
      app: kitchenly,
      platform: 'android',
      environment: 'production',
    );
    await item(
      'Staging keystore',
      ItemType.androidKeystore,
      app: kitchenly,
      platform: 'android',
      environment: 'staging',
    );
    await item(
      'APNs key',
      ItemType.appleAuthKey,
      app: kitchenly,
      platform: 'ios',
      environment: 'production',
    );
    await item('Distribution', ItemType.appleCertificate, app: fieldnote);
    await item('Sentry DSN', ItemType.genericSecret);

    final tree = (await index()).tree;
    expect(tree.map((n) => n.app?.name), ['fieldnote', 'Kitchenly', null]);
    final k = tree[1];
    expect(k.count, 4);
    expect(k.platforms.map((p) => (p.platform, p.count)), [
      ('android', 3),
      ('ios', 1),
    ]);
    expect(k.platforms.first.environments, {'production': 2, 'staging': 1});
    expect(tree[0].platforms.single.platform, isNull);
    expect(tree[2].count, 1, reason: 'No app group');
  });

  test('counts tags and orders expiries soonest first', () async {
    await item(
      'A',
      ItemType.appleCertificate,
      tags: ['release', 'signing'],
      expires: DateTime.utc(2027, 3, 4),
    );
    await item(
      'B',
      ItemType.provisioningProfile,
      tags: ['release'],
      expires: DateTime.utc(2026, 10, 19),
    );
    await item('C', ItemType.appleAuthKey, tags: ['push']);

    final idx = await index();
    expect(idx.tagCounts, {'push': 1, 'release': 2, 'signing': 1});
    expect(idx.byExpiry.map((i) => i.title), ['B', 'A']);
    expect(idx.all.map((i) => i.title), ['A', 'B', 'C']);
  });

  group('search', () {
    setUp(() async {
      final kitchenly = await app(
        'Kitchenly',
        bundleIds: ['com.kitchenly.app'],
      );
      await item(
        'Upload keystore',
        ItemType.androidKeystore,
        app: kitchenly,
        platform: 'android',
        environment: 'production',
        fields: const {
          'alias': ItemField(value: 'upload', source: FieldSource.file),
          'sha1': ItemField(
            value: '5E:8F:16:06:2E:A3:CD:2C',
            source: FieldSource.file,
          ),
          'store_password': ItemField(
            value: 'hunter2-store',
            source: FieldSource.user,
            secret: true,
          ),
        },
        notes: 'rotate after the audit',
      );
      await item(
        'APNs key',
        ItemType.appleAuthKey,
        platform: 'ios',
        fields: const {
          'key_id': ItemField(value: '7X2K9QH4LM', source: FieldSource.file),
        },
      );
    });

    Future<List<String>> find(String q) async =>
        (await index()).filter(query: q).map((i) => i.title).toList();

    test('finds titles, types, apps, bundle ids and key ids', () async {
      expect(await find('upload'), ['Upload keystore']);
      expect(await find('keystore'), ['Upload keystore']);
      expect(await find('com.kitchenly'), ['Upload keystore']);
      expect(await find('7x2k9'), ['APNs key']);
      expect(await find('apple auth'), ['APNs key']);
    });

    test('finds fingerprints with or without colons', () async {
      expect(await find('5E:8F:16'), ['Upload keystore']);
      expect(await find('5e8f16062e'), ['Upload keystore']);
    });

    test('every word has to match', () async {
      expect(await find('upload production'), ['Upload keystore']);
      expect(await find('upload ios'), isEmpty);
    });

    test('never matches secrets or notes', () async {
      expect(await find('hunter2'), isEmpty);
      expect(await find('audit'), isEmpty);
    });

    test('combines with the sidebar filters', () async {
      final idx = await index();
      expect(idx.filter(platform: 'ios').map((i) => i.title), ['APNs key']);
      expect(idx.filter(withoutApp: true).map((i) => i.title), ['APNs key']);
      expect(idx.filter(platform: 'ios', query: 'upload'), isEmpty);
    });
  });

  group('organizations and identifiers', () {
    Future<AppRecord> orgApp(
      String name, {
      String? organization,
      List<AppIdentifier> identifiers = const [],
    }) => vault.putApp(
      vault.newApp(
        name: name,
        organization: organization,
        identifiers: identifiers,
      ),
    );

    test('search finds every identifier kind and the organization, never '
        'secrets', () async {
      final billing = await orgApp(
        'Billing API',
        organization: 'Acme Corp',
        identifiers: [
          AppIdentifier.of(IdentifierKind.domain, 'api.acme.example'),
          AppIdentifier.of(IdentifierKind.repository, 'github.com/acme/bill'),
          AppIdentifier.of(IdentifierKind.url, 'https://status.acme.example'),
          AppIdentifier.of(IdentifierKind.other, 'acct_1Billing'),
          AppIdentifier.of(IdentifierKind.packageName, 'com.acme.android'),
        ],
      );
      await item(
        'Stripe key',
        ItemType.genericSecret,
        app: billing,
        fields: const {
          'value': ItemField(
            value: 'sk_live_secret',
            source: FieldSource.user,
            secret: true,
          ),
        },
      );
      await item('Other', ItemType.genericSecret);
      final idx = await index();
      List<String> find(String q) =>
          idx.filter(query: q).map((i) => i.title).toList();
      expect(find('api.acme.example'), ['Stripe key']);
      expect(find('github.com/acme'), ['Stripe key']);
      expect(find('status.acme'), ['Stripe key']);
      expect(find('acct_1billing'), ['Stripe key']);
      expect(find('com.acme.android'), ['Stripe key']);
      expect(find('acme corp'), ['Stripe key']);
      expect(find('sk_live'), isEmpty);
    });

    test('app notes are never searchable', () async {
      final billing = await vault.putApp(
        vault.newApp(name: 'Billing API', notes: 'Rotate **quarterly**'),
      );
      await item('Stripe key', ItemType.genericSecret, app: billing);
      final idx = await index();
      expect(idx.filter(query: 'billing').map((i) => i.title), ['Stripe key']);
      expect(idx.filter(query: 'quarterly'), isEmpty);
    });

    test('lists organizations and groups the tree by them', () async {
      final billing = await orgApp('Billing API', organization: 'Acme Corp');
      final web = await orgApp('Web', organization: 'acme labs');
      final kitchenly = await orgApp('Kitchenly');
      await orgApp('Unused', organization: 'Zeta');
      await item('A', ItemType.genericSecret, app: billing);
      await item('B', ItemType.genericSecret, app: web);
      await item('C', ItemType.genericSecret, app: kitchenly);
      await item('D', ItemType.genericSecret);

      final idx = await index();
      expect(idx.organizations, ['Acme Corp', 'acme labs', 'Zeta']);
      expect(
        [
          for (final g in idx.orgGroups)
            (
              g.organization,
              [for (final n in g.apps) n.app!.name].join(', '),
              g.count,
            ),
        ],
        [
          ('Acme Corp', 'Billing API', 1),
          ('acme labs', 'Web', 1),
          // Its only app has no items, so isn't in the tree.
          ('Zeta', '', 0),
          (null, 'Kitchenly', 1),
        ],
      );
      expect(idx.filter(organization: 'Acme Corp').map((i) => i.title), ['A']);
      expect(idx.filter(personal: true).map((i) => i.title), ['C']);
    });

    test('no organization anywhere: the tree stays flat', () async {
      final kitchenly = await orgApp('Kitchenly');
      await item('C', ItemType.genericSecret, app: kitchenly);
      final idx = await index();
      expect(idx.organizations, isEmpty);
      expect(idx.orgGroups, isEmpty);
    });
  });

  group('organization records (SPEC §6.7)', () {
    Future<OrganizationRecord> org(String name) =>
        vault.putOrganization(vault.newOrganization(name: name));

    Future<AppRecord> orgApp(String name, {String? organization}) =>
        vault.putApp(vault.newApp(name: name, organization: organization));

    List<(String?, String, int, int)> groups(VaultIndex idx) => [
      for (final g in idx.orgGroups)
        (
          g.organization,
          [for (final n in g.apps) n.app!.name].join(', '),
          g.count,
          g.records.length,
        ),
    ];

    test('an organization without apps is listed and gets a group', () async {
      final globex = await org('Globex');
      final idx = await index();
      expect(idx.organizationRecords.keys, [globex.id]);
      expect(idx.organizations, ['Globex']);
      expect(groups(idx), [
        ('Globex', '', 0, 1),
      ], reason: 'no Personal group: no app lacks an organization');
      expect(idx.orgGroups.single.records.single.id, globex.id);
    });

    test('a record and the apps naming it are one group', () async {
      final acme = await org('Acme Corp');
      final billing = await orgApp('Billing API', organization: 'Acme Corp');
      final web = await orgApp('Web', organization: 'Initech');
      await item('A', ItemType.genericSecret, app: billing);
      await item('B', ItemType.genericSecret, app: web);
      await item('C', ItemType.genericSecret, app: billing);
      final idx = await index();
      expect(idx.organizations, ['Acme Corp', 'Initech']);
      expect(groups(idx), [
        ('Acme Corp', 'Billing API', 2, 1),
        ('Initech', 'Web', 1, 0),
      ]);
      expect(idx.orgGroups.first.records.single.id, acme.id);
      expect(idx.filter(organization: 'Acme Corp').map((i) => i.title), [
        'A',
        'C',
      ]);
    });

    test('records with the same name are one organization', () async {
      final first = await org('Globex');
      final second = await org('Globex');
      final idx = await index();
      expect(idx.organizations, ['Globex']);
      expect(groups(idx), [('Globex', '', 0, 2)]);
      expect(
        idx.orgGroups.single.records.map((r) => r.id),
        ([first.id, second.id]..sort()),
      );
    });

    test('organizations sort A–Z ignoring case; Personal comes last, '
        'only when an app has no organization', () async {
      await org('zeta');
      await org('Acme');
      final kitchenly = await orgApp('Kitchenly');
      await item('K', ItemType.genericSecret, app: kitchenly);
      await item('No app', ItemType.genericSecret);
      final idx = await index();
      expect(idx.organizations, ['Acme', 'zeta']);
      expect(groups(idx), [
        ('Acme', '', 0, 1),
        ('zeta', '', 0, 1),
        (null, 'Kitchenly', 1, 0),
      ]);
      // The "No app" node stays out of the groups.
      expect(idx.tree.last.app, isNull);
    });
  });

  test('passes quarantined objects through for the UI', () async {
    final a = await item('A', ItemType.genericSecret);
    final b = await item('B', ItemType.genericSecret);
    File('${dir.path}/items/${a.id}.enc')
        .copySync('${dir.path}/items/${b.id}.enc');
    final idx = await index();
    expect(idx.items.keys, [a.id]);
    expect(idx.quarantined.single.objectId, b.id);
  });

  test('1,000 items load and index quickly', () async {
    for (var i = 0; i < 1000; i++) {
      await item(
        'Item $i',
        ItemType.values[i % ItemType.values.length],
        tags: ['t${i % 7}'],
        platform: i.isEven ? 'ios' : 'android',
      );
    }
    final watch = Stopwatch()..start();
    final idx = await index();
    final searched = idx.filter(query: 'item 99');
    watch.stop();
    expect(idx.items, hasLength(1000));
    expect(searched.map((i) => i.title), containsAll(['Item 99', 'Item 990']));
    // ignore: avoid_print
    print('load + index of 1000 items: ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));

    // P1-20: a search over 1,000 items answers within a frame (16 ms).
    // Best of a few runs, so a busy CI machine doesn't fail it.
    final runs = <Duration>[];
    for (var i = 0; i < 5; i++) {
      final search = Stopwatch()..start();
      idx.filter(query: 'item 9 ios', platform: 'ios');
      runs.add(search.elapsed);
    }
    runs.sort();
    // ignore: avoid_print
    print('search over 1000 items: ${runs.first.inMicroseconds} µs');
    expect(runs.first, lessThan(const Duration(milliseconds: 16)));
    // Writing the 1,000 items (atomic, fsynced) is the slow part, not what
    // is measured: on a Windows runner it can take most of the default 30 s.
  }, timeout: const Timeout(Duration(minutes: 3)));
}
