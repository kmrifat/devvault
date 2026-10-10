import 'package:flutter/painting.dart' show EdgeInsets;

import 'desktop_theme.dart' show DesktopKit;

/// Sizes from docs/design/desktop.md (macOS points; Windows and Linux use
/// the same layout). Screens use these instead of literals.
abstract final class DesktopMetrics {
  /// Push buttons, menu rows and other small controls.
  static const double controlHeight = 22;

  /// Text fields, pop-ups and combo boxes: one height, so a form's controls
  /// line up.
  static const double fieldHeight = 28;

  /// Push buttons: regular (sheets, forms) and large (lock screens).
  static const double buttonHeight = 26;
  static const double largeButtonHeight = 32;

  /// Corner radius of fields and the token field.
  static const double fieldRadius = 5;

  /// Corner radius of a menu, and of the highlighted row inside it.
  static const double menuRadius = 6;
  static const double menuItemRadius = 4;

  /// macOS menus (context, pull-down, pop-up, combo box), as the system
  /// draws them: the panel's corner radius and its highlighted row's,
  /// concentric across the panel's 5 pt inset; a row's height; and the
  /// room a separator between two groups of rows takes.
  static const double menuPanelRadius = 12;
  static const double menuRowRadius = 7;
  static const double menuRowHeight = 24;
  static const double menuSeparatorHeight = 11;

  /// The widest a menu grows for a long choice (unless its field is wider);
  /// longer labels end in an ellipsis.
  static const double menuMaxWidth = 400;

  /// Corner radius of a tag pill.
  static const double tokenRadius = 9;

  /// The token field's least height: the design's 22 pt row on macOS (its
  /// pills make it 22), and on Windows and Linux as tall as the kit's own
  /// text field (Fluent's `TextBox`, Yaru's `TextField`).
  static double tokenFieldHeight(DesktopKit kit) => switch (kit) {
    DesktopKit.macos => 20,
    DesktopKit.fluent => 31,
    DesktopKit.yaru => 35,
  };

  /// A place combo box (platform, environment) beside others in a row: wide
  /// enough for "development" in that kit's field.
  static double placeFieldWidth(DesktopKit kit) => switch (kit) {
    DesktopKit.macos => 140,
    DesktopKit.fluent => 136,
    DesktopKit.yaru => 164,
  };

  /// The menu button inside a Yaru combo box: small enough that the combo
  /// box is as tall as a text field, like the pop-ups beside it.
  static const double yaruFieldButtonSize = 32;

  /// A Yaru push button that leads with a symbol: narrower at the sides
  /// than Yaru's 16 all round, so the recovery kit's four fit on one line.
  static const yaruSymbolButtonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 16,
  );

  static const double sidebarWidth = 220;
  static const double sidebarRowHeight = 26;
  static const double toolbarHeight = 52;
  static const double toolbarSearchHeight = 28;
  static const double statusBarHeight = 24;

  /// The item table: header, two-line rows, and its starting width.
  static const double tableHeaderHeight = 24;
  static const double tableRowHeight = 40;
  static const double tableWidth = 400;

  /// The item table's fixed Type and Expires columns; Name takes the rest.
  static const double tableTypeColumnWidth = 100;
  static const double tableExpiresColumnWidth = 62;

  /// The inspector: its type tile, and the rows of its Fields box.
  static const double inspectorTileSize = 40;
  static const double inspectorFieldRowHeight = 31;

  /// The inspector's item name.
  static const double inspectorTitleSize = 18;

  /// The expiry table's one-line rows.
  static const double expiryRowHeight = 32;

  /// Lock screens (unlock, create, recovery kit) are a centred column this
  /// wide.
  static const double lockWidth = 560;

  /// Settings: the panes' column, and each icon tab along the top.
  static const double settingsWidth = 636;
  static const double settingsTabWidth = 64;

  /// Sheets: the right-aligned label column, and the gap after it.
  static const double formLabelWidth = 120;
  static const double formLabelGap = 8;
  static const double formRowGap = 10;

  /// macOS form rows: a 22 pt control plus the focus-ring room macos_ui
  /// keeps around a text field. Rows this tall sit flush, 31 pt apart, as
  /// in the frames.
  static const double formRowHeight = 36;

  /// Below a form's in-between lines (a strength meter, a field message) on
  /// macOS, where rows have no gap of their own.
  static const double formNoteGap = 6;

  /// Floating panels (quick open): corner radius, width, and how far below
  /// the top of the window they sit.
  static const double panelRadius = 12;

  /// A toast: the macOS banner's width, and the Linux snackbar's range.
  static const double toastWidth = 340;
  static const double toastMinWidth = 280;
  static const double toastMaxWidth = 520;

  /// How far a toast sits from the window's right edge (the macOS banner)
  /// and above the status bar (the banner and the Linux snackbar).
  static const double toastInset = 12;
  static const double panelWidth = 600;
  static const double panelTop = 120;

  /// A form field for a short value (a bucket name), where a full-width
  /// one would look like it wants more.
  static const double narrowFieldWidth = 220;

  /// A note's Markdown preview (item and app editors) and an app's notes
  /// over the item table: at least about three lines, and scrolling past
  /// the maximum.
  static const double notesPreviewMinHeight = 64;
  static const double notesPreviewMaxHeight = 200;

  /// Body text and secondary text.
  static const double bodySize = 13;
  static const double secondarySize = 11;

  /// Table cells beside the name column, and row descriptions (Settings).
  static const double cellSize = 12;

  /// Secondary text and mono values at the larger size: the inspector's
  /// path, field names and values.
  static const double labelSize = 12;
}
