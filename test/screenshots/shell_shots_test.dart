@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/desktop/desktop_toast.dart';
import 'package:flutter/material.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  /// Selects Kitchenly, Android, Production, then Upload keystore, like the
  /// N03 frame.
  Future<void> selectProduction(WidgetTester tester) async {
    Finder inSidebar(String text) => find.descendant(
      of: find.byType(VaultSidebar),
      matching: find.text(text),
    );
    await tester.tap(inSidebar('Kitchenly'));
    await tester.pumpAndSettle();
    for (final (filter, choice) in [
      ('platform-filter', 'Android'),
      ('environment-filter', 'Production'),
    ]) {
      await tester.tap(find.byKey(ValueKey(filter)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.descendant(
        of: find.byType(VaultListPane),
        matching: find.text('Upload keystore'),
      ),
    );
  }

  shot('N03-vault', Routes.vault(), sample: true, interact: selectProduction);
  for (final brightness in Brightness.values) {
    shot(
      brightness == Brightness.dark ? 'N03-toast' : 'N03-toast-light',
      Routes.vault(),
      sample: true,
      brightness: brightness,
      interact: (tester) async {
        await selectProduction(tester);
        await tester.pumpAndSettle();
        showDesktopToast(
          tester.element(find.byType(VaultSidebar)),
          title: '“Upload keystore” moved to Kitchenly',
          kind: DesktopToastKind.success,
          actionLabel: 'Undo',
          onAction: () {},
          // Stays up for the shot, with no timer left running.
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
      },
    );
  }
  shot(
    'N03-vault-light',
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

  /// Ledgerly as a backend service for a client, with a domain and a
  /// repository; Kitchenly stays personal. Then Ledgerly is selected.
  Future<void> addOrganization(WidgetTester tester) async {
    final session = appContainer(tester).read(vaultSessionProvider) as Unlocked;
    final ledgerly = session.index.apps.values.firstWhere(
      (a) => a.name == 'Ledgerly',
    );
    await tester.runAsync(
      () => appContainer(tester)
          .read(vaultSessionProvider.notifier)
          .saveApp(
            ledgerly.copyWith(
              organization: 'Acme Corp',
              kindName: AppKind.backend.wireName,
              identifiers: [
                AppIdentifier.of(IdentifierKind.domain, 'api.ledgerly.example'),
                AppIdentifier.of(
                  IdentifierKind.repository,
                  'github.com/acme/ledgerly',
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(VaultSidebar),
        matching: find.text('Ledgerly'),
      ),
    );
    await tester.pumpAndSettle();
  }

  shot(
    'N03-vault-organizations',
    Routes.vault(),
    sample: true,
    interact: addOrganization,
  );
  shot(
    'N03-app-editor',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      await addOrganization(tester);
      await tester.tap(find.text('Edit app…'));
    },
  );
  shot(
    'B2-vault-organizations',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      final session =
          appContainer(tester).read(vaultSessionProvider) as Unlocked;
      final ledgerly = session.index.apps.values.firstWhere(
        (a) => a.name == 'Ledgerly',
      );
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveApp(ledgerly.copyWith(organization: 'Acme Corp')),
      );
    },
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
