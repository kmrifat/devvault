import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/recovery_kit_card.dart';
import 'package:devvault/features/settings/new_recovery_kit_dialog.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.settingsSecurity,
      layout: AppLayout.desktop,
    );
  }

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'never finished');
    await tester.pumpAndSettle();
  }

  Finder password() => find.descendant(
    of: find.byType(NewRecoveryKitDialog),
    matching: find.byType(EditableText),
  );

  Finder button(String label) => find.descendant(
    of: find.byType(NewRecoveryKitDialog),
    matching: find.widgetWithText(DesktopButton, label),
  );

  testWidgets('asks for the password, then shows a new key once', (
    tester,
  ) async {
    await open(tester);
    final oldKey = lastTestRecoveryKey!;
    await tester.tap(find.text('New Kit…'));
    await tester.pumpAndSettle();
    expect(find.text('New recovery kit'), findsOneWidget);

    // Nothing typed.
    await tester.tap(button('Make New Key'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your master password'), findsOneWidget);

    // Wrong password: nothing changes.
    await tester.enterText(password(), 'not my password');
    await tester.pump();
    await tester.tap(button('Make New Key'));
    await settle(
      tester,
      () => find.text("That isn't your master password").evaluate().isNotEmpty,
    );
    expect(find.byType(RecoveryKitCard), findsNothing);

    await tester.enterText(password(), testPassword);
    await tester.pump();
    await tester.tap(button('Make New Key'));
    await settle(
      tester,
      () => find.byType(RecoveryKitCard).evaluate().isNotEmpty,
    );
    final newKey = tester
        .widget<RecoveryKitCard>(find.byType(RecoveryKitCard))
        .kit
        .recoveryKey;
    expect(newKey, isNot(oldKey));
    expect(newKey.split('-'), hasLength(14));

    // Done waits for the confirmation.
    expect(tester.widget<DesktopButton>(button('Done')).onPressed, isNull);
    await tester.tap(find.text("I've saved the new key"));
    await tester.pump();
    await tester.tap(button('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(NewRecoveryKitDialog), findsNothing);

    // On disk: the old key no longer opens the vault, the new one does.
    final container = appContainer(tester);
    final store = findVault(
      Directory('${container.read(appSupportDirProvider).path}/vaults'),
    )!;
    await tester.runAsync(() async {
      final crypto = container.read(cryptoProvider);
      final old = RecoveryKey.parse(crypto, oldKey);
      await expectLater(
        Vault.unlockWithRecovery(
          crypto: crypto,
          store: store,
          recoveryKey: old,
          deviceId: testDeviceId,
          now: () => testNow,
        ),
        throwsA(isA<WrongRecoveryKey>()),
      );
      final fresh = RecoveryKey.parse(crypto, newKey);
      final vault = await Vault.unlockWithRecovery(
        crypto: crypto,
        store: store,
        recoveryKey: fresh,
        deviceId: testDeviceId,
        now: () => testNow,
      );
      vault.lock();
    });
    // The master password still works too.
    expect(
      await tester.runAsync(
        () => container
            .read(vaultSessionProvider.notifier)
            .checkPassword(testPassword),
      ),
      isTrue,
    );
  });

  testWidgets('Cancel changes nothing', (tester) async {
    await open(tester);
    final store = findVault(
      Directory(
        '${appContainer(tester).read(appSupportDirProvider).path}/vaults',
      ),
    )!;
    final before = File('${store.root.path}/vault.json').readAsStringSync();
    await tester.tap(find.text('New Kit…'));
    await tester.pumpAndSettle();
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(NewRecoveryKitDialog), findsNothing);
    expect(File('${store.root.path}/vault.json').readAsStringSync(), before);
  });
}
