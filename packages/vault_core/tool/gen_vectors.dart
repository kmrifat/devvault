// Generates docs/format/vectors/: known-answer vectors for every primitive
// and a complete mini-vault, all from a fixed seed so the output never
// changes unless the format does.
//
//   cd packages/vault_core && dart run tool/gen_vectors.dart
//
// tools/vectorcheck (Go) verifies these independently; test/vectors_test.dart
// checks that this generator still reproduces the committed files.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

const password = 'correct horse battery staple';
const deviceId = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';

Future<void> main(List<String> args) async {
  final out = Directory(
    args.isNotEmpty ? args.first : '../../docs/format/vectors',
  );
  await generate(out);
  stdout.writeln('Wrote ${out.path}');
}

Future<void> generate(Directory out) async {
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);
  // Seeded randomness is exactly what reproducible vectors need.
  // ignore: invalid_use_of_visible_for_testing_member
  final crypto = await VaultCrypto.withFixedRandom(
    utf8.encode('devvault vectors v1'),
  );

  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  String keyHex(SecureKey k) => k.runUnlockedSync(hex);

  // --- Primitives -----------------------------------------------------------
  final salt = crypto.randomBytes(16);
  final argon = crypto.argon2id(
    password: KdfParams.passwordBytes(password),
    salt: salt,
    opsLimit: 3,
    memLimit: 64 * 1024 * 1024,
  );

  const vaultIdForKeys = '7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e';
  final recoveryKey = RecoveryKey.generate(crypto);
  final kek = crypto.hkdfSha256(
    ikm: recoveryKey.key,
    salt: VaultCrypto.utf8Bytes(vaultIdForKeys),
    info: VaultKeys.recoveryInfo,
  );

  final vk = crypto.randomKey();
  const objectId = '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6';
  final envelopes = [
    for (final (type, text) in [
      (ObjectType.item, '{"schema":1}'),
      (ObjectType.blob, 'raw file bytes'),
    ])
      {
        'key': keyHex(vk),
        'vault_id': vaultIdForKeys,
        'object_id': objectId,
        'object_type': type.wireName,
        'plaintext_hex': hex(utf8.encode(text)),
        'envelope_hex': hex(
          Envelope.seal(
            crypto,
            slot: ObjectSlot(
              vaultId: vaultIdForKeys,
              objectId: objectId,
              type: type,
            ),
            key: vk,
            plaintext: Uint8List.fromList(utf8.encode(text)),
          ),
        ),
      },
  ];

  final hlcs = [
    Hlc(1759827600000, 0, deviceId),
    Hlc(1759827600000, 1, deviceId),
    Hlc(1759827600000, 1, 'ffffffff-ffff-4fff-bfff-ffffffffffff'),
    Hlc(1759827600001, 0, '00000000-0000-4000-8000-000000000000'),
  ].map((h) => h.toString()).toList();

  final vectors = {
    'about': 'DevVault format v1 test vectors. See docs/format/SPEC.md.',
    'argon2id': [
      {
        'password': password,
        'password_utf8_nfc_hex': hex(KdfParams.passwordBytes(password)),
        'salt_hex': hex(salt),
        'ops_limit': 3,
        'mem_limit': 64 * 1024 * 1024,
        'parallelism': 1,
        'key_hex': keyHex(argon),
      },
    ],
    'recovery_kek': [
      {
        'recovery_key_hex': keyHex(recoveryKey.key),
        'recovery_key_text': recoveryKey.toDisplayString(),
        'vault_id': vaultIdForKeys,
        'info': VaultKeys.recoveryInfo,
        'kek_hex': keyHex(kek),
      },
    ],
    'vk_id': [
      {
        'vk_hex': keyHex(vk),
        'message': VaultKeys.vkIdMessage,
        'vk_id': VaultKeys.vkId(crypto, vk),
      },
    ],
    'envelope': envelopes,
    'hlc_sorted': hlcs,
  };
  File('${out.path}/vectors.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(vectors)}\n',
  );

  // --- Mini-vault -----------------------------------------------------------
  var clock = DateTime.utc(2026, 10, 7, 9);
  DateTime now() => clock = clock.add(const Duration(minutes: 1));
  final vaultsDir = Directory('${out.path}/mini-vault')..createSync();

  // The vault id comes from the seeded randomness, so create it in a staging
  // folder and move it into place under its id.
  final staging = Directory('${vaultsDir.path}/staging');
  final (vault, miniRecovery) = await Vault.create(
    crypto: crypto,
    store: VaultStore(staging),
    password: password,
    deviceId: deviceId,
    now: now,
  );

  final app = await vault.putApp(
    AppRecord(
      id: vault.newId(),
      name: 'Kitchenly',
      bundleIds: const ['com.kitchenly.app'],
      packageNames: const ['com.kitchenly.app'],
      createdAt: clock,
      updatedAt: clock,
      rev: Hlc.zero(deviceId),
      deviceId: deviceId,
    ),
  );
  final p8 = utf8.encode(
    '-----BEGIN PRIVATE KEY-----\n'
    'MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgVEK5Tyt5r1rP0d1O\n'
    '-----END PRIVATE KEY-----\n',
  );
  final attachment = await vault.addAttachment(
    Uint8List.fromList(p8),
    filename: 'AuthKey_7X2K9QH4LM.p8',
    mime: 'application/pkcs8',
  );
  final apns = await vault.putItem(
    vault
        .newItem(
          type: ItemType.appleAuthKey,
          title: 'APNs key',
          fields: const {
            'key_id': ItemField(value: '7X2K9QH4LM', source: FieldSource.file),
            'team_id': ItemField(value: 'A1B2C3D4E5', source: FieldSource.user),
          },
        )
        .copyWith(
          appId: app.id,
          platform: 'ios',
          environment: 'production',
          tags: ['push'],
          attachments: [attachment],
        ),
  );
  final cert = await vault.putItem(
    vault
        .newItem(
          type: ItemType.genericSecret,
          title: 'Sentry DSN',
          fields: const {
            'value': ItemField(
              value: 'https://abc@o1.ingest.sentry.io/1',
              source: FieldSource.user,
              secret: true,
            ),
          },
        )
        .copyWith(
          expiresAt: DateTime.utc(2027, 3, 4),
          expiresSource: ExpirySource.user,
        ),
  );
  final doomed = await vault.putItem(
    vault.newItem(type: ItemType.genericSecret, title: 'Old token'),
  );
  await vault.delete(doomed.id, TombstoneKind.item);
  vault.lock();
  staging.renameSync('${vaultsDir.path}/${vault.vaultId}');

  final expected = {
    'password': password,
    'recovery_key_text': miniRecovery.toDisplayString(),
    'vault_id': vault.vaultId,
    'vk_id': vault.header.vkId,
    'items': {
      for (final item in [apns, cert])
        item.id: {
          'type': item.typeName,
          'title': item.title,
          'fields': {for (final f in item.fields.entries) f.key: f.value.value},
          'attachments': [
            for (final a in item.attachments)
              {'blob_id': a.blobId, 'filename': a.filename, 'sha256': a.sha256},
          ],
        },
    },
    'apps': {app.id: app.name},
    'tombstones': [doomed.id],
  };
  File('${out.path}/mini-vault.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
  );
}
