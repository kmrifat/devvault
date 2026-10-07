import 'dart:convert';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import '../data/sync_setup.dart';

/// Pairing a new device (P4-06): the sync storage settings and keys, sealed
/// under a short code, so a phone can join without typing them.
///
/// The format is in `docs/format/pairing.md`. In short: the payload text
/// is `devvault-pair:1:<base64url envelope>`; the envelope carries the
/// vault id, an expiry ten minutes out, the Argon2id salt and costs, a
/// nonce and an XChaCha20-Poly1305 box keyed by Argon2id(code). The vault
/// key is never in it: the new device still needs the master password.
abstract final class Pairing {
  static const prefix = 'devvault-pair:1:';

  /// How long a code works.
  static const lifetime = Duration(minutes: 10);

  /// Clock difference tolerated between the two devices.
  static const skew = Duration(minutes: 2);

  /// Argon2id costs: moderate, so a phone derives the key in about a
  /// second while 40 bits of code stay out of reach offline.
  static const opsLimit = 3;
  static const memLimit = 64 * 1024 * 1024;

  static const _saltBytes = 16;

  /// Crockford base32: no I, L, O or U, so the code reads aloud cleanly.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// A fresh 8-character code (40 bits).
  static String newCode(VaultCrypto crypto) {
    final bytes = crypto.randomBytes(5);
    var bits = 0;
    for (final b in bytes) {
      bits = (bits << 8) | b;
    }
    return [for (var i = 7; i >= 0; i--) alphabet[(bits >> (i * 5)) & 31]]
        .join();
  }

  /// `ABCD-EFGH`, for showing.
  static String display(String code) =>
      '${code.substring(0, 4)}-${code.substring(4)}';

  /// What the user typed, as the code: upper case, no dashes or spaces,
  /// and the look-alikes Crockford folds (O→0, I/L→1). `null` if it can't
  /// be a code.
  static String? normalize(String typed) {
    final code = typed
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (code.length != 8) return null;
    if (!code.split('').every(alphabet.contains)) return null;
    return code;
  }

  static Uint8List _aad(String vaultId, String expiresAt, int ops, int mem) =>
      VaultCrypto.utf8Bytes('devvault/v1/pair|$vaultId|$expiresAt|$ops|$mem');

  /// Seals [settings] and [credentials] for [vaultId] under [code].
  /// Returns the text to put in the QR. Runs Argon2id: call it off the UI
  /// isolate's critical path (it takes about a second).
  static Future<String> seal({
    required VaultCrypto crypto,
    required String vaultId,
    required SyncSettings settings,
    required AwsCredentials credentials,
    required String code,
    required DateTime now,
    int ops = opsLimit,
    int mem = memLimit,
  }) async {
    final expiresAt = formatTimestamp(now.toUtc().add(lifetime));
    final salt = crypto.randomBytes(_saltBytes);
    final nonce = crypto.randomBytes(VaultCrypto.nonceBytes);
    final key = await crypto.argon2idIsolated(
      password: VaultCrypto.utf8Bytes(code),
      salt: salt,
      opsLimit: ops,
      memLimit: mem,
    );
    final plain = VaultCrypto.utf8Bytes(
      jsonEncode({
        'settings': settings.toJson(),
        'access_key_id': credentials.accessKeyId,
        'secret_access_key': credentials.secretAccessKey,
        'session_token': ?credentials.sessionToken,
      }),
    );
    try {
      final box = crypto.aeadEncrypt(
        message: plain,
        additionalData: _aad(vaultId, expiresAt, ops, mem),
        nonce: nonce,
        key: key,
      );
      final envelope = jsonEncode({
        'vault_id': vaultId,
        'expires_at': expiresAt,
        'salt': base64Url.encode(salt),
        'ops': ops,
        'mem': mem,
        'nonce': base64Url.encode(nonce),
        'box': base64Url.encode(box),
      });
      return '$prefix${base64Url.encode(utf8.encode(envelope)).replaceAll('=', '')}';
    } finally {
      key.dispose();
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Reads the envelope without the code: which vault, and until when.
  /// Throws [PairingFormatException] if [text] isn't a pairing payload.
  static PairingEnvelope read(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(prefix)) throw const PairingFormatException();
    try {
      var body = trimmed.substring(prefix.length);
      body = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      final json = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (json is! Map<String, Object?>) throw const FormatException();
      final vaultId = json['vault_id'];
      final expiresAt = json['expires_at'];
      final ops = json['ops'];
      final mem = json['mem'];
      if (vaultId is! String ||
          !isCanonicalUuid(vaultId) ||
          expiresAt is! String ||
          ops is! int ||
          mem is! int) {
        throw const FormatException();
      }
      // Bounds keep a crafted payload from making us burn minutes or
      // gigabytes on Argon2id.
      if (ops < 1 || ops > 10 || mem < 8 * 1024 * 1024 || mem > memLimit) {
        throw const FormatException();
      }
      return PairingEnvelope._(
        vaultId: vaultId,
        expiresAtText: expiresAt,
        expiresAt: parseTimestamp(expiresAt, 'expires_at'),
        salt: base64Url.decode(json['salt']! as String),
        ops: ops,
        mem: mem,
        nonce: base64Url.decode(json['nonce']! as String),
        box: base64Url.decode(json['box']! as String),
      );
    } on PairingFormatException {
      rethrow;
    } on Object {
      throw const PairingFormatException();
    }
  }

  /// Opens [text] with [code] at [now]. Throws [PairingFormatException],
  /// [PairingExpired] or [WrongPairingCode]; nothing about the contents is
  /// revealed by any of them.
  static Future<PairingContents> open({
    required VaultCrypto crypto,
    required String text,
    required String code,
    required DateTime now,
  }) async {
    final envelope = read(text);
    final utcNow = now.toUtc();
    if (utcNow.isAfter(envelope.expiresAt.add(skew)) ||
        envelope.expiresAt.isAfter(utcNow.add(lifetime + skew))) {
      throw const PairingExpired();
    }
    final normalized = normalize(code);
    if (normalized == null) throw const WrongPairingCode();
    final key = await crypto.argon2idIsolated(
      password: VaultCrypto.utf8Bytes(normalized),
      salt: envelope.salt,
      opsLimit: envelope.ops,
      memLimit: envelope.mem,
    );
    Uint8List? plain;
    try {
      plain = crypto.aeadDecrypt(
        cipherText: envelope.box,
        additionalData: _aad(
          envelope.vaultId,
          envelope.expiresAtText,
          envelope.ops,
          envelope.mem,
        ),
        nonce: envelope.nonce,
        key: key,
      );
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map<String, Object?> ||
          json['settings'] is! Map<String, Object?> ||
          json['access_key_id'] is! String ||
          json['secret_access_key'] is! String) {
        throw const PairingFormatException();
      }
      return PairingContents(
        vaultId: envelope.vaultId,
        settings: SyncSettings.fromJson(
          json['settings']! as Map<String, Object?>,
        ),
        credentials: AwsCredentials(
          accessKeyId: json['access_key_id']! as String,
          secretAccessKey: json['secret_access_key']! as String,
          sessionToken: json['session_token'] as String?,
        ),
      );
    } on DecryptionFailed {
      throw const WrongPairingCode();
    } on PairingFormatException {
      rethrow;
    } on Object {
      throw const PairingFormatException();
    } finally {
      key.dispose();
      plain?.fillRange(0, plain.length, 0);
    }
  }
}

/// The readable part of a pairing payload.
class PairingEnvelope {
  const PairingEnvelope._({
    required this.vaultId,
    required this.expiresAtText,
    required this.expiresAt,
    required this.salt,
    required this.ops,
    required this.mem,
    required this.nonce,
    required this.box,
  });

  final String vaultId;
  final String expiresAtText;
  final DateTime expiresAt;
  final Uint8List salt;
  final int ops;
  final int mem;
  final Uint8List nonce;
  final Uint8List box;
}

/// What a pairing payload opens to: where the vault syncs, and the keys.
class PairingContents {
  const PairingContents({
    required this.vaultId,
    required this.settings,
    required this.credentials,
  });

  final String vaultId;
  final SyncSettings settings;
  final AwsCredentials credentials;

  @override
  String toString() => 'PairingContents($vaultId, secrets hidden)';
}

class PairingFormatException implements Exception {
  const PairingFormatException();
  @override
  String toString() => 'This isn’t a DevVault pairing code.';
}

class PairingExpired implements Exception {
  const PairingExpired();
  @override
  String toString() => 'This pairing code has expired.';
}

class WrongPairingCode implements Exception {
  const WrongPairingCode();
  @override
  String toString() => 'That code doesn’t match.';
}
