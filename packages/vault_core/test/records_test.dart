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
  });
}
