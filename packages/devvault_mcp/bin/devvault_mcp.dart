import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:devvault_mcp/devvault_mcp.dart';

/// `devvault-mcp`: an MCP server over stdio that asks the DevVault app for
/// credentials (docs/agent/USING.md). stdout carries MCP only; nothing is
/// ever logged.
///
///     devvault-mcp [--socket <path>] [--no-launch]
void main(List<String> args) {
  final environment = io.Platform.environment;
  final home = environment['HOME'];
  if (home == null) {
    io.stderr.writeln('devvault-mcp: HOME is not set');
    io.exit(64);
  }
  final socketAt = args.indexOf('--socket');
  final socket = socketAt >= 0 && socketAt + 1 < args.length
      ? args[socketAt + 1]
      : defaultSocketPath(
          environment,
          macOS: io.Platform.isMacOS,
          linux: io.Platform.isLinux,
        );
  if (socket == null) {
    io.stderr.writeln(
      io.Platform.isLinux
          ? 'devvault-mcp: XDG_RUNTIME_DIR is not set'
          : 'devvault-mcp: DevVault agents run on macOS and Linux',
    );
    io.exit(64);
  }
  final launch = !args.contains('--no-launch');

  DevVaultMcpServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    version: devvaultMcpVersion,
    tools: (client) => DevVaultTools(
      AppConnection(
        socketPath: socket,
        tokens: TokenStore.inHome(home),
        client: client,
        launchApp: launch ? launchDevVault : null,
      ),
    ),
  );
}
