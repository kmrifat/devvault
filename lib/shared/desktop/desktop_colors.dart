import 'package:flutter/widgets.dart';

/// DevVault's desktop colour tokens (docs/design/desktop.md › Colours).
///
/// The kits draw their own controls in their own colours; these are the
/// surfaces and status colours DevVault paints itself: window regions,
/// zebra rows, group boxes, badges and text. Screens read them from
/// `context.desktopColors` and never hard-code a colour.
@immutable
class DesktopColors {
  const DesktopColors({
    required this.window,
    required this.lockWindow,
    required this.sidebar,
    required this.toolbar,
    required this.bar,
    required this.separator,
    required this.innerSeparator,
    required this.zebra,
    required this.groupBox,
    required this.groupBoxInner,
    required this.groupBoxStroke,
    required this.menu,
    required this.field,
    required this.fieldStroke,
    required this.toolbarField,
    required this.text,
    required this.secondaryText,
    required this.tertiaryText,
    required this.accent,
    required this.onAccent,
    required this.accentIcon,
    required this.success,
    required this.warning,
    required this.warningBadge,
    required this.onWarningBadge,
    required this.danger,
    required this.dangerBadge,
    required this.onDangerBadge,
    required this.conflict,
    required this.conflictBadge,
    required this.onConflictBadge,
    required this.shadow,
  });

  /// Window and content background.
  final Color window;

  /// The lock screens' compact window (unlock, create, recovery kit).
  final Color lockWindow;

  /// Source-list sidebar (the vibrancy tint on macOS).
  final Color sidebar;

  /// Unified toolbar.
  final Color toolbar;

  /// Status bar and table header.
  final Color bar;

  /// Line between panes.
  final Color separator;

  /// Line inside a pane: rows, group boxes, form sections.
  final Color innerSeparator;

  /// Every other table row.
  final Color zebra;

  /// Group box fill, and the box nested inside one (fields table, file box).
  final Color groupBox;
  final Color groupBoxInner;
  final Color groupBoxStroke;

  /// Menus DevVault draws itself (the macOS combo box's suggestions); their
  /// border is [groupBoxStroke].
  final Color menu;

  /// Text fields, combo boxes and the token field.
  final Color field;
  final Color fieldStroke;

  /// The toolbar's search field, which sits on the toolbar without a border.
  final Color toolbarField;

  final Color text;
  final Color secondaryText;
  final Color tertiaryText;

  /// Selection fill (selected table row, token pills) and its text.
  final Color accent;
  final Color onAccent;

  /// Accent-coloured icons and links, lighter in dark mode.
  final Color accentIcon;

  final Color success;

  final Color warning;
  final Color warningBadge;
  final Color onWarningBadge;

  final Color danger;
  final Color dangerBadge;
  final Color onDangerBadge;

  final Color conflict;
  final Color conflictBadge;
  final Color onConflictBadge;

  /// The shadow under floating panels (quick open).
  final Color shadow;

  static const light = DesktopColors(
    window: Color(0xFFFFFFFF),
    lockWindow: Color(0xFFF6F6F8),
    sidebar: Color(0xFFECEAEF),
    toolbar: Color(0xFFFAFAFA),
    bar: Color(0xFFFAFAFA),
    separator: Color(0xFFE3E3E6),
    innerSeparator: Color(0xFFE3E3E6),
    zebra: Color(0xFFF5F5F7),
    groupBox: Color(0xFFF6F6F8),
    groupBoxInner: Color(0xFFFFFFFF),
    groupBoxStroke: Color(0xFFE3E3E6),
    menu: Color(0xFFF6F6F8),
    field: Color(0xFFFFFFFF),
    fieldStroke: Color(0xFFD1D1D6),
    toolbarField: Color(0xFFEBEBED),
    text: Color(0xFF1D1D1F),
    // The design's #6E6E73 is 4.25:1 on the sidebar; this is the nearest
    // shade that reaches WCAG AA (4.5:1) there.
    secondaryText: Color(0xFF66666B),
    tertiaryText: Color(0xFF8E8E93),
    accent: Color(0xFF0A64D8),
    onAccent: Color(0xFFFFFFFF),
    accentIcon: Color(0xFF0A64D8),
    success: Color(0xFF1F9D55),
    warning: Color(0xFFC77700),
    warningBadge: Color(0xFFFFF1D6),
    onWarningBadge: Color(0xFFA15C00),
    danger: Color(0xFFD70015),
    dangerBadge: Color(0xFFFDE8EA),
    onDangerBadge: Color(0xFFD70015),
    conflict: Color(0xFF8944AB),
    conflictBadge: Color(0xFFF1E4F8),
    onConflictBadge: Color(0xFF8944AB),
    shadow: Color(0x33000000),
  );

  static const dark = DesktopColors(
    window: Color(0xFF1E1E1E),
    lockWindow: Color(0xFF1E1E1E),
    sidebar: Color(0xFF29272E),
    toolbar: Color(0xFF2B2B2D),
    bar: Color(0xFF252527),
    separator: Color(0xFF000000),
    innerSeparator: Color(0xFF3A3A3C),
    zebra: Color(0xFF242426),
    groupBox: Color(0xFF2A2A2C),
    groupBoxInner: Color(0xFF252527),
    groupBoxStroke: Color(0xFF3A3A3C),
    menu: Color(0xFF2A2A2C),
    field: Color(0xFF1C1C1E),
    fieldStroke: Color(0xFF48484A),
    toolbarField: Color(0xFF3A3A3C),
    text: Color(0xFFF5F5F7),
    secondaryText: Color(0xFF98989D),
    tertiaryText: Color(0xFF8D8D93),
    accent: Color(0xFF0A64D8),
    onAccent: Color(0xFFFFFFFF),
    accentIcon: Color(0xFF4D9BFF),
    success: Color(0xFF32D74B),
    warning: Color(0xFFFFB340),
    warningBadge: Color(0xFF3D2E12),
    onWarningBadge: Color(0xFFFFB340),
    danger: Color(0xFFFF6961),
    dangerBadge: Color(0xFF3D1A1A),
    onDangerBadge: Color(0xFFFF6961),
    conflict: Color(0xFFD49BF5),
    conflictBadge: Color(0xFF3A2846),
    onConflictBadge: Color(0xFFD49BF5),
    shadow: Color(0x80000000),
  );

  static DesktopColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
