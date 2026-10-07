@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  /// Selects Kitchenly › Android › Production, like the D03 frame.
  Future<void> selectProduction(WidgetTester tester) async {
    Finder inSidebar(String text) => find.descendant(
      of: find.byType(VaultSidebar),
      matching: find.text(text),
    );
    await tester.tap(inSidebar('Android'));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar('Production'));
  }

  // The sidebar is real (P1-06); the list and detail panes are still
  // placeholders until P1-07 and P1-08.
  shot(
    'D03-vault-shell',
    Routes.vault(),
    sample: true,
    interact: selectProduction,
  );
  shot(
    'D03-vault-shell-light',
    Routes.vault(),
    sample: true,
    interact: selectProduction,
    brightness: Brightness.light,
  );
  shot('B2-vault-shell', Routes.vault(), device: ShotDevice.mobile);
  shot(
    'B2-vault-shell-light',
    Routes.vault(),
    device: ShotDevice.mobile,
    brightness: Brightness.light,
  );
}
