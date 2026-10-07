@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // General and security settings. D07 in the design is the sync storage
  // page (P2-09); this one follows its layout.
  shot('D07-settings', Routes.settings, sample: true);
  shot(
    'D07-settings-light',
    Routes.settings,
    sample: true,
    brightness: Brightness.light,
  );

  // Sync storage with nothing set up yet: R2 preselected.
  shot('D07-sync-storage', Routes.settingsSync, sample: true);
  shot(
    'D07-sync-storage-light',
    Routes.settingsSync,
    sample: true,
    brightness: Brightness.light,
  );
}
