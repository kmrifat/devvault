// The only file that uses dart_mcp (ADR-0006): swap it here if needed.
import 'package:agent_bridge/agent_bridge.dart' show ClientInfo;
import 'package:dart_mcp/server.dart';

import 'tools.dart';

const _instructions = '''
DevVault is the user's encrypted vault for developer credentials (signing
keys, API keys, service accounts, .env values). You can browse what is in it
freely; every secret value needs the user's approval in the DevVault app,
and each call waits (up to 2 minutes) until they answer.

- Start with list_items or get_item to find the item id and field names.
- Prefer write_secret_file, write_env_file or run_with_secrets: the value
  goes where it's needed and never into this conversation.
- Use get_secret only when you must see the value itself; it is sent to the
  AI model.
- Always give a short, honest reason: the user sees it word for word.
- If the user denies a request, don't ask again unless they tell you to.''';

/// `devvault-mcp` as an MCP server over [channel].
base class DevVaultMcpServer extends MCPServer with ToolsSupport {
  DevVaultMcpServer(
    super.channel, {
    required DevVaultTools Function(ClientInfo Function() client) tools,
    required String version,
  }) : super.fromStreamChannel(
         implementation: Implementation(name: 'devvault', version: version),
         instructions: _instructions,
       ) {
    final t = tools(
      () => ClientInfo(
        name: _clientName(clientInfo.name),
        version: _short(clientInfo.version),
      ),
    );
    for (final (tool, impl) in [
      (_vaultStatus, t.vaultStatus),
      (_listItems, t.listItems),
      (_getItem, t.getItem),
      (_getSecret, t.getSecret),
      (_writeSecretFile, t.writeSecretFile),
      (_writeEnvFile, t.writeEnvFile),
      (_runWithSecrets, t.runWithSecrets),
    ]) {
      registerTool(tool, (request) async {
        final out = await impl(request.arguments ?? const {});
        return CallToolResult(
          content: [TextContent(text: out.text)],
          isError: out.isError ? true : null,
        );
      });
    }
  }

  static String _clientName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'mcp-client';
    return clean.length > 64 ? clean.substring(0, 64) : clean;
  }

  static String _short(String version) =>
      version.length > 32 ? version.substring(0, 32) : version;
}

final _reason = Schema.string(
  description:
      'Why you need it, in one short sentence. Shown to the user word for '
      'word when they approve.',
);

final _itemId = Schema.string(
  description: 'The item id from list_items or get_item.',
);

final _env = Schema.object(
  description:
      'Environment variable name → "<item id>#<field name>", e.g. '
      '{"STRIPE_KEY": "6f1c…#value"}. All values are approved together.',
  additionalProperties: Schema.string(),
);

final _vaultStatus = Tool(
  name: 'vault_status',
  description:
      'Whether DevVault is running, and whether its vault is locked. Needs '
      'no approval.',
  inputSchema: Schema.object(),
  annotations: ToolAnnotations(readOnlyHint: true, title: 'Vault status'),
);

final _listItems = Tool(
  name: 'list_items',
  description:
      "Lists the vault's items: ids, titles, types, apps, platforms, "
      'environments, tags, field names (with non-secret values such as key '
      'ids), attachments and expiry. Never secret values. Filters are '
      'optional and combine. If the vault is locked, DevVault asks the user '
      'to unlock it and this waits.',
  inputSchema: Schema.object(
    properties: {
      'query': Schema.string(
        description: 'Words that must all appear in the metadata.',
      ),
      'app': Schema.string(description: 'App name or id.'),
      'platform': Schema.string(description: 'e.g. ios, android, web, server'),
      'environment': Schema.string(description: 'e.g. production, staging'),
      'type': Schema.string(
        description:
            'apple_auth_key, apple_certificate, provisioning_profile, '
            'android_keystore, firebase_config, gcp_service_account, '
            'oauth_client, ssh_key, generic_file or generic_secret',
      ),
      'tag': Schema.string(),
    },
  ),
  annotations: ToolAnnotations(readOnlyHint: true, title: 'List items'),
);

final _getItem = Tool(
  name: 'get_item',
  description: "One item's metadata (no secret values).",
  inputSchema: Schema.object(properties: {'id': _itemId}, required: ['id']),
  annotations: ToolAnnotations(readOnlyHint: true, title: 'Get item'),
);

final _getSecret = Tool(
  name: 'get_secret',
  description:
      'Returns secret values to you, after the user approves in DevVault. '
      'The values enter this conversation and are sent to the AI model, so '
      'prefer write_secret_file, write_env_file or run_with_secrets. With no '
      'fields, attachment_ids or notes, returns every field. Text '
      'attachments up to 64 KiB come back as text.',
  inputSchema: Schema.object(
    properties: {
      'item_id': _itemId,
      'fields': Schema.list(
        items: Schema.string(),
        description: 'Field names from get_item.',
      ),
      'attachment_ids': Schema.list(
        items: Schema.string(),
        description: 'Attachment ids from get_item.',
      ),
      'notes': Schema.bool(description: "Include the item's notes."),
      'reason': _reason,
    },
    required: ['item_id', 'reason'],
  ),
  annotations: ToolAnnotations(readOnlyHint: true, title: 'Get secret'),
);

final _writeSecretFile = Tool(
  name: 'write_secret_file',
  description:
      "Writes one field's value or one attachment (e.g. a .p8 key, a "
      'keystore, a service-account JSON) to a file only this user can read '
      '(0600), after the user approves in DevVault. You get back the path '
      'and size, never the content.',
  inputSchema: Schema.object(
    properties: {
      'item_id': _itemId,
      'field': Schema.string(description: 'A field name (or attachment_id).'),
      'attachment_id': Schema.string(description: 'An attachment id.'),
      'path': Schema.string(
        description: 'Absolute path; its folder must exist.',
      ),
      'overwrite': Schema.bool(
        description: 'Replace the file if it exists (default false).',
      ),
      'reason': _reason,
    },
    required: ['item_id', 'path', 'reason'],
  ),
  annotations: ToolAnnotations(
    readOnlyHint: false,
    destructiveHint: true,
    title: 'Write secret to file',
  ),
);

final _writeEnvFile = Tool(
  name: 'write_env_file',
  description:
      'Sets variables in a dotenv file (e.g. /path/to/project/.env), after '
      'the user approves in DevVault. Existing lines for those names are '
      'replaced, other lines are kept, and the file becomes 0600. You get '
      'back the variable names, never the values.',
  inputSchema: Schema.object(
    properties: {
      'path': Schema.string(description: 'Absolute path to the .env file.'),
      'env': _env,
      'reason': _reason,
    },
    required: ['path', 'env', 'reason'],
  ),
  annotations: ToolAnnotations(
    readOnlyHint: false,
    destructiveHint: true,
    title: 'Write .env file',
  ),
);

final _runWithSecrets = Tool(
  name: 'run_with_secrets',
  description:
      'Runs a shell command with secrets as environment variables, after the '
      'user approves in DevVault (they see the command). Returns the exit '
      'code and output with every secret value replaced by [redacted:NAME]. '
      'Refer to the variables in the command, e.g. '
      r'`fastlane deliver --api_key_path "$ASC_KEY_PATH"`.',
  inputSchema: Schema.object(
    properties: {
      'command': Schema.string(description: 'Run with /bin/sh -c.'),
      'env': _env,
      'cwd': Schema.string(description: 'Working directory (absolute).'),
      'timeout_seconds': Schema.int(description: 'Default 300, at most 3600.'),
      'reason': _reason,
    },
    required: ['command', 'env', 'reason'],
  ),
  annotations: ToolAnnotations(
    readOnlyHint: false,
    destructiveHint: true,
    openWorldHint: true,
    title: 'Run command with secrets',
  ),
);
