@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  shot('D00-unlock', Routes.unlock, vault: TestVault.locked, realKdf: true);
  shot(
    'D00-unlock-light',
    Routes.unlock,
    vault: TestVault.locked,
    realKdf: true,
    brightness: Brightness.light,
  );
  shot(
    'B1-unlock',
    Routes.unlock,
    device: ShotDevice.mobile,
    vault: TestVault.locked,
    realKdf: true,
  );
}
