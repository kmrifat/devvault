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

  test('both themes use the DevVault accent', () {
    expect(tokens(AppTheme.light()).accent, AppTheme.accent);
    expect(tokens(AppTheme.dark()).accent, AppTheme.accent);
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
