// P0-15: a vault written on one OS opens on another. CI (core-matrix.yml)
// makes a vault on each desktop OS, then opens every other OS's vault.
//
//   cd packages/vault_core
//   dart run tool/cross_vault.dart make <dir>      # a vault + expect.json
//   dart run tool/cross_vault.dart open <dir>...   # unlock and compare
//
// The vaults are throwaway: expect.json holds their password and recovery
// key so the other side can check both ways in.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

const _password = 'cross platform vault: first password';
const _newPassword = 'cross platform vault: changed password';

Future<void> main(List<String> args) async {
  if (args.length < 2 || !{'make', 'open'}.contains(args.first)) {
    stderr.writeln('usage: cross_vault.dart make <dir> | open <dir>...');
    exitCode = 64;
    return;
  }
  final crypto = await VaultCrypto.init();
  if (args.first == 'make') {
    await make(crypto, Directory(args[1]));
  } else {
    var failed = false;
    for (final dir in args.skip(1)) {
      final problems = await open(crypto, Directory(dir));
      if (problems.isEmpty) {
        stdout.writeln('OK   $dir');
      } else {
        failed = true;
        stdout.writeln('FAIL $dir');
        for (final p in problems) {
          stdout.writeln('  $p');
        }
      }
    }
    if (failed) exitCode = 1;
  }
}

/// Writes a vault to [dir]/vault and what it should hold to
/// [dir]/expect.json.
Future<void> make(VaultCrypto crypto, Directory dir) async {
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final root = Directory('${dir.path}/vault')..createSync(recursive: true);
  var clock = DateTime.now().toUtc();
  DateTime now() => clock = clock.add(const Duration(milliseconds: 1));
  final deviceId = '00000000-0000-4000-8000-${_platformTag()}';

  final (vault, recoveryKey) = await Vault.create(
    crypto: crypto,
    store: VaultStore(root),
    password: _password,
    deviceId: deviceId,
    now: now,
  );

  final app = await vault.putApp(
    vault.newApp(name: 'Kitchenly · ${Platform.operatingSystem}'),
  );
  final file = Uint8List.fromList([
    for (var i = 0; i < 300 * 1024; i++) (i * 31 + 7) % 256,
  ]);
  final attachment = await vault.addAttachment(
    file,
    filename: 'upload-keystore.jks',
  );
  final items = <Item>[
    await vault.putItem(
      vault
          .newItem(type: ItemType.androidKeystore, title: 'Upload keystore')
          .copyWith(
            appId: app.id,
            attachments: [attachment],
            fields: const {
              'alias': ItemField(value: 'upload', source: FieldSource.file),
              'store_password': ItemField(
                value: 'p@ss\r\nwith line endings',
                source: FieldSource.user,
                secret: true,
              ),
            },
            expiresAt: DateTime.utc(2051, 1, 14),
            expiresSource: ExpirySource.file,
          ),
    ),
    await vault.putItem(
      vault
          .newItem(type: ItemType.genericSecret, title: 'Clé d’API · 鍵 · ключ')
          .copyWith(
            fields: const {
              'value': ItemField(
                value: 'sk_live_ünïcode',
                source: FieldSource.user,
                secret: true,
              ),
            },
            tags: ['ci', 'prod'],
          ),
    ),
  ];
  // A password change rewrites vault.json in place: that path too.
  await vault.changePassword(_newPassword);

  File('${dir.path}/expect.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'made_on': Platform.operatingSystem,
      'vault_id': vault.vaultId,
      'password': _newPassword,
      'recovery_key': recoveryKey.toDisplayString(),
      'app': app.toJson(),
      'items': [for (final item in items) item.toJson()],
      'files': {attachment.blobId: VaultCrypto.sha256(file).toList()},
    }),
  );
  vault.lock();
  recoveryKey.dispose();
  stdout.writeln('Made ${vault.vaultId} on ${Platform.operatingSystem}');
}

/// Opens [dir]'s vault by password and by recovery key; returns what didn't
/// match expect.json (empty when everything did).
Future<List<String>> open(VaultCrypto crypto, Directory dir) async {
  final expected = jsonDecode(
    File('${dir.path}/expect.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final problems = <String>[];
  final madeOn = expected['made_on'];
  final deviceId = '00000000-0000-4000-8000-${_platformTag()}';
  DateTime now() => DateTime.now().toUtc();

  Future<void> check(String how, Future<Vault> Function() unlock) async {
    final Vault vault;
    try {
      vault = await unlock();
    } on Object catch (e) {
      problems.add('$how: unlock failed (${e.runtimeType})');
      return;
    }
    if (vault.vaultId != expected['vault_id']) {
      problems.add('$how: vault id ${vault.vaultId}');
    }
    final contents = await vault.loadAll();
    if (contents.quarantined.isNotEmpty) {
      problems.add('$how: ${contents.quarantined.length} unreadable objects');
    }
    final app = contents.apps.values.firstOrNull;
    if (jsonEncode(app?.toJson()) != jsonEncode(expected['app'])) {
      problems.add('$how: the app differs');
    }
    for (final json in (expected['items']! as List).cast<Map>()) {
      final want = Item.fromJson(json.cast<String, Object?>());
      final got = contents.items[want.id];
      if (got == null) {
        problems.add('$how: "${want.title}" is missing');
        continue;
      }
      if (jsonEncode(got.toJson()) != jsonEncode(want.toJson())) {
        problems.add('$how: "${want.title}" differs');
      }
      for (final attachment in got.attachments) {
        final bytes = await vault.readAttachment(attachment);
        final want = (expected['files']! as Map)[attachment.blobId] as List?;
        if (want == null ||
            !_same(VaultCrypto.sha256(bytes), want.cast<int>())) {
          problems.add('$how: ${attachment.filename} differs');
        }
      }
    }
    vault.lock();
  }

  final store = VaultStore(Directory('${dir.path}/vault'));
  await check(
    'password (made on $madeOn)',
    () => Vault.unlock(
      crypto: crypto,
      store: store,
      password: expected['password']! as String,
      deviceId: deviceId,
      now: now,
    ),
  );
  await check('recovery key (made on $madeOn)', () {
    final key = RecoveryKey.parse(crypto, expected['recovery_key']! as String);
    return Vault.unlockWithRecovery(
      crypto: crypto,
      store: store,
      recoveryKey: key,
      deviceId: deviceId,
      now: now,
    );
  });
  return problems;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A device id tail per OS, so each side writes as a different device.
String _platformTag() => switch (Platform.operatingSystem) {
  'macos' => '00000000000a',
  'windows' => '00000000000b',
  'linux' => '00000000000c',
  _ => '00000000000d',
};
