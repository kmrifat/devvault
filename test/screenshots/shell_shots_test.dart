@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/desktop/desktop_toast.dart';
import 'package:devvault/shared/desktop/desktop_icon_button.dart';
import 'package:devvault/shared/desktop/desktop_text_field.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  for (final kit in otherKits) {
    for (final brightness in Brightness.values) {
      shot(
        'N03-vault-${kit.name}-${brightness.name}',
        Routes.vault(),
        sample: true,
        interact: selectProduction,
        brightness: brightness,
        kit: kit,
      );
    }
  }
  shot(
    'N03-explorer-focus',
    Routes.vault(),
    sample: true,
    brightness: Brightness.light,
    interact: (tester) async {
      // Kitchenly clicked, then the cursor moved two rows down by keyboard.
      await tester.tap(
        find.descendant(
          of: find.byType(VaultSidebar),
          matching: find.text('Kitchenly'),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
    },
  );
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
        // Hovered, so the shot shows its ×.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(find.textContaining('moved to')),
        );
        addTearDown(mouse.removePointer);
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

  /// The editor with a password shown and a long value typed: the dots
  /// have room between them, and a shown value wraps to its full length.
  Future<void> editWithLongValue(WidgetTester tester) async {
    await editKeystore(tester);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is DesktopIconButton && w.tooltip == 'Show value',
          )
          .first,
    );
    await tester.tap(find.text('Add Field'));
    await tester.pumpAndSettle();
    EditableText input(String placeholder) => tester.widget<EditableText>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is DesktopTextField && w.placeholder == placeholder,
              skipOffstage: false,
            ),
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          )
          .last,
    );
    input('Value').controller.text =
        'postgresql://limit_yes_user:AVNS_example@db-postgresql-fra1-0000'
        '.example.com:25060/limit_yes?sslmode=require';
    input('Name').controller.text = 'Database string';
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add Field'));
    await tester.pumpAndSettle();
  }

  shot(
    'N03e-item-editor-values-light',
    Routes.vault(),
    sample: true,
    interact: editWithLongValue,
    brightness: Brightness.light,
  );
  for (final kit in otherKits) {
    shot(
      'N03e-item-editor-${kit.name}-light',
      Routes.vault(),
      sample: true,
      interact: editKeystore,
      brightness: Brightness.light,
      kit: kit,
    );
  }

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
