import 'dart:convert';

/// MCP clients that Settings › AI Agents has setup steps for. Any other
/// client works too: `devvault-mcp` is a plain stdio MCP server ([other]).
enum AgentClientKind {
  claudeCode('Claude Code'),
  codex('Codex CLI'),
  cursor('Cursor'),
  geminiCli('Gemini CLI'),
  claudeDesktop('Claude Desktop'),
  vsCode('VS Code'),
  windsurf('Windsurf'),
  other('Other MCP client');

  const AgentClientKind(this.label);

  final String label;
}

/// How to add DevVault to one client: what to do with [snippet], and the
/// snippet to copy.
class AgentSetup {
  const AgentSetup(this.instruction, this.snippet);

  final String instruction;
  final String snippet;
}

/// Setup for [kind], running the helper at [helper].
///
/// Clients stop waiting for a tool after their own timeout; DevVault waits
/// up to 2 minutes for the user, so where a client's default is shorter
/// (Codex: 60 s) the snippet raises it.
AgentSetup agentSetupFor(AgentClientKind kind, String helper) {
  String json(Map<String, Object?> config) =>
      const JsonEncoder.withIndent('  ').convert(config);
  final mcpServers = json({
    'mcpServers': {
      'devvault': {'command': helper},
    },
  });
  return switch (kind) {
    AgentClientKind.claudeCode => AgentSetup(
      'Run this once in a terminal:',
      "claude mcp add --scope user devvault -- '$helper'",
    ),
    AgentClientKind.codex => AgentSetup(
      'Add this to ~/.codex/config.toml:',
      '[mcp_servers.devvault]\n'
          'command = "$helper"\n'
          '# DevVault waits up to 2 minutes for you to approve.\n'
          'tool_timeout_sec = 150',
    ),
    AgentClientKind.cursor => AgentSetup(
      'Add this to ~/.cursor/mcp.json (merge it into mcpServers if the file '
      'has some):',
      mcpServers,
    ),
    AgentClientKind.geminiCli => AgentSetup(
      'Add this to ~/.gemini/settings.json (merge it into mcpServers if the '
      'file has some):',
      mcpServers,
    ),
    AgentClientKind.claudeDesktop => AgentSetup(
      'Add this to ~/Library/Application Support/Claude/'
      'claude_desktop_config.json, then restart Claude:',
      mcpServers,
    ),
    AgentClientKind.vsCode => AgentSetup(
      'Add this to .vscode/mcp.json in your project, or to your user '
      'mcp.json (MCP: Open User Configuration):',
      json({
        'servers': {
          'devvault': {'type': 'stdio', 'command': helper},
        },
      }),
    ),
    AgentClientKind.windsurf => AgentSetup(
      'Add this to ~/.codeium/windsurf/mcp_config.json (merge it into '
      'mcpServers if the file has some):',
      mcpServers,
    ),
    AgentClientKind.other => AgentSetup(
      'Any MCP client: add a stdio server named devvault that runs this '
      'command, with no arguments:',
      helper,
    ),
  };
}
