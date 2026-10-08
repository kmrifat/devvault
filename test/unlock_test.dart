import 'dart:io';
import 'dart:typed_data';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/unlock/unlock_screen.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> openLocked(
    WidgetTester tester, {
    String? at,
    required AppLayout layout,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => testSupportDir(TestVault.locked));
    await tester.pumpWidget(
      testApp(location: at ?? Routes.unlock, supportDir: dir!, layout: layout),
    );
    await tester.pumpAndSettle();
  }

  /// The Unlock button: a push button on phones, the arrow inside the
  /// password field on desktop (N00).
  Finder unlockButton(AppLayout layout) => switch (layout) {
    AppLayout.mobile => find.text('Unlock'),
    AppLayout.desktop => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Unlock',
    ),
  };

  /// Types [password] and presses Unlock, giving Argon2id real time until
  /// the attempt finishes (however busy the machine is).
  Future<void> tryPassword(
    WidgetTester tester,
    String password, {
    required AppLayout layout,
  }) async {
    await tester.enterText(find.byType(EditableText), password);
    await tester.pump();
    if (layout == AppLayout.mobile) {
      // Tapped inside runAsync so the unlock (an isolate) runs in real time.
      await tester.runAsync(() async {
        await tester.tap(unlockButton(layout));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    } else {
      // Tapped in the test's zone: the macOS field's cursor animates on
      // timers started where focus returns, and real ones would outlive
      // the test. The loop below still gives the isolate real time.
      await tester.tap(unlockButton(layout));
    }
    await tester.pump();
    for (
      var i = 0;
      i < 500 && find.text('Unlocking…').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  for (final layout in AppLayout.values) {
    group(layout.name, () {
      testWidgets('shows only what vault.json says', (tester) async {
        await openLocked(tester, layout: layout);
        expect(find.text('Unlock your vault'), findsOneWidget);
        expect(
          find.textContaining('Argon2id · 8 MiB · 1 pass'),
          findsOneWidget,
        );
        expect(find.textContaining('vault '), findsOneWidget);
      });

      testWidgets('a wrong password says so and clears the field', (
        tester,
      ) async {
        await openLocked(tester, layout: layout);
        await tryPassword(tester, 'not the password', layout: layout);
        expect(
          find.text("That password didn't open this vault"),
          findsOneWidget,
        );
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          isEmpty,
        );
        expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
      });

      testWidgets('the right password opens the vault where you were going', (
        tester,
      ) async {
        await openLocked(tester, at: Routes.expiry, layout: layout);
        expect(location(tester), '/unlock?from=%2Fexpiry');
        await tryPassword(tester, testPassword, layout: layout);
        expect(
          appContainer(tester).read(vaultSessionProvider),
          isA<Unlocked>(),
        );
        expect(location(tester), Routes.expiry);
      });

      testWidgets('links to recovery', (tester) async {
        await openLocked(tester, layout: layout);
        await tester.tap(find.textContaining('Use your recovery key'));
        await tester.pumpAndSettle();
        expect(location(tester), Routes.recover);
      });
    });
  }

  testWidgets('desktop: Return unlocks; the arrow waits for a password', (
    tester,
  ) async {
    await openLocked(tester, layout: AppLayout.desktop);
    final arrow = tester.widget<Semantics>(unlockButton(AppLayout.desktop));
    expect(arrow.properties.enabled, isFalse);
    await tester.enterText(find.byType(EditableText), testPassword);
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(unlockButton(AppLayout.desktop))
          .properties
          .enabled,
      isTrue,
    );
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (
      var i = 0;
      i < 500 && appContainer(tester).read(vaultSessionProvider) is! Unlocked;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(appContainer(tester).read(vaultSessionProvider), isA<Unlocked>());
  });

  test('waits longer after repeated wrong passwords', () {
    expect(UnlockScreen.backoff(4), Duration.zero);
    expect(UnlockScreen.backoff(5), const Duration(seconds: 30));
    expect(UnlockScreen.backoff(6), const Duration(seconds: 60));
    expect(UnlockScreen.backoff(8), const Duration(seconds: 240));
    expect(UnlockScreen.backoff(20), const Duration(minutes: 5));
  });

  group('with Face ID', () {
    /// A locked vault whose key is stored behind "Face ID" ([stale]: a key
    /// from another vault, as after a rotation elsewhere).
    Future<MemoryBiometricKeyStore> openWithFaceId(
      WidgetTester tester, {
      bool succeeds = true,
      bool stale = false,
      AppLayout layout = AppLayout.mobile,
    }) async {
      final desktop = layout == AppLayout.desktop;
      tester.view
        ..physicalSize = desktop
            ? const Size(1440, 900)
            : const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = desktop ? 1 : 3;
      addTearDown(tester.view.reset);
      final keys = MemoryBiometricKeyStore(
        kind: desktop ? Biometry.touchId : Biometry.faceId,
      )..nextPromptSucceeds = succeeds;
      final dir = (await tester.runAsync(() async {
        final dir = await testSupportDir(TestVault.locked);
        final store = findVault(Directory('${dir.path}/vaults'))!;
        final vault = await Vault.unlock(
          crypto: testCrypto,
          store: store,
          password: testPassword,
          deviceId: testDeviceId,
          now: () => testNow,
        );
        keys.keys[vault.vaultId] = stale
            ? testCrypto.randomBytes(VaultCrypto.keyBytes)
            : vault.withVaultKeyBytes(Uint8List.fromList);
        vault.lock();
        return dir;
      }))!;
      await tester.pumpWidget(
        testApp(
          location: Routes.unlock,
          supportDir: dir,
          layout: layout,
          overrides: [biometricKeyStoreProvider.overrideWithValue(keys)],
        ),
      );
      return keys;
    }

    /// Lets the prompt and the unlock run in real time.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    VaultSession session(WidgetTester tester) =>
        appContainer(tester).read(vaultSessionProvider);

    testWidgets('prompts by itself and unlocks', (tester) async {
      final keys = await openWithFaceId(tester);
      await settle(tester);
      expect(keys.prompts, 1);
      expect(session(tester), isA<Unlocked>());
      expect(find.byType(UnlockScreen), findsNothing);
    });

    testWidgets('a dismissed prompt leaves the password and a retry', (
      tester,
    ) async {
      final keys = await openWithFaceId(tester, succeeds: false);
      await settle(tester);
      expect(keys.prompts, 1, reason: 'asks once by itself, not in a loop');
      expect(session(tester), isA<Locked>());
      expect(find.text('Master password'), findsOneWidget);

      keys.nextPromptSucceeds = true;
      await tester.tap(find.text('Unlock with Face ID'));
      await settle(tester);
      expect(keys.prompts, 2);
      expect(session(tester), isA<Unlocked>());
    });

    testWidgets('a stale key turns Face ID off and says why', (tester) async {
      final keys = await openWithFaceId(tester, stale: true);
      await settle(tester);
      expect(session(tester), isA<Locked>());
      expect(keys.keys, isEmpty);
      expect(find.textContaining('Face ID was turned off'), findsOneWidget);
      expect(find.text('Unlock with Face ID'), findsNothing);
    });

    group('desktop (N00), with Touch ID', () {
      testWidgets('prompts by itself and unlocks', (tester) async {
        final keys = await openWithFaceId(tester, layout: AppLayout.desktop);
        await settle(tester);
        expect(keys.prompts, 1);
        expect(session(tester), isA<Unlocked>());
      });

      testWidgets('a dismissed prompt leaves the password and a retry', (
        tester,
      ) async {
        final keys = await openWithFaceId(
          tester,
          succeeds: false,
          layout: AppLayout.desktop,
        );
        await settle(tester);
        expect(keys.prompts, 1);
        expect(session(tester), isA<Locked>());
        expect(find.byType(EditableText), findsOneWidget);

        keys.nextPromptSucceeds = true;
        await tester.tap(find.text('Unlock with Touch ID'));
        await settle(tester);
        expect(keys.prompts, 2);
        expect(session(tester), isA<Unlocked>());
      });

      testWidgets('a stale key turns Touch ID off and says why', (
        tester,
      ) async {
        final keys = await openWithFaceId(
          tester,
          stale: true,
          layout: AppLayout.desktop,
        );
        await settle(tester);
        expect(session(tester), isA<Locked>());
        expect(keys.keys, isEmpty);
        expect(find.textContaining('Touch ID was turned off'), findsOneWidget);
        expect(find.text('Unlock with Touch ID'), findsNothing);
      });
    });
  });
}
