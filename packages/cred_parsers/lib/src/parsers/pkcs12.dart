import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../pkcs12.dart';
import '../x509.dart';

/// PKCS#12 bundles (`.p12`, `.pfx`): a certificate, usually with its
/// private key, sealed with a password.
///
/// The password is checked against the file's MAC. Until the right one is
/// supplied the result has no facts and asks for [password]; an empty
/// password is tried first, since some files have one. Once open, the leaf
/// certificate is read as a `.cer` would be ([certificateFacts]) and its
/// `notAfter` is the expiry. The private key is never decrypted: only
/// whether there is one is reported.
///
/// Like a `.cer`, an opened bundle is only an Apple Certificate when its
/// leaf says so; otherwise (e.g. an Android PKCS#12 upload key) it keeps
/// its facts but imports as a generic file. Until it is opened the type is
/// provisional.
class Pkcs12Parser implements CredentialParser {
  const Pkcs12Parser();

  /// The [SecretRequest.key] for the file's password.
  static const password = 'password';

  /// `true` or `false`: whether the file holds a private key.
  static const hasPrivateKey = 'has_private_key';

  /// How many certificates the file holds (leaf plus any chain).
  static const certificateCount = 'certificate_count';

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.pkcs12};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final supplied = input.secrets[password];
    final Pkcs12Contents p12;
    try {
      p12 = Pkcs12Contents.read(input.bytes, supplied ?? '');
    } on Pkcs12PasswordException {
      return ParseResult(
        type: ItemType.appleCertificate,
        format: format,
        secretsNeeded: [
          SecretRequest(
            key: password,
            label: 'Password',
            rejected: supplied != null,
          ),
        ],
      );
    }

    final bag = p12.leaf;
    final leaf = bag == null ? null : X509Certificate.parse(bag.der);
    final count = p12.certificates.length;
    final isApple = leaf?.appleType != null;
    return ParseResult(
      type: isApple ? ItemType.appleCertificate : ItemType.genericFile,
      format: format,
      facts: {
        ...?(leaf == null ? null : certificateFacts(leaf)),
        hasPrivateKey: ItemField(
          value: '${p12.hasPrivateKey}',
          source: FieldSource.file,
        ),
        certificateCount: ItemField(value: '$count', source: FieldSource.file),
      },
      expiresAt: leaf?.notAfter,
      warnings: [
        if (count == 0) 'This file holds no certificate.',
        if (count > 0 && leaf == null)
          'This file holds $count certificates and doesn\'t say which one '
              'is its own, so no certificate details were read.',
        if (leaf != null && !isApple)
          'This certificate isn\'t marked as an Apple certificate, so it '
              'was imported as a generic file.',
      ],
    );
  }
}
