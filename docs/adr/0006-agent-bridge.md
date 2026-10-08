# ADR-0006: AI agent bridge over a Unix socket in the app container

- Status: Accepted (2026-10-09)

## Context

P5 lets an AI agent (Claude Code, or any MCP client) ask DevVault for a
credential. The agent starts an MCP server as a child process and talks
to it over stdio, so the MCP server has to be a command-line program. The
vault is decrypted only inside the running app, which is sandboxed on
macOS. The Release build has `network.client` but not `network.server`.

The question for the spike was how the command-line helper reaches the
app.

## Spike (P5-01)

The spike used a Release build (`flutter build macos --release`,
ad-hoc signed, App Sandbox on) with a throwaway hook in `main()`. It was
run on macOS 27 (Darwin 27.0.0) with Flutter 3.47.5 and Dart 3.13.4.

| Check | Result |
|---|---|
| `ServerSocket.bind(InternetAddress(path, type: unix))` at `$HOME/tmp/dv.sock` | **Works.** `$HOME` inside the sandbox is `~/Library/Containers/com.binarycastle.devvault/Data` |
| A non-sandboxed process (Python, from a terminal) connects to that socket | **Works.** No TCC prompt |
| `ServerSocket.bind(127.0.0.1, …)` | **Fails** with `Operation not permitted`, as expected without `network.server` |
| Killing the app leaves the socket file behind | Yes, so the server has to clean up stale sockets |
| `dart_mcp` 0.5.2 over stdio, compiled with `dart compile exe` | **Works.** `initialize` and `tools/call` both answer |
| The compiled helper under the hardened runtime | **Killed** (SIGKILL) unless it's signed with `cs.allow-jit`, `cs.allow-unsigned-executable-memory` and `cs.disable-library-validation`. With those three entitlements it runs |

The socket path is 74 bytes for this user, against the 104-byte
`sun_path` limit on macOS. A home folder name would have to exceed about
40 characters to break it.

## Decision

1. **Transport:** a Unix domain socket at
   `~/Library/Containers/com.binarycastle.devvault/Data/tmp/dv.sock`. The
   app derives the path from `$HOME`; the helper builds it from the bundle
   id. The container's `tmp` folder is mode 0700, so
   only the user's own processes reach the socket. The app creates it only
   while *Settings → AI agents* is on. No new entitlement is needed.
2. **One server:** if the socket exists, the app first tries to connect.
   If that succeeds, another instance (for example a Debug build sharing
   the container) already serves the socket, and this one does not. If it
   fails, the socket is stale, so the app deletes it and binds.
3. **MCP library:** `dart_mcp` (labs.dart.dev), pinned. All use of it
   lives in `packages/devvault_mcp/lib/src/mcp_server.dart`, so the
   library can be swapped for a hand-written JSON-RPC loop (only
   `initialize`, `tools/list` and `tools/call` are needed) if it breaks.
4. **Helper packaging:** the helper is compiled with `dart compile exe` and
   embedded at `Contents/Helpers/devvault-mcp`. It is signed with the
   three entitlements above and is **not** sandboxed, because it writes
   files and runs commands for the agent outside the app container.
   Developer ID distribution allows this; the Mac App Store does not,
   and DevVault doesn't ship there.
5. **Fallback** (not needed now): if a future macOS blocks connecting into
   another app's container, the app moves the socket to an app group
   container, or adds `network.server` and binds loopback with the pairing
   token required on every request.

## Consequences

- The helper never reads the vault, the password or any file in the
  container other than the socket. Its pairing token lives in
  `~/.config/devvault/agent-token`.
- Windows (named pipe) and Linux (`$XDG_RUNTIME_DIR`) get their own
  transport in P5-11. The protocol above the byte stream is the same.
- The wire protocol is a contract like the vault format. It is versioned
  and specified in `docs/agent/PROTOCOL.md`.
