@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// The phone's Search tab (design frames I2–I4), drawn with bc_ui's bars
/// as on Android and in tests; on iPhone the bars are UIKit's.
void main() {
  setUpAll(loadAppFonts);

  shot('I2-search', Routes.search(), device: ShotDevice.mobile, sample: true);
  shot(
    'I2-search-light',
    Routes.search(),
    device: ShotDevice.mobile,
    sample: true,
    brightness: Brightness.light,
  );
  shot(
    'I3-search-results',
    Routes.search(q: 'com.kitchenly'),
    device: ShotDevice.mobile,
    sample: true,
  );
  shot(
    'I4-search-empty',
    Routes.search(q: '7X2K9QH5'),
    device: ShotDevice.mobile,
    sample: true,
  );
}
