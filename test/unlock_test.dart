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

  Future<void> openLocked(WidgetTester tester, {String? at}) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => testSupportDir(TestVault.locked));
    await tester.pumpWidget(
      testApp(location: at ?? Routes.unlock, supportDir: dir!),
    );
    await tester.pumpAndSettle();
  }

  /// Types [password] and presses Unlock, giving Argon2id real time until
  /// the attempt finishes (however busy the machine is).
  Future<void> tryPassword(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(EditableText), password);
    await tester.pump();
    // Tapped inside runAsync so the unlock (an isolate) runs in real time.
    await tester.runAsync(() async {
      await tester.tap(find.text('Unlock'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
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

  testWidgets('shows only what vault.json says', (tester) async {
    await openLocked(tester);
    expect(find.text('Unlock your vault'), findsOneWidget);
    expect(find.textContaining('Argon2id · 8 MiB · 1 pass'), findsOneWidget);
    expect(find.textContaining('vault '), findsOneWidget);
  });

  testWidgets('a wrong password says so and clears the field', (tester) async {
    await openLocked(tester);
    await tryPassword(tester, 'not the password');
    expect(find.text("That password didn't open this vault"), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
  });

  testWidgets('the right password opens the vault where you were going', (
    tester,
  ) async {
    await openLocked(tester, at: Routes.expiry);
    expect(location(tester), '/unlock?from=%2Fexpiry');
    await tryPassword(tester, testPassword);
    expect(appContainer(tester).read(vaultSessionProvider), isA<Unlocked>());
    expect(location(tester), Routes.expiry);
  });

  testWidgets('links to recovery', (tester) async {
    await openLocked(tester);
    await tester.tap(find.text('Use your recovery key'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.recover);
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
    }) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final keys = MemoryBiometricKeyStore()..nextPromptSucceeds = succeeds;
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
          layout: AppLayout.mobile,
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
  });
}
