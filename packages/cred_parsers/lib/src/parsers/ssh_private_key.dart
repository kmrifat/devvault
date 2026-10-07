import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vault_core/vault_core.dart';

import '../der.dart';
import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';

/// OpenSSH private keys (`openssh-key-v1`, what `ssh-keygen` writes).
///
/// The public half is stored in clear even when the key has a passphrase,
/// so the type, size and fingerprint are always read, matching
/// `ssh-keygen -lf`. The comment lives with the private half: it is read
/// only from a key without a passphrase. The private key itself is never
/// reported. OpenSSH keys don't expire.
class SshPrivateKeyParser implements CredentialParser {
  const SshPrivateKeyParser();

  /// `ED25519`, `RSA`, `ECDSA` …, as `ssh-keygen -lf` names them.
  static const keyType = 'key_type';

  /// Key size in bits.
  static const bits = 'bits';

  /// `SHA256:<base64>`, as `ssh-keygen -lf` prints it.
  static const fingerprint = 'fingerprint';

  /// The key's comment; only readable without a passphrase.
  static const comment = 'comment';

  /// `true` or `false`: whether the private half is encrypted.
  static const passphraseProtected = 'passphrase_protected';

  static const _magic = 'openssh-key-v1\x00';

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.sshPrivateKey};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final blocks = decodePem(latin1.decode(input.bytes))
        .where((b) => b.label == 'OPENSSH PRIVATE KEY')
        .toList();
    if (blocks.length != 1) {
      throw const FormatException('expected one OPENSSH PRIVATE KEY block');
    }
    final r = _SshReader(blocks.single.bytes);
    if (latin1.decode(r.raw(_magic.length)) != _magic) {
      throw const FormatException('not an openssh-key-v1 key');
    }
    final cipher = r.text();
    r.string(); // kdf name
    r.string(); // kdf options
    if (r.uint32() != 1) {
      throw const FormatException('only single-key files are read');
    }
    final publicBlob = r.string();
    final private = r.string();
    r.end();

    final public = _SshReader(publicBlob);
    final type = public.text();
    final size = _bits(type, public);
    final encrypted = cipher != 'none';
    final keyComment = encrypted ? null : _comment(type, private);

    ItemField fact(String value) =>
        ItemField(value: value, source: FieldSource.file);
    return ParseResult(
      type: ItemType.sshKey,
      format: format,
      facts: {
        keyType: fact(_label(type)),
        if (size != null) bits: fact('$size'),
        fingerprint: fact(
          'SHA256:${base64.encode(sha256.convert(publicBlob).bytes).replaceAll('=', '')}',
        ),
        if (keyComment != null && keyComment.isNotEmpty)
          comment: fact(keyComment),
        passphraseProtected: fact('$encrypted'),
      },
    );
  }

  static String _label(String type) => switch (type) {
    'ssh-ed25519' => 'ED25519',
    'ssh-rsa' => 'RSA',
    'ssh-dss' => 'DSA',
    'sk-ssh-ed25519@openssh.com' => 'ED25519-SK',
    'sk-ecdsa-sha2-nistp256@openssh.com' => 'ECDSA-SK',
    _ when type.startsWith('ecdsa-sha2-') => 'ECDSA',
    _ => type,
  };

  /// The key size, from the public half; `null` for types not read here.
  static int? _bits(String type, _SshReader public) {
    switch (type) {
      case 'ssh-ed25519' || 'sk-ssh-ed25519@openssh.com':
        return 256;
      case 'ssh-rsa':
        public.string(); // e
        return _bitLength(public.string());
      case 'ecdsa-sha2-nistp256' || 'sk-ecdsa-sha2-nistp256@openssh.com':
        return 256;
      case 'ecdsa-sha2-nistp384':
        return 384;
      case 'ecdsa-sha2-nistp521':
        return 521;
      default:
        return null;
    }
  }

  /// The comment from an unencrypted private section: two matching check
  /// words, the key's own fields, then the comment.
  static String? _comment(String type, Uint8List private) {
    final r = _SshReader(private);
    if (r.uint32() != r.uint32()) {
      throw const FormatException('private section check words differ');
    }
    if (r.text() != type) {
      throw const FormatException('private and public key types differ');
    }
    final fields = switch (type) {
      'ssh-ed25519' => 2, // public, private
      'ssh-rsa' => 6, // n, e, d, iqmp, p, q
      _ when type.startsWith('ecdsa-sha2-') => 3, // curve, Q, d
      _ => null,
    };
    if (fields == null) return null;
    for (var i = 0; i < fields; i++) {
      r.string();
    }
    return utf8.decode(r.string());
  }

  static int _bitLength(Uint8List mpint) {
    var i = 0;
    while (i < mpint.length && mpint[i] == 0) {
      i++;
    }
    if (i == mpint.length) return 0;
    return (mpint.length - i - 1) * 8 + mpint[i].bitLength;
  }
}

/// Reads the SSH wire format (RFC 4251 §5): big-endian uint32 and
/// length-prefixed strings, bounds-checked.
class _SshReader {
  _SshReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  Uint8List raw(int n) {
    if (n < 0 || n > _bytes.length - _pos) {
      throw const FormatException('truncated SSH data');
    }
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return out;
  }

  int uint32() {
    final b = raw(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  Uint8List string() => raw(uint32());

  String text() => latin1.decode(string());

  void end() {
    if (_pos != _bytes.length) {
      throw const FormatException('trailing SSH data');
    }
  }
}
