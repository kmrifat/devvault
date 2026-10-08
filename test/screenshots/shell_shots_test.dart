@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_overrides.dart';
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
  Future<void> editKeystore(WidgetTester tester) async {
    await selectProduction(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Edit'));
  }

  shot(
    'N03e-item-editor',
    Routes.vault(),
    sample: true,
    interact: editKeystore,
  );
  shot(
    'N03e-item-editor-light',
    Routes.vault(),
    sample: true,
    interact: editKeystore,
    brightness: Brightness.light,
  );
  shot('B2-vault', Routes.vault(), device: ShotDevice.mobile, sample: true);
  shot(
    'B2-vault-light',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    brightness: Brightness.light,
  );

  shot(
    'B3-item',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      final session =
          appContainer(tester).read(vaultSessionProvider) as Unlocked;
      final keystore = session.index.all.firstWhere(
        (i) => i.title == 'Upload keystore',
      );
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)))
          .push(Routes.item(keystore.id));
    },
  );
}
