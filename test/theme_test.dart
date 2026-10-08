import 'dart:math';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/theme.dart';
import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  BCThemeExtension tokens(ThemeData theme) =>
      theme.extension<BCThemeExtension>()!;

  test('dark uses the DevVault accent, light its AA-contrast shade', () {
    expect(tokens(AppTheme.dark()).accent, AppTheme.accent);
    final light = tokens(AppTheme.light());
    expect(light.accent, AppTheme.accentLight);
    // WCAG AA (4.5:1) for accent text on the light background and on its
    // own soft tint, and for white labels on accent buttons.
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    final soft = Color.alphaBlend(light.accentSoft, light.background);
    expect(contrast(light.accent, light.background), greaterThanOrEqualTo(4.5));
    expect(contrast(light.accent, soft), greaterThanOrEqualTo(4.5));
    expect(
      contrast(light.accentForeground, light.accent),
      greaterThanOrEqualTo(4.5),
    );
    expect(contrast(light.muted, light.background), greaterThanOrEqualTo(4.5));
  });

  test('dark fields get a hairline ring in the separator colour', () {
    final bc = tokens(AppTheme.dark());
    final shadow = bc.fieldShadow.shadows.single;
    expect(shadow.color, bc.separator);
    expect(shadow.spreadRadius, 1);
    expect(shadow.blurRadius, 0);
  });

  test('light fields keep bc_ui\'s own field shadow', () {
    final light = AppTheme.light();
    final stock = BCTheme.light(
      overrides: const BCThemeOverrides(accent: AppTheme.accent),
    );
    expect(
      tokens(light).fieldShadow.shadows,
      tokens(stock).fieldShadow.shadows,
    );
  });

  testWidgets('mono style uses JetBrains Mono with tabular figures', (
    tester,
  ) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            style = AppText.mono(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(style.fontFamily, AppText.monoFamily);
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(style.color, tokens(AppTheme.dark()).foreground);
  });

  testWidgets('app follows the system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final dir = await tester.runAsync(testSupportDir);
    await tester.pumpWidget(testApp(location: Routes.unlock, supportDir: dir!));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Create a master password'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
