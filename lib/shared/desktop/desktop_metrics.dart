/// Sizes from docs/design/desktop.md (macOS points; Windows and Linux use
/// the same layout). Screens use these instead of literals.
abstract final class DesktopMetrics {
  /// Text fields, pop-ups, combo boxes and push buttons.
  static const double controlHeight = 22;

  /// Corner radius of fields and the token field.
  static const double fieldRadius = 5;

  /// Corner radius of a menu, and of the highlighted row inside it.
  static const double menuRadius = 6;
  static const double menuItemRadius = 4;

  /// Corner radius of a tag pill.
  static const double tokenRadius = 9;

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

  /// Sheets: the right-aligned label column, and the gap after it.
  static const double formLabelWidth = 120;
  static const double formLabelGap = 8;
  static const double formRowGap = 10;

  /// Floating panels (quick open): corner radius, width, and how far below
  /// the top of the window they sit.
  static const double panelRadius = 12;
  static const double panelWidth = 600;
  static const double panelTop = 120;

  /// Body text and secondary text.
  static const double bodySize = 13;
  static const double secondarySize = 11;

  /// Secondary text and mono values at the larger size: the inspector's
  /// path, field names and values.
  static const double labelSize = 12;
}
