@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/services/updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../update_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  // The vault window under the toolbar: the one-time question, then a
  // newer release.
  for (final (name, overrides) in [
    ('N03-update-ask', updateOverrides()),
    (
      'N03-update-available',
      updateOverrides(checks: true, latest: const AppVersion(1, 1, 0)),
    ),
  ]) {
    shot(name, Routes.vault(), sample: true, overrides: overrides);
    shot(
      '$name-light',
      Routes.vault(),
      sample: true,
      overrides: overrides,
      brightness: Brightness.light,
    );
  }
}
