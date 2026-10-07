/// Golden screenshots of whole screens, rendered with the real fonts.
///
/// Every file under `test/screenshots/` is tagged `golden`. Font rasterising
/// differs between macOS and Linux, so CI checks goldens on macOS only, and
/// the images are (re)generated on a Mac:
///
/// ```sh
/// flutter test --tags golden --update-goldens
/// ```
///
/// Images land in `screenshots/<name>.png` at the repo root, named after the
/// design frame they implement (`D03-vault`, `B2-vault`, …), so they can be
/// compared side by side with `design/DevVault.fig`.
@Tags(['golden'])
library;

import 'dart:convert';

import 'package:devvault/app/app.dart';
import 'package:devvault/app/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import '../test_overrides.dart';

/// Gets a screenshot file ready: libsodium. The app's real fonts are
/// loaded for every test by `test/flutter_test_config.dart`.
Future<void> loadAppFonts() => loadTestCrypto();

/// The devices screenshots are taken on. They match the design frames.
enum ShotDevice {
  /// iPhone-sized, like the Mobile · bc_ui frames (B1–B4).
  mobile(
    AppLayout.mobile,
    Size(390, 844),
    2,
    EdgeInsets.only(top: 47, bottom: 34),
  ),

  /// The desktop window, like the Desktop · bc_ui frames (D00–D07).
  desktop(AppLayout.desktop, Size(1440, 900), 1, EdgeInsets.zero);

  const ShotDevice(this.layout, this.size, this.pixelRatio, this.insets);

  final AppLayout layout;
  final Size size;
  final double pixelRatio;
  final EdgeInsets insets;
}

/// Registers a test that opens [route] on [device] and compares it with
/// `screenshots/<name>.png`.
///
/// The vault is unlocked unless [vault] says the device holds no vault or
/// a locked one (first-run and lock screens). [sample] fills the unlocked
/// vault with the design frames' credentials.
///
/// [interact] runs after the first frame settles (tap through to a dialog,
/// type into a field) before the capture.
void shot(
  String name,
  String route, {
  ShotDevice device = ShotDevice.desktop,
  Brightness brightness = Brightness.dark,
  Future<void> Function(WidgetTester tester)? interact,
  List<Override> overrides = const [],
  TestVault? vault,
  bool sample = false,
  bool realKdf = false,
}) {
  testWidgets(name, (tester) async {
    final ratio = device.pixelRatio;
    final padding = FakeViewPadding(
      top: device.insets.top * ratio,
      bottom: device.insets.bottom * ratio,
    );
    tester.view
      ..physicalSize = device.size * ratio
      ..devicePixelRatio = ratio
      ..padding = padding
      ..viewPadding = padding;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });

    // flutter_test draws shadows as hard offsets unless told otherwise. The
    // flag has to be restored inside the body: it is checked before
    // tearDowns run.
    debugDisableShadows = false;
    // Seeded per shot, so vault ids, recovery keys and nonces are the same
    // on every run and the image only changes when the UI does.
    final crypto = await tester.runAsync(
      // Seeded randomness is what reproducible screenshots need.
      // ignore: invalid_use_of_visible_for_testing_member
      () => VaultCrypto.withFixedRandom(utf8.encode('devvault shot $name')),
    );
    try {
      if (vault == null) {
        await pumpUnlockedApp(
          tester,
          location: route,
          vault: sample ? TestVault.sample : TestVault.locked,
          layout: device.layout,
          overrides: overrides,
          crypto: crypto,
          settle: () => _settle(tester),
        );
      } else {
        // First-run and lock screens: the device holds [vault], unopened.
        final dir = await tester.runAsync(
          () => testSupportDir(vault, crypto, realKdf),
        );
        await tester.pumpWidget(
          testApp(
            location: route,
            supportDir: dir!,
            layout: device.layout,
            overrides: overrides,
            realKdf: realKdf,
            crypto: crypto,
          ),
        );
        await _settle(tester);
      }
      if (interact != null) {
        await interact(tester);
        await _settle(tester);
      }
      await expectLater(
        find.byType(DevVaultApp),
        matchesGoldenFile('../../screenshots/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// Like pumpAndSettle, but tolerates endless animations (spinners).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
