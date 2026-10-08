@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  final overrides = [
    credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
    storageBackendFactoryProvider.overrideWithValue((_, _) => MemoryBackend()),
    storageProbeProvider.overrideWithValue(
      (_, _, _) async => StorageCapabilities.full,
    ),
    pairingOpsLimitProvider.overrideWithValue(1),
    pairingMemLimitProvider.overrideWithValue(8 * 1024 * 1024),
  ];

  /// Turns sync on (R2), then opens Pair a device and waits for the QR,
  /// which needs Argon2id on an isolate (real time).
  Future<void> pair(WidgetTester tester) async {
    await tester.runAsync(
      () => appContainer(tester)
          .read(syncSetupProvider.notifier)
          .save(
            const SyncSettings(
              provider: StorageProvider.r2,
              accountId: '0123456789abcdef0123456789abcdef',
              bucket: 'kitchenly-devvault',
            ),
            const AwsCredentials(
              accessKeyId: 'AKIA-SCREENSHOT',
              secretAccessKey: 'not-a-real-secret',
            ),
            StorageCapabilities.full,
          ),
    );
    // Turning sync on starts a sync: let one finish first.
    for (var i = 0; i < 500; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (appContainer(tester).read(syncControllerProvider) case SyncIdle(
        lastSync: _?,
      )) {
        break;
      }
    }
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(Routes.pair);
    for (var i = 0; i < 500; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.byType(QrImageView).evaluate().isNotEmpty) break;
    }
    expect(find.byType(QrImageView), findsOneWidget);
  }

  shot(
    'N08-pair-device',
    Routes.settings,
    sample: true,
    overrides: overrides,
    interact: pair,
  );
  shot(
    'N08-pair-device-light',
    Routes.settings,
    sample: true,
    overrides: overrides,
    interact: pair,
    brightness: Brightness.light,
  );
  // Phones scan the QR; desktops paste the text instead (pairing_flow_test).
  shot(
    'P4-join-with-pairing-code',
    Routes.joinVault,
    vault: TestVault.none,
    device: ShotDevice.mobile,
  );
}
