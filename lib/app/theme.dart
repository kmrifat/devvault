import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

/// DevVault's bc_ui themes. Dark is the designed look; light follows the
/// same tokens, and the app picks between them with [ThemeMode.system].
abstract final class AppTheme {
  /// bc_ui's own accent, written out so a brand change is one edit here.
  static const Color accent = Color(0xFF0485F7);

  /// The same blue, darkened just enough for WCAG AA (4.5:1) in light mode:
  /// as text on the light background, on its own soft tint (the selected
  /// sidebar row) and for white button labels on it. `accent` itself is
  /// 2.8–3.7:1 there (P4-08).
  static const Color accentLight = Color(0xFF035DB0);

  static const BCThemeOverrides _overrides = BCThemeOverrides(accent: accent);

  static ThemeData light() {
    final theme = BCTheme.light(
      overrides: const BCThemeOverrides(accent: accentLight),
    );
    final bc = theme.extension<BCThemeExtension>()!;
    // bc_ui 0.7.0's light muted and soft-status text sit just under 4.5:1
    // on its own backgrounds (muted 4.43, warning 3.61, danger 3.80). These
    // are the nearest shades of the same hues that pass.
    return theme.copyWith(
      extensions: [
        bc.copyWith(
          muted: const Color(0xFF686871),
          accentSoftForeground: const Color(0xFF0760B0),
          warningSoftForeground: const Color(0xFF885F27),
          dangerSoftForeground: const Color(0xFFB62E2F),
        ),
        AppColors.light,
      ],
    );
  }

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
        AppColors.dark,
      ],
    );
  }
}

/// Two hues bc_ui doesn't have, used only to tell item types apart
/// (provisioning profiles and OAuth clients). Status meaning (success,
/// warning, danger) always comes from bc_ui's own tokens.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.violet,
    required this.violetSoft,
    required this.teal,
    required this.tealSoft,
  });

  final Color violet;
  final Color violetSoft;
  final Color teal;
  final Color tealSoft;

  // Soft variants use the same 15% alpha as bc_ui's accentSoft and friends.
  static const light = AppColors(
    violet: Color(0xFF7C3AED),
    violetSoft: Color(0x267C3AED),
    teal: Color(0xFF0F8F86),
    tealSoft: Color(0x260F8F86),
  );

  static const dark = AppColors(
    violet: Color(0xFFC4A2FF),
    violetSoft: Color(0x26A47CF5),
    teal: Color(0xFF4FD1C5),
    tealSoft: Color(0x2638B2A8),
  );

  @override
  AppColors copyWith({
    Color? violet,
    Color? violetSoft,
    Color? teal,
    Color? tealSoft,
  }) => AppColors(
    violet: violet ?? this.violet,
    violetSoft: violetSoft ?? this.violetSoft,
    teal: teal ?? this.teal,
    tealSoft: tealSoft ?? this.tealSoft,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      violet: Color.lerp(violet, other.violet, t)!,
      violetSoft: Color.lerp(violetSoft, other.violetSoft, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      tealSoft: Color.lerp(tealSoft, other.tealSoft, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// DevVault's extra hues for the current theme.
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
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
