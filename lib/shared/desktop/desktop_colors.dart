import 'package:flutter/widgets.dart';
import 'package:yaru/yaru.dart' as yaru;

import 'desktop_theme.dart' show DesktopKit;

/// DevVault's desktop colour tokens (docs/design/desktop.md › Colours).
///
/// The kits draw their own controls in their own colours; these are the
/// surfaces and status colours DevVault paints itself: window regions,
/// zebra rows, group boxes, badges and text. Screens read them from
/// `context.desktopColors` and never hard-code a colour.
///
/// macOS and Windows share one palette, with the blue accent. Linux follows
/// Ubuntu: Yaru's orange in place of the blue ([of]).
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
    required this.selectedSegment,
    required this.text,
    required this.secondaryText,
    required this.tertiaryText,
    required this.accent,
    required this.onAccent,
    required this.accentIcon,
    required this.selection,
    required this.onSelection,
    required this.success,
    required this.warning,
    required this.warningBadge,
    required this.onWarningBadge,
    required this.danger,
    required this.dangerButton,
    required this.onDangerButton,
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

  /// The chosen segment of a segmented control, on a [toolbarField] track.
  final Color selectedSegment;

  final Color text;
  final Color secondaryText;
  final Color tertiaryText;

  /// The accent: focus and drop rings, the app mark, washes (token pills),
  /// and the symbol on it.
  final Color accent;
  final Color onAccent;

  /// Accent-coloured icons and links, lighter in dark mode.
  final Color accentIcon;

  /// A selected or highlighted row (sidebar, item table, quick open) and
  /// its text. The accent itself on macOS and Windows; on Linux a darker
  /// shade of it, since white on Ubuntu's orange isn't AA.
  final Color selection;
  final Color onSelection;

  final Color success;

  final Color warning;
  final Color warningBadge;
  final Color onWarningBadge;

  final Color danger;

  /// A filled destructive button (Delete on Windows and Linux) and its
  /// label: a deeper red than [danger] in dark mode, so white text is AA.
  final Color dangerButton;
  final Color onDangerButton;

  /// A band or badge tinted for danger (an expired badge, the Expiry
  /// table's Expired group), and the text on it.
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
    selectedSegment: Color(0xFFFFFFFF),
    text: Color(0xFF1D1D1F),
    // The design's #6E6E73 is 4.25:1 on the sidebar; this is the nearest
    // shade that reaches WCAG AA (4.5:1) there.
    secondaryText: Color(0xFF66666B),
    tertiaryText: Color(0xFF8E8E93),
    accent: Color(0xFF0A64D8),
    onAccent: Color(0xFFFFFFFF),
    accentIcon: Color(0xFF0A64D8),
    selection: Color(0xFF0A64D8),
    onSelection: Color(0xFFFFFFFF),
    success: Color(0xFF1F9D55),
    warning: Color(0xFFC77700),
    warningBadge: Color(0xFFFFF1D6),
    onWarningBadge: Color(0xFFA15C00),
    danger: Color(0xFFD70015),
    dangerButton: Color(0xFFD70015),
    onDangerButton: Color(0xFFFFFFFF),
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
    selectedSegment: Color(0xFF5A5A5E),
    text: Color(0xFFF5F5F7),
    secondaryText: Color(0xFF98989D),
    tertiaryText: Color(0xFF8D8D93),
    accent: Color(0xFF0A64D8),
    onAccent: Color(0xFFFFFFFF),
    accentIcon: Color(0xFF4D9BFF),
    selection: Color(0xFF0A64D8),
    onSelection: Color(0xFFFFFFFF),
    success: Color(0xFF32D74B),
    warning: Color(0xFFFFB340),
    warningBadge: Color(0xFF3D2E12),
    onWarningBadge: Color(0xFFFFB340),
    danger: Color(0xFFFF6961),
    // White on #FF6961 is 2.8:1; the light red carries it at 5.4:1.
    dangerButton: Color(0xFFD70015),
    onDangerButton: Color(0xFFFFFFFF),
    dangerBadge: Color(0xFF3D1A1A),
    onDangerBadge: Color(0xFFFF6961),
    conflict: Color(0xFFD49BF5),
    conflictBadge: Color(0xFF3A2846),
    onConflictBadge: Color(0xFFD49BF5),
    shadow: Color(0x80000000),
  );

  /// Linux (Yaru): Ubuntu's orange. White on it is only 3.6:1, so it
  /// carries symbols and rings, not text. Selected rows, links and icons
  /// take the darker orange of Yaru's dark theme (white on it, and it on
  /// white, 6.7:1).
  static final yaruLight = light._withAccent(
    accent: yaru.YaruColors.orange,
    accentIcon: yaru.yaruDark.colorScheme.secondary,
    selection: yaru.yaruDark.colorScheme.secondary,
    onSelection: light.onAccent,
  );

  /// Linux in dark mode: as [yaruLight], with the lighter orange of Yaru's
  /// light theme for icons and links.
  static final yaruDark = dark._withAccent(
    accent: yaru.YaruColors.orange,
    accentIcon: yaru.yaruLight.colorScheme.secondary,
    selection: yaru.yaruDark.colorScheme.secondary,
    onSelection: dark.onAccent,
  );

  /// The palette for [kit] in [brightness].
  static DesktopColors of(
    Brightness brightness, [
    DesktopKit kit = DesktopKit.macos,
  ]) => switch ((kit, brightness)) {
    (DesktopKit.yaru, Brightness.light) => yaruLight,
    (DesktopKit.yaru, Brightness.dark) => yaruDark,
    (_, Brightness.light) => light,
    (_, Brightness.dark) => dark,
  };

  DesktopColors _withAccent({
    required Color accent,
    required Color accentIcon,
    required Color selection,
    required Color onSelection,
  }) => DesktopColors(
    window: window,
    lockWindow: lockWindow,
    sidebar: sidebar,
    toolbar: toolbar,
    bar: bar,
    separator: separator,
    innerSeparator: innerSeparator,
    zebra: zebra,
    groupBox: groupBox,
    groupBoxInner: groupBoxInner,
    groupBoxStroke: groupBoxStroke,
    menu: menu,
    field: field,
    fieldStroke: fieldStroke,
    toolbarField: toolbarField,
    selectedSegment: selectedSegment,
    text: text,
    secondaryText: secondaryText,
    tertiaryText: tertiaryText,
    accent: accent,
    onAccent: onAccent,
    accentIcon: accentIcon,
    selection: selection,
    onSelection: onSelection,
    success: success,
    warning: warning,
    warningBadge: warningBadge,
    onWarningBadge: onWarningBadge,
    danger: danger,
    dangerButton: dangerButton,
    onDangerButton: onDangerButton,
    dangerBadge: dangerBadge,
    onDangerBadge: onDangerBadge,
    conflict: conflict,
    conflictBadge: conflictBadge,
    onConflictBadge: onConflictBadge,
    shadow: shadow,
  );
}
