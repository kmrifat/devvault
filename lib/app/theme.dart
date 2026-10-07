import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

/// DevVault's bc_ui themes. Dark is the designed look; light follows the
/// same tokens, and the app picks between them with [ThemeMode.system].
abstract final class AppTheme {
  /// bc_ui's own accent, written out so a brand change is one edit here.
  static const Color accent = Color(0xFF0485F7);

  static const BCThemeOverrides _overrides = BCThemeOverrides(accent: accent);

  static ThemeData light() => BCTheme.light(overrides: _overrides);

  static ThemeData dark() {
    final theme = BCTheme.dark(overrides: _overrides);
    final bc = theme.extension<BCThemeExtension>()!;

    // In dark, a field has no resting border and `field` == `surface`, so a
    // field on a card is invisible. A zero-blur, 1px-spread shadow traces the
    // field's continuous corners like a hairline border would, and reaches
    // every field-shaped component (same fix as the GoGarage app).
    return theme.copyWith(
      extensions: [
        bc.copyWith(
          fieldShadow: BCShadowSet(
            shadows: [BoxShadow(color: bc.separator, spreadRadius: 1)],
          ),
        ),
      ],
    );
  }
}

/// Text styles DevVault adds on top of bc_ui's Inter scale.
abstract final class AppText {
  static const String monoFamily = 'JetBrains Mono';

  /// Monospace style for key IDs, team IDs, fingerprints, filenames and
  /// recovery keys, where telling `0`/`O` and `1`/`l` apart matters.
  ///
  /// Defaults to the body-small size in the theme's foreground colour.
  /// Tabular figures keep fingerprint columns aligned.
  static TextStyle mono(
    BuildContext context, {
    double fontSize = BCTypography.sizeSm,
    FontWeight fontWeight = BCTypography.regular,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: fontSize,
      height: 20 / 14,
      fontWeight: fontWeight,
      color: color ?? context.bcTheme.foreground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
