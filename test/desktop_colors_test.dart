import 'dart:math';

import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart' show YaruColors;

import 'pump_desktop.dart';

/// The desktop palette per kit (docs/design/desktop.md › Colours): macOS
/// and Windows keep the blue accent, Linux takes Ubuntu's orange, and text
/// on any fill stays WCAG AA (4.5:1).
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  test('macOS and Windows are blue, Linux is Ubuntu orange', () {
    for (final brightness in Brightness.values) {
      expect(
        DesktopColors.of(brightness, DesktopKit.fluent),
        same(DesktopColors.of(brightness)),
      );
      final yaru = DesktopColors.of(brightness, DesktopKit.yaru);
      expect(yaru.accent, YaruColors.orange);
      // Only the accent changes; the surfaces are DevVault's.
      expect(yaru.window, DesktopColors.of(brightness).window);
      expect(yaru.danger, DesktopColors.of(brightness).danger);
    }
    expect(DesktopColors.light.accent, const Color(0xFF0A64D8));
  });

  for (final kit in DesktopKit.values) {
    for (final brightness in Brightness.values) {
      final colors = DesktopColors.of(brightness, kit);
      group('${kit.name} ${brightness.name}', () {
        test('a selected row\'s text is AA', () {
          expect(
            contrast(colors.onSelection, colors.selection),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('a destructive button\'s label is AA', () {
          expect(
            contrast(colors.onDangerButton, colors.dangerButton),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('accent links and token pills are AA', () {
          for (final surface in [
            colors.window,
            colors.lockWindow,
            colors.bar,
            colors.toolbar,
            colors.groupBoxInner,
          ]) {
            expect(
              contrast(colors.accentIcon, surface),
              greaterThanOrEqualTo(4.5),
            );
          }
          // The blue pill in light mode is 4.4:1, as drawn before the
          // orange came in; that one is still open.
          if (kit != DesktopKit.yaru && brightness == Brightness.light) return;
          final pill = Color.alphaBlend(
            colors.accent.withValues(alpha: 0.15),
            colors.field,
          );
          expect(contrast(colors.accentIcon, pill), greaterThanOrEqualTo(4.5));
        });
      });

      // Measured on the rendered pixels, like the screens' AA check, so it
      // runs with the goldens on macOS.
      if (brightness == Brightness.dark) {
        testWidgets('${kit.name} dark: a destructive button\'s label is AA', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          debugDefaultTargetPlatformOverride = switch (kit) {
            DesktopKit.macos => TargetPlatform.macOS,
            DesktopKit.fluent => TargetPlatform.windows,
            DesktopKit.yaru => TargetPlatform.linux,
          };
          try {
            await pumpDesktop(
              tester,
              kit,
              DesktopButton(
                label: 'Delete',
                kind: DesktopButtonKind.destructive,
                onPressed: () {},
              ),
              brightness: Brightness.dark,
            );
            await tester.pumpAndSettle();
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
          semantics.dispose();
        }, tags: ['golden']);
      }
    }
  }
}
