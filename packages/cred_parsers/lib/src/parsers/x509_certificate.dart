import 'dart:convert';

import 'package:vault_core/vault_core.dart';

import '../der.dart';
import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../x509.dart';

/// A single X.509 certificate, DER (`.cer`) or PEM.
///
/// Apple certificates (recognised by their common-name prefix or Apple
/// marker extension) import as Apple Certificates. Any other certificate
/// keeps its facts and expiry but imports as a generic file: DevVault
/// doesn't call something an Apple certificate unless the file says so.
class X509CertificateParser implements CredentialParser {
  const X509CertificateParser();

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.x509Certificate};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final bytes = input.bytes;
    final pem = decodePem(latin1.decode(bytes))
        .where((b) => b.label == 'CERTIFICATE')
        .toList();
    if (pem.length > 1) {
      throw const FormatException('more than one certificate');
    }
    final cert = X509Certificate.parse(pem.isEmpty ? bytes : pem.single.bytes);
    final isApple = cert.appleType != null;
    return ParseResult(
      type: isApple ? ItemType.appleCertificate : ItemType.genericFile,
      format: format,
      facts: certificateFacts(cert),
      expiresAt: cert.notAfter,
      warnings: [
        if (!isApple)
          'This certificate isn\'t marked as an Apple certificate, so it '
              'was imported as a generic file.',
      ],
    );
  }
}
