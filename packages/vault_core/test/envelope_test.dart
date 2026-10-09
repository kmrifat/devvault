import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  late SecureKey key;
  setUpAll(() async => crypto = await VaultCrypto.init());
  setUp(() => key = crypto.keyFromBytes(seq(32)));
  tearDown(() => key.dispose());

  const vaultId = '7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e';
  const otherVault = '11111111-2222-4333-8444-555555555555';
  const objectId = '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6';
  const otherObject = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  ObjectSlot slot({
    String vault = vaultId,
    String object = objectId,
    ObjectType type = ObjectType.item,
  }) => ObjectSlot(vaultId: vault, objectId: object, type: type);

  Uint8List seal(Uint8List plaintext, {ObjectSlot? at}) =>
      Envelope.seal(crypto, slot: at ?? slot(), key: key, plaintext: plaintext);

  Uint8List open(Uint8List envelope, {ObjectSlot? at, SecureKey? withKey}) =>
      Envelope.open(
        crypto,
        slot: at ?? slot(),
        key: withKey ?? key,
        envelope: envelope,
      );

  final plaintext = Uint8List.fromList(utf8.encode('{"schema":1}'));

  test('matches the byte layout produced by Go', () {
    final envelope = Envelope.seal(
      crypto,
      slot: slot(),
      key: key,
      plaintext: plaintext,
      nonce: seq(24, 0x80),
    );
    expect(
      hex(envelope),
      '44564c540101808182838485868788898a8b8c8d8e8f9091929394959697'
      '39cc2a3a8ff12e0b3e221286a8be856b72c7a2918dcef19b78a0a5d6',
    );
  });

  test('every object type round-trips and records its type byte', () {
    for (final type in ObjectType.values) {
      final at = slot(type: type);
      final envelope = seal(plaintext, at: at);
      expect(envelope.sublist(0, 4), utf8.encode('DVLT'));
      expect(envelope[4], 1);
      expect(envelope[5], type.code);
      expect(envelope.length, plaintext.length + Envelope.overhead);
      expect(open(envelope, at: at), plaintext);
    }
  });

  test('uses a fresh nonce every time', () {
    expect(seal(plaintext), isNot(seal(plaintext)));
  });

  group('refuses objects that are not where they were written', () {
    late Uint8List envelope;
    setUp(() => envelope = seal(plaintext));

    final failures = throwsA(isA<DecryptionFailed>());

    test('copied over another object', () {
      expect(() => open(envelope, at: slot(object: otherObject)), failures);
    });

    test('moved into another vault', () {
      expect(() => open(envelope, at: slot(vault: otherVault)), failures);
    });

    test('moved into another folder', () {
      // The header says "item"; reading it as a blob fails on the type byte.
      expect(() => open(envelope, at: slot(type: ObjectType.blob)), failures);
      // Forge the type byte too: the AAD still disagrees.
      final forged = Uint8List.fromList(envelope)..[5] = ObjectType.blob.code;
      expect(() => open(forged, at: slot(type: ObjectType.blob)), failures);
    });

    test('claiming another format version', () {
      final forged = Uint8List.fromList(envelope)..[4] = 2;
      expect(() => open(forged), failures);
    });

    test('any flipped bit anywhere', () {
      for (var i = 0; i < envelope.length; i++) {
        final tampered = Uint8List.fromList(envelope)..[i] ^= 0x01;
        expect(() => open(tampered), failures, reason: 'byte $i');
      }
    });

    test('truncated, empty or not an envelope at all', () {
      expect(() => open(envelope.sublist(0, envelope.length - 1)), failures);
      expect(() => open(Uint8List(0)), failures);
      expect(() => open(Uint8List.fromList(utf8.encode('{"a":1}'))), failures);
    });

    test('opened with another key', () {
      final other = crypto.randomKey();
      expect(() => open(envelope, withKey: other), failures);
      other.dispose();
    });
  });

  group('slots', () {
    test('build the AAD from location, as in the spec', () {
      expect(utf8.decode(slot().associatedData), '$vaultId|$objectId|item|1');
      expect(
        utf8.decode(slot(type: ObjectType.vkWrapRecovery).associatedData),
        '$vaultId|$objectId|vk_wrap_recovery|1',
      );
    });

    test('only accept canonical lowercase UUIDs', () {
      expect(
        () => slot(object: objectId.toUpperCase()),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => slot(vault: 'my-vault'),
        throwsA(isA<VaultFormatException>()),
      );
      expect(isCanonicalUuid(objectId), isTrue);
      expect(isCanonicalUuid('$objectId.enc'), isFalse);
    });

    test('folders match the layout', () {
      expect(ObjectType.item.folder, 'items');
      expect(ObjectType.app.folder, 'apps');
      expect(ObjectType.blob.folder, 'blobs');
      expect(ObjectType.tombstone.folder, 'tombstones');
      expect(ObjectType.organization.folder, 'organizations');
      expect(ObjectType.vkWrapPassword.folder, isNull);
    });

    test('organizations are type 0x07, named organization', () {
      expect(ObjectType.organization.code, 0x07);
      expect(ObjectType.organization.wireName, 'organization');
    });

    test('type codes are distinct', () {
      final codes = ObjectType.values.map((t) => t.code).toSet();
      expect(codes, hasLength(ObjectType.values.length));
    });
  });
}

Uint8List seq(int length, [int start = 0]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) start + i]);

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
