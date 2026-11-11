/// The wire protocol between the DevVault app and the `devvault-mcp`
/// helper. See docs/agent/PROTOCOL.md.
library;

export 'src/channel.dart' show BridgeChannel, BridgeListener, isPipeEndpoint;
export 'src/client.dart';
export 'src/framing.dart';
export 'src/messages.dart';
export 'src/protocol.dart';
export 'src/server.dart';
export 'src/windows_pipe.dart'
    show PipeException, currentUserSid, pipeNameForCurrentUser;
