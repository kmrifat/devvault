# AI agent bridge: threat model (P5-10)

What the agent bridge (ADR-0006, PROTOCOL.md) protects, from whom, and
what it deliberately doesn't. The rule from the plan still holds: secrets
never leak into logs, exceptions, toasts, `toString()`, search indexes or
analytics.

## What is protected

- **The master password and the vault key.** Neither ever leaves the
  app. The helper has no way to ask for them: the protocol has no such
  method, and unlocking happens only in DevVault's own window.
- **Secret values (secret fields, notes, attachments).** One leaves the
  app only as the answer to a `request_secret` the user approved. With
  *Allow for 15 Minutes*, only an identical request is let through without
  asking: same client, same items, same names, and the same delivery (mode,
  path, command, folder, variables).
- **Metadata** (titles, apps, field names, non-secret values, expiry).
  Readable by a paired client, without asking unless the user turns that
  off.

## Threats and what stops them

| # | Threat | Mitigation | Where |
|---|---|---|---|
| 1 | Another user on the Mac connects to the socket | It sits in the app's container `tmp` folder, which is mode 0700. Other users can't reach it. | ADR-0006 |
| 2 | Another program running as you connects (malware, a script, a different agent) | It must pair first, which takes an approval in DevVault while the vault is unlocked. Until then it gets only `hello`, `pair` and `status`. A paired token still can't read a single value without a per-request approval. | `BridgeServer`, `_pair` |
| 3 | A stolen or leaked token (`~/.config/devvault/agent-tokens.json`) | The file is 0600 in a 0700 folder. The token gives metadata only. Every secret still asks, except a request identical to one the user granted for 15 minutes (#4). Settings › AI Agents › Disconnect revokes it and drops its connections. DevVault stores only the SHA-256. | `TokenStore`, `revoke` |
| 4 | Prompt injection makes the agent ask for something the user didn't intend | The sheet shows the client, its stated reason, every item and field, and exactly where values go: the file path, or the command line with its folder and which value each variable carries. Nothing goes out without that click. A 15-minute grant lets through only an identical request (same client, items, names and delivery), and ends on lock. A grant for `make test` doesn't cover `get_secret`, another command, another folder or another field. | `SecretPrompt`, `_checkEnv`, N09 |
| 5 | The agent gets values into the AI model's context and transcript | `get_secret` is the only tool that returns values, and its sheet warns about exactly that. The other tools deliver without exposure, and the server's instructions steer agents to them. | `devvault_mcp` tools |
| 6 | A command prints a secret back (`echo $KEY`) | Output is redacted as a whole after the command ends: every value, each line of a multi-line value, and a value cut off at the end. Values shorter than 4 characters are not redacted (see below). | `Redactor` |
| 7 | A file written with the value is readable by others | It is written through a temp file made 0600 before any byte is written, then renamed. An existing file is replaced only with `overwrite: true`, and that check runs before the user is asked. | `writePrivateFile`, `checkTarget` |
| 8 | Requests pile up or hang | At most 8 requests wait per connection (`busy`). Each times out after 120 s. A client that hangs up takes its prompts with it. Turning agents off closes everything. | `BridgeServer`, `_race` |
| 9 | Values end up in logs or errors | No value-bearing type prints its value (`SecretItem`, `SecretAttachment`, `ItemField`). Handler crashes reach the client as `internal`, without their message. The activity list holds titles and outcomes only. Nothing is logged to disk. | `messages.dart`, `server.dart` |
| 10 | A malformed or huge message | Lines over 48 MiB, non-JSON and non-objects close the connection. Params are validated: reason length, item count ≤ 20, absolute paths. | `framing.dart`, `SecretRequest` |
| 11 | A stale socket, or two DevVaults (Debug and Release) | A live socket is left to its owner, and this instance stands down and says so in Settings. A stale one is removed. | `BridgeServer.bind` |
| 12 | The vault locks while a request waits | Locking denies every open secret or metadata prompt, clears all grants and drops the decrypted index. A request waiting for unlock keeps waiting (with the banner) until its timeout. | `AgentBridgeNotifier` |

## Accepted risks

- **Approved values leave DevVault's protection.**
  - With *reveal*, they are in the agent's context and its provider's
    logs.
  - With *file*, they sit on disk (0600) until someone deletes them.
  - With *command*, the command can do anything with them (send them
    over the network, write them elsewhere). DevVault shows the command
    but can't judge it.

  That is the point of approving. The sheet says where each value goes.
- **Same-user processes are trusted for transport.** Any process running
  as you can talk to the socket. It can't read values without your
  approval, but it can ask (#2), and a request it makes looks like any
  other client's. The client name is self-reported: "claude-code" is what
  the client says it is.
- **Short values aren't redacted** (under 4 characters): redacting them
  would wreck the output and protect almost nothing.
- **Dart can't zero memory.** Values pass through Dart strings in the app
  and the helper, as elsewhere in DevVault (PLAN.md §5).
- **Unsandboxed helper.** `devvault-mcp` isn't sandboxed (ADR-0006),
  because it writes files and runs commands where the agent works. It
  runs with the agent's permissions, never DevVault's.

## Checked by

- `packages/agent_bridge/test`: session rules, redaction in
  `toString`, validation.
- `packages/devvault_mcp/test`: file modes, `.env` merge, redaction
  including split and cut-off values, refusal before asking, stdio MCP.
- `test/agent_bridge_test.dart`: pairing, revoke, metadata without
  values, grants and lock, timeout, hang-up.
- `test/agent_e2e_test.dart`: the real helper process against the app's
  bridge, from pairing through deny, write and lock.
- `test/tool/network_boundary_test.dart`: the bridge opens Unix domain
  sockets only.
