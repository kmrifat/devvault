import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show NativeLiquidGlassUtils;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vault_core/vault_core.dart';

import 'app/app.dart';
import 'app/layout.dart';
import 'app/settings_bridge.dart';
import 'app/settings_window_launcher.dart';
import 'app/routes.dart';
import 'data/app_settings.dart';
import 'data/providers.dart';
import 'features/settings/settings_window.dart';
import 'services/agent_socket.dart';
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

Future<void> main([List<String> args = const []]) async {
  // desktop_multi_window starts each window's engine here with
  // `multi_window`, its id and its arguments: macOS's Settings window.
  if (args case ['multi_window', _, final arguments]) {
    final settings = SettingsWindowArguments.decode(arguments);
    if (settings != null) return runSettingsWindow(settings);
  }
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
  // AI agents (P5) reach the app through a Unix socket (ADR-0006): in its
  // sandbox container on macOS, in `$XDG_RUNTIME_DIR` on Linux.
  final agents = switch (defaultTargetPlatform) {
    TargetPlatform.macOS => AgentEndpoint.macOS(
      Platform.environment,
      Platform.resolvedExecutable,
    ),
    TargetPlatform.linux => AgentEndpoint.linux(
      Platform.environment,
      Platform.resolvedExecutable,
    ),
    _ => null,
  };

  runApp(
    ProviderScope(
      overrides: [
        appSupportDirProvider.overrideWithValue(supportDir),
        deviceIdProvider.overrideWithValue(deviceId),
        cryptoProvider.overrideWithValue(crypto),
        initialSettingsProvider.overrideWithValue(settings),
        alertSchedulerProvider.overrideWithValue(alerts),
        agentSocketPathProvider.overrideWithValue(agents?.socket),
        appVersionProvider.overrideWithValue(version),
        updateInstallerProvider.overrideWithValue(installer),
        agentHelperPathProvider.overrideWithValue(agents?.helper),
        agentHelperArgsProvider.overrideWithValue(
          agents?.helperArgs ?? const [],
        ),
        if (!phone) bringToFrontProvider.overrideWithValue(bringWindowToFront),
        if (!phone && defaultTargetPlatform == TargetPlatform.macOS)
          settingsWindowProvider.overrideWith(
            (ref) => SettingsWindows(
              SettingsBridgeHost(ref, const WindowChannelTransport()),
            ),
          ),
        if (_biometricPlatforms.contains(defaultTargetPlatform))
          biometricKeyStoreProvider.overrideWithValue(
            const ChannelBiometricKeyStore(),
          ),
        // The UIKit bars draw nothing before iOS 26, so older iPhones keep
        // bc_ui's.
        if (NativeLiquidGlassUtils.supportsLiquidGlass)
          nativeBarsProvider.overrideWithValue(true),
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
