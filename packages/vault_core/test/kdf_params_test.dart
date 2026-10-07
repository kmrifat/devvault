import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Map<String, Object?> json({
    Object? alg = 'argon2id13',
    Object? ops = 3,
    Object? mem = 64 * 1024 * 1024,
    Object? saltValue,
  }) => {
    'alg': alg,
    'ops_limit': ops,
    'mem_limit': mem,
    'salt': saltValue ?? base64.encode(salt),
  };

  test('new vaults get the ADR-0003 defaults and a fresh salt', () {
    final a = KdfParams.generate(crypto);
    final b = KdfParams.generate(crypto);
    expect(a.opsLimit, 3);
    expect(a.memLimit, 64 * 1024 * 1024);
    expect(a.salt, hasLength(16));
    expect(a.salt, isNot(b.salt));
  });

  test('round-trips through the vault.json shape', () {
    final params = KdfParams.fromJson(json());
    expect(params.toJson(), json());
    expect(KdfParams.fromJson(params.toJson()), params);
  });

  group('rejects tampered headers before deriving anything', () {
    final cases = <String, Object?>{
      'ops below 1': json(ops: 0),
      'ops above 10': json(ops: 11),
      'memory below 8 MiB': json(mem: 4 * 1024 * 1024),
      'memory above 1 GiB': json(mem: 2 * 1024 * 1024 * 1024),
      'short salt': json(saltValue: base64.encode(List.filled(15, 0))),
      'salt not base64': json(saltValue: 'not base64!'),
      'another algorithm': json(alg: 'scrypt'),
      'ops as a string': json(ops: '3'),
      'not an object': 'argon2id13',
    };
    for (final MapEntry(key: name, value: header) in cases.entries) {
      test(name, () {
        expect(
          () => KdfParams.fromJson(header),
          throwsA(isA<VaultFormatException>()),
        );
      });
    }
  });

  test('passwords are NFC-normalised before hashing', () {
    const composed = 'café'; // é as one code point
    const decomposed = 'café'; // e + combining acute accent
    expect(
      KdfParams.passwordBytes(decomposed),
      KdfParams.passwordBytes(composed),
    );
    expect(KdfParams.passwordBytes(composed), utf8.encode(composed));
  });

  test('derives the same key as Go on a background isolate', () async {
    final params = KdfParams.fromJson(json());
    final key = await params.deriveKey(crypto, 'correct horse battery staple');
    expect(
      key.runUnlockedSync(hex),
      '0d1a3c6523c8f06e4e0af9c515aa5b5448cfebd6838f2d52c3d8b6ef8ddc3c2e',
    );
    key.dispose();
  });

  test('keeps the calling isolate responsive while deriving', () async {
    final params = KdfParams.fromJson(json());
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final key = await params.deriveKey(crypto, 'correct horse battery staple');
    timer.cancel();
    key.dispose();
    expect(ticks, greaterThan(3), reason: 'timer ran during Argon2id');
  });
}
