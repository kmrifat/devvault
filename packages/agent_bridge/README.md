# agent_bridge

The wire protocol between the DevVault app and `devvault-mcp`, the helper
that AI agents run as an MCP server. Pure Dart, with no dependency on
`vault_core`, so the helper compiles without libsodium.

- `BridgeServer`: binds the Unix socket, frames messages, enforces the
  session rules (hello first, pairing) and hands calls to the app.
- `BridgeClient`: what the helper uses to talk to the app.
- `SecretRequest` / `SecretResult`: the `request_secret` shapes. Their
  `toString()` never prints a value.

The contract is `docs/agent/PROTOCOL.md`; ADR-0006 explains the transport.
