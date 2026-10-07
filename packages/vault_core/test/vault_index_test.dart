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
  });
}
