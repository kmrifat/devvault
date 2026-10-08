# ADR-0005: A native UI kit per desktop OS; bc_ui stays on phones

- Status: Accepted pending design review (2026-10-08)

## Context

The owner tried the app on macOS. bc_ui is designed for phones, and on
desktop its controls are oversized compared with native apps. The owner
wants desktop to look and feel native on each OS, in the style of
TablePlus, and doesn't need bc_ui there. Other packages are welcome.

A spike (branch `spike/desktop-native-ui`, `lib/spike/`) built the same
vault screen in three kits:
- a sidebar;
- a toolbar with search;
- a table-like item list;
- an inspector with a combo box, a pop-up, a password field and a switch;
- on macOS, the menu bar.

CI built each kit on each desktop OS, launched it on a real runner and
screenshotted the screen (`.github/workflows/spike-desktop-ui.yml` on that
branch). All nine combinations built and kept running.

| Kit (version) | Licence | On its own OS | Off its OS | Combo box (suggest + type your own) |
|---|---|---|---|---|
| `macos_ui` 2.2.2 | MIT, Flutter Favorite | Native: traffic lights, translucent sidebar, unified toolbar, real menu bar ([shot](0005/macos_ui-on-macOS.png)) | Runs but breaks: black background, missing labels ([on Windows](0005/macos_ui-on-Windows.png)); macOS only in practice | None built in; text field + pull-down works |
| `fluent_ui` 4.16.1 | BSD-3, Flutter Favorite, most active | Native Windows 11 ([shot](0005/fluent_ui-on-Windows.png)) | Works, but looks like Windows | `EditableComboBox`, `AutoSuggestBox` |
| `yaru` 10.2.0 | MPL-2.0 (Canonical) | Native Ubuntu/GNOME ([shot](0005/yaru-on-Linux.png)); the window frame was missing only because the CI display has no window manager | Works (Material underneath) | `YaruAutocomplete` |

`libadwaita` and `adwaita` haven't been released since 2023, so they were
ruled out.

## Decision

- **macOS:** `macos_ui`, with Flutter's `PlatformMenuBar` for the native
  menu bar.
- **Windows:** `fluent_ui`, with its `MenuBar` in the window, as TablePlus
  does on Windows.
- **Linux:** `yaru`.
- **Phones:** bc_ui, unchanged (B-frames).
- **One layout:** screens are written once against an app-level desktop
  layer, roughly fifteen primitives:
  - window/shell, sidebar, toolbar, list row, inspector row;
  - text field, combo box, pop-up select, password field, switch;
  - buttons, dialog/sheet, menu, toast/notice, icons.

  Each primitive has a macOS, Windows and Linux implementation.
- **Icons:** each OS uses its own set: SF-style Cupertino icons, Fluent
  icons, and Yaru icons (`yaru_icons`).
- **App root:** the root app widget is chosen per OS. `MacosApp.router`,
  `FluentApp.router`, and `MaterialApp.router` with `YaruTheme` all exist,
  so go_router stays. The design system's colours come from each kit's
  theme on desktop, and from bc_ui on phones.
- **Combo box:** platform and environment become combo boxes: suggestions
  plus any value the user types. Each kit has the base (or, on macOS, a
  text field plus a pull-down). The format already stores free strings
  (SPEC §5).

## Consequences

- **Icon font:** the macOS kit's icons need the `cupertino_icons` font.
  The spike showed "?" glyphs without it.
- **`yaru` 11:** blocked for now. It needs `dbus` 0.8, but
  `flutter_local_notifications` 22 pins 0.7. Stay on 10.x until the
  notifications plugin moves.
- **Window setup:** `macos_ui` styles the window through
  `macos_window_utils`. The app already sizes it with `window_manager`, so
  both must agree: one owns size, the other appearance. This gets checked
  when the shell moves over.
- **Rendering differs per OS:** goldens are macOS-only today, so desktop
  goldens cover the macOS kit. Windows and Linux get CI screenshots like
  the spike's, and widget tests run per kit.
- **Next:** design frames, then the layer, menu bar and screens (board
  cards). The frames are drawn once (macOS/TablePlus as the reference);
  Windows and Linux use the same layout with their kit's controls and are
  reviewed from CI screenshots.
