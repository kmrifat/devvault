import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import 'common.dart';

/// Reads a GCP service-account key (`"type": "service_account"`). The file
/// states no expiry (SPEC §6.5); the user may set one later.
class ServiceAccountParser implements CredentialParser {
  const ServiceAccountParser();

  /// `project_id`.
  static const projectId = 'project_id';

  /// `client_email`: the service account's address.
  static const clientEmail = 'client_email';

  /// `client_id`: the service account's numeric id.
  static const clientId = 'client_id';

  /// `private_key_id`: identifies the key in the console. Not secret.
  static const privateKeyId = 'private_key_id';

  /// `private_key`: the PEM private key. **Secret.**
  static const privateKey = 'private_key';

  @override
  Set<CredentialFormat> get formats => const {
    CredentialFormat.serviceAccountJson,
  };

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final json = decodeJsonObject(input.bytes);
    if (json['type'] != 'service_account') {
      throw const FormatException('Not a service-account key');
    }

    final facts = <String, ItemField>{};
    putFact(facts, projectId, readString(json, 'project_id'));
    putFact(facts, clientEmail, readString(json, 'client_email'));
    putFact(facts, clientId, readString(json, 'client_id'));
    putFact(facts, privateKeyId, readString(json, 'private_key_id'));
    putFact(facts, privateKey, readString(json, 'private_key'), secret: true);
    if (facts.isEmpty) throw const FormatException('No facts');

    return ParseResult(
      type: ItemType.gcpServiceAccount,
      format: format,
      facts: facts,
    );
  }
}
