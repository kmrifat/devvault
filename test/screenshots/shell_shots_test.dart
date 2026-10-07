@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // Placeholder shells until the real screens land; each later screen adds
  // its own shot named after its design frame.
  shot('D03-vault-shell', Routes.vault());
  shot('D03-vault-shell-light', Routes.vault(), brightness: Brightness.light);
  shot('B2-vault-shell', Routes.vault(), device: ShotDevice.mobile);
  shot(
    'B2-vault-shell-light',
    Routes.vault(),
    device: ShotDevice.mobile,
    brightness: Brightness.light,
  );
}
