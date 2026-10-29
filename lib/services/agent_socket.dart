import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart'
    show
        appImageHelperArgument,
        pipeNameForCurrentUser,
        socketPathInContainer,
        socketPathInRuntimeDir;

/// Where AI agents (P5, ADR-0006) reach the app on this machine, and how
/// their MCP clients run the helper. Null where agents aren't served.
class AgentEndpoint {
  const AgentEndpoint({
    required this.socket,
    this.helper,
    this.helperArgs = const [],
  });

  /// The app's Unix socket.
  final String socket;

  /// `devvault-mcp`, as an MCP client should run it; null when this build
  /// doesn't ship it (a debug run).
  final String? helper;
  final List<String> helperArgs;

  /// macOS: the socket in the app's sandbox container, where `$HOME`
  /// points; the helper in `Contents/Helpers`. Only for the sandboxed app.
  static AgentEndpoint? macOS(Map<String, String> environment, String exe) {
    final home = environment['HOME'];
    if (home == null || !home.contains('/Library/Containers/')) return null;
    return AgentEndpoint(
      socket: socketPathInContainer(home),
      // …/DevVault.app/Contents/MacOS/DevVault → Contents/Helpers.
      helper: '${File(exe).parent.parent.path}/Helpers/devvault-mcp',
    );
  }

  /// Windows: the current user's named pipe, `\\.\pipe\devvault-<SID>`
  /// (owner-only, PROTOCOL.md §1). The helper is `devvault-mcp.exe`
  /// beside the app in the release folder; the MSIX has none yet.
  static AgentEndpoint windows(String exe) {
    final bundled = File('${File(exe).parent.path}\\devvault-mcp.exe');
    return AgentEndpoint(
      socket: pipeNameForCurrentUser(),
      helper: bundled.existsSync() ? bundled.path : null,
    );
  }

  /// Linux: the socket in `$XDG_RUNTIME_DIR`, which must be a directory
  /// only its owner can open (the XDG spec's 0700), or agents stay off.
  /// The helper is the AppImage run with `--mcp`, or `devvault-mcp` beside
  /// the app in the release bundle.
  static AgentEndpoint? linux(Map<String, String> environment, String exe) {
    final runtime = environment['XDG_RUNTIME_DIR'];
    if (runtime == null || runtime.isEmpty) return null;
    final stat = FileStat.statSync(runtime);
    // No access for group or others: 0o077.
    if (stat.type != FileSystemEntityType.directory || stat.mode & 0x3F != 0) {
      return null;
    }
    final appImage = environment['APPIMAGE'];
    final bundled = File('${File(exe).parent.path}/devvault-mcp');
    return AgentEndpoint(
      socket: socketPathInRuntimeDir(runtime),
      helper: appImage != null && appImage.isNotEmpty
          ? appImage
          : bundled.existsSync()
          ? bundled.path
          : null,
      helperArgs: appImage != null && appImage.isNotEmpty
          ? const [appImageHelperArgument]
          : const [],
    );
  }
}
