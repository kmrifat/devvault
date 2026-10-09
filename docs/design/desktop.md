# Desktop design: native per OS (TablePlus style)

The approved desktop direction (owner review, 2026-10-08), following
[ADR-0005](../adr/0005-desktop-ui-kits.md). The frames are drawn on the
**Desktop · macOS** page of `design/DevVault.fig` (names start with `N`),
and exported here under `desktop/`.

- **Reference platform:** macOS. Windows and Linux use the same layout
  with their own kit's controls (see [Per OS](#per-os)).
- **Phones:** unchanged. They keep bc_ui and the B-frames.
- **Appearance:** every screen in light. The vault window, import and
  Settings are also drawn in dark to set the dark palette. The app follows
  the system setting.

## Frames

| Frame | Screen | Light | Dark |
|---|---|---|---|
| N00 | Unlock: compact window, password + Touch ID, recovery link | [png](desktop/N00-unlock-light.png) | |
| N01 | Create vault: password, strength, Argon2 note | [png](desktop/N01-create-light.png) | |
| N02 | Recovery kit: the key, Save PDF / Print / Copy, confirm | [png](desktop/N02-recovery-kit-light.png) | |
| N03 | Vault window: source list, toolbar, table, inspector, status bar | [png](desktop/N03-vault-light.png) | [png](desktop/N03-vault-dark.png) |
| N03e | Item editor (sheet) | [png](desktop/N03e-item-editor-light.png) | |
| N04 | Import (sheet) | [png](desktop/N04-import-light.png) | [png](desktop/N04-import-dark.png) |
| N05 | Conflict (sheet): choose per field, Keep Both | [png](desktop/N05-conflict-light.png) | |
| N06 | Expiry: grouped table, where each date came from, no-expiry count | [png](desktop/N06-expiry-light.png) | |
| N07 | Settings window (⌘,): Security | [png](desktop/N07-settings-security-light.png) | [png](desktop/N07-settings-security-dark.png) |
| N07b | Settings window: Sync (storage form, Pair) | [png](desktop/N07b-settings-sync-light.png) | |
| N07c | Settings window: General (appearance, reminders) | [png](desktop/N07c-settings-general-light.png) | |
| N07d | Settings window: AI Agents (allow, metadata, Claude Code setup, clients, activity; P5-06). Drawn in code first, not yet in `DevVault.fig` | [png](../../screenshots/N07d-settings-agents-light.png) | [png](../../screenshots/N07d-settings-agents.png) |
| N08 | Pair a device (sheet) | [png](desktop/N08-pair-device-light.png) | |
| N09 | AI agent asks for secrets (sheet): reason, items, where the values go (P5-05). Drawn in code first, not yet in `DevVault.fig` | [png](../../screenshots/N09-agent-reveal-light.png) | [png](../../screenshots/N09-agent-command.png) |
| N09b | AI agent asks to connect (sheet) | [png](../../screenshots/N09b-agent-pair-light.png) | |

## Structure

- **Main window:** source-list sidebar (220 pt), a unified toolbar
  (52 pt), then content.
  - The **content** is a resizable item table (about 400 pt) beside an
    inspector, with a 24 pt status bar along the bottom.
  - The **sidebar** holds:
    - the vault switcher;
    - the smart lists, with counts: All items, Expiring in 30 days,
      Expired, Conflicts;
    - the Apps explorer, like a file explorer: Organization › App ›
      Item. Without any organization it is App › Item. Organizations are
      listed A–Z, then "Personal" for apps without one, and "No app"
      last. Every app shows, with or without items; apps start closed
      unless they hold the selection. An item row shows the item's type
      icon and title, with its platform symbol and environment dot at
      the trailing edge. Clicking an organization or app lists its items;
      clicking an item selects it.
    - Every explorer row has a context menu:
      - organization: New item…, New app…, Rename organization…, Delete
        organization… (its apps stay, under Personal);
      - app: New item…, Edit app…, Move to organization…, Remove from
        *organization*, Delete app…;
      - item (also on table rows): Edit item…, Move to app…, Delete
        item…;
      - the Apps label: New organization…, New app…, New item….
    - An organization can be empty (SPEC §6.7): New organization… makes
      one to drag apps into.
    - Drag to rearrange. An item (from the explorer or the table) dropped
      on an app, "No app" or another item moves to that app. An app
      dropped on an organization (or Personal) moves into it. Both toasts
      offer Undo. Drags start from a mouse only, so touch still scrolls.
      Holding a drag over a closed organization or app for a moment
      opens it, so the drop can go onto a row inside.
    - The keyboard works it like a file explorer: ↑/↓, Home and End move
      a cursor (an accent focus ring, frame `N03-explorer-focus`); →
      opens a row or steps into it, ← closes it or steps out; Enter or
      Space opens what the row lists; F2 renames an organization or
      edits an app or item; Delete (⌘⌫ on macOS) deletes; Shift-F10 or
      the menu key opens the row's menu; typing jumps to a row by name.
      Clicking a row puts the cursor there.
    - Tags;
    - a footer with the auto-lock time.
  - The **toolbar** has the title and path, Import, New, the search field
    (⌘F), sync status and Lock.
  - Above the **item table**, the All / Expiring / Files / Secrets scope
    bar, then Platform and Environment pop-ups when the listed items
    have more than one of either.
  - The **item table** has columns Name / Type / Expires and is sortable.
    - Rows are 40 pt and two lines: the name, then the file name in mono.
    - Rows alternate shades (zebra).
    - The selected row is filled with the accent colour.
    - Warning and conflict show as badges.
  - The **inspector**:
    - a header (type tile, name, path) with Export, Edit and ⋯;
    - an expiry box with where the date came from;
    - a Fields table (value, reveal, copy);
    - a File box (Save As…, Replace…);
    - Notes.
- **Sheets** (import, editor, conflict, pairing) slide down from the
  toolbar. They use a classic macOS form: labels right-aligned to a fixed
  column, then controls, with Cancel and the default action (blue) bottom
  right.
- **Settings** is its own window (⌘,) with icon tabs: General, Security,
  Sync. On macOS, the Settings row leaves the main window's sidebar.
- **Lock screens** (unlock, create, recovery kit) are a compact centred
  window (560 pt) with the app mark.

## Controls (macOS sizes)

| Control | Size | macos_ui |
|---|---|---|
| Text field, secure field | 22 pt high, 5 pt radius | `MacosTextField` (`obscureText`) |
| Pop-up (fixed choices) | 22 pt, blue arrows | `MacosPopupButton` |
| Combo box (suggest + type your own) | 22 pt field, chevron inside its trailing edge | DevVault widget: `MacosTextField` + a menu in the macOS style (`MenuAnchor`) |
| Token field (tags) | 22 pt, pill tokens | DevVault widget |
| Push button / default | 22 pt (24 in the inspector) | `PushButton` (`secondary` for plain) |
| Segmented control | 22 pt | `MacosSegmentedControl` |
| Switch, checkbox, radio | system sizes | `MacosSwitch`, `MacosCheckbox`, `MacosRadioButton` |
| Search field | 28 pt in the toolbar | `MacosSearchField` |
| Sidebar rows | 26 pt | `Sidebar` + `SidebarItems` |
| Table header / rows | 24 pt / 40 pt (32 pt in Expiry) | DevVault table over `ListView` |

Body text is 13 pt and secondary text 11–12 pt. Mono text (IDs,
fingerprints, file names, keys) is JetBrains Mono 11–12 pt. The frames use
Inter in place of SF Pro, but the app uses the system font on macOS.

## Colours

Light (dark):

| Token | Light | Dark |
|---|---|---|
| Window / content | `#FFFFFF` | `#1E1E1E` |
| Sidebar (vibrancy) | `#ECEAEF` | `#29272E` |
| Toolbar, status bar, table header | `#FAFAFA` | `#2B2B2D` / `#252527` |
| Separator | `#E3E3E6` | `#000000` (panes), `#3A3A3C` (inside) |
| Zebra row | `#F5F5F7` | `#242426` |
| Group box | `#F6F6F8` / `#FFFFFF`, stroke `#E3E3E6` | `#2A2A2C` / `#252527`, stroke `#3A3A3C` |
| Text / secondary / tertiary | `#1D1D1F` / `#66666B`¹ / `#8E8E93` | `#F5F5F7` / `#98989D` / `#8D8D93` |
| Accent, selection | `#0A64D8` | `#0A64D8` (icons `#4D9BFF`) |
| Success | `#1F9D55` | `#32D74B` |
| Warning | `#C77700`, badge `#FFF1D6` / `#A15C00` | `#FFB340`, badge `#3D2E12` |
| Danger | `#D70015`, badge `#FDE8EA` | `#FF6961`, badge `#3D1A1A` |
| Conflict | `#8944AB`, badge `#F1E4F8` | `#D49BF5`, badge `#3A2846` |

¹ The frames use `#6E6E73`, which is 4.25:1 on the sidebar. The app uses
`#66666B`, the nearest shade that reaches WCAG AA (4.5:1) there. Tertiary
text is only for placeholders and disabled controls.

In code these come from the kit's theme (`MacosTheme`, `MacosColors`) plus
DevVault's own tokens (`DesktopColors`, read with `context.desktopColors`)
for the surfaces, fields, badges and group boxes. No colour is hard-coded in
a screen.

## In code

The desktop layer is `lib/shared/desktop/`, and desktop screens import it
through `package:devvault/shared/desktop_ui.dart`:

- `DesktopTheme` goes in `MaterialApp.builder` and picks the kit for the
  OS (`DesktopKit`), so menus the kits push as routes are themed too.
- `DesktopColors` and `DesktopMetrics` hold the tokens and sizes above.
- Controls: `DesktopTextField` (also the secure field), `DesktopComboBox`,
  `DesktopPopup`, `DesktopTokenField`, `DesktopButton`, `DesktopSegmented`,
  `DesktopSwitch`, `DesktopCheckbox`, `DesktopIconButton`,
  `DesktopSearchField`, and `DesktopForm` / `DesktopFormRow` for sheet
  forms (on macOS, rows sit at a fixed 31 pt pitch, since a text field
  keeps room for its focus ring).
- `DesktopDateField`: a date field (medium format, "Mar 1, 2027") with a
  calendar to pick from and a Clear action; typing `YYYY-MM-DD` still
  works. macOS drops macos_ui's graphical `MacosDatePicker` in the menu
  style, Windows opens Fluent's `CalendarView` in a flyout, Linux drops
  Material's `CalendarDatePicker` in a popover.
- `showDesktopSheet` + `DesktopSheet` (title, optional icon tile and
  message or subtitle, content, buttons bottom right, Escape closes; on
  macOS it hangs from the toolbar) and `DesktopGroupBox` for the sheets
  and the inspector's boxes. `DesktopFormRow` takes an `error` that
  replaces its note in red.
- `showDesktopPanel` + `DesktopPanel`: a floating panel near the top of the
  window, like Spotlight (quick open, ⌘K). `DesktopRadio` (the conflict
  sheet's choices) and `DesktopProgress` (a spinner).
- `showDesktopToast`: a short, passing message with an optional action
  (Undo). On macOS it's a banner like Notification Center's, at the top
  right under the toolbar: a status symbol, the title in bold, a push
  button for the action, and, on hover, a round × over its top-left
  corner. Hovering keeps it open. On
  Windows it's Fluent's `InfoBar` at the bottom; on Linux, a Yaru
  snackbar. One shows at a time. Screens call `showAppToast`, which
  picks this on desktop and bc_ui's toast on phones. Frames:
  `N03-toast`, `N03-toast-light`.
- `DesktopPullDownButton`: an icon push button (⋯) that drops a menu of
  commands, destructive ones in red (the inspector's Replace file… and
  Delete item…). `DesktopContextMenu` opens the same kind of menu where
  its child is right-clicked (long-pressed on touch), and exposes each
  command as a semantics action (the sidebar rows' menus). `DesktopScopeBar`: recessed scope buttons that narrow a
  list (the table's All / Expiring / Files / Secrets); a segmented control
  is for settings.
- `DesktopLockWindow` for the lock screens (unlock, create, recovery kit,
  recover, join): a centred `lockWidth` column on the lock-window colour,
  with the app mark, and a footer row for a link and the default button.
  `DesktopLink` is a text link (Fluent `HyperlinkButton`, Yaru
  `TextButton`); `DesktopButton` can lead with a symbol.
- `DesktopSymbol` / `DesktopIcon`: icons by meaning, drawn from each OS's
  own set (Cupertino, Fluent, Yaru). CupertinoIcons has no Touch ID or
  Face ID glyph, so macOS uses the app's Lucide ones for those two.
- `DesktopWindow`: the main window's frame. In the app on macOS it is
  `MacosWindow` + `Sidebar`, so the sidebar runs under the traffic lights
  with the system's vibrancy and can be resized; `macos_window_utils` sets
  the window's look (transparent title bar, full-size content) and
  `window_manager` its size. Windows, Linux and tests draw the same layout
  in flat colours under the OS's own title bar.

The shell (`lib/app/desktop_shell.dart`) puts the source list
(`VaultSidebar`), toolbar (`ShellToolbar`) and status bar (`ShellStatusBar`)
in that frame. The vault branch is the item table
(`lib/features/vault/vault_list_pane.dart`) beside the inspector
(`desktop_inspector.dart`); the status bar shows the selected item's
created / updated line.

Each control is drawn by the running OS's kit and behaves the same on all
three (`test/desktop_controls_test.dart`). The macOS kit's goldens are
`screenshots/desktop-controls-macos-{light,dark}.png` and
`desktop-combo-menu-macos-light.png`.

## Menu bar (macOS)

Built with `PlatformMenuBar`:

| Menu | Items |
|---|---|
| DevVault | About, Settings… ⌘,, Quit |
| File | New Item ⌘N, Import… ⌘I |
| Edit | Copy, Paste, Select All, Find ⌘F |
| View | Quick Open ⌘K |
| Vault | Sync Now ⌘R, Lock ⌘L, Expiry |
| Window | Window |
| Help | DevVault Help, Using DevVault with AI Agents, Report an Issue… |

Items are disabled while the vault is locked, except Help's. Help opens
pages on GitHub in the browser: the README, `docs/agent/USING.md` and a
new issue.

In code: `lib/app/app_menus.dart` (`AppMenus`) above the Navigator, so the
menu bar is there on the lock screens too. On macOS it's `PlatformMenuBar`,
which owns the shortcuts. Edit is rebuilt there (Undo, Redo, Cut, Copy,
Paste, Select All) because the menu bar replaces the default one. Windows
and Linux get a menu bar along the top of the window (File, Edit, View,
Vault, Help; Settings and Quit in File, About in Help) and keep their key
handlers. The vault window binds the commands only it can run (New Item,
Import, Find, Quick Open) through `DesktopCommands`. Help opens its pages
through `linkOpenerProvider`. Settings opens in the main window until it
gets its own (⌘,).

## Per OS

Same layout and regions on every OS; each OS draws them with its own kit:

| Region | macOS (`macos_ui`) | Windows (`fluent_ui`) | Linux (`yaru`) |
|---|---|---|---|
| Window and sidebar | `MacosWindow` + `Sidebar` | `NavigationView` + `NavigationPane` (expanded) | `YaruMasterTile` list in a side pane |
| Toolbar | `ToolBar` | `CommandBar` in the page header | `AppBar` actions + `YaruSearchField` |
| Menus | `PlatformMenuBar` | `MenuBar` in the window | `MenuBar` in the window |
| Fields | `MacosTextField` | `TextBox`, `PasswordBox` | `TextField` (Yaru theme) |
| Combo box | DevVault widget | `EditableComboBox` | `YaruAutocomplete` |
| Pop-up | `MacosPopupButton` | `ComboBox` | `DropdownMenu` |
| Sheets | `MacosSheet` | `ContentDialog` | `AlertDialog` (Yaru) |
| Settings | Separate window (⌘,) | Page in the window | Page in the window |

Spike screenshots of each kit are in [ADR-0005](../adr/0005-desktop-ui-kits.md).
