@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/features/create_vault/desktop_recovery_kit_view.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_overrides.dart';
import '../update_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // Desktop Settings: a tab per pane (N07c General, N07 Security, N07b
  // Sync), on a Mac with Touch ID like the frames.
  final touchId = [
    biometricKeyStoreProvider.overrideWith(
      (ref) => MemoryBiometricKeyStore(kind: Biometry.touchId),
    ),
  ];
  // General with update checks on (ADR-0007), as on a release build.
  final updates = updateOverrides(checks: true);
  for (final (name, route) in [
    ('N07c-settings-general', Routes.settings),
    ('N07-settings-security', Routes.settingsSecurity),
    // Nothing set up yet: R2 preselected.
    ('N07b-settings-sync', Routes.settingsSync),
  ]) {
    final overrides = [...touchId, if (route == Routes.settings) ...updates];
    shot(name, route, sample: true, overrides: overrides);
    shot(
      '$name-light',
      route,
      sample: true,
      overrides: overrides,
      brightness: Brightness.light,
    );
  }
  // Security › New Kit…: the new key in N02's panel, on a sheet (WALK-06).
  Future<void> newKit(WidgetTester tester, {bool saved = false}) async {
    await tester.tap(find.text('New Kit…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, testPassword);
    await tester.tap(find.text('Make New Key'));
    final panel = find.byType(DesktopRecoveryKitPanel);
    for (var i = 0; i < 1000 && panel.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(panel, findsOneWidget);
    await tester.pumpAndSettle();
    if (saved) await tester.tap(find.text("I've saved the new key"));
  }

  shot(
    'N07-new-recovery-kit',
    Routes.settingsSecurity,
    sample: true,
    overrides: touchId,
    interact: newKit,
  );
  // As N02's light frame: the key is saved and Done is ready.
  shot(
    'N07-new-recovery-kit-light',
    Routes.settingsSecurity,
    sample: true,
    overrides: touchId,
    brightness: Brightness.light,
    interact: (tester) => newKit(tester, saved: true),
  );

  // Windows and Linux: General and Security, with the platform's own
  // biometrics rather than Touch ID.
  final biometrics = [
    biometricKeyStoreProvider.overrideWith(
      (ref) => MemoryBiometricKeyStore(kind: Biometry.biometrics),
    ),
  ];
  for (final kit in otherKits) {
    for (final (name, route) in [
      ('N07c-settings-general', Routes.settings),
      ('N07-settings-security', Routes.settingsSecurity),
    ]) {
      shot(
        '$name-${kit.name}-light',
        route,
        sample: true,
        overrides: [...biometrics, if (route == Routes.settings) ...updates],
        brightness: Brightness.light,
        kit: kit,
      );
    }
  }

  // Phones: General and Security on one page, sync storage on its own
  // (P3-07).
  shot(
    'B-settings',
    Routes.settings,
    device: ShotDevice.mobile,
    sample: true,
    overrides: [lockInBackgroundProvider.overrideWithValue(true)],
  );
  shot(
    'B-sync-storage',
    Routes.settingsSync,
    device: ShotDevice.mobile,
    sample: true,
  );
}
