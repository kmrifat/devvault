# Changelog

## 1.1.1 (2026-10-12)

[v1.1.1](https://github.com/kmrifat/devvault/releases/tag/v1.1.1), macOS and Linux.

Fixes to the item editor and the inspector, from a look at 1.1.0.

- A masked value's dots no longer run together: they're drawn with room
  between them in every password field.
- The item editor's field rows no longer cut off the bottom of their
  text, and a value you show wraps onto more lines so all of it can be
  read (a connection string, a key). Field names get more room.
- The inspector and the app header have a Delete button with a trash
  icon in place of a ⋯ menu that held little else. Items with more than
  one file get Replace files… beside it.
- Buttons beside Edit are the same height as Edit on macOS, Windows and
  Linux.

## 1.1.0 (2026-10-12)

[v1.1.0](https://github.com/kmrifat/devvault/releases/tag/v1.1.0), macOS and Linux.

What developers trying 1.0.1 told us, and a walk through every desktop
screen.

### Sidebar

- Each organization is a section of its own, over its apps, instead of a
  row under a heading that said "Apps". Items in no app sit under
  Personal.
- Easier to start: New app at the foot of the sidebar; + on an
  organization (a new app there) and on an app (a new item in it) when the
  pointer is over them; an empty vault explains apps and organizations and
  offers both.
- Rows are bigger (28 pt, 16 pt icons, 12 pt chevrons). Item rows drop the
  platform symbol, which was the same phone for iOS and Android, and name
  the environment only where two items in an app share a name.

### Menus, toolbar and icons

- On macOS, context menus and the ⋯ buttons are the system's own menus,
  with an icon beside each command. The old drawn menu was so transparent
  it was hard to read.
- The toolbar's Import and New are labelled buttons; New offers Item,
  Secure note, App and Organization.
- Icon buttons are drawn at their real size (they were all 12 pt), and
  nothing clickable is smaller than 24 × 24 pt.
- With nothing selected, the inspector offers Import a file… and New
  item….

### Readability

- Password fields type the system's dot (●), and hidden values show eight
  clear dots instead of tiny bullets.
- Fields read from a file say "From file" instead of showing a coloured
  dot; the item table names each item's platform and environment.
- A disabled default button is grey, not pale blue.

### Consistency

- Platforms and environments read the same everywhere ("Android",
  "Production"); anything you typed yourself shows as you typed it.
- The unlock screen names the vault by the first eight characters of its
  ID. Settings has its own toolbar, and Security lists the vault's ID,
  location and encryption as rows.
- The item editor's fields are one height, and the import sheet's
  controls one width.

### App colours

- Pick an app's badge colour in the app editor. The vault stores the
  colour's name (format: an optional `color` on app records, SPEC §6.2);
  apps without one keep the colour they had, and older versions keep the
  field as it is.

## 1.0.1 (2026-10-11)

[v1.0.1](https://github.com/kmrifat/devvault/releases/tag/v1.0.1), macOS and Linux.

- New app icon on every platform: a stack of credential files sealed by a
  lock, white on rose. The 16 and 32 px macOS sizes use a simpler mark
  that stays legible.
- The same mark in the app: the unlock screen, the create-vault header
  and the sidebar's vault header.
- The macOS disk image opens on a window with DevVault, an Applications
  link and an arrow between them: drag the app across to install it.

## 1.0.0 (2026-10-11)

The first release: [v1.0.0](https://github.com/kmrifat/devvault/releases/tag/v1.0.0),
macOS and Linux.

DevVault keeps developer credential files in a local, end-to-end encrypted
vault, and syncs it through an S3-compatible bucket you own. There is no
DevVault server. The app shows only facts: metadata and dates come from
the file or from you, never from a guess.

### Platforms

| Platform | Minimum | Download |
|---|---|---|
| macOS | 12 | `DevVault-macos.dmg`, notarized |
| Linux (x64) | GTK 3 and libsecret on the host | `devvault-linux-x64.AppImage` or `.tar.gz`, each with a `.asc` GPG signature |

Check a download against `SHA256SUMS` on the release page. Windows, iOS
and Android follow in a 1.0.x release: Windows once its code signing is
set up, the phones once TestFlight, Google Play and the device checks
are done.

### The vault

- **Encryption:** a master password (Argon2id) and a one-time recovery key
  each wrap a random vault key. Every item and file is sealed with
  XChaCha20-Poly1305 and bound to its slot. The format is specified in
  `docs/format/SPEC.md`, with test vectors and an independent Go verifier.
- **Recovery kit:** shown when the vault is created, to save as PDF or
  text, print or copy. A new kit (Settings › Security) asks for the master
  password first.
- **Recovery:** unlock with the recovery key and set a new master password.
- **Start over:** with the master password and the recovery key both
  lost, nothing can open the vault. The recovery screen can erase it from
  the device (after you type ERASE) so you can create a new one. A copy in
  your bucket is left as it is.
- **Key rotation:** Settings › Security replaces the vault key and
  re-encrypts everything; other devices adopt the new key at their next
  sync.
- **Auto-lock and clipboard:** the vault locks after the idle time you
  set. Copied secrets are cleared after the time you set.

### Credential files

DevVault reads these files and shows what they say:

- Apple: `.p8` auth keys (including APNs), certificates (`.cer`, PEM),
  `.p12` / PKCS#12, and `.mobileprovision` profiles.
- Android: Java keystores (JKS and JCEKS) and PKCS#12 keystores.
- Google: Firebase configs, GCP service accounts and OAuth clients.
- PEM bundles and OpenSSH private keys, with the fingerprint
  `ssh-keygen -lf` prints.
- Anything else as a generic file, and pasted text as a generic secret.

Exports give back the original file byte for byte, checked against its
SHA-256. Importing a newer file over an item keeps the item and its tags.

### Organizing

- Organizations, apps, platforms and environments, shown on the desktop as
  an Organization › App › Item explorer. Every row has a context menu, and
  items and apps can be dragged to a new place, with Undo.
- Markdown notes on items, apps and organizations.
- **Secure notes:** Markdown documents in the vault, in an app or in none.
  The editor shows the note as it reads: typing `# ` makes a heading,
  `- ` a list, ```` ``` ```` a code block, and the marks disappear. A
  Markdown mode shows the source. Notes are encrypted like every item and
  never searchable; Copy clears from the clipboard like a secret.
- Search over titles and metadata. Secret values are never indexed.

### Expiry

- An expiry date is set only from the file or by you, and always shows
  where it came from.
- The expiry dashboard groups items into Expired, within 30 days, Later
  and No expiry.
- At most two reminders per item, at 09:00 local: one when it enters the
  30-day window and one on the day it expires.

### Sync

- Any S3-compatible storage: Cloudflare R2, AWS S3, Backblaze B2 or MinIO.
  The bucket sees encrypted objects with random names; it can see how many
  there are and how big they are.
- Changes from several devices merge. When two devices change the same
  item, DevVault shows both versions field by field; you pick each field
  or keep both. Nothing is resolved without your choice.
- Storage keys stay in the OS keychain (Keychain on macOS, libsecret on
  Linux). Without a keyring on Linux, they last until DevVault quits, and
  Settings says so.
- **Adding a device:** paste the pairing text another device shows with
  its QR code, and type the 8-character code shown next to it. The code
  expires after 10 minutes. The pairing text holds the storage settings,
  never the vault key, so the master password is still needed.

### On the desktop

- Native controls on each OS: macOS controls on a Mac and Yaru on
  Linux. There is a menu bar, keyboard shortcuts (⌘ on a Mac,
  Ctrl elsewhere), and toasts in each OS's own style.
- The explorer works from the keyboard: arrow keys, Return, type-ahead,
  and Shift-F10 or the menu key for the context menu.
- Touch ID unlocks on a Mac, with a key that macOS invalidates when the
  enrolled fingerprints change.

### AI agents (macOS)

- An MCP server, `devvault-mcp`, ships inside the app. Claude Code and
  other MCP clients can list items and read their metadata.
- A secret value leaves DevVault only after you approve it in the app:
  *Allow once*, *Allow 15 min* or *Deny*. It can go to the model, into a
  file with 0600 permissions (the agent sees only the path and size), or
  into a command's environment with the values redacted from its output.
- Off by default. Setup for each client is in Settings › AI Agents and
  `docs/agent/USING.md`; the threat model is in `docs/agent/THREATS.md`.

### Updates (desktop)

- Once you agree (a question under the toolbar, or Settings › General ›
  *Check for updates*), DevVault asks GitHub once a day for its latest
  published release. Only that request is sent: no version, device or
  vault. Until you agree it asks nothing, except when you press *Check
  Now*.
- When a newer release is out, a line under the toolbar says so, with
  the version and date as GitHub gives them. *View Release* opens its
  page.
- **macOS:** *Update…* installs it in place with Sparkle, which checks
  the update's EdDSA signature and the Developer ID before installing.
- **Linux:** the AppImage carries update information for AppImageUpdate,
  Gear Lever and AppImageLauncher; the app itself offers *View Release*.

### Not in 1.0.0

- Windows, iOS and Android builds (see Platforms).
- AI agents on Windows and Linux (planned).
- Settings in its own macOS window (waits for Flutter's multi-window
  support).
- Browser autofill, team sharing, iCloud sync, a web app and a CLI.
- Hiding how many objects the bucket holds, or their sizes, from the
  storage provider.
- Wiping secrets from memory: Dart can't do it reliably, so DevVault
  limits exposure with auto-lock and clipboard clearing instead.
