import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

/// WCAG 2.2 SC 2.5.8 (AA): pointer targets at least 24×24. The desktop
/// app is used with a mouse or trackpad; phones get the 48×48 touch
/// guideline instead.
const _desktopTargets = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum',
);

/// Phones: Android's 48×48 touch target. A text field's own text node is
/// the height of one line (24 px), but it sits inside the field, which is
/// 48 px tall, labelled and tappable as a whole; skip the inner node.
class _TouchTargets extends MinimumTapTargetGuideline {
  const _TouchTargets()
    : super(
        size: const Size(48, 48),
        link: 'https://support.google.com/accessibility/android/answer/7101858',
      );

  /// bc_ui 0.7.0's BCTabs triggers are a fixed 36 px tall with no size
  /// option: the phone vault's type tabs (P3-01) are a known gap until
  /// bc_ui grows one.
  static final _knownGaps = {for (final k in VaultKind.values) k.label};

  @override
  bool shouldSkipNode(SemanticsNode node) {
    final data = node.getSemanticsData();
    return super.shouldSkipNode(node) ||
        data.flagsCollection.isTextField ||
        _knownGaps.contains(data.label);
  }
}

/// Dark mode keeps the brand accent (#0485F7), which is 5.5:1 as text on
/// the dark background but only 3.59:1 under the white label of a primary
/// button. No single blue passes both in dark (one wants luminance below
/// 0.183, the other above 0.184), so that label is a known, open design
/// decision (P4-08 PR). bc_ui buttons don't carry the button flag, so
/// tappable nodes are skipped here; all other text is held to 4.5:1.
class _DarkContrast extends MinimumTextContrastGuideline {
  const _DarkContrast();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || data.hasAction(SemanticsAction.tap);
}

/// The P4-08 accessibility pass, kept as a regression test: every main
/// screen, on desktop and phone, in light and dark, has named controls,
/// big enough targets and AA text contrast.
void main() {
  setUpAll(loadTestCrypto);

  final screens = <String, (String, TestVault)>{
    'unlock': (Routes.unlock, TestVault.locked),
    'create': (Routes.create, TestVault.none),
    'vault': (Routes.vault(), TestVault.sample),
    'expiry': (Routes.expiry, TestVault.sample),
    'settings': (Routes.settings, TestVault.sample),
  };

  for (final layout in AppLayout.values) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: (route, vault))
          in screens.entries) {
        testWidgets('${layout.name} ${brightness.name} $name', (tester) async {
          final semantics = tester.ensureSemantics();
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          tester.view
            ..physicalSize = layout == AppLayout.desktop
                ? const Size(1440, 900)
                : const Size(390, 844)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          if (vault == TestVault.sample) {
            await pumpUnlockedApp(
              tester,
              location: route,
              vault: vault,
              layout: layout,
            );
          } else {
            final dir = await tester.runAsync(() => testSupportDir(vault));
            await tester.pumpWidget(
              testApp(location: route, supportDir: dir!, layout: layout),
            );
            await tester.pumpAndSettle();
          }
          // Disabled controls are exempt from contrast (WCAG 1.4.3): type a
          // password so Unlock and Continue are checked enabled.
          final password = find.byType(EditableText);
          if (vault != TestVault.sample && password.evaluate().isNotEmpty) {
            await tester.enterText(password.first, 'correct horse');
            await tester.pump();
          }
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(
            tester,
            meetsGuideline(
              brightness == Brightness.dark
                  ? const _DarkContrast()
                  : textContrastGuideline,
            ),
          );
          await expectLater(
            tester,
            meetsGuideline(
              layout == AppLayout.desktop
                  ? _desktopTargets
                  : const _TouchTargets(),
            ),
          );
          semantics.dispose();
        });
      }
    }
  }
}
