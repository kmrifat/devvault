import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import 'common.dart';

/// Reads an OAuth client secret downloaded from the Google Cloud console
/// (`client_secret_*.json`), for an `installed` (desktop/mobile) or `web`
/// client. The file states no expiry (SPEC §6.5).
class OAuthClientParser implements CredentialParser {
  const OAuthClientParser();

  /// The top-level key the client sits under: `installed` or `web`.
  static const clientType = 'client_type';

  /// `client_id`.
  static const clientId = 'client_id';

  /// `client_secret`. **Secret.**
  static const clientSecret = 'client_secret';

  /// `project_id`.
  static const projectId = 'project_id';

  /// `redirect_uris`, one per line.
  static const redirectUris = 'redirect_uris';

  /// `javascript_origins`, one per line.
  static const javascriptOrigins = 'javascript_origins';

  static const _types = ['installed', 'web'];

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.oauthClientJson};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final json = decodeJsonObject(input.bytes);
    final present = [
      for (final type in _types)
        if (json.containsKey(type)) type,
    ];
    // Both at once isn't something the console writes; don't pick one.
    if (present.length != 1) {
      throw const FormatException('Expected exactly one client');
    }
    final type = present.single;
    final client = readMap(json, type);
    final id = client == null ? null : readString(client, 'client_id');
    if (client == null || id == null) {
      throw const FormatException('Client without a client_id');
    }

    final facts = <String, ItemField>{};
    putFact(facts, clientType, type);
    putFact(facts, clientId, id);
    putFact(
      facts,
      clientSecret,
      readString(client, 'client_secret'),
      secret: true,
    );
    putFact(facts, projectId, readString(client, 'project_id'));
    putFact(
      facts,
      redirectUris,
      readStrings(client, 'redirect_uris')?.join('\n'),
    );
    putFact(
      facts,
      javascriptOrigins,
      readStrings(client, 'javascript_origins')?.join('\n'),
    );

    return ParseResult(
      type: ItemType.oauthClient,
      format: format,
      facts: facts,
    );
  }
}
