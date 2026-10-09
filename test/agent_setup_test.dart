import 'dart:convert';

import 'package:devvault/core/agent_setup.dart';
import 'package:flutter_test/flutter_test.dart';

const _helper = '/Applications/DevVault.app/Contents/Helpers/devvault-mcp';

void main() {
  test('every client gets an instruction and a snippet running the helper', () {
    for (final kind in AgentClientKind.values) {
      final setup = agentSetupFor(kind, _helper);
      expect(setup.instruction, isNotEmpty, reason: kind.label);
      expect(setup.snippet, contains(_helper), reason: kind.label);
    }
  });

  test('JSON configs are valid and name the server devvault', () {
    for (final kind in [
      AgentClientKind.cursor,
      AgentClientKind.geminiCli,
      AgentClientKind.claudeDesktop,
      AgentClientKind.windsurf,
    ]) {
      final json = jsonDecode(agentSetupFor(kind, _helper).snippet);
      expect(json['mcpServers']['devvault']['command'], _helper);
    }
    final vsCode = jsonDecode(
      agentSetupFor(AgentClientKind.vsCode, _helper).snippet,
    );
    expect(vsCode['servers']['devvault'], {
      'type': 'stdio',
      'command': _helper,
    });
  });

  test('Codex waits longer than its 60 s default', () {
    final codex = agentSetupFor(AgentClientKind.codex, _helper).snippet;
    expect(codex, contains('[mcp_servers.devvault]'));
    expect(codex, contains('command = "$_helper"'));
    expect(codex, contains('tool_timeout_sec = 150'));
  });

  test('Claude Code is one command', () {
    expect(
      agentSetupFor(AgentClientKind.claudeCode, _helper).snippet,
      "claude mcp add --scope user devvault -- '$_helper'",
    );
  });
}
