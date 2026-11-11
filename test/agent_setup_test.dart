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

  group('the Linux AppImage, run with --mcp', () {
    const appImage = '/home/a/Apps/devvault-linux-x64.AppImage';
    const args = ['--mcp'];

    test('JSON configs carry it as args', () {
      final json = jsonDecode(
        agentSetupFor(AgentClientKind.cursor, appImage, args).snippet,
      );
      expect(json['mcpServers']['devvault'], {
        'command': appImage,
        'args': args,
      });
      final vsCode = jsonDecode(
        agentSetupFor(AgentClientKind.vsCode, appImage, args).snippet,
      );
      expect(vsCode['servers']['devvault']['args'], args);
    });

    test('Claude Code and Codex pass it after the command', () {
      expect(
        agentSetupFor(AgentClientKind.claudeCode, appImage, args).snippet,
        "claude mcp add --scope user devvault -- '$appImage' '--mcp'",
      );
      expect(
        agentSetupFor(AgentClientKind.codex, appImage, args).snippet,
        contains('args = ["--mcp"]'),
      );
    });

    test('a path with a quote stays one word', () {
      expect(
        agentSetupFor(AgentClientKind.claudeCode, "/home/o'neil/dv").snippet,
        r"claude mcp add --scope user devvault -- '/home/o'\''neil/dv'",
      );
    });
  });

  group('Windows', () {
    const exe = r'C:\Users\a\DevVault\devvault-mcp.exe';

    test('Claude Code quotes with double quotes, for PowerShell and cmd', () {
      expect(
        agentSetupFor(AgentClientKind.claudeCode, exe, const [], true).snippet,
        'claude mcp add --scope user devvault -- "$exe"',
      );
    });

    test("Codex's TOML escapes the backslashes; JSON keeps the path", () {
      expect(
        agentSetupFor(AgentClientKind.codex, exe, const [], true).snippet,
        contains(r'command = "C:\\Users\\a\\DevVault\\devvault-mcp.exe"'),
      );
      final json = jsonDecode(
        agentSetupFor(AgentClientKind.cursor, exe, const [], true).snippet,
      );
      expect(json['mcpServers']['devvault']['command'], exe);
    });

    test("Claude Desktop's config is under %APPDATA%", () {
      expect(
        agentSetupFor(
          AgentClientKind.claudeDesktop,
          exe,
          const [],
          true,
        ).instruction,
        contains(r'%APPDATA%\Claude\claude_desktop_config.json'),
      );
    });
  });
}
