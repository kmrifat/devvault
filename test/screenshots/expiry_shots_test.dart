@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  shot('N06-expiry', Routes.expiry, sample: true);
  shot(
    'N06-expiry-light',
    Routes.expiry,
    sample: true,
    brightness: Brightness.light,
  );
  for (final kit in otherKits) {
    shot(
      'N06-expiry-${kit.name}-light',
      Routes.expiry,
      sample: true,
      brightness: Brightness.light,
      kit: kit,
    );
  }
  shot('B-expiry', Routes.expiry, sample: true, device: ShotDevice.mobile);
}
