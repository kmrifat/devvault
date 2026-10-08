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
| N08 | Pair a device (sheet) | [png](desktop/N08-pair-device-light.png) | |

## Structure

- **Main window:** source-list sidebar (220 pt), a unified toolbar
  (52 pt), then content.
  - The **content** is a resizable item table (about 400 pt) beside an
    inspector, with a 24 pt status bar along the bottom.
  - The **sidebar** holds:
    - the vault switcher;
    - the smart lists, with counts: All items, Expiring in 30 days,
      Expired, Conflicts;
    - the Apps tree (app › platform › environment);
    - Tags;
    - a footer with the auto-lock time.
  - The **toolbar** has the title and path, Import, New, the search field
    (⌘F), sync status and Lock.
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
  forms.
- `showDesktopSheet` + `DesktopSheet` (title, optional icon tile and
  message, content, buttons bottom right, Escape closes) and
  `DesktopGroupBox` for the sheets and the inspector's boxes.
  `DesktopFormRow` takes an `error` that replaces its note in red.
- `showDesktopPanel` + `DesktopPanel`: a floating panel near the top of the
  window, like Spotlight (quick open, ⌘K). `DesktopRadio` (the conflict
  sheet's choices) and `DesktopProgress` (a spinner).
- `DesktopPullDownButton`: an icon push button (⋯) that drops a menu of
  commands, destructive ones in red (the inspector's Replace file… and
  Delete item…). `DesktopScopeBar`: recessed scope buttons that narrow a
  list (the table's All / Expiring / Files / Secrets); a segmented control
  is for settings.
- `DesktopSymbol` / `DesktopIcon`: icons by meaning, drawn from each OS's
  own set (Cupertino, Fluent, Yaru).
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
| Help | Help |

Items are disabled while the vault is locked.

In code: `lib/app/app_menus.dart` (`AppMenus`) above the Navigator, so the
menu bar is there on the lock screens too. On macOS it's `PlatformMenuBar`,
which owns the shortcuts. Edit is rebuilt there (Undo, Redo, Cut, Copy,
Paste, Select All) because the menu bar replaces the default one. Windows
and Linux get a menu bar along the top of the window (File, Edit, View,
Vault, Help; Settings and Quit in File, About in Help) and keep their key
handlers. The vault window binds the commands only it can run (New Item,
Import, Find, Quick Open) through `DesktopCommands`. Help has no items yet,
and Settings opens in the main window until it gets its own (⌘,).

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
