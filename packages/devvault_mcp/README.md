# devvault_mcp

`devvault-mcp`: the MCP server that AI agents (Claude Code, or any MCP
client) run over stdio to ask DevVault for credentials. It never reads the
vault itself. It asks the running app over the bridge socket
(`packages/agent_bridge`, `docs/agent/PROTOCOL.md`), and the user approves
every secret in the app.

| Tool | Approval | The agent gets |
|---|---|---|
| `vault_status` | none | whether DevVault runs, and whether the vault is locked |
| `list_items`, `get_item` | none (setting) | metadata: never secret values |
| `get_secret` | yes | the values (they go to the AI model) |
| `write_secret_file` | yes | the path and size; the file is 0600 |
| `write_env_file` | yes | the variable names; the .env is merged, 0600 |
| `run_with_secrets` | yes | exit code and output, values redacted |

- **Code layout:** `lib/src/mcp_server.dart` is the only file that uses
  `dart_mcp`. The tools live in `lib/src/tools.dart` and don't depend on
  it (ADR-0006).
- **Pairing tokens:** one per MCP client name, kept in
  `~/.config/devvault/agent-tokens.json` (0600, folder 0700).

Run it from source, or see `docs/agent/USING.md` for the built binary:

    dart run packages/devvault_mcp/bin/devvault_mcp.dart [--socket <path>] [--no-launch]
