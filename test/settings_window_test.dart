import 'dart:convert';
import 'dart:io';

import 'package:devvault/app/settings_bridge.dart';
import 'package:devvault/app/settings_window_launcher.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/settings/settings_layout.dart';
import 'package:devvault/features/settings/settings_window.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart' show AwsCredentials;

import 'test_overrides.dart';

/// Two ends of a bridge in one test: what the main window's channel and
/// the Settings window's channel do between engines.
class _Pipe implements BridgeTransport {
  _Pipe? other;
  Future<String?> Function(String method, String? body)? _on;

  /// Whether the other end has gone (its window closed).
  bool closed = false;

  @override
  Future<void> listen(
    Future<String?> Function(String method, String? body) on,
  ) async => _on = on;

  @override
  Future<String?> call(String method, [String? body]) async {
    final on = other?._on;
    if (on == null || other!.closed) throw StateError('No window');
    return on(method, body);
  }
}

/// macOS's Settings window (⌘,): a second engine that mirrors the main
/// window over [SettingsBridgeHost] / [SettingsBridgeClient].
void main() {
  setUpAll(loadTestCrypto);

  test('arguments round-trip; anything else is not a Settings window', () {
    final arguments = SettingsWindowArguments(SettingsPane.sync).encode();
    expect(SettingsWindowArguments.decode(arguments)?.pane, SettingsPane.sync);
    expect(SettingsWindowArguments.decode(''), isNull);
    expect(SettingsWindowArguments.decode('{"window":"other"}'), isNull);
  });

  group('bridge', () {
    late ProviderContainer mainWindow;
    late ProviderContainer settingsWindow;
    late SettingsBridgeClient client;
    late MemoryBiometricKeyStore biometrics;
    late _Pipe hostEnd;
    late Object? Function() probeError;

    setUp(() async {
      final Directory dir = await testSupportDir(TestVault.locked);
      biometrics = MemoryBiometricKeyStore(kind: Biometry.touchId);
      probeError = () => null;
      hostEnd = _Pipe();
      final windowEnd = _Pipe()..other = hostEnd;
      hostEnd.other = windowEnd;
      final host = Provider((ref) => SettingsBridgeHost(ref, hostEnd));
      mainWindow = ProviderContainer(
        overrides: [
          ...testOverrides(supportDir: dir),
          biometricKeyStoreProvider.overrideWithValue(biometrics),
          storageProbeProvider.overrideWithValue((_, _, _) async {
            if (probeError() case final Object e) throw e;
            return const StorageCapabilities(
              conditionalCreate: true,
              conditionalUpdate: true,
              conditionalDelete: true,
            );
          }),
        ],
      );
      addTearDown(mainWindow.dispose);
      // Listened to, as DevVaultApp does, so it hears every change.
      mainWindow.listen(host, (_, _) {});
      await mainWindow.read(vaultSessionProvider.notifier).unlock(testPassword);

      client = SettingsBridgeClient(windowEnd);
      final first = await client.connect();
      settingsWindow = ProviderContainer(
        overrides: settingsWindowOverrides(client, first, testCrypto),
      );
      addTearDown(settingsWindow.dispose);
      client.onState = settingsWindow
          .read(settingsSnapshotProvider.notifier)
          .set;
    });

    /// Lets the providers settle and the host's coalesced push arrive.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('the window sees the open vault, and nothing while locked', () {
      final facts = settingsWindow.read(vaultFactsProvider);
      expect(facts, mainWindow.read(vaultFactsProvider));
      expect(facts?.vaultId, isNotEmpty);
    });

    test('a setting changed in either window shows in the other', () async {
      settingsWindow
          .read(settingsProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await settle();
      expect(mainWindow.read(settingsProvider).themeMode, ThemeMode.dark);

      mainWindow.read(settingsProvider.notifier).setExpiryReminders(false);
      await settle();
      expect(settingsWindow.read(settingsProvider).expiryReminders, isFalse);
    });

    test('the password is checked and changed in the main window', () async {
      final vault = settingsWindow.read(vaultActionsProvider);
      expect(await vault.checkPassword('not it'), isFalse);
      expect(await vault.checkPassword(testPassword), isTrue);

      await vault.changePassword('a brand new passphrase');
      final session = mainWindow.read(vaultSessionProvider.notifier);
      expect(await session.checkPassword('a brand new passphrase'), isTrue);
      expect(await session.checkPassword(testPassword), isFalse);
    });

    test('a new recovery key comes back whole', () async {
      final key = await settingsWindow
          .read(vaultActionsProvider)
          .replaceRecoveryKey();
      addTearDown(key.dispose);
      expect(key.toDisplayString(), isNotEmpty);
    });

    test('Touch ID: turned on through the main window, its status '
        'mirrored', () async {
      final vault = settingsWindow.read(vaultActionsProvider);
      expect(await vault.enableBiometricUnlock(reason: 'r'), isTrue);
      expect(biometrics.keys, hasLength(1));
      await settle();
      await settle();
      expect(
        (await settingsWindow.read(biometricUnlockProvider.future)).enabled,
        isTrue,
      );

      biometrics.storable = false;
      await expectLater(
        vault.enableBiometricUnlock(reason: 'r'),
        throwsA(
          isA<BiometricKeyUnavailable>().having(
            (e) => e.code,
            'code',
            isNot(''),
          ),
        ),
      );
    });

    test('a storage error reaches the form as the same kind', () async {
      const settings = SyncSettings(
        bucket: 'b',
        accountId: '0123456789abcdef0123456789abcdef',
      );
      const keys = AwsCredentials(accessKeyId: 'id', secretAccessKey: 'secret');
      final setup = settingsWindow.read(syncSetupProvider.notifier);

      final capabilities = await setup.test(settings, keys);
      expect(capabilities.conditionalCreate, isTrue);

      probeError = () => const StorageAccessDenied('403');
      await expectLater(
        setup.test(settings, keys),
        throwsA(isA<StorageAccessDenied>()),
      );
    });

    test('anything else that fails says only that it failed', () async {
      // Changing the password while locked throws a StateError naming
      // nothing secret; the window still gets no text at all.
      mainWindow.read(vaultSessionProvider.notifier).lock();
      await expectLater(
        settingsWindow.read(vaultActionsProvider).changePassword('x'),
        throwsA(isA<BridgeFailure>()),
      );
    });

    test('locking the vault closes the window', () async {
      var closed = false;
      client.onClose = () => closed = true;
      mainWindow.read(vaultSessionProvider.notifier).lock();
      await settle();
      expect(closed, isTrue);
    });

    test('input in the window counts against auto-lock', () async {
      final before = mainWindow.read(userActivityProvider);
      await client.call(SettingsCalls.activity);
      expect(mainWindow.read(userActivityProvider), before + 1);
    });

    test('agents: the window lists clients; revoking happens in the main '
        'window', () {
      final agents = settingsWindow.read(agentBridgeProvider);
      expect(agents.clients, mainWindow.read(agentBridgeProvider).clients);
      expect(agents.otherInstance, isFalse);
    });

    test('a closed window stops getting updates', () async {
      hostEnd.other!.closed = true;
      mainWindow.read(settingsProvider.notifier).setExpiryReminders(false);
      await settle();
      // No throw; the next window asks for a fresh snapshot.
      expect(settingsWindow.read(settingsProvider).expiryReminders, isTrue);
    });
  });

  test('snapshot JSON round-trips', () {
    const snapshot = SettingsSnapshot(
      settings: AppSettings(),
      supportDir: '/tmp/x',
      vault: VaultFacts(
        vaultId: 'v',
        folder: '/tmp/x/vaults/v',
        kdfOpsLimit: 3,
        kdfMemLimit: 64 << 20,
      ),
      biometric: BiometricUnlock(
        Biometry.touchId,
        unavailable: BiometryUnavailable.unavailable,
        enabled: true,
        storable: true,
      ),
      credentialsDegraded: true,
      agentsElsewhere: true,
    );
    final back = SettingsSnapshot.fromJson(
      (jsonDecode(jsonEncode(snapshot.toJson())) as Map)
          .cast<String, Object?>(),
    );
    expect(back.vault, snapshot.vault);
    expect(back.biometric?.biometry, Biometry.touchId);
    expect(back.biometric?.unavailable, BiometryUnavailable.unavailable);
    expect(back.biometric?.enabled, isTrue);
    expect(back.credentialsDegraded, isTrue);
    expect(back.agentsElsewhere, isTrue);
    expect(back.supportDir, '/tmp/x');
  });
}
