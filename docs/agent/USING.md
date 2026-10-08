# Using DevVault from Claude Code (and other AI agents)

DevVault ships an MCP server, `devvault-mcp`. An agent such as Claude Code
can use it to find credentials in your vault and, **with your approval in
the DevVault app**, use them. You never type your master password into
the agent. DevVault asks you, in its own window, every time a secret
value would leave it.

macOS only for now. Windows and Linux are planned in P5-11.

## Set it up (once)

1. In DevVault, open **Settings › AI Agents** and turn on **Allow AI
   agents**.
2. Add the server to Claude Code. Settings › AI Agents has the exact line
   with a Copy button:

   ```bash
   claude mcp add --scope user devvault -- /Applications/DevVault.app/Contents/Helpers/devvault-mcp
   ```

   From a source checkout, without a built app:

   ```bash
   claude mcp add --scope user devvault -- dart run /path/to/devvault/packages/devvault_mcp/bin/devvault_mcp.dart
   ```

3. Ask Claude for something that needs a credential, e.g. *"set
   STRIPE_KEY in .env from my vault"*. The first time, DevVault asks
   **"claude-code" wants to connect to DevVault**. If the vault is locked,
   it asks you to unlock it first. Choose **Allow**.

If DevVault isn't running, the helper starts it. If AI agents are off,
the agent is told to ask you to turn them on.

## What the agent can do

| Tool | DevVault asks you? | What reaches the agent (and the AI model) |
|---|---|---|
| `vault_status` | no | whether DevVault runs and the vault is locked |
| `list_items`, `get_item` | no¹ | titles, types, apps, platforms, environments, tags, field names, non-secret values (key IDs, team IDs, fingerprints), attachment names, expiry with its source. **Never secret values or notes.** |
| `get_secret` | **yes** | the values themselves. The sheet warns you about this. |
| `write_secret_file` | **yes**, showing the path | the path and size. The file is written readable only by you (0600). |
| `write_env_file` | **yes**, showing the path | the variable names. The `.env` is merged in place, made 0600. |
| `run_with_secrets` | **yes**, showing the command | exit code and output, with every value replaced by `[redacted:NAME]` |

¹ Turn off **Read metadata without asking** to be asked for these too.

### The approval sheet

Every request shows:
- which client is asking;
- the reason it gave, word for word;
- each item, as app › platform › environment › title, with the fields
  and files it wants;
- where the values will go: the file path, or the command with the
  folder it runs in and which value each variable carries.

You answer with one of:
- **Allow Once.**
- **Allow for 15 Minutes:** exactly the same request (same client,
  items, fields and destination) won't ask again until then, or until the
  vault locks. Anything different asks.
- **Deny.** The agent is told not to ask again unless you say so.

Unanswered requests fail after 2 minutes. Locking the vault cancels
anything still waiting.

Prefer the last three tools. With them the value goes where it's needed
and never into the conversation. The server tells the agent the same.

## Claude Code permissions

DevVault already asks before any value leaves it. You can also let Claude
Code run the read-only tools without its own prompt, and leave the rest
on "ask" (the default). Add this to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__devvault__vault_status",
      "mcp__devvault__list_items",
      "mcp__devvault__get_item"
    ]
  }
}
```

## Disconnecting

- **Revoke a client:** Settings › AI Agents › Connected clients ›
  **Disconnect**. Its connection drops and its token stops working. It
  asks to connect again the next time.
- **Where the tokens live:** the helper keeps one token per client name
  in `~/.config/devvault/agent-tokens.json` (mode 0600). DevVault keeps
  only their SHA-256 hashes.
- **Turning everything off:** with **Allow AI agents** off, DevVault
  doesn't listen at all.

## Troubleshooting

| The agent says | What to do |
|---|---|
| "DevVault isn't running, or AI agents are off" | Open DevVault and turn on Settings › AI Agents › Allow AI agents. |
| "Nobody answered in DevVault within 2 minutes" | Look for the sheet in DevVault (it comes to the front), then ask again. |
| "The user denied this" | You pressed Deny. Ask the agent again if you meant to allow it. |
| "Another copy of DevVault is already serving agents" (in Settings) | Quit the other copy, e.g. a debug build sharing the same data. |

How it works: [ADR-0006](../adr/0006-agent-bridge.md),
[PROTOCOL.md](PROTOCOL.md). What it defends against:
[THREATS.md](THREATS.md).
