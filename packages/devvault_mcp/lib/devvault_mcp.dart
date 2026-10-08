/// `devvault-mcp`: the MCP server AI agents run to ask DevVault for
/// credentials. See docs/agent/USING.md and docs/agent/PROTOCOL.md.
library;

export 'src/app_connection.dart';
export 'src/delivery.dart';
export 'src/mcp_server.dart';
export 'src/token_store.dart';
export 'src/tools.dart';

/// This helper's version, reported to MCP clients.
const devvaultMcpVersion = '0.1.0';
