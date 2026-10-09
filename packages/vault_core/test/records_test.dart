import 'dart:convert';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  const id = '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6';
  const device = '2530b979-e992-4aaf-8aac-52a2ce7abaf4';
  const blob = '9e8d7c6b-5a49-4382-9170-6f5e4d3c2b1a';
  final rev = Hlc(1759827600000, 0, device);
  final sha = '3f9a0c7e' * 8;

  Map<String, Object?> keystoreJson() => {
    'schema': 1,
    'id': id,
    'type': 'android_keystore',
    'title': 'Upload keystore',
    'app_id': null,
    'platform': 'android',
    'environment': 'production',
    'tags': ['release', 'signing'],
    'fields': {
      'alias': {'value': 'upload', 'source': 'file'},
      'store_password': {
        'value': 'hunter2-store',
        'source': 'user',
        'secret': true,
      },
    },
    'attachments': [
      {
        'blob_id': blob,
        'filename': 'kitchenly-upload.jks',
        'mime': 'application/octet-stream',
        'size': 2614,
        'sha256': sha,
      },
    ],
    'expires_at': '2051-01-14T00:00:00Z',
    'expires_source': 'file',
    'notes': 'Upload key only.',
    'created_at': '2025-02-03T10:00:00Z',
    'updated_at': '2026-09-12T08:30:00Z',
    'rev': rev.toString(),
    'device_id': device,
    'conflict': null,
  };

  group('Item', () {
    test('round-trips the spec example', () {
      final item = Item.fromJson(keystoreJson());
      expect(item.type, ItemType.androidKeystore);
      expect(item.fields['store_password']!.secret, isTrue);
      expect(item.fields['alias']!.source, FieldSource.file);
      expect(item.expiresSource, ExpirySource.file);
      expect(item.expiresAt, DateTime.utc(2051, 1, 14));
      expect(item.attachments.single.sha256, sha);
      expect(item.toJson(), keystoreJson());
    });

    test('keeps fields this version does not know, at every level', () {
      final json = keystoreJson()
        ..['future'] = {'x': 1}
        ..['fields'] = {
          'alias': {'value': 'upload', 'source': 'file', 'confidence': 1},
        }
        ..['attachments'] = [
          <String, Object?>{
            ...((keystoreJson()['attachments']! as List).first
                as Map<String, Object?>),
            'compression': 'none',
          },
        ];
      final rewritten = Item.fromJson(json).toJson();
      expect(rewritten['future'], {'x': 1});
      expect(
        (rewritten['fields']! as Map)['alias'],
        containsPair('confidence', 1),
      );
      expect(
        (rewritten['attachments']! as List).single,
        containsPair('compression', 'none'),
      );
    });

    test('keeps an unknown type instead of dropping the item', () {
      final item = Item.fromJson(keystoreJson()..['type'] = 'team_secret');
      expect(item.type, isNull);
      expect(item.typeName, 'team_secret');
      expect(item.toJson()['type'], 'team_secret');
    });

    test('a newer schema is read-only', () {
      expect(Item.fromJson(keystoreJson()..['schema'] = 2).isReadOnly, isTrue);
      expect(Item.fromJson(keystoreJson()).isReadOnly, isFalse);
    });

    group('expiry is a fact or nothing', () {
      test('date without a source is rejected', () {
        expect(
          () => Item.fromJson(keystoreJson()..['expires_source'] = null),
          throwsA(isA<VaultFormatException>()),
        );
      });

      test('source without a date is rejected', () {
        expect(
          () => Item.fromJson(keystoreJson()..['expires_at'] = null),
          throwsA(isA<VaultFormatException>()),
        );
      });

      test('an inferred source is rejected', () {
        expect(
          () => Item.fromJson(keystoreJson()..['expires_source'] = 'guess'),
          throwsA(isA<VaultFormatException>()),
        );
      });

      test('no expiry at all is fine', () {
        final item = Item.fromJson(
          keystoreJson()
            ..['expires_at'] = null
            ..['expires_source'] = null,
        );
        expect(item.expiresAt, isNull);
        expect(item.expiresSource, isNull);
      });

      test('copyWith sets and clears the pair together', () {
        final item = Item.fromJson(keystoreJson());
        final userSet = item.copyWith(
          expiresAt: DateTime.utc(2027),
          expiresSource: ExpirySource.user,
        );
        expect(userSet.expiresSource, ExpirySource.user);
        final cleared = item.copyWith(clearExpiry: true);
        expect(cleared.expiresAt, isNull);
        expect(cleared.expiresSource, isNull);
      });
    });

    test('rejects malformed values without echoing them', () {
      final cases = {
        'id': 'not-a-uuid',
        'tags': 'release',
        'created_at': '2025-02-03',
        'rev': 'yesterday',
        'fields': {
          'x': {'value': 1, 'source': 'file'},
        },
      };
      for (final MapEntry(key: field, value: bad) in cases.entries) {
        expect(
          () => Item.fromJson(keystoreJson()..[field] = bad),
          throwsA(
            isA<VaultFormatException>().having(
              (e) => e.message,
              'message',
              isNot(contains(bad.toString())),
            ),
          ),
          reason: field,
        );
      }
    });

    test('never prints secrets, titles or notes', () {
      final item = Item.fromJson(keystoreJson());
      final printed = '$item ${item.fields.values.join(' ')}';
      expect(printed, isNot(contains('hunter2')));
      expect(printed, isNot(contains('Upload keystore')));
      expect(printed, isNot(contains('Upload key only')));
    });
  });

  group('encoding', () {
    test('records are compact JSON with sorted keys', () {
      final item = Item.fromJson(keystoreJson());
      final text = utf8.decode(encodeRecord(item));
      expect(text, startsWith('{"app_id":null,"attachments":'));
      expect(text, isNot(contains('\n')));
      expect(
        decodeRecord(ObjectType.item, encodeRecord(item)).toJson(),
        item.toJson(),
      );
    });

    test('non-JSON plaintext is a format error', () {
      expect(
        () => decodeRecord(ObjectType.item, utf8.encode('not json')),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => decodeRecord(ObjectType.item, [0xff, 0xfe]),
        throwsA(isA<VaultFormatException>()),
      );
    });
  });

  test('apps round-trip', () {
    final json = {
      'schema': 1,
      'id': id,
      'name': 'Kitchenly',
      'bundle_ids': ['com.kitchenly.app'],
      'package_names': ['com.kitchenly.app'],
      'icon_blob_id': null,
      'created_at': '2025-02-03T10:00:00Z',
      'updated_at': '2025-02-03T10:00:00Z',
      'rev': rev.toString(),
      'device_id': device,
    };
    final app = AppRecord.fromJson(json);
    expect(app.name, 'Kitchenly');
    expect(app.toJson(), json);
    expect(decodeRecord(ObjectType.app, encodeRecord(app)), isA<AppRecord>());
  });

  group('apps: organization, kind and identifiers (SPEC §6.2)', () {
    Map<String, Object?> appJson([Map<String, Object?> fields = const {}]) => {
      'schema': 1,
      'id': id,
      'name': 'Billing API',
      'bundle_ids': <String>[],
      'package_names': <String>[],
      'icon_blob_id': null,
      'created_at': '2025-02-03T10:00:00Z',
      'updated_at': '2025-02-03T10:00:00Z',
      'rev': rev.toString(),
      'device_id': device,
      ...fields,
    };

    test('round-trip with every field set', () {
      final json = appJson({
        'organization': 'Acme Corp',
        'kind': 'backend',
        'bundle_ids': ['com.acme.billing'],
        'package_names': ['com.acme.billing.android'],
        'identifiers': [
          {'kind': 'domain', 'value': 'api.acme.example'},
          {'kind': 'url', 'value': 'https://acme.example/billing'},
          {'kind': 'repository', 'value': 'github.com/acme/billing'},
          {'kind': 'other', 'value': 'Stripe acct_1'},
        ],
      });
      final app = AppRecord.fromJson(json);
      expect(app.organization, 'Acme Corp');
      expect(app.kind, AppKind.backend);
      expect(app.label, 'Acme Corp › Billing API');
      expect(app.allIdentifiers.map((i) => i.kind), [
        IdentifierKind.bundleId,
        IdentifierKind.packageName,
        IdentifierKind.domain,
        IdentifierKind.url,
        IdentifierKind.repository,
        IdentifierKind.other,
      ]);
      expect(app.toJson(), json);
      final again = decodeRecord(ObjectType.app, encodeRecord(app));
      expect(encodeRecord(again), encodeRecord(app));
    });

    test('an app written before these fields reads and rewrites unchanged', () {
      final json = appJson({
        'name': 'Kitchenly',
        'bundle_ids': ['com.kitchenly.app'],
        'package_names': ['com.kitchenly.android'],
      });
      final app = AppRecord.fromJson(json);
      expect(app.organization, isNull);
      expect(app.kindName, isNull);
      expect(app.identifiers, isEmpty);
      expect(app.label, 'Kitchenly');
      expect(app.allIdentifiers, [
        AppIdentifier.of(IdentifierKind.bundleId, 'com.kitchenly.app'),
        AppIdentifier.of(IdentifierKind.packageName, 'com.kitchenly.android'),
      ]);
      // No new keys: the bytes are exactly what an older writer stored.
      expect(app.toJson(), json);
      expect(utf8.decode(encodeRecord(app)), jsonEncode(sortKeys(json)));
    });

    test('unknown kinds and fields are kept, at both levels', () {
      final json = appJson({
        'kind': 'game',
        'pinned': true,
        'identifiers': [
          {'kind': 'npm_package', 'value': '@acme/billing', 'scope': 'org'},
          {'kind': 'domain', 'value': 'acme.example', 'primary': true},
        ],
      });
      final app = AppRecord.fromJson(json);
      expect(app.kind, isNull);
      expect(app.kindName, 'game');
      expect(app.identifiers.first.kind, isNull);
      expect(app.identifiers.first.kindLabel, 'npm_package');
      expect(app.unknownFields, {'pinned': true});
      expect(app.toJson(), json);
      // And through a rewrite by this version.
      final renamed = app.copyWith(name: 'Billing');
      expect(renamed.toJson()['pinned'], true);
      expect(renamed.toJson()['identifiers'], json['identifiers']);
      expect(renamed.toJson()['kind'], 'game');
    });

    test('an older client still reads bundle IDs and package names, and '
        'keeps the new fields when it rewrites the app', () {
      final app = AppRecord(
        id: id,
        name: 'Billing API',
        organization: 'Acme Corp',
        kindName: AppKind.mobile.wireName,
        identifiers: [
          AppIdentifier.of(IdentifierKind.bundleId, 'com.acme.app'),
          AppIdentifier.of(IdentifierKind.packageName, 'com.acme.android'),
          AppIdentifier.of(IdentifierKind.domain, 'acme.example'),
        ],
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        rev: rev,
        deviceId: device,
      );
      final stored =
          jsonDecode(utf8.decode(encodeRecord(app))) as Map<String, Object?>;
      // What the older reader looks at: only the arrays it always had.
      expect(stored['bundle_ids'], ['com.acme.app']);
      expect(stored['package_names'], ['com.acme.android']);
      expect(stored['identifiers'], [
        {'kind': 'domain', 'value': 'acme.example'},
      ]);

      // The older writer: its own fields, plus everything else verbatim
      // (SPEC §6: writers preserve unknown fields).
      const olderKnown = {
        'schema',
        'id',
        'name',
        'bundle_ids',
        'package_names',
        'icon_blob_id',
        'created_at',
        'updated_at',
        'rev',
        'device_id',
      };
      final rewritten = {
        for (final e in stored.entries)
          if (!olderKnown.contains(e.key)) e.key: e.value,
        for (final e in stored.entries)
          if (olderKnown.contains(e.key)) e.key: e.value,
        'bundle_ids': [...stored['bundle_ids']! as List, 'com.acme.widget'],
      };
      final back = AppRecord.fromJson(rewritten);
      expect(back.organization, 'Acme Corp');
      expect(back.kind, AppKind.mobile);
      expect(back.bundleIds, ['com.acme.app', 'com.acme.widget']);
      expect(back.identifiers, [
        AppIdentifier.of(IdentifierKind.domain, 'acme.example'),
      ]);
    });

    test('values are trimmed; empty ones and repeats within a kind dropped; '
        'bundle IDs and package names stored in their arrays', () {
      final app = AppRecord.fromJson(
        appJson({
          'organization': '  Acme Corp ',
          'kind': ' ',
          'bundle_ids': [' com.acme.app ', 'com.acme.app', ''],
          'identifiers': [
            {'kind': 'domain', 'value': ' acme.example '},
            {'kind': 'domain', 'value': 'acme.example'},
            {'kind': 'repository', 'value': 'acme.example'},
            {'kind': 'url', 'value': '   '},
            {'kind': ' ', 'value': 'nothing'},
            {'kind': 'bundle_id', 'value': 'com.acme.app'},
            {'kind': 'package_name', 'value': ' com.acme.android'},
          ],
        }),
      );
      expect(app.organization, 'Acme Corp');
      expect(app.kindName, isNull);
      expect(app.bundleIds, ['com.acme.app']);
      expect(app.packageNames, ['com.acme.android']);
      expect(app.identifiers, [
        AppIdentifier.of(IdentifierKind.domain, 'acme.example'),
        AppIdentifier.of(IdentifierKind.repository, 'acme.example'),
      ]);
      final json = app.toJson();
      expect(json.containsKey('kind'), isFalse);
      expect(
        AppRecord.fromJson(appJson({'organization': ''})).toJson(),
        isNot(contains('organization')),
      );
    });

    test('malformed identifiers make the record unreadable', () {
      for (final bad in <Object?>[
        'domain:acme.example',
        ['acme.example'],
        [
          {'kind': 'domain'},
        ],
        [
          {'kind': 3, 'value': 'x'},
        ],
      ]) {
        expect(
          () => AppRecord.fromJson(appJson({'identifiers': bad})),
          throwsA(isA<VaultFormatException>()),
          reason: '$bad',
        );
      }
      expect(
        () => AppRecord.fromJson(appJson({'organization': 7})),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('copyWith replaces identifiers and clears with an empty string', () {
      final app = AppRecord.fromJson(
        appJson({'organization': 'Acme', 'kind': 'web'}),
      );
      final edited = app.copyWith(
        organization: '',
        kindName: '',
        identifiers: [
          AppIdentifier.of(IdentifierKind.bundleId, 'com.acme.app'),
          AppIdentifier.of(IdentifierKind.domain, 'acme.example'),
        ],
      );
      expect(edited.organization, isNull);
      expect(edited.kindName, isNull);
      expect(edited.bundleIds, ['com.acme.app']);
      expect(edited.identifiers.single.value, 'acme.example');
      expect(edited.toString(), isNot(contains('Billing')));
    });
  });

  group('apps: notes (SPEC §6.2)', () {
    Map<String, Object?> appJson([Map<String, Object?> fields = const {}]) => {
      'schema': 1,
      'id': id,
      'name': 'Billing API',
      'bundle_ids': <String>[],
      'package_names': <String>[],
      'icon_blob_id': null,
      'created_at': '2025-02-03T10:00:00Z',
      'updated_at': '2025-02-03T10:00:00Z',
      'rev': rev.toString(),
      'device_id': device,
      ...fields,
    };
    const markdown =
        '## Keys\n\nRotate **every** 90 days.\n\n- `make rotate`\n- '
        '[wiki](https://wiki.example)';

    test('round-trip: Markdown text kept as typed', () {
      final json = appJson({'notes': markdown});
      final app = AppRecord.fromJson(json);
      expect(app.notes, markdown);
      expect(app.toJson(), json);
      final again = decodeRecord(ObjectType.app, encodeRecord(app));
      expect((again as AppRecord).notes, markdown);
      expect(encodeRecord(again), encodeRecord(app));
    });

    test('an app without notes reads as none and encodes no notes key', () {
      final json = appJson();
      final app = AppRecord.fromJson(json);
      expect(app.notes, isNull);
      expect(app.toJson().containsKey('notes'), isFalse);
      expect(utf8.decode(encodeRecord(app)), jsonEncode(sortKeys(json)));
    });

    test('trimmed at both ends; empty or null notes are left out', () {
      expect(
        AppRecord.fromJson(appJson({'notes': '\n  $markdown \n\n'})).notes,
        markdown,
      );
      for (final empty in [null, '', ' \n\t ']) {
        final app = AppRecord.fromJson(appJson({'notes': empty}));
        expect(app.notes, isNull);
        expect(app.toJson().containsKey('notes'), isFalse);
      }
    });

    test('a client that predates notes keeps them as an unknown field', () {
      // What an older reader does (SPEC §6): unknown fields ride along.
      final json = appJson({'notes': markdown});
      final older = AppRecord.fromJson({
        for (final MapEntry(:key, :value) in json.entries)
          if (key != 'notes') key: value,
      });
      expect(older.notes, isNull);
      final rewritten = AppRecord(
        id: older.id,
        name: older.name,
        createdAt: older.createdAt,
        updatedAt: older.updatedAt,
        rev: older.rev,
        deviceId: older.deviceId,
        unknownFields: {'notes': markdown},
      );
      expect(rewritten.toJson()['notes'], markdown);
    });

    test('malformed notes make the record unreadable', () {
      expect(
        () => AppRecord.fromJson(appJson({'notes': 42})),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('copyWith sets and clears notes; toString never prints them', () {
      final app = AppRecord.fromJson(appJson());
      final noted = app.copyWith(notes: markdown);
      expect(noted.notes, markdown);
      expect(noted.toString(), isNot(contains('Rotate')));
      expect(noted.copyWith(notes: '').notes, isNull);
      expect(noted.copyWith(name: 'Renamed').notes, markdown);
    });
  });

  group('organizations (SPEC §6.7)', () {
    Map<String, Object?> orgJson([Map<String, Object?> fields = const {}]) => {
      'schema': 1,
      'id': id,
      'name': 'Acme Corp',
      'created_at': '2025-02-03T10:00:00Z',
      'updated_at': '2025-02-03T10:00:00Z',
      'rev': rev.toString(),
      'device_id': device,
      ...fields,
    };

    test('round-trip', () {
      final org = OrganizationRecord.fromJson(orgJson());
      expect(org.name, 'Acme Corp');
      expect(org.objectType, ObjectType.organization);
      expect(org.isReadOnly, isFalse);
      expect(org.toJson(), orgJson());
      final again = decodeRecord(ObjectType.organization, encodeRecord(org));
      expect(again, isA<OrganizationRecord>());
      expect(utf8.decode(encodeRecord(again)), utf8.decode(encodeRecord(org)));
    });

    test('the name is trimmed', () {
      final org = OrganizationRecord.fromJson(orgJson({'name': '  Acme  '}));
      expect(org.name, 'Acme');
      expect(org.toJson()['name'], 'Acme');
      expect(org.copyWith(name: ' Globex\n').name, 'Globex');
    });

    test('an empty name or a bad id is malformed, and never echoed', () {
      for (final json in [
        orgJson({'name': '   '}),
        orgJson({'name': ''}),
        orgJson({'name': null}),
        orgJson({'name': 42}),
        orgJson({'id': 'Secret Corp'}),
      ]) {
        expect(
          () => OrganizationRecord.fromJson(json),
          throwsA(
            isA<VaultFormatException>().having(
              (e) => e.toString(),
              'message',
              allOf(isNot(contains('Acme')), isNot(contains('Secret'))),
            ),
          ),
        );
      }
    });

    test('unknown fields are kept; a newer schema is read-only', () {
      final json = orgJson({'schema': 2, 'colour': 'teal'});
      final org = OrganizationRecord.fromJson(json);
      expect(org.isReadOnly, isTrue);
      expect(org.toJson(), json);
      expect(org.copyWith(name: 'Globex').toJson()['colour'], 'teal');
    });

    test('toString never prints the name', () {
      final org = OrganizationRecord.fromJson(orgJson());
      expect(org.toString(), 'OrganizationRecord($id)');
    });
  });

  test('tombstones round-trip and know what they delete', () {
    final json = {
      'schema': 1,
      'id': id,
      'kind': 'item',
      'deleted_at': '2026-10-07T09:00:00Z',
      'rev': rev.toString(),
      'device_id': device,
    };
    final tombstone = Tombstone.fromJson(json);
    expect(tombstone.kind, TombstoneKind.item);
    expect(tombstone.toJson(), json);
    expect(
      () => Tombstone.fromJson({...json, 'kind': 'blob'}),
      throwsA(isA<VaultFormatException>()),
    );
    final org = Tombstone.fromJson({...json, 'kind': 'organization'});
    expect(org.kind, TombstoneKind.organization);
    expect(org.kind.recordType, ObjectType.organization);
    expect(org.toJson()['kind'], 'organization');
  });
}
