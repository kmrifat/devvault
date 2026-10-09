# macOS walkthrough (P1-25)

**Date:** 2026-10-09. **Build:** `main` at `b808752`, debug, Flutter
3.47.5, on macOS 27.0 (Apple silicon), in the desktop layout with the
native window and the macOS menu bar.

The walk is automated, so it can be run again after each fix:

```sh
flutter test integration_test/macos_walkthrough_test.dart -d macos
```

It opens the app on the screen and goes through every flow on the card
the way a user would: clicks, typing, the menu bar's commands, keyboard
navigation in the explorer and a mouse drag. It takes 2 to 3 minutes.

**It doesn't touch the owner's vault, settings or keychain.** The app runs
with the provider overrides the widget tests use, pointed at a fresh
temporary folder. The keychain is in memory. Notifications, save and open
dialogs, Finder, the browser and the printer are recording fakes. Sync
uses a local folder (`LocalDirBackend`) in place of a bucket, and the AI
agents socket is in the test's folder. Crypto is the real libsodium at
the real Argon2id cost (64 MiB, 3 passes). The system clipboard is real.
Only made-up values are copied, and the test leaves it empty. The parser
fixtures are compiled into the test (`integration_test/walkthrough_fixtures.dart`),
because the sandboxed app can't read the source tree.
`test/tool/walkthrough_fixtures_test.dart` keeps those copies equal to the
originals.

**Screenshots** (one per step, 71 on this run) go to the app's sandbox. The
test prints the folder's path:
`~/Library/Containers/com.binarycastle.devvault/Data/tmp/devvault-walkthrough-<time>/`.
They aren't committed. The names below are from that folder.

## Result

**All 22 steps pass. They found 6 product problems** ([findings](#findings)).
The test checks each open one with `knownIssue(...)`, which logs and lists
the problem instead of failing. It also reports when a problem no longer
reproduces. A fixed one becomes a normal expectation (WALK-02 so far).
No Flutter errors (overflows, exceptions) were reported during the walk.

| # | Flow | Result | Notes |
|---|---|---|---|
| 1 | Create a vault (N01): a short password and a mismatched confirmation are refused; the strength meter shows; Argon2id runs | Pass | |
| 1b | Recovery kit (N02): Open Vault waits for the checkbox; Save as Text… saves the key and the vault id; the toast has no secret | Pass | |
| 2 | Vault › Lock (⌘L); a wrong password says "That password didn't open this vault" and clears the field; the right one unlocks | Pass | |
| 3 | Import every type (D04 / N04), alternating the toolbar's Import and File › Import… (⌘I): `.p8` (Team ID asked), `.p12` (password), `.mobileprovision`, `.jks` (store password), `google-services.json`, `GoogleService-Info.plist`, service account, OAuth client, SSH key, an unknown file (generic), and the same file twice (Open existing) | Pass | Every fact the parser reads is on the sheet. The expiry comes from the file, or the sheet says there's none. Each item lands in the table, selected. WALK-04, WALK-05 |
| 3b | File › New Item (⌘N): two Generic Secrets with your own expiry (in 10 days, 3 days ago) | Pass | Covers Generic Secret: on desktop, Import has no "Paste a secret" (that's the phone's B4b) |
| 4 | Inspector: fields, "From file", reveal and hide a secret, the status bar's history, Save As… writes the file back byte for byte | Pass | |
| 4b | Clipboard guard: Settings › Security › Clear copied secrets after 10 seconds; Copy Value puts it on the real clipboard; the toast says 10 seconds and has no secret; cleared after ~9.5–9.7 s; something copied since is left alone | Pass | |
| 5 | Search (Edit › Find, ⌘F): by title, key ID (`TESTKEY123`) and file name (`google-services.json`); a secret's value finds nothing | Pass | |
| 5b | Quick open (View › Quick Open, ⌘K): recent items, then by key ID, file name and title; Return opens; Escape closes; secrets aren't found | Pass | |
| 6 | Expiry (Vault › Expiry, N06): Expired · 1, Within 30 days · 1, Later · 3; "Set by you" / "From file"; status bar "5 dated · 7 without a date", "Reminders on"; sidebar Expired and Expiring lists; a row opens its item | Pass | WALK-03 |
| 7a | Settings › General › Expiry reminders: reminders were scheduled for the dated items at 09:00, with no secret in them; turning it off withdraws them and the status bar says "Reminders off" | Pass | Against a fake notification centre (8 scheduled) |
| 7b | Settings › Security › Lock after 1 minute: the sidebar footer says 1m; a minute without input locks the vault and leaves the clipboard empty; the password unlocks | Pass | Idle time moved on the clock, not waited out |
| 7c | Change… master password: a wrong current password is refused; the change says so with no secret in the toast; the old password no longer opens it, the new one does | Pass | |
| 7d | New Kit…: Show in Finder, the vault id, a new key after the password; Copy | Pass | WALK-01, WALK-06 |
| 7e | Rotate… with the master password: a new key, the same items; lock, unlock with the password, every file still opens | Pass | |
| 7f | Settings › Sync with a local folder in place of the bucket: Test Connection, Turn On Sync, a first sync (23 objects), Vault › Sync Now (⌘R); keys only in the keychain, not in settings.json | Pass | |
| 7g | Pair a device (N08): QR and code, "Works for 10:00"; Done | Pass | No device paired |
| 7h | Settings › AI Agents: setup command, no clients; turning agents on opens the socket, turning them off closes it | Pass | |
| 8a | Explorer: Apps › New organization…; the organization's New app… fills in the organization | Pass | |
| 8b | Drag an item from the table onto an app with the mouse; the toast's Undo puts it back; drag again | Pass | |
| 8c | Explorer keyboard: click, →, Return, ←, F2 (Edit app), Shift-F10, Home, type-to-jump; the table row's context menu | Pass | WALK-02 (fixed) |
| 9 | Lock from the toolbar | Pass | |

## Findings

Each needs a card. Severity is **blocker**, **should fix** or **nice to
have**. None is a blocker.

### WALK-01 · The recovery-key copy toast always says "30 seconds" (should fix)

- **Steps:** Settings › Security › Clear copied secrets after 10 seconds.
  Then New Kit…, enter the password, Make New Key, then Copy.
- **Expected:** "It clears from the clipboard in 10 seconds." This is the
  setting, and the guard does clear it after 10 s.
- **Actual:** "It clears from the clipboard in 30 seconds." The text is
  hard-coded in `RecoveryKitActions.copyKit`
  (`lib/features/create_vault/recovery_kit_card.dart`). The inspector's
  copy toast reads the setting.
- **Screenshot:** `49-new-recovery-kit-copied.png`

### WALK-02 · The keyboard can't work a context menu (should fix) · fixed

**Fixed:** a context menu now takes the keyboard when it opens, on every
kit. From Shift-F10 or the menu key its first command is highlighted;
after a right click nothing is, until ↓ or ↑. ↑/↓ move, Return or Space
runs the command, and Escape closes the menu and gives the keyboard back
to the explorer, with the cursor where it was. The macOS ⋯ pull-down
button's menu works the same way. The walkthrough now expects this.

- **Steps:** In the explorer, click an app row and press Shift-F10. Then
  press Escape, or ↓ then Return. Or right-click a row in the table and
  press Escape.
- **Expected:** The menu takes focus, as a macOS menu does. ↓ and Return
  choose a command, and Escape closes the menu (design doc › explorer
  keyboard: "Shift-F10 or the menu key opens the row's menu").
- **Actual:** Focus stays on the explorer tree. Escape leaves the menu
  open. ↓ and Return move the tree's cursor behind the menu, and here they
  opened the item under the app, with the menu still showing. Only a
  click closes it. `DesktopContextMenu` opens its `MenuAnchor` without
  moving focus into it. No test covers Escape or the arrow keys.
- **Screenshots:** `68-explorer-shift-f10-menu.png`,
  `69-explorer-menu-after-escape.png`

### WALK-03 · "4 days ago" for something that expired 3 days ago (nice to have)

- **Steps:** Make an item with your own expiry 3 days back
  (2026-10-06, on 2026-10-09), then open Vault › Expiry.
- **Expected:** Left says "3 days ago", as N06 does for its expired row.
- **Actual:** "4 days ago". `DesktopExpiryTable.left` rounds the time
  since expiry up, the same way it rounds the time left. That is right
  for "days left", but it overstates "days ago". The item in 10 days
  reads "10 days" as it should.
- **Screenshot:** `39-expiry-sidebar-expired.png`

### WALK-04 · The import sheet hides the expiry below the fold (should fix)

- **Steps:** At the default window size (1280 × 800), import `legacy.p12`
  (after its password), `development.mobileprovision` or `test.jks`.
- **Expected:** The expiry line ("Expires Oct 7, 2027 · From the file")
  is in view, or the sheet shows that there's more to see.
- **Actual:** The sheet stops at Tags. The "Keep the password with the
  item" checkbox is cut through the middle, and the expiry line is out of
  view. macOS hides the scroll bar, so nothing shows that the sheet
  scrolls. The facts box (12 rows for a `.p12`) takes the room.
- **Screenshot:** `10-import-legacy-p12.png` (also `11-…`, `13-…`)

### WALK-05 · The toast covers the inspector's buttons after an import (should fix)

- **Steps:** Import any file and look at the inspector right away.
- **Expected:** Export, Edit and ⋯ can be clicked.
- **Actual:** The "File imported" banner sits at the top right under the
  toolbar, over the inspector's header buttons, until it times out (4 s).
  Hovering keeps it open, so a user who reaches for Edit keeps it there.
  This happened on 8 of 9 imports.
- **Screenshot:** `10-import-legacy-p12.png` (the toast over the header
  behind the sheet), `14-import-google-services-json.png`

### WALK-06 · New Kit and Rotate show the phone's recovery-key card (should fix)

- **Steps:** Settings › Security › New Kit… (or Rotate…), then enter the
  password.
- **Expected:** The key with N02's desktop push buttons (Save PDF…,
  Print…, Save as Text…, Copy), like the create flow's recovery-kit screen.
- **Actual:** bc_ui's phone card: blue and grey pill buttons "Save PDF",
  "Print", "Save as text" and "Copy", with a dark key box. It doesn't
  match the desktop sheet around it or `docs/design/desktop.md`
  (sheets use the macOS kit's controls).
- **Screenshots:** `48-new-recovery-kit.png`, `51-rotate-key-done.png`

### Also seen (no card needed yet)

- Settings opens in the main window, with a Settings row in the sidebar.
  The design wants its own window (⌘,), and the design doc already notes
  that it "opens in the main window until it gets its own".
- The import sheet shows some facts raw: "Has private key: true" and
  ISO timestamps ("2027-10-07T00:00:00Z") above the formatted expiry.
  They are what the file says, so this is only about formatting.
- "Expiring in 30 days" opens the whole Expiry dashboard (expired and
  later items too), not only the item it counts. That's how N06 draws it.

## Still needs a human

The automated walk can't cover these:

- **Real notifications at 09:00.** The walk checks what is handed to the
  notification centre (a fake), not that macOS posts it, asks for
  permission or opens the item from a click.
- **Touch ID.** Turning on "Unlock with Touch ID" and unlocking with it
  need the Secure Enclave and a finger. The walk runs without biometrics.
- **The real Keychain.** The keychain is in memory. Saving and reading
  storage keys in the login keychain, and the `-34018` case of unsigned
  builds, need a signed build (P1-24).
- **A real bucket** (R2 or S3) and a second device: sync ran against a
  local folder.
- **Pairing a device:** scanning the QR with a phone and joining.
- **Real key presses through AppKit.** ⌘ shortcuts are owned by the menu
  bar. The walk selects the menu item that has the shortcut, which is
  what AppKit does with the key. It doesn't press the keys. Return in a
  text field is sent as the field's input action.
- **Real idle time and sleep.** The walk moves the clock past the
  auto-lock time instead of waiting, and doesn't sleep the Mac or lock
  the screen.
- **Save, open and print dialogs, Finder, the browser:** these are fakes.
  The real NSSavePanel or NSOpenPanel, drag-out and drop from Finder
  still need a person.
- **AI agents end to end:** a real `claude mcp add` client asking for a
  secret (P5) was out of scope.
- **Look and feel:** vibrancy, light mode (this run followed the system's
  dark mode) and the 14-day dogfood itself (P1-24).
