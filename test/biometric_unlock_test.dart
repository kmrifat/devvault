import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/features/settings/desktop_settings.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopSwitch;
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

    test('rotating the vault key deletes the stored key', () async {
      await session().enableBiometricUnlock(reason: 'r');
      (await session().rotateVaultKey(testPassword)).dispose();
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

    test('a build that cannot keep the key is not storable', () async {
      keys.storable = false;
      final status = await container.read(biometricUnlockProvider.future);
      expect(status.biometry, Biometry.faceId);
      expect(status.storable, isFalse);
      expect(status.enabled, isFalse);
      await expectLater(
        session().enableBiometricUnlock(reason: 'r'),
        throwsA(isA<BiometricKeyUnavailable>()),
      );
    });

    test('turning it off deletes the key', () async {
      await session().enableBiometricUnlock(reason: 'r');
      await session().disableBiometricUnlock();
      expect(keys.keys, isEmpty);
    });
  });

  test('a key read over the channel can be wiped', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const name = 'devvault/biometric_key';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(name, (message) async {
      final reply = const StandardMethodCodec().encodeSuccessEnvelope(
        Uint8List.fromList([1, 2, 3]),
      );
      // As from the engine: a platform's reply arrives read-only.
      return reply.asUnmodifiableView();
    });
    addTearDown(() => messenger.setMockMessageHandler(name, null));

    final key = await const ChannelBiometricKeyStore().read('v', reason: 'r');
    expect(key, [1, 2, 3]);
    key!.fillRange(0, key.length, 0);
    expect(key, [0, 0, 0]);
  });

  group('settings', () {
    Future<MemoryBiometricKeyStore> open(
      WidgetTester tester, {
      Biometry? kind = Biometry.faceId,
      BiometryUnavailable? unavailable,
      bool storable = true,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1100)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final keys = MemoryBiometricKeyStore(
        kind: kind,
        unavailable: unavailable,
        storable: storable,
      );
      await pumpUnlockedApp(
        tester,
        location: Routes.settingsSecurity,
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
          matching: find.byType(DesktopSettingsRow),
        ),
        matching: find.byType(DesktopSwitch),
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

    testWidgets('a build that cannot keep the key says so, switched off', (
      tester,
    ) async {
      final keys = await open(tester, kind: Biometry.touchId, storable: false);
      expect(find.text('Unlock with Touch ID'), findsOneWidget);
      expect(find.textContaining("isn't signed to keep a key"), findsOneWidget);
      final toggle = tester.widget<DesktopSwitch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Unlock with Touch ID'),
            matching: find.byType(DesktopSettingsRow),
          ),
          matching: find.byType(DesktopSwitch),
        ),
      );
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);

      await tester.tap(find.text('Unlock with Touch ID'));
      await tester.pumpAndSettle();
      expect(keys.keys, isEmpty);
    });

    testWidgets('Touch ID unavailable right now: disabled, with the reason', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final keys = await open(
        tester,
        kind: Biometry.touchId,
        unavailable: BiometryUnavailable.unavailable,
      );
      expect(find.text('Unlock with Touch ID'), findsOneWidget);
      expect(
        find.textContaining("isn't available right now. A MacBook's sensor"),
        findsOneWidget,
      );
      final toggle = tester.widget<DesktopSwitch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Unlock with Touch ID'),
            matching: find.byType(DesktopSettingsRow),
          ),
          matching: find.byType(DesktopSwitch),
        ),
      );
      expect(toggle.onChanged, isNull);
      await tester.tap(find.text('Unlock with Touch ID'));
      await tester.pumpAndSettle();
      expect(keys.keys, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('nothing enrolled: disabled, says to set it up', (
      tester,
    ) async {
      await open(
        tester,
        kind: Biometry.touchId,
        unavailable: BiometryUnavailable.notEnrolled,
      );
      expect(
        find.textContaining("Touch ID isn't set up on this device"),
        findsOneWidget,
      );
    });

    testWidgets('no row without biometrics', (tester) async {
      await open(tester, kind: null);
      expect(find.textContaining('Unlock with'), findsNothing);
    });
  });
}
