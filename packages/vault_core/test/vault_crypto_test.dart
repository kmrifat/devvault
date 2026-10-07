import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

/// Expected values were produced independently with Go's
/// golang.org/x/crypto (argon2, hkdf, chacha20poly1305, blake2b), the
/// library the future CLI will use.
void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  Uint8List seq(int length, [int start = 0]) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) start + i]);
  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));
  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Uint8List unhex(String s) => Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ]);
  String keyHex(SecureKey key) => key.runUnlockedSync(hex);

  group('Argon2id', () {
    test('matches Go at the default parameters (ops 3, 64 MiB, p 1)', () {
      final key = crypto.argon2id(
        password: text('correct horse battery staple'),
        salt: seq(16),
        opsLimit: 3,
        memLimit: 64 * 1024 * 1024,
      );
      expect(
        keyHex(key),
        '0d1a3c6523c8f06e4e0af9c515aa5b5448cfebd6838f2d52c3d8b6ef8ddc3c2e',
      );
      key.dispose();
    });

    test('hashes the UTF-8 bytes of non-ASCII passwords', () {
      final key = crypto.argon2id(
        password: text('pässwörd'),
        salt: seq(16),
        opsLimit: 1,
        memLimit: 8 * 1024 * 1024,
      );
      expect(
        keyHex(key),
        '1d536f501d2872496f3cecbbe716116992442b7d363ac283e8d13b99503bae65',
      );
      key.dispose();
    });
  });

  test('HKDF-SHA256 recovery derivation matches Go', () {
    final ikm = crypto.keyFromBytes(seq(32, 0x40));
    final key = crypto.hkdfSha256(
      ikm: ikm,
      salt: text('7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e'),
      info: 'devvault/v1/recovery-kek',
    );
    expect(
      keyHex(key),
      '27f8c0f0c3db65941217bac15e67dbdbd58aceada166a478dcffcda6088609ba',
    );
    ikm.dispose();
    key.dispose();
  });

  test('keyed BLAKE2b-256 matches Go', () {
    final key = crypto.keyFromBytes(seq(32));
    expect(
      hex(crypto.keyedHash(key: key, message: text('devvault/v1/vk-id'))),
      'cbac3b26918d0f62fd449dd3d12163ba4549e7b53d661981f7145b4e0fb42016',
    );
    key.dispose();
  });

  group('XChaCha20-Poly1305', () {
    late SecureKey key;
    final nonce = Uint8List.fromList([for (var i = 0; i < 24; i++) 0x80 + i]);
    final ad = utf8.encode('vault|obj|item|1');
    const expected =
        '2a8b353588b4270f6a6e428e23c9293d'
        '122efdedeef0ff39d7764212ae89';

    setUp(() => key = crypto.keyFromBytes(seq(32)));
    tearDown(() => key.dispose());

    Uint8List open(Uint8List ct, {List<int>? withAd, SecureKey? withKey}) =>
        crypto.aeadDecrypt(
          cipherText: ct,
          additionalData: Uint8List.fromList(withAd ?? ad),
          nonce: nonce,
          key: withKey ?? key,
        );

    test('ciphertext matches Go and round-trips', () {
      final ct = crypto.aeadEncrypt(
        message: text('hello devvault'),
        additionalData: Uint8List.fromList(ad),
        nonce: nonce,
        key: key,
      );
      expect(hex(ct), expected);
      expect(utf8.decode(open(ct)), 'hello devvault');
    });

    test('every kind of tampering fails the same way', () {
      final ct = unhex(expected);
      final flipped = Uint8List.fromList(ct)..[3] ^= 0x01;
      final wrongKey = crypto.keyFromBytes(seq(32, 1));
      expect(() => open(flipped), throwsA(isA<DecryptionFailed>()));
      expect(
        () => open(ct, withAd: utf8.encode('vault|obj|blob|1')),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => open(ct, withKey: wrongKey),
        throwsA(isA<DecryptionFailed>()),
      );
      expect(
        () => open(Uint8List(8)),
        throwsA(isA<DecryptionFailed>()),
        reason: 'shorter than a tag',
      );
      wrongKey.dispose();
    });

    test('failures do not explain themselves', () {
      expect(const DecryptionFailed().toString(), 'DecryptionFailed');
    });
  });

  group('randomness', () {
    test('OS randomness gives distinct keys', () {
      final a = crypto.randomKey();
      final b = crypto.randomKey();
      expect(keyHex(a), isNot(keyHex(b)));
      expect(a.length, VaultCrypto.keyBytes);
      a.dispose();
      b.dispose();
    });

    test('a fixed seed gives the same bytes every time', () async {
      final a = await VaultCrypto.withFixedRandom([1, 2, 3]);
      final b = await VaultCrypto.withFixedRandom([1, 2, 3]);
      final c = await VaultCrypto.withFixedRandom([1, 2, 4]);
      final first = a.randomBytes(40);
      expect(first, b.randomBytes(40));
      expect(first, isNot(c.randomBytes(40)));
      expect(a.randomBytes(40), isNot(first), reason: 'stream advances');
    });
  });

  test('SHA-256 matches the FIPS 180 "abc" vector', () {
    expect(
      hex(VaultCrypto.sha256(utf8.encode('abc'))),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
