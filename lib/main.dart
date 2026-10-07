import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vault_core/vault_core.dart';

import 'app/app.dart';
import 'app/layout.dart';
import 'app/routes.dart';
import 'data/app_settings.dart';
import 'data/providers.dart';
import 'services/device_id.dart';
import 'services/incoming_files.dart';
import 'services/notifications.dart';
import 'services/share_sheet_saver.dart';
import 'services/window.dart';

/// Opens the app at any route, e.g. `--dart-define=START=/vault`.
const String _start = String.fromEnvironment(
  'START',
  defaultValue: Routes.unlock,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindow();

  // Load everything that needs I/O before the first frame, so providers can
  // stay synchronous.
  final supportDir = await getApplicationSupportDirectory();
  final deviceId = await loadOrCreateDeviceId(supportDir);
  final crypto = await VaultCrypto.init();
  final settings = AppSettings.load(supportDir);
  final alerts = await LocalAlertScheduler.init();
  // Phones export through the share sheet; clear any copy a crash left.
  final phone = AppLayout.current == AppLayout.mobile;
  if (phone) ShareSheetSaver.sweep();

  runApp(
    ProviderScope(
      overrides: [
        appSupportDirProvider.overrideWithValue(supportDir),
        deviceIdProvider.overrideWithValue(deviceId),
        cryptoProvider.overrideWithValue(crypto),
        initialSettingsProvider.overrideWithValue(settings),
        alertSchedulerProvider.overrideWithValue(alerts),
        if (phone) ...[
          fileSaverProvider.overrideWithValue(ShareSheetSaver()),
          incomingFilesProvider.overrideWithValue(ChannelIncomingFiles()),
        ],
      ],
      child: const DevVaultApp(initialLocation: _start),
    ),
  );
}
