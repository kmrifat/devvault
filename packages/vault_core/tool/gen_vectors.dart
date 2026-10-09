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
    'app_records': _appRecordVectors(),
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
  // An app that isn't a mobile app, for an organization (SPEC §6.2).
  final billing = await vault.putApp(
    vault.newApp(
      name: 'Billing API',
      organization: 'Acme Corp',
      kindName: AppKind.backend.wireName,
      identifiers: [
        AppIdentifier.of(IdentifierKind.domain, 'api.acme.example'),
        AppIdentifier.of(
          IdentifierKind.repository,
          'github.com/acme/billing-api',
        ),
        AppIdentifier.of(IdentifierKind.bundleId, 'com.acme.billing'),
      ],
      notes: _billingNotes,
    ),
  );
  // An organization without apps (SPEC §6.7). Acme Corp has no record: it
  // exists through Billing API's organization alone.
  final globex = await vault.putOrganization(
    vault.newOrganization(name: 'Globex'),
  );
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
    'apps': {app.id: app.name, billing.id: billing.name},
    // What every app record holds, as SPEC §6.2 reads it.
    'app_records': {
      for (final a in [app, billing])
        a.id: {
          'name': a.name,
          'organization': a.organization,
          'kind': a.kindName,
          'bundle_ids': a.bundleIds,
          'package_names': a.packageNames,
          'identifiers': [for (final i in a.identifiers) i.toJson()],
          'notes': a.notes,
        },
    },
    'organizations': {globex.id: globex.name},
    'tombstones': [doomed.id],
  };
  File('${out.path}/mini-vault.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
  );
}

/// A Markdown note on an app (SPEC §6.2).
const _billingNotes =
    '## Billing API\n'
    '\n'
    'Rotate the **Stripe** keys every *90 days*:\n'
    '\n'
    '1. Create the new key in the dashboard.\n'
    '2. Run `make rotate-keys`.\n'
    '\n'
    '```sh\n'
    'make deploy ENV=production\n'
    '```\n'
    '\n'
    'Runbook: [wiki](https://wiki.acme.example/billing)';

/// SPEC §6.2: app records as a writer might have stored them, each with
/// the exact bytes a conforming writer stores when it rewrites the record
/// unchanged (`canonical`, the plaintext of §6's "compact, keys sorted"),
/// and every identifier a reader shows, in order.
List<Map<String, Object?>> _appRecordVectors() {
  Map<String, Object?> record(Map<String, Object?> fields) => {
    'schema': 1,
    'id': 'faf3ad88-4000-4edb-a4a8-03ba341039cb',
    'name': 'Billing API',
    'bundle_ids': <String>[],
    'package_names': <String>[],
    'icon_blob_id': null,
    'created_at': '2026-10-07T09:00:00Z',
    'updated_at': '2026-10-07T09:00:00Z',
    'rev': '001759827600000-00000-$deviceId',
    'device_id': deviceId,
    ...fields,
  };
  final cases = <(String, Map<String, Object?>)>[
    (
      'Written before organization, kind and identifiers existed: '
          'rewritten byte for byte.',
      record({
        'name': 'Kitchenly',
        'bundle_ids': ['com.kitchenly.app'],
        'package_names': ['com.kitchenly.android'],
      }),
    ),
    (
      'Every field set; bundle IDs stay in bundle_ids.',
      record({
        'organization': 'Acme Corp',
        'kind': 'backend',
        'bundle_ids': ['com.acme.billing'],
        'identifiers': [
          {'kind': 'domain', 'value': 'api.acme.example'},
          {'kind': 'url', 'value': 'https://billing.acme.example/admin'},
          {'kind': 'repository', 'value': 'github.com/acme/billing-api'},
          {'kind': 'other', 'value': 'Stripe account acct_1Acme'},
        ],
      }),
    ),
    (
      'Normalized: values trimmed, empty ones and repeats within a kind '
          'dropped, bundle_id and package_name entries moved to their '
          'arrays.',
      record({
        'organization': '  Acme Corp ',
        'kind': 'web',
        'bundle_ids': [' com.acme.app ', 'com.acme.app', ''],
        'identifiers': [
          {'kind': 'domain', 'value': ' acme.example '},
          {'kind': 'domain', 'value': 'acme.example'},
          {'kind': 'url', 'value': '   '},
          {'kind': 'bundle_id', 'value': 'com.acme.app'},
          {'kind': 'bundle_id', 'value': 'com.acme.widget'},
          {'kind': 'package_name', 'value': 'com.acme.android'},
          {'kind': 'repository', 'value': 'acme.example'},
        ],
      }),
    ),
    (
      'Empty organization and identifiers: left out.',
      record({'organization': ' ', 'kind': null, 'identifiers': <Object>[]}),
    ),
    (
      'Kinds and fields this version does not know: kept as they are.',
      record({
        'kind': 'game',
        'pinned': true,
        'identifiers': [
          {'kind': 'npm_package', 'value': '@acme/billing', 'scope': 'org'},
          {'kind': 'domain', 'value': 'acme.example', 'primary': true},
        ],
      }),
    ),
    (
      'Notes: Markdown text, kept as typed apart from white space trimmed '
          'at both ends.',
      record({'notes': '\n  $_billingNotes\n\n'}),
    ),
    (
      'Notes with raw HTML, an image and non-ASCII text: stored as text, '
          'nothing escaped that needn\'t be.',
      record({
        'notes':
            '<b>Not bold</b> & ![logo](https://acme.example/logo.png)\n'
            '\n'
            '> Café — \u65e5\u672c \u{1F511}',
      }),
    ),
    ('Empty notes: left out.', record({'notes': ' \n\t '})),
  ];
  return [
    for (final (about, json) in cases)
      () {
        final app = AppRecord.fromJson(json);
        return {
          'about': about,
          'record': json,
          'canonical': utf8.decode(encodeRecord(app)),
          'identifiers': [
            for (final id in app.allIdentifiers)
              {'kind': id.kindName, 'value': id.value},
          ],
        };
      }(),
  ];
}
