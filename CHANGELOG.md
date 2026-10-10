# Changelog

## 1.0.0 (not released yet)

The first release. Paste this section into the draft GitHub release
(docs/release.md › Cutting a release) and set the date when it is
published.

DevVault keeps developer credential files in a local, end-to-end encrypted
vault, and syncs it through an S3-compatible bucket you own. There is no
DevVault server. The app shows only facts: metadata and dates come from
the file or from you, never from a guess.

### Platforms

| Platform | Minimum | Download |
|---|---|---|
| macOS | 12 | `DevVault-macos.dmg`, notarized |
| Windows | 10 | `devvault-windows-x64.msix`, or the signed `devvault-windows-x64.zip` |
| Linux (x64) | GTK 3 and libsecret on the host | `devvault-linux-x64.AppImage` or `.tar.gz`, each with a `.asc` GPG signature |
| iOS | 15 | TestFlight |
| Android | 7.0 (API 24) | Google Play internal testing |

Check a download against `SHA256SUMS` on the release page.

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
- **Auto-lock and clipboard:** the vault locks after the idle time you set
  and when a phone goes to the background. Copied secrets are cleared
  after the time you set, and marked sensitive where the OS supports it.

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
- Storage keys stay in the OS keychain (Keychain, Android Keystore, DPAPI
  on Windows, libsecret on Linux). Without a keyring on Linux, they last
  until DevVault quits, and Settings says so.
- **Adding a device:** scan the desktop's QR code (or paste it) and type
  the 8-character code shown next to it. The code expires after
  10 minutes. The QR holds the storage settings, never the vault key, so
  the master password is still needed.

### On the desktop

- Native controls on each OS: macOS controls on a Mac, Fluent on Windows
  and Yaru on Linux. There is a menu bar, keyboard shortcuts (⌘ on a Mac,
  Ctrl elsewhere), and toasts in each OS's own style.
- The explorer works from the keyboard: arrow keys, Return, type-ahead,
  and Shift-F10 or the menu key for the context menu.

### On phones

- Face ID, Touch ID or the fingerprint sensor unlocks, with a key that the
  OS invalidates when the enrolled biometrics change.
- The app-switcher snapshot is blurred, and Android blocks screenshots.
- Credential files can be opened in DevVault from other apps; a file
  that arrives while the vault is locked waits for unlock.

### AI agents (macOS)

- An MCP server, `devvault-mcp`, ships inside the app. Claude Code and
  other MCP clients can list items and read their metadata.
- A secret value leaves DevVault only after you approve it in the app:
  *Allow once*, *Allow 15 min* or *Deny*. It can go to the model, into a
  file with 0600 permissions (the agent sees only the path and size), or
  into a command's environment with the values redacted from its output.
- Off by default. Setup for each client is in Settings › AI Agents and
  `docs/agent/USING.md`; the threat model is in `docs/agent/THREATS.md`.

### Not in 1.0.0

- AI agents on Windows and Linux (planned).
- Settings in its own macOS window (waits for Flutter's multi-window
  support).
- Browser autofill, team sharing, iCloud sync, a web app and a CLI.
- Hiding how many objects the bucket holds, or their sizes, from the
  storage provider.
- Wiping secrets from memory: Dart can't do it reliably, so DevVault
  limits exposure with auto-lock and clipboard clearing instead.
