import 'dart:convert';
import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../x509.dart';
import 'pkcs12.dart';

/// A PEM file with several blocks: a certificate chain, or a certificate
/// with its private key, which is how APNs certificates are often kept
/// (`openssl pkcs12 -nodes` output).
///
/// The leaf is the one certificate that issued none of the others; if
/// that doesn't single one out, no certificate details are read. Like a
/// `.cer`, the bundle is an Apple Certificate only when its leaf says so.
/// Private keys are noticed, never decoded: encrypted ones need no
/// password to be listed.
class PemBundleParser implements CredentialParser {
  const PemBundleParser();

  static const hasPrivateKey = Pkcs12Parser.hasPrivateKey;
  static const certificateCount = Pkcs12Parser.certificateCount;

  /// `true` or `false`: whether the private key is password-protected.
  static const privateKeyEncrypted = 'private_key_encrypted';

  static final _block = RegExp(
    r'-----BEGIN ([A-Z0-9 ]+)-----([\s\S]*?)-----END \1-----',
  );

  static const _keyLabels = {
    'PRIVATE KEY',
    'ENCRYPTED PRIVATE KEY',
    'RSA PRIVATE KEY',
    'EC PRIVATE KEY',
    'DSA PRIVATE KEY',
  };

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.pemBundle};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final certs = <X509Certificate>[];
    var keys = 0;
    var encrypted = false;
    var skipped = 0;
    for (final m in _block.allMatches(latin1.decode(input.bytes))) {
      final label = m[1]!;
      final body = m[2]!;
      if (label == 'CERTIFICATE') {
        certs.add(X509Certificate.parse(_base64(body)));
      } else if (_keyLabels.contains(label)) {
        keys++;
        encrypted |=
            label == 'ENCRYPTED PRIVATE KEY' ||
            body.contains('Proc-Type: 4,ENCRYPTED');
      } else {
        skipped++;
      }
    }
    if (certs.isEmpty) throw const FormatException('no certificate');

    final leaf = _leaf(certs);
    final isApple = leaf?.appleType != null;
    ItemField fact(String value) =>
        ItemField(value: value, source: FieldSource.file);
    return ParseResult(
      type: isApple ? ItemType.appleCertificate : ItemType.genericFile,
      format: format,
      facts: {
        ...?(leaf == null ? null : certificateFacts(leaf)),
        hasPrivateKey: fact('${keys > 0}'),
        if (keys > 0) privateKeyEncrypted: fact('$encrypted'),
        certificateCount: fact('${certs.length}'),
      },
      expiresAt: leaf?.notAfter,
      warnings: [
        if (leaf == null)
          'This file holds ${certs.length} certificates and doesn\'t say '
              'which one is its own, so no certificate details were read.',
        if (leaf != null && !isApple)
          'This certificate isn\'t marked as an Apple certificate, so it '
              'was imported as a generic file.',
        if (keys > 1) 'This file holds $keys private keys.',
        if (skipped > 0)
          '$skipped other PEM block${skipped == 1 ? '' : 's'} in this file '
              '${skipped == 1 ? 'was' : 'were'} kept but not read.',
      ],
    );
  }

  /// The one certificate that is nobody's issuer, or `null` if there isn't
  /// exactly one. Self-signed certificates don't count as issuing
  /// themselves.
  static X509Certificate? _leaf(List<X509Certificate> certs) {
    final unique = {for (final c in certs) c.sha256Fingerprint: c}.values;
    if (unique.length == 1) return unique.single;
    final candidates = [
      for (final c in unique)
        if (!unique.any((o) => !identical(o, c) && o.issuer == c.subject)) c,
    ];
    return candidates.length == 1 ? candidates.single : null;
  }

  static Uint8List _base64(String body) =>
      base64.decode(body.replaceAll(RegExp(r'\s'), ''));
}
