@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  /// Selects Kitchenly › Android › Production › Upload keystore, like the
  /// D03 frame.
  Future<void> selectProduction(WidgetTester tester) async {
    Finder inSidebar(String text) => find.descendant(
      of: find.byType(VaultSidebar),
      matching: find.text(text),
    );
    await tester.tap(inSidebar('Android'));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar('Production'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(VaultListPane),
        matching: find.text('Upload keystore'),
      ),
    );
  }

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
