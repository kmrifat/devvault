import 'dart:io';

import 'package:devvault/app/routes.dart';
import 'package:devvault/app/session_redirect.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  group('sessionRedirect', () {
    late Locked locked;
    late Unlocked unlocked;

    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('redirect_');
      final (vault, rk) = await Vault.create(
        crypto: testCrypto,
        store: VaultStore(dir),
        password: 'pw',
        deviceId: testDeviceId,
        now: () => testNow,
        opsLimit: 1,
        memLimit: KdfParams.minMemLimit,
      );
      rk.dispose();
      locked = Locked(vault.store, vault.header);
      unlocked = Unlocked(vault, VaultIndex(await vault.loadAll()));
    });

    String? go(
      VaultSession session,
      String location, {
      bool kitPending = false,
    }) => sessionRedirect(
      session,
      Uri.parse(location),
      recoveryKitPending: kitPending,
    );

    test('first launch only offers create', () {
      expect(go(const NoVault(), Routes.create), isNull);
      expect(go(const NoVault(), Routes.vault()), Routes.create);
      expect(go(const NoVault(), Routes.unlock), Routes.create);
    });

    test('locked keeps unlock and recover, bounces the rest back later', () {
      expect(go(locked, Routes.unlock), isNull);
      expect(go(locked, Routes.recover), isNull);
      expect(go(locked, Routes.expiry), '/unlock?from=%2Fexpiry');
      expect(
        go(locked, '/vault?item=abc'),
        '/unlock?from=%2Fvault%3Fitem%3Dabc',
      );
      expect(go(locked, Routes.create), Routes.unlock);
    });

    test('unlocked returns to where the user was going', () {
      expect(go(unlocked, '/unlock?from=%2Fexpiry'), Routes.expiry);
      expect(go(unlocked, Routes.unlock), Routes.vault());
      expect(go(unlocked, Routes.create), Routes.vault());
      expect(go(unlocked, Routes.settings), isNull);
    });

    test('only in-app paths are honoured as a return target', () {
      expect(go(unlocked, '/unlock?from=https://evil.example'), Routes.vault());
      expect(go(unlocked, '/unlock?from=//evil.example/x'), Routes.vault());
      expect(go(unlocked, '/unlock?from=%2Funlock'), Routes.vault());
    });

    test('a fresh recovery key must be seen before anything else', () {
      expect(
        go(unlocked, Routes.vault(), kitPending: true),
        Routes.createRecoveryKit,
      );
      expect(go(unlocked, Routes.createRecoveryKit, kitPending: true), isNull);
      expect(go(unlocked, Routes.createRecoveryKit), Routes.vault());
    });
  });

  group('VaultSessionNotifier', () {
    Future<ProviderContainer> container(TestVault vault) async {
      final dir = await testSupportDir(vault);
      final c = ProviderContainer(overrides: testOverrides(supportDir: dir));
      addTearDown(c.dispose);
      return c;
    }

    test('finds no vault on first launch, then creates one', () async {
      final c = await container(TestVault.none);
      expect(c.read(vaultSessionProvider), isA<NoVault>());
      final rk = await c
          .read(vaultSessionProvider.notifier)
          .create('a long master password');
      expect(c.read(vaultSessionProvider), isA<Unlocked>());
      expect(rk.toDisplayString(), hasLength(69));
    });

    test('finds a locked vault and unlocks it', () async {
      final c = await container(TestVault.locked);
      final notifier = c.read(vaultSessionProvider.notifier);
      expect(c.read(vaultSessionProvider), isA<Locked>());

      await expectLater(notifier.unlock('nope'), throwsA(isA<WrongPassword>()));
      expect(c.read(vaultSessionProvider), isA<Locked>());

      await notifier.unlock(testPassword);
      expect(c.read(vaultSessionProvider), isA<Unlocked>());
    });

    test('locking wipes the key and drops the decrypted index', () async {
      final c = await container(TestVault.locked);
      final notifier = c.read(vaultSessionProvider.notifier);
      await notifier.unlock(testPassword);
      final vault = (c.read(vaultSessionProvider) as Unlocked).vault;
      notifier.lock();
      expect(c.read(vaultSessionProvider), isA<Locked>());
      expect(vault.isLocked, isTrue);
    });

    test('recovery key typos are caught before trying to decrypt', () async {
      final c = await container(TestVault.locked);
      await expectLater(
        c.read(vaultSessionProvider.notifier).unlockWithRecovery('ABCD-1234'),
        throwsA(isA<RecoveryKeyFormatException>()),
      );
      expect(c.read(vaultSessionProvider), isA<Locked>());
    });
  });

  group('routing follows the session', () {
    String location(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
            .toString();

    testWidgets('first launch opens create, whatever the link', (tester) async {
      final dir = await tester.runAsync(testSupportDir);
      await tester.pumpWidget(
        testApp(location: Routes.expiry, supportDir: dir!),
      );
      await tester.pumpAndSettle();
      expect(location(tester), Routes.create);
    });

    testWidgets('a deep link while locked resumes after unlocking', (
      tester,
    ) async {
      final dir = await tester.runAsync(() => testSupportDir(TestVault.locked));
      await tester.pumpWidget(
        testApp(location: Routes.expiry, supportDir: dir!),
      );
      await tester.pumpAndSettle();
      expect(location(tester), '/unlock?from=%2Fexpiry');

      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .unlock(testPassword),
      );
      await tester.pumpAndSettle();
      expect(location(tester), Routes.expiry);

      appContainer(tester).read(vaultSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(location(tester), '/unlock?from=%2Fexpiry');
    });

    testWidgets('a new vault shows its recovery kit before the vault', (
      tester,
    ) async {
      final dir = await tester.runAsync(testSupportDir);
      await tester.pumpWidget(
        testApp(location: Routes.create, supportDir: dir!),
      );
      await tester.pumpAndSettle();
      final c = appContainer(tester);
      await tester.runAsync(() async {
        final rk = await c
            .read(vaultSessionProvider.notifier)
            .create('a long master password');
        c.read(pendingRecoveryKeyProvider.notifier).hold(rk);
      });
      await tester.pumpAndSettle();
      expect(location(tester), Routes.createRecoveryKit);

      c.read(pendingRecoveryKeyProvider.notifier).confirmSaved();
      await tester.pumpAndSettle();
      expect(location(tester), Routes.vault());
    });
  });
}
