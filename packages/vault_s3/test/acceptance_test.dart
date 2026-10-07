/// P2-14 acceptance run against a real S3-compatible store.
///
/// Runs only when `S3_TEST_ENDPOINT` and friends are set (see
/// `s3_backend_test.dart`): MinIO in CI, or any provider by hand. Each run
/// works under its own `acceptance-<timestamp>/` folder in the bucket.
/// Results are written up in `docs/acceptance/p2.md`.
@Tags(['acceptance'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

void main() {
  final env = Platform.environment;
  final endpoint = env['S3_TEST_ENDPOINT'];
  final skip = endpoint == null ? 'S3_TEST_ENDPOINT not set' : false;

  late VaultCrypto crypto;
  late Directory dir;
  late String folder;
  final log = <String>[];

  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() {
    dir = Directory.systemTemp.createTempSync('devvault_acceptance_');
    folder = 'acceptance-${DateTime.now().microsecondsSinceEpoch}/';
    log.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  S3Backend backend() => S3Backend(
    config: S3Config(
      endpoint: Uri.parse(endpoint!),
      bucket: env['S3_TEST_BUCKET']!,
      region: env['S3_TEST_REGION'] ?? 'us-east-1',
      pathStyle: env['S3_TEST_VIRTUAL_HOST'] == null,
    ),
    credentials: AwsCredentials(
      accessKeyId: env['S3_TEST_ACCESS_KEY']!,
      secretAccessKey: env['S3_TEST_SECRET_KEY']!,
    ),
    onLog: log.add,
  );

  var clock = DateTime.utc(2026, 10, 7, 9);
  DateTime now() => clock = clock.add(const Duration(seconds: 1));

  Future<Vault> createVault(String password) async {
    final (vault, recovery) = await Vault.create(
      crypto: crypto,
      store: VaultStore(Directory('${dir.path}/a')),
      password: password,
      deviceId: '00000000-0000-4000-8000-0000000000aa',
      now: now,
      opsLimit: 1,
      memLimit: KdfParams.minMemLimit,
    );
    recovery.dispose();
    return vault;
  }

  /// A second device with a copy of everything in the bucket.
  Future<Vault> join(S3Backend s3, String vaultId, String password) async {
    final root = Directory('${dir.path}/b');
    final prefix = '$folder$vaultId/';
    for (final o in await s3.list(prefix)) {
      final f = File('${root.path}/${o.key.substring(prefix.length)}');
      await f.parent.create(recursive: true);
      await f.writeAsBytes((await s3.get(o.key))!.bytes);
    }
    return Vault.unlock(
      crypto: crypto,
      store: VaultStore(root),
      password: password,
      deviceId: '00000000-0000-4000-8000-0000000000bb',
      now: now,
    );
  }

  SyncEngine engine(Vault v, StorageBackend s3) =>
      SyncEngine(vault: v, backend: s3, rootPrefix: folder, now: () => clock);

  Future<Item> addSecret(Vault v, String title, String secret) => v.putItem(
    v.newItem(
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

  test('a password change is one PUT, of vault.json', () async {
    final s3 = backend();
    addTearDown(s3.close);
    final a = await createVault('first password');
    await addSecret(a, 'Stripe key', 'sk_live_acceptance');
    await engine(a, s3).sync();

    await a.changePassword('second password');
    log.clear();
    await engine(a, s3).sync();
    final writes = log.where((l) => !l.startsWith('GET list')).toList();
    // ignore: avoid_print
    print('Request log for a password change:\n  ${log.join('\n  ')}');
    expect(writes, hasLength(1));
    expect(writes.single, matches(RegExp(r'^PUT .*/vault\.json 200 ')));
  }, skip: skip);

  test('nothing in the bucket is readable without the vault key', () async {
    final s3 = backend();
    addTearDown(s3.close);
    final a = await createVault('pw');
    await addSecret(a, 'GitHub deploy key', 'ghp_acceptance_marker');
    final file = await a.addAttachment(
      Uint8List.fromList(utf8.encode('-----BEGIN PRIVATE KEY----- marker')),
      filename: 'AuthKey_ACCEPT0001.p8',
    );
    final item = await addSecret(a, 'APNs', 'apns-marker');
    await a.putItem(item.copyWith(attachments: [file]));
    await engine(a, s3).sync();

    final keys = (await s3.list('$folder${a.vaultId}/')).map((o) => o.key);
    for (final key in keys) {
      final text = latin1.decode((await s3.get(key))!.bytes);
      for (final marker in [
        'ghp_acceptance_marker',
        'apns-marker',
        'GitHub deploy key',
        'BEGIN PRIVATE KEY',
        'AuthKey_ACCEPT0001',
      ]) {
        expect(text, isNot(contains(marker)), reason: '$marker in $key');
      }
    }
    // And a different key can't open any object.
    final other = await createVaultElsewhere(crypto, dir);
    for (final key in keys.where((k) => k.contains('/items/'))) {
      final id = key.split('/').last.replaceAll('.enc', '');
      expect(
        other.openRecord(ObjectType.item, id, (await s3.get(key))!.bytes),
        isNull,
      );
    }
  }, skip: skip);

  test('an object copied over another (AAD swap) is refused', () async {
    final s3 = backend();
    addTearDown(s3.close);
    final a = await createVault('pw');
    final x = await addSecret(a, 'X', 'x');
    final y = await addSecret(a, 'Y', 'y');
    await engine(a, s3).sync();
    final b = await join(s3, a.vaultId, 'pw');
    await engine(b, s3).sync();

    final prefix = '$folder${a.vaultId}/items/';
    final xBytes = (await s3.get('$prefix${x.id}.enc'))!.bytes;
    await s3.put('$prefix${y.id}.enc', xBytes);
    final report = await engine(b, s3).sync();
    expect(report.unreadable, 1);
    expect((await b.loadAll()).items[y.id]!.title, 'Y');
  }, skip: skip);

  test(
    'concurrent offline edits: nothing lost, both devices converge',
    () async {
      final s3 = backend();
      addTearDown(s3.close);
      final a = await createVault('pw');
      final item = await addSecret(a, 'Token', 'v0');
      await engine(a, s3).sync();
      final b = await join(s3, a.vaultId, 'pw');
      await engine(b, s3).sync();

      // Both offline: each edits the same secret and something else.
      Future<void> edit(Vault v, String secret, String title) async {
        final current = (await v.loadAll()).items[item.id]!;
        await v.putItem(
          current.copyWith(
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
      }

      await edit(a, 'from-a', 'Token');
      await edit(b, 'from-b', 'Token (renamed on B)');
      await engine(a, s3).sync();
      final merge = await engine(b, s3).sync();
      await engine(a, s3).sync();
      expect(merge.conflicts, 1);

      final onA = (await a.loadAll()).items[item.id]!;
      final onB = (await b.loadAll()).items[item.id]!;
      expect(onA.toJson(), onB.toJson());
      expect(onA.title, 'Token (renamed on B)');
      final values = {
        onA.fields['value']!.value,
        for (final v in Conflict.of(onA).versions) v.fields['value']!.value,
      };
      expect(values, containsAll(['from-a', 'from-b']));
    },
    skip: skip,
  );
}

/// An unrelated vault: its key must not open this vault's objects.
Future<Vault> createVaultElsewhere(VaultCrypto crypto, Directory dir) async {
  final (vault, recovery) = await Vault.create(
    crypto: crypto,
    store: VaultStore(Directory('${dir.path}/elsewhere')),
    password: 'unrelated',
    deviceId: '00000000-0000-4000-8000-0000000000cc',
    now: DateTime.now,
    opsLimit: 1,
    memLimit: KdfParams.minMemLimit,
  );
  recovery.dispose();
  return vault;
}
