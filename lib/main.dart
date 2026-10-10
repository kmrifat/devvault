import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart' show socketPathInContainer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vault_core/vault_core.dart';

import 'app/app.dart';
import 'app/layout.dart';
import 'app/routes.dart';
import 'data/app_settings.dart';
import 'data/providers.dart';
import 'services/biometric_key_store.dart';
import 'services/clipboard_guard.dart';
import 'services/device_id.dart';
import 'services/incoming_files.dart';
import 'services/notifications.dart';
import 'services/share_sheet_saver.dart';
import 'services/update_installer.dart';
import 'services/updates.dart';
import 'services/window.dart';

/// Opens the app at any route, e.g. `--dart-define=START=/vault`.
const String _start = String.fromEnvironment(
  'START',
  defaultValue: Routes.unlock,
);

/// Debug builds only: keep the app's data in a separate profile, a folder
/// named this inside the app support folder (the sandbox allows nothing
/// else), to try first run or onboarding without touching the vault on
/// this machine, e.g. `--dart-define=DEVVAULT_DATA=onboarding`.
const String _dataDirOverride = String.fromEnvironment('DEVVAULT_DATA');

/// CI's Windows update test only (desktop-checks.yml): start installing
/// the update from [appInstallerFeed] as soon as the app is up.
const bool _e2eInstall = bool.fromEnvironment('DEVVAULT_E2E_INSTALL');

/// Where `packages/biometric_key` keeps the vault key behind biometrics.
const _biometricPlatforms = {
  TargetPlatform.iOS,
  TargetPlatform.android,
  TargetPlatform.macOS,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindow();

  // Load everything that needs I/O before the first frame, so providers can
  // stay synchronous.
  final appSupport = await getApplicationSupportDirectory();
  final supportDir = kDebugMode && _dataDirOverride.isNotEmpty
      ? await Directory('${appSupport.path}/dev-profiles/$_dataDirOverride')
            .create(recursive: true)
      : appSupport;
  final deviceId = await loadOrCreateDeviceId(supportDir);
  final crypto = await VaultCrypto.init();
  final settings = AppSettings.load(supportDir);
  final alerts = await LocalAlertScheduler.init();
  // Phones export through the share sheet; clear any copy a crash left.
  final phone = AppLayout.current == AppLayout.mobile;
  if (phone) ShareSheetSaver.sweep();
  // Update checks (ADR-0007) compare against this; phones update through
  // their stores.
  final version = phone
      ? null
      : AppVersion.tryParse((await PackageInfo.fromPlatform()).version);
  // Sparkle on macOS installs in place; elsewhere, View Release.
  final installer = phone ? null : await ChannelUpdateInstaller.load();
  // AI agents (P5) reach the app through a socket in its sandbox
  // container, where `$HOME` points (ADR-0006). macOS only for now.
  final home = Platform.environment['HOME'];
  final agentSocket =
      defaultTargetPlatform == TargetPlatform.macOS &&
          home != null &&
          home.contains('/Library/Containers/')
      ? socketPathInContainer(home)
      : null;

  runApp(
    ProviderScope(
      overrides: [
        appSupportDirProvider.overrideWithValue(supportDir),
        deviceIdProvider.overrideWithValue(deviceId),
        cryptoProvider.overrideWithValue(crypto),
        initialSettingsProvider.overrideWithValue(settings),
        alertSchedulerProvider.overrideWithValue(alerts),
        agentSocketPathProvider.overrideWithValue(agentSocket),
        appVersionProvider.overrideWithValue(version),
        updateInstallerProvider.overrideWithValue(installer),
        if (agentSocket != null)
          agentHelperPathProvider.overrideWithValue(
            // …/DevVault.app/Contents/MacOS/DevVault → Contents/Helpers.
            '${File(Platform.resolvedExecutable).parent.parent.path}'
            '/Helpers/devvault-mcp',
          ),
        if (!phone) bringToFrontProvider.overrideWithValue(bringWindowToFront),
        if (_biometricPlatforms.contains(defaultTargetPlatform))
          biometricKeyStoreProvider.overrideWithValue(
            const ChannelBiometricKeyStore(),
          ),
        if (phone) ...[
          lockInBackgroundProvider.overrideWithValue(true),
          clipboardAccessProvider.overrideWithValue(
            const ChannelSensitiveClipboard(),
          ),
          fileSaverProvider.overrideWithValue(ShareSheetSaver()),
          incomingFilesProvider.overrideWithValue(ChannelIncomingFiles()),
        ],
      ],
      child: const DevVaultApp(initialLocation: _start, nativeWindow: true),
    ),
  );
  if (_e2eInstall && installer != null && version != null) {
    Future<void>.delayed(
      const Duration(seconds: 5),
      () => installer.install(Release(version: version)),
    );
  }
}
