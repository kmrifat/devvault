# DevVault agent bridge protocol, version 1

This is the wire contract between the DevVault app and the
`devvault-mcp` helper that AI agents run. Like `docs/format/SPEC.md`,
changes are contract changes: update this file, `packages/agent_bridge`
and its tests in the same PR, and bump `protocol` for anything a v1 peer
would misread.

ADR-0006 explains the transport choice.

## 1. Transport

- **macOS:** a Unix domain socket at
  `$HOME/Library/Containers/com.binarycastle.devvault/Data/tmp/dv.sock`.
  Inside the sandbox the app sees the same file as `$HOME/tmp/dv.sock`.
- The app creates the socket only while *Settings → AI agents* is on. It
  sits in the container's `tmp` folder, which is mode 0700, so only the
  user's own processes can reach it.
- Before binding, the app tries to connect to an existing socket. If the
  connect succeeds, another DevVault instance owns it and this one doesn't
  serve. If it fails, the socket is stale, so the app deletes it and binds.
- One connection is one session. Closing the connection cancels every
  request still waiting for the user.

## 2. Framing

- Each message is one JSON object encoded as UTF-8 on a single line,
  ending in `\n`. `jsonEncode` never emits a raw newline, so no escaping
  is needed.
- A line may be at most 48 MiB, which leaves room for a 25 MiB attachment
  in base64. A peer that receives a longer line closes the connection.
- **Requests** (helper → app): `{"id": <int>, "method": "<name>", "params": {…}}`
- **Responses** (app → helper):
  - success: `{"id": <same int>, "result": {…}}`
  - failure: `{"id": <same int>, "error": {"code": "<code>", "message": "<text>"}}`
- Requests may be in flight at the same time. Responses may come back in
  any order and are matched by `id`.
- Unknown keys are ignored in both directions.

## 3. Session

The first request on a connection must be `hello`. Until a `hello`
carries a valid token, only `hello`, `pair` and `status` are allowed;
every other method fails with `not_paired`.

### `hello`
- **params:** `protocol` (int, `1`), `client` (`{"name": str, "version": str}`), `token` (str, optional)
- **result:** `protocol` (int), `app_version` (str), `paired` (bool), `state` (one of `no_vault`, `locked`, `unlocked`)
- A `protocol` the app doesn't speak fails with `unsupported_protocol`.

### `pair`
- **params:** `client` (`{"name": str, "version": str}`)
- **result:** `token` (str: 32 random bytes as base64url, no padding)
- The app shows "Allow *name* to connect to DevVault?" and waits for the
  user. On approval it returns a new token and marks this connection as
  paired.
- The app stores only the token's SHA-256, never the token.
- The helper keeps the token in `~/.config/devvault/agent-token` with
  mode 0600.

### `status`
- **params:** none
- **result:** `state` (`no_vault` | `locked` | `unlocked`)

## 4. Reading metadata

These methods need a paired session. When the vault is locked, the app
brings its window forward on the unlock screen with a banner naming the
client. The request waits until the vault is unlocked or the request
times out. If *Allow metadata without asking* is off, each call also
needs approval.

### `list`
- **params** (all optional): `query`, `app`, `platform`, `environment`, `type`, `tag`
- **result:** `{"items": [ItemMeta…]}`, sorted by title
- `query` uses the app's search, which only looks at non-secret metadata.
- `app` matches an app's id or its name (case-insensitive).

### `get`
- **params:** `id` (item UUID)
- **result:** `{"item": ItemMeta}`, or the error `not_found`

### ItemMeta

Every value is exactly what the vault stores. Nothing is defaulted or
inferred, and absent keys mean the vault has no value.

```json
{
  "id": "uuid",
  "title": "str",
  "type": "apple_auth_key",
  "app": {"id": "uuid", "name": "str"},
  "platform": "ios",
  "environment": "prod",
  "tags": ["str"],
  "fields": [
    {"name": "key_id", "secret": false, "source": "file", "value": "ABC123"},
    {"name": "private_key", "secret": true, "source": "file"}
  ],
  "attachments": [
    {"id": "uuid", "filename": "AuthKey.p8", "mime": "application/x-pem-file", "size": 257}
  ],
  "has_notes": true,
  "expires_at": "2027-01-01T00:00:00Z",
  "expires_source": "file",
  "updated_at": "2026-10-01T09:00:00Z"
}
```

- `app` is present only when the item points to an app that exists.
- `value` is present only for fields that aren't secret.
- `expires_at` and `expires_source` are either both present or both absent.
- Notes are never sent as metadata, because they may hold secrets.

## 5. Secrets

### `request_secret`

**params:**

| Key | Type | Meaning |
|---|---|---|
| `reason` | str, required | Why the agent needs it. Shown verbatim to the user. |
| `delivery` | object, required | `{"mode": "reveal"}`, `{"mode": "file", "path": str}` or `{"mode": "command", "command": str}`. Shown to the user. |
| `items` | list, required, 1–20 entries | Each entry: `{"id": uuid, "fields": [names]?, "attachments": [ids]?, "notes": bool?}` |

- When an entry has neither `fields`, `attachments` nor `notes`, it asks
  for every field (secret or not) and no attachments.

**result:**

```json
{"items": [{
  "id": "uuid",
  "fields": {"name": "value"},
  "attachments": [{"id": "uuid", "filename": "str", "mime": "str", "data": "<base64>"}],
  "notes": "str"
}]}
```

**How the app handles it:**
1. It checks every id, field and attachment before asking the user. A
   missing one fails with `not_found`, naming only the id or field name.
2. It waits for unlock if the vault is locked, as in §4.
3. It shows the approval sheet: client, reason, delivery and, per item,
   the path (app › platform › environment › title) plus the requested
   names. A `reveal` delivery carries a warning that the value will be
   sent to the AI model.
4. It waits for *Allow once*, *Allow for 15 minutes* or *Deny*.
   - *Allow for 15 minutes* records a grant for (client, item id). Later
     requests from the same client whose items are all granted skip the
     sheet.
   - Every grant is cleared when the vault locks.
5. *Deny* fails with `denied`. After 120 s with no answer, the request
   fails with `timeout`.

The `delivery` is information for the user. The app doesn't write files
or run commands; the helper does, after it receives the values.

## 6. Errors

| Code | When |
|---|---|
| `bad_request` | Malformed message, unknown method or invalid params |
| `unsupported_protocol` | `hello` with a version the app doesn't speak |
| `not_paired` | Any method other than `hello`/`pair`/`status` without a valid token, or a revoked one |
| `disabled` | AI agents were switched off while the connection was open |
| `no_vault` | There is no vault on this device |
| `not_found` | Unknown item, field or attachment |
| `denied` | The user declined |
| `timeout` | Nobody answered within 120 s |
| `busy` | More than 8 requests are waiting on this connection |
| `internal` | Anything else |

`message` is for people and never contains a secret value. The app
writes only the method name, client name, item titles and outcome to its
activity list.
