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

/// Setup for [kind], running the helper at [helper] with [args] (the
/// Linux AppImage's `--mcp`; none elsewhere). [windows] quotes for its
/// shells and names its config folders.
///
/// Clients stop waiting for a tool after their own timeout; DevVault waits
/// up to 2 minutes for the user, so where a client's default is shorter
/// (Codex: 60 s) the snippet raises it.
AgentSetup agentSetupFor(
  AgentClientKind kind,
  String helper, [
  List<String> args = const [],
  bool windows = false,
]) {
  String json(Map<String, Object?> config) =>
      const JsonEncoder.withIndent('  ').convert(config);
  final server = {'command': helper, if (args.isNotEmpty) 'args': args};
  final mcpServers = json({
    'mcpServers': {'devvault': server},
  });
  // PowerShell and cmd both take double quotes; POSIX shells single.
  String quoted(String word) =>
      windows ? '"$word"' : "'${word.replaceAll("'", r"'\''")}'";
  final commandLine = [helper, ...args].map(quoted).join(' ');
  return switch (kind) {
    AgentClientKind.claudeCode => AgentSetup(
      'Run this once in a terminal:',
      'claude mcp add --scope user devvault -- $commandLine',
    ),
    AgentClientKind.codex => AgentSetup(
      'Add this to ~/.codex/config.toml:',
      '[mcp_servers.devvault]\n'
          // A TOML basic string escapes as JSON does: Windows paths' \.
          'command = ${jsonEncode(helper)}\n'
          '${args.isEmpty ? '' : 'args = ${jsonEncode(args)}\n'}'
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
      windows
          ? r'Add this to %APPDATA%\Claude\claude_desktop_config.json, then '
                'restart Claude:'
          : 'Add this to ~/Library/Application Support/Claude/'
                'claude_desktop_config.json, then restart Claude:',
      mcpServers,
    ),
    AgentClientKind.vsCode => AgentSetup(
      'Add this to .vscode/mcp.json in your project, or to your user '
      'mcp.json (MCP: Open User Configuration):',
      json({
        'servers': {
          'devvault': {'type': 'stdio', ...server},
        },
      }),
    ),
    AgentClientKind.windsurf => AgentSetup(
      'Add this to ~/.codeium/windsurf/mcp_config.json (merge it into '
      'mcpServers if the file has some):',
      mcpServers,
    ),
    AgentClientKind.other => AgentSetup(
      args.isEmpty
          ? 'Any MCP client: add a stdio server named devvault that runs this '
                'command, with no arguments:'
          : 'Any MCP client: add a stdio server named devvault that runs this '
                'command with these arguments:',
      commandLine,
    ),
  };
}
