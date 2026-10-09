import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/desktop_recovery_kit_view.dart';
import 'package:devvault/features/create_vault/recovery_kit_card.dart';
import 'package:devvault/features/settings/new_recovery_kit_dialog.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'recovery_kit_test.dart' show FakeFileSaver, FakePrinter;
import 'test_overrides.dart';
import 'toasts.dart';

void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;
  late FakeFileSaver saver;
  late FakePrinter printer;

  /// Settings › Security, with the clipboard, save and print dialogs
  /// faked and copied secrets cleared after [clearAfter].
  Future<void> open(
    WidgetTester tester, {
    AppLayout layout = AppLayout.desktop,
    Duration clearAfter = AppSettings.defaultClipboardClear,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    saver = FakeFileSaver();
    printer = FakePrinter();
    await pumpUnlockedApp(
      tester,
      location: layout == AppLayout.desktop
          ? Routes.settingsSecurity
          : Routes.settings,
      layout: layout,
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(clipboardClearAfter: clearAfter),
        ),
        clipboardAccessProvider.overrideWithValue(clipboard),
        fileSaverProvider.overrideWithValue(saver),
        documentPrinterProvider.overrideWithValue(printer),
      ],
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

  Finder inDialog(String text) => find.descendant(
    of: find.byType(NewRecoveryKitDialog),
    matching: find.text(text),
  );

  /// New Kit… through to the new key; returns it.
  Future<String> makeNewKey(WidgetTester tester, AppLayout layout) async {
    final desktop = layout == AppLayout.desktop;
    final newKit = find.text(desktop ? 'New Kit…' : 'New kit…');
    await tester.ensureVisible(newKit);
    await tester.tap(newKit);
    await tester.pumpAndSettle();
    await tester.enterText(password(), testPassword);
    await tester.pump();
    await tester.tap(inDialog(desktop ? 'Make New Key' : 'Make new key'));
    final kit = desktop
        ? find.byType(DesktopRecoveryKitPanel)
        : find.byType(RecoveryKitCard);
    await settle(tester, () => kit.evaluate().isNotEmpty);
    return desktop
        ? tester.widget<DesktopRecoveryKitPanel>(kit).kit.recoveryKey
        : tester.widget<RecoveryKitCard>(kit).kit.recoveryKey;
  }

  /// The key and every group of it.
  List<String> partsOf(String key) => [key, ...key.split(RegExp('[- ]'))];

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
    expect(find.byType(DesktopRecoveryKitPanel), findsNothing);

    await tester.enterText(password(), testPassword);
    await tester.pump();
    await tester.tap(button('Make New Key'));
    await settle(
      tester,
      () => find.byType(DesktopRecoveryKitPanel).evaluate().isNotEmpty,
    );
    final newKey = tester
        .widget<DesktopRecoveryKitPanel>(find.byType(DesktopRecoveryKitPanel))
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

  testWidgets('desktop: N02 push buttons, not the phone card (WALK-06)', (
    tester,
  ) async {
    await open(tester);
    final key = await makeNewKey(tester, AppLayout.desktop);
    expect(find.byType(RecoveryKitCard), findsNothing);
    for (final label in ['Save PDF…', 'Print…', 'Save as Text…', 'Copy']) {
      expect(button(label), findsOneWidget);
    }
    // The key as N02 writes it: two rows of seven groups.
    final groups = key.split('-');
    expect(find.text(groups.take(7).join('-')), findsOneWidget);
    expect(find.text(groups.skip(7).join('-')), findsOneWidget);

    // Save as Text…
    await tester.tap(button('Save as Text…'));
    await tester.pumpAndSettle();
    expect(saver.saved['DevVault Recovery Key.txt'], contains(key));
    expectNoSecretInToasts(tester, partsOf(key));

    // Save PDF…: saved, then its bytes wiped.
    await tester.tap(button('Save PDF…'));
    await settle(
      tester,
      () => saver.saved.containsKey('DevVault Recovery Key.pdf'),
    );
    expect(saver.saved['DevVault Recovery Key.pdf'], startsWith('%PDF-'));
    expect(
      saver.buffers['DevVault Recovery Key.pdf']!.every((b) => b == 0),
      isTrue,
    );

    // Print…
    await tester.tap(button('Print…'));
    await settle(tester, () => printer.printed != null);
    expect(printer.printed, startsWith('%PDF-'));
    expect(printer.buffer!.every((b) => b == 0), isTrue);

    // Copy, through the guard.
    await tester.tap(button('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard.text, key);
    expectNoSecretInToasts(tester, partsOf(key));
    await tester.pump(const Duration(seconds: 30));
    expect(clipboard.text, '');

    // Done still waits for the confirmation.
    expect(tester.widget<DesktopButton>(button('Done')).onPressed, isNull);
    await tester.tap(find.text("I've saved the new key"));
    await tester.pump();
    await tester.tap(button('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(NewRecoveryKitDialog), findsNothing);
  });

  // WALK-01: the copy toast says the time the setting clears it after.
  for (final layout in AppLayout.values) {
    for (final seconds in [10, 30]) {
      testWidgets('${layout.name}: copy toast says $seconds seconds', (
        tester,
      ) async {
        final after = Duration(seconds: seconds);
        await open(tester, layout: layout, clearAfter: after);
        final key = await makeNewKey(tester, layout);
        await tester.tap(inDialog('Copy'));
        // A second for the toast to come in; settling would run past the
        // clear.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(clipboard.text, key);
        expect(
          toastTexts(tester),
          contains('It clears from the clipboard in $seconds seconds.'),
        );
        expectNoSecretInToasts(tester, partsOf(key));
        // And the guard clears it then.
        await tester.pump(after - const Duration(seconds: 2));
        expect(clipboard.text, key);
        await tester.pump(const Duration(seconds: 1));
        expect(clipboard.text, '');
        await tester.pumpAndSettle();
      });
    }
  }
}
