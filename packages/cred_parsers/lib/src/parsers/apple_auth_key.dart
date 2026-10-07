import 'dart:convert';

import 'package:vault_core/vault_core.dart';

import '../der.dart';
import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';

/// App Store Connect / APNs auth keys: a PKCS#8 EC P-256 private key in a
/// `.p8` file.
///
/// The file holds nothing but the key, so the Key ID comes only from
/// Apple's `AuthKey_<KEYID>.p8` filename. A renamed file has no Key ID
/// fact; the user types it in. These keys don't expire.
class AppleAuthKeyParser implements CredentialParser {
  const AppleAuthKeyParser();

  /// The 10-character Key ID from the filename.
  static const keyId = 'key_id';

  /// The key's algorithm and curve, from the PKCS#8 structure.
  static const keyAlgorithm = 'key_algorithm';

  static const _oidEcPublicKey = '1.2.840.10045.2.1';
  static const _oidPrime256v1 = '1.2.840.10045.3.1.7';

  static final _filename = RegExp(r'(?:^|[/\\])AuthKey_([A-Z0-9]{10})\.p8$');

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.appleAuthKey};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final blocks = decodePem(latin1.decode(input.bytes))
        .where((b) => b.label == 'PRIVATE KEY')
        .toList();
    if (blocks.length != 1) {
      throw const FormatException('expected one PRIVATE KEY block');
    }
    _checkEcP256(Asn1.parse(blocks.single.bytes));

    final id = _filename.firstMatch(input.filename)?[1];
    return ParseResult(
      type: ItemType.appleAuthKey,
      format: format,
      facts: {
        keyAlgorithm: const ItemField(
          value: 'EC P-256',
          source: FieldSource.file,
        ),
        if (id != null) keyId: ItemField(value: id, source: FieldSource.file),
      },
    );
  }

  /// PrivateKeyInfo { version 0, AlgorithmIdentifier { ecPublicKey,
  /// prime256v1 }, privateKey OCTET STRING (ECPrivateKey) }.
  static void _checkEcP256(Asn1 info) {
    info.expect(Asn1.tagSequence);
    if (info[0].integer != BigInt.zero) {
      throw const FormatException('unsupported PKCS#8 version');
    }
    final algorithm = info[1].expect(Asn1.tagSequence);
    if (algorithm[0].oid != _oidEcPublicKey ||
        algorithm[1].oid != _oidPrime256v1) {
      throw const FormatException('not an EC P-256 key');
    }
    final ecKey = Asn1.parse(info[2].octets).expect(Asn1.tagSequence);
    if (ecKey[0].integer != BigInt.one || ecKey[1].octets.length != 32) {
      throw const FormatException('malformed ECPrivateKey');
    }
  }
}
