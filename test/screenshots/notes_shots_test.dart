@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_overrides.dart';
import 'harness.dart';

/// Markdown notes (SPEC §6.6): an item's in the inspector and on the phone,
/// an app's over its items, and the editors' Preview.
void main() {
  setUpAll(loadAppFonts);

  const itemNote =
      '## Rotation\n'
      '\n'
      'Upload key for **Play App Signing**. Google holds the app signing '
      'key; this one only *uploads*.\n'
      '\n'
      '1. Ask Play support to reset the upload key.\n'
      '2. Run `./gradlew signingReport` and send the new SHA-1.\n'
      '\n'
      '> Never commit the keystore.\n'
      '\n'
      'Runbook: [Play Console help](https://support.google.com/googleplay)\n'
      '![screenshot](https://example.com/console.png)';

  const appNote =
      '### Ledgerly backend\n'
      '\n'
      'Deploys from `main` through **GitHub Actions**. Staging resets every '
      'night.\n'
      '\n'
      '- Owner: platform team\n'
      '- Dashboard: [status](https://status.ledgerly.example)\n'
      '\n'
      '```sh\n'
      'make deploy ENV=production\n'
      '```';

  Unlocked session(WidgetTester tester) =>
      appContainer(tester).read(vaultSessionProvider) as Unlocked;

  Future<void> noteOnKeystore(WidgetTester tester) async {
    final keystore = session(tester).index.all
        .firstWhere((i) => i.title == 'Upload keystore');
    await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .saveItem(keystore.copyWith(notes: itemNote)),
    );
    await tester.pumpAndSettle();
  }

  Future<String> noteOnLedgerly(WidgetTester tester) async {
    final ledgerly = session(tester).index.apps.values
        .firstWhere((a) => a.name == 'Ledgerly');
    await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .saveApp(ledgerly.copyWith(notes: appNote)),
    );
    await tester.pumpAndSettle();
    return ledgerly.id;
  }

  /// Kitchenly › Android › Production › Upload keystore, with a note.
  Future<void> selectKeystore(WidgetTester tester) async {
    await noteOnKeystore(tester);
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
    await tester.pumpAndSettle();
  }

  Future<void> openLedgerly(WidgetTester tester) async {
    await noteOnLedgerly(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(VaultSidebar),
        matching: find.text('Ledgerly'),
      ),
    );
    await tester.pumpAndSettle();
  }

  shot(
    'N03-item-markdown',
    Routes.vault(),
    sample: true,
    interact: selectKeystore,
  );
  shot(
    'N03-item-markdown-light',
    Routes.vault(),
    sample: true,
    interact: selectKeystore,
    brightness: Brightness.light,
  );
  shot(
    'N03e-item-editor-notes-preview',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      await selectKeystore(tester);
      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview'));
    },
  );
  shot(
    'N03-app-notes',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      await openLedgerly(tester);
      await tester.tap(find.bySemanticsLabel('Show notes'));
    },
  );
  shot(
    'N03-app-notes-folded',
    Routes.vault(),
    sample: true,
    interact: openLedgerly,
    brightness: Brightness.light,
  );
  shot(
    'N03-app-editor-notes',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      await openLedgerly(tester);
      await tester.tap(find.text('Edit app…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview'));
    },
  );
  shot(
    'B3-item-markdown',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      await noteOnKeystore(tester);
      final keystore = session(tester).index.all
          .firstWhere((i) => i.title == 'Upload keystore');
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)))
          .push(Routes.item(keystore.id));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Never commit the keystore.'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
    },
  );
  shot(
    'B2-vault-app-notes',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      final id = await noteOnLedgerly(tester);
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)))
          .go(Routes.vault(app: id));
    },
  );
}
