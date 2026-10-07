import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/vault_crypto.dart';

/// The 256-bit recovery key and its text form (SPEC §8):
/// Crockford base32 of `key || first 20 bits of SHA-256(key)`, 56
/// characters shown as 14 groups of 4.
///
/// Holds the key in secure memory; [dispose] when done.
class RecoveryKey {
  RecoveryKey._(this.key);

  /// Wraps [key] (32 bytes). The [RecoveryKey] takes ownership.
  factory RecoveryKey.fromKey(SecureKey key) {
    if (key.length != VaultCrypto.keyBytes) {
      throw ArgumentError('A recovery key is 32 bytes');
    }
    return RecoveryKey._(key);
  }

  /// A fresh random recovery key.
  factory RecoveryKey.generate(VaultCrypto crypto) =>
      RecoveryKey._(crypto.randomKey());

  /// Parses what the user typed. Case doesn't matter, `I`/`L` read as `1`,
  /// `O` as `0`, and spaces and dashes are ignored.
  ///
  /// Throws [RecoveryKeyFormatException] for a wrong length, a character
  /// that isn't in the alphabet (with its position) or a checksum mismatch,
  /// before any decryption is attempted.
  factory RecoveryKey.parse(VaultCrypto crypto, String input) {
    final symbols = <int>[];
    var position = 0;
    for (final rune in input.toUpperCase().runes) {
      final char = String.fromCharCode(rune);
      position++;
      if (char == '-' || char.trim().isEmpty) continue;
      final normalised = switch (char) {
        'I' || 'L' => '1',
        'O' => '0',
        _ => char,
      };
      final value = alphabet.indexOf(normalised);
      if (value < 0) {
        throw RecoveryKeyFormatException.invalidCharacter(position);
      }
      symbols.add(value);
    }
    if (symbols.length != textLength) {
      throw RecoveryKeyFormatException.wrongLength(symbols.length);
    }

    final bytes = _unpack(symbols); // 35 bytes: key, 20-bit checksum, pad
    final keyBytes = Uint8List.sublistView(bytes, 0, VaultCrypto.keyBytes);
    final checksum = _checksum(keyBytes);
    final matches =
        bytes[32] == checksum[0] &&
        bytes[33] == checksum[1] &&
        bytes[34] == checksum[2];
    if (!matches) {
      bytes.fillRange(0, bytes.length, 0);
      throw RecoveryKeyFormatException.checksum();
    }
    final key = crypto.keyFromBytes(Uint8List.fromList(keyBytes));
    bytes.fillRange(0, bytes.length, 0);
    return RecoveryKey._(key);
  }

  /// Crockford base32: digits and letters without I, L, O and U.
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Characters in the text form, without separators.
  static const int textLength = 56;

  final SecureKey key;

  /// The text form in 14 groups of 4: `K7QF-2M9X-…`.
  String toDisplayString() {
    final text = key.runUnlockedSync((bytes) {
      final checksum = _checksum(bytes);
      final packed = Uint8List(35)
        ..setAll(0, bytes)
        ..[32] = checksum[0]
        ..[33] = checksum[1]
        ..[34] = checksum[2];
      final encoded = _pack(packed);
      packed.fillRange(0, packed.length, 0);
      return encoded;
    });
    return [for (var i = 0; i < text.length; i += 4) text.substring(i, i + 4)]
        .join('-');
  }

  void dispose() => key.dispose();

  /// First 20 bits of SHA-256(key), as 3 bytes with the low 4 bits zero.
  static Uint8List _checksum(List<int> keyBytes) {
    final hash = VaultCrypto.sha256(keyBytes);
    return Uint8List.fromList([hash[0], hash[1], hash[2] & 0xF0]);
  }

  /// 35 bytes (280 bits) → 56 base32 characters, most significant bit first.
  @visibleForTesting
  static String encodeBase32(Uint8List bytes) => _pack(bytes);

  static String _pack(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 0x1F]);
      }
      buffer &= (1 << bits) - 1;
    }
    return out.toString();
  }

  static Uint8List _unpack(List<int> symbols) {
    final out = Uint8List(35);
    var buffer = 0;
    var bits = 0;
    var index = 0;
    for (final symbol in symbols) {
      buffer = (buffer << 5) | symbol;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out[index++] = (buffer >> bits) & 0xFF;
        buffer &= (1 << bits) - 1;
      }
    }
    return out;
  }
}

/// What the user typed isn't a valid recovery key.
class RecoveryKeyFormatException implements Exception {
  const RecoveryKeyFormatException._(this.kind, this.message, {this.position});

  factory RecoveryKeyFormatException.invalidCharacter(int position) =>
      RecoveryKeyFormatException._(
        RecoveryKeyProblem.invalidCharacter,
        'Character $position is not part of a recovery key',
        position: position,
      );

  factory RecoveryKeyFormatException.wrongLength(int length) =>
      RecoveryKeyFormatException._(
        RecoveryKeyProblem.wrongLength,
        'A recovery key has ${RecoveryKey.textLength} characters, '
        'this has $length',
      );

  factory RecoveryKeyFormatException.checksum() =>
      const RecoveryKeyFormatException._(
        RecoveryKeyProblem.checksum,
        'This recovery key has a typo',
      );

  final RecoveryKeyProblem kind;
  final String message;

  /// 1-based position in the input, for [RecoveryKeyProblem.invalidCharacter].
  final int? position;

  @override
  String toString() => 'RecoveryKeyFormatException: $message';
}

enum RecoveryKeyProblem { invalidCharacter, wrongLength, checksum }
