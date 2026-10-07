import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  String keyHex(RecoveryKey rk) => rk.key.runUnlockedSync(
    (b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
  );

  test('shows 14 groups of 4 Crockford base32 characters', () {
    final rk = RecoveryKey.generate(crypto);
    final text = rk.toDisplayString();
    expect(
      text,
      matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){13}[0-9A-HJKMNP-TV-Z]{4}$')),
    );
    rk.dispose();
  });

  test('parses back to the same key', () {
    for (var i = 0; i < 20; i++) {
      final rk = RecoveryKey.generate(crypto);
      final parsed = RecoveryKey.parse(crypto, rk.toDisplayString());
      expect(keyHex(parsed), keyHex(rk));
      rk.dispose();
      parsed.dispose();
    }
  });

  test('a known key has a known text form', () {
    final rk = RecoveryKey.fromKey(crypto.keyFromBytes(Uint8List(32)));
    // 256 zero bits, then the first 20 bits of SHA-256(32 zero bytes)
    // (0x66687), then four zero pad bits.
    expect(rk.toDisplayString().replaceAll('-', ''), '${'0' * 51}6CT3G');
    rk.dispose();
  });

  test('is forgiving about how it was typed', () {
    final rk = RecoveryKey.generate(crypto);
    final text = rk.toDisplayString();
    final sloppy = text
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('1', 'l')
        .replaceAll('0', 'o');
    final parsed = RecoveryKey.parse(crypto, sloppy);
    expect(keyHex(parsed), keyHex(rk));
    rk.dispose();
    parsed.dispose();
  });

  group('catches typos before any decryption', () {
    late String text;
    setUp(() {
      final rk = RecoveryKey.generate(crypto);
      text = rk.toDisplayString();
      rk.dispose();
    });

    RecoveryKeyFormatException problem(String input) {
      try {
        RecoveryKey.parse(crypto, input).dispose();
      } on RecoveryKeyFormatException catch (e) {
        return e;
      }
      fail('accepted a broken key: $input');
    }

    test('one wrong character fails the checksum', () {
      final first = text[0];
      final replacement = first == 'A' ? 'B' : 'A';
      expect(
        problem('$replacement${text.substring(1)}').kind,
        RecoveryKeyProblem.checksum,
      );
    });

    test('two swapped characters fail the checksum', () {
      final i = text.indexOf(RegExp(r'[^-]'), 5);
      final chars = text.split('');
      var j = i + 1;
      while (chars[j] == '-' || chars[j] == chars[i]) {
        j++;
      }
      final swapped =
          (List.of(chars)
                ..[i] = chars[j]
                ..[j] = chars[i])
              .join();
      expect(problem(swapped).kind, RecoveryKeyProblem.checksum);
    });

    test('a character outside the alphabet says where it is', () {
      final broken = '${text.substring(0, 7)}U${text.substring(8)}';
      final e = problem(broken);
      expect(e.kind, RecoveryKeyProblem.invalidCharacter);
      expect(e.position, 8);
    });

    test('a missing group is the wrong length', () {
      expect(problem(text.substring(5)).kind, RecoveryKeyProblem.wrongLength);
    });
  });
}
