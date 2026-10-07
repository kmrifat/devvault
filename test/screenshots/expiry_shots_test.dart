@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  shot('D06-expiry', Routes.expiry, sample: true);
  shot(
    'D06-expiry-light',
    Routes.expiry,
    sample: true,
    brightness: Brightness.light,
  );
  shot('B-expiry', Routes.expiry, sample: true, device: ShotDevice.mobile);
}
