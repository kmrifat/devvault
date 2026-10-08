@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  for (final (name, route) in [
    ('N07c-settings-general', Routes.settings),
    ('N07-settings-security', Routes.settingsSecurity),
    // Nothing set up yet: R2 preselected.
    ('N07b-settings-sync', Routes.settingsSync),
  ]) {
    shot(name, route, sample: true, overrides: touchId);
    shot(
      '$name-light',
      route,
      sample: true,
      overrides: touchId,
      brightness: Brightness.light,
    );
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
