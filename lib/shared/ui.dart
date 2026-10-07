/// Everything a screen needs to build UI: bc_ui, the Lucide icons, the
/// DevVault theme helpers and the shared widgets. Screens import this one
/// file instead of the packages directly.
library;

export 'package:bc_ui/bc_ui.dart';
export 'package:flutter/material.dart';
export 'package:lucide_icons_flutter/lucide_icons.dart';

export '../app/theme.dart' show AppColors, AppColorsContext, AppText, AppTheme;
export 'widgets/confirm_dialog.dart';
export 'widgets/mono_text.dart';
export 'widgets/password_field.dart';
export 'widgets/provenance_label.dart';
export 'widgets/secret_row.dart';
export 'widgets/type_icon_tile.dart';
