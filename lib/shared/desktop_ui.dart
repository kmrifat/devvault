/// Everything a desktop screen needs to build UI: the desktop layer
/// (ADR-0005, docs/design/desktop.md), which draws each control with the
/// running OS's own kit, plus Flutter's widgets and the DevVault theme
/// helpers. Desktop screens import this file instead of the kits directly;
/// phone screens import `ui.dart`.
library;

export 'package:flutter/widgets.dart';

export '../app/theme.dart' show AppText;
export 'desktop/desktop_button.dart';
export 'desktop/desktop_colors.dart';
export 'desktop/desktop_combo_box.dart';
export 'desktop/desktop_form.dart';
export 'desktop/desktop_icon_button.dart';
export 'desktop/desktop_metrics.dart';
export 'desktop/desktop_popup.dart';
export 'desktop/desktop_search_field.dart';
export 'desktop/desktop_symbols.dart';
export 'desktop/desktop_text_field.dart';
export 'desktop/desktop_theme.dart';
export 'desktop/desktop_toggles.dart';
export 'desktop/desktop_token_field.dart';
export 'desktop/desktop_window.dart';
