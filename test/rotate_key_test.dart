import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/recovery_kit_card.dart';
import 'package:devvault/features/settings/new_recovery_kit_dialog.dart';
import 'package:devvault/shared/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

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

  VaultStore storeOf(WidgetTester tester) => findVault(
    Directory(
      '${appContainer(tester).read(appSupportDirProvider).path}/vaults',
    ),
  )!;

  Finder button(String label) => find.descendant(
    of: find.byType(NewRecoveryKitDialog),
    matching: find.widgetWithText(BCButton, label),
  );

  Finder password() => find.descendant(
    of: find.byType(PasswordField),
    matching: find.byType(EditableText),
  );

  testWidgets('Settings › Rotate: new key, same items, old recovery key dead', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.settings,
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
    final oldRecovery = lastTestRecoveryKey!;
    final before =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked);
    final oldVkId = before.vault.header.vkId;
    final titles = before.index.all.map((i) => i.title).toList();
    final files = before.index.all
        .expand((i) => i.attachments)
        .map((a) => a.sha256)
        .toList();

    await tester.ensureVisible(find.text('Rotate…'));
    await tester.tap(find.text('Rotate…'));
    await tester.pumpAndSettle();
    expect(find.text('Rotate vault key'), findsOneWidget);

    await tester.enterText(password(), 'not my password');
    await tester.pump();
    await tester.tap(button('Rotate key'));
    await settle(
      tester,
      () => find.text("That isn't your master password").evaluate().isNotEmpty,
    );
    expect(
      (appContainer(
        tester,
      ).read(vaultSessionProvider) as Unlocked).vault.header.vkId,
      oldVkId,
    );

    await tester.enterText(password(), testPassword);
    await tester.pump();
    await tester.tap(button('Rotate key'));
    await settle(
      tester,
      () => find.byType(RecoveryKitCard).evaluate().isNotEmpty,
    );
    expect(find.text('Your new recovery key'), findsOneWidget);
    final newRecovery = tester
        .widget<RecoveryKitCard>(find.byType(RecoveryKitCard))
        .kit
        .recoveryKey;
    await tester.tap(find.text("I've saved the new key"));
    await tester.pump();
    await tester.tap(button('Done'));
    await tester.pumpAndSettle();

    // Same items and files, under a new key.
    final after = appContainer(tester).read(vaultSessionProvider) as Unlocked;
    expect(after.vault.header.vkId, isNot(oldVkId));
    expect(after.index.all.map((i) => i.title).toList(), titles);
    expect(
      after.index.all
          .expand((i) => i.attachments)
          .map((a) => a.sha256)
          .toList(),
      files,
    );
    final keystore = after.index.all.firstWhere(
      (i) => i.attachments.isNotEmpty,
    );
    expect(
      await tester.runAsync(
        () => after.vault.readAttachment(keystore.attachments.single),
      ),
      isNotNull,
    );

    // On disk: the master password still opens it, the new recovery key
    // does, the old one doesn't.
    final store = storeOf(tester);
    await tester.runAsync(() async {
      final header = await store.readHeader();
      (await VaultKeys.unlockWithPassword(
        testCrypto,
        header,
        testPassword,
      )).dispose();
      VaultKeys.unlockWithRecovery(
        testCrypto,
        header,
        RecoveryKey.parse(testCrypto, newRecovery),
      ).dispose();
      expect(
        () => VaultKeys.unlockWithRecovery(
          testCrypto,
          header,
          RecoveryKey.parse(testCrypto, oldRecovery),
        ),
        throwsA(isA<WrongRecoveryKey>()),
      );
    });
  });

  testWidgets('an interrupted rotation is finished on unlock and its key '
      'shown once', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => testSupportDir(TestVault.sample),
    ))!;
    final store = findVault(Directory('${dir.path}/vaults'))!;

    // A power cut a few writes into a rotation.
    await tester.runAsync(() async {
      var writes = 0;
      final crashing = await Vault.unlock(
        crypto: testCrypto,
        store: VaultStore(
          store.root,
          beforeRename: (_) {
            if (writes++ == 3) {
              throw const FileSystemException('power cut');
            }
          },
        ),
        password: testPassword,
        deviceId: testDeviceId,
        now: () => testNow,
      );
      await expectLater(
        crashing.rotateVaultKey(testPassword),
        throwsA(isA<FileSystemException>()),
      );
      crashing.lock();
    });

    await tester.pumpWidget(
      testApp(
        location: Routes.unlock,
        supportDir: dir,
        layout: AppLayout.desktop,
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .unlock(testPassword),
    );
    await settle(
      tester,
      () => find.text('Key rotation finished').evaluate().isNotEmpty,
    );
    final shown = tester
        .widget<RecoveryKitCard>(find.byType(RecoveryKitCard))
        .kit
        .recoveryKey;
    await tester.runAsync(() async {
      VaultKeys.unlockWithRecovery(
        testCrypto,
        await store.readHeader(),
        RecoveryKey.parse(testCrypto, shown),
      ).dispose();
    });
    // Handed over once: nothing left to show again.
    expect(
      appContainer(tester)
          .read(vaultSessionProvider.notifier)
          .takePendingRecoveryKey(),
      isNull,
    );
    await tester.tap(find.text("I've saved the new key"));
    await tester.pump();
    await tester.tap(button('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(NewRecoveryKitDialog), findsNothing);
  });
}
