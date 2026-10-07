import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  group('session', () {
    late MemoryBiometricKeyStore keys;
    late ProviderContainer container;

    VaultSessionNotifier session() =>
        container.read(vaultSessionProvider.notifier);
    String vaultId() => switch (container.read(vaultSessionProvider)) {
      Unlocked(:final vault) => vault.vaultId,
      Locked(:final header?) => header.vaultId,
      _ => throw StateError('no vault'),
    };

    setUp(() async {
      final Directory dir = await testSupportDir(TestVault.locked);
      keys = MemoryBiometricKeyStore();
      container = ProviderContainer(
        overrides: [
          ...testOverrides(supportDir: dir),
          biometricKeyStoreProvider.overrideWithValue(keys),
        ],
      );
      addTearDown(container.dispose);
      await session().unlock(testPassword);
    });

    test('once turned on, biometrics open the vault', () async {
      expect(
        (await container.read(biometricUnlockProvider.future)).enabled,
        isFalse,
      );
      expect(await session().enableBiometricUnlock(reason: 'r'), isTrue);
      expect(keys.keys, contains(vaultId()));
      expect(
        (await container.read(biometricUnlockProvider.future)).enabled,
        isTrue,
      );

      session().lock();
      expect(await session().unlockWithBiometrics(reason: 'r'), isTrue);
      expect(container.read(vaultSessionProvider), isA<Unlocked>());
    });

    test('a cancelled prompt leaves the vault locked', () async {
      await session().enableBiometricUnlock(reason: 'r');
      session().lock();
      keys.nextPromptSucceeds = false;
      expect(await session().unlockWithBiometrics(reason: 'r'), isFalse);
      expect(container.read(vaultSessionProvider), isA<Locked>());
      expect(keys.keys, isNotEmpty, reason: 'a cancel keeps the key');
    });

    test('changing the master password deletes the stored key', () async {
      await session().enableBiometricUnlock(reason: 'r');
      await session().changePassword('a new and different passphrase');
      expect(keys.keys, isEmpty);
      expect(
        (await container.read(biometricUnlockProvider.future)).enabled,
        isFalse,
      );
    });

    test('a key from before a rotation is refused and deleted', () async {
      await session().enableBiometricUnlock(reason: 'r');
      final vault = (container.read(vaultSessionProvider) as Unlocked).vault;
      (await vault.rotateVaultKey(testPassword)).dispose();
      session().lock();

      await expectLater(
        session().unlockWithBiometrics(reason: 'r'),
        throwsA(isA<BiometricKeyGone>()),
      );
      expect(container.read(vaultSessionProvider), isA<Locked>());
      expect(keys.keys, isEmpty);
    });

    test('a key the platform invalidated is reported as gone', () async {
      await session().enableBiometricUnlock(reason: 'r');
      session().lock();
      keys.keys.clear(); // enrolment changed
      await expectLater(
        session().unlockWithBiometrics(reason: 'r'),
        throwsA(isA<BiometricKeyGone>()),
      );
    });

    test('turning it off deletes the key', () async {
      await session().enableBiometricUnlock(reason: 'r');
      await session().disableBiometricUnlock();
      expect(keys.keys, isEmpty);
    });
  });

  group('settings', () {
    Future<MemoryBiometricKeyStore> open(
      WidgetTester tester, {
      Biometry? kind = Biometry.faceId,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1100)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final keys = MemoryBiometricKeyStore(kind: kind);
      await pumpUnlockedApp(
        tester,
        location: Routes.settings,
        layout: AppLayout.desktop,
        overrides: [biometricKeyStoreProvider.overrideWithValue(keys)],
      );
      return keys;
    }

    testWidgets('the switch stores and deletes the key', (tester) async {
      final keys = await open(tester);
      expect(find.text('Unlock with Face ID'), findsOneWidget);
      final toggle = find.descendant(
        of: find.ancestor(
          of: find.text('Unlock with Face ID'),
          matching: find.byType(BCListGroupItem),
        ),
        matching: find.byType(BCSwitch),
      );

      await tester.runAsync(() async {
        await tester.tap(toggle);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(keys.keys, hasLength(1));

      await tester.runAsync(() async {
        await tester.tap(toggle);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(keys.keys, isEmpty);
    });

    testWidgets('no row without biometrics', (tester) async {
      await open(tester, kind: null);
      expect(find.textContaining('Unlock with'), findsNothing);
    });
  });
}
